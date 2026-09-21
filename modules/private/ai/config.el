;;; private/ai/config.el -*- lexical-binding: t; -*-
;;
;; Three ways to work with agents, all under SPC l (see +ai/menu):
;;   claude-code-ide  Claude Code in a side window, connected to Emacs over
;;                    MCP, so it sees the buffer, diagnostics and our tools.
;;   agent-shell      the same agent in a plain Emacs buffer, over ACP.
;;   gptel            inline chat and rewrites against the Claude API.

(defvar +ai-claude-model nil
  "Model for the claude CLI, or nil for its default.
Set it with `+ai/set-claude-model'.")

(defvar +ai-gptel-directives
  '((cpp . "You are a senior C++ engineer working in C++20 with CMake and \
clang-tidy. Prefer small, modern, safe code. Show diffs, not whole files, \
and say briefly why.")
    (embedded . "You are an embedded firmware engineer using ESP32, STM32 \
and AVR with PlatformIO and FreeRTOS. Watch memory, timing, interrupts and \
power, and name concrete registers and peripherals.")
    (elisp . "You are an Emacs Lisp and Doom Emacs expert. Use Doom idioms \
(use-package!, after!, map!, modulep!) and describe keys as SPC sequences.")
    (org . "You organise notes and tasks in Org mode, GTD style: short \
entries with TODO keywords, tags, dates and org-roam links where they help.")
    (commit . "Write a conventional commit message for this diff: an \
imperative subject of at most 72 characters, a blank line, then why. Output \
the message only.")
    (review . "Review this code for correctness, edge cases, security and \
readability. Cite lines, propose fixes, and rank findings by severity."))
  "Extra system prompts added to `gptel-directives'.")

(defvar +ai-hook-script (file-name-concat doom-user-dir "bin/claude-emacs-hook")
  "Script that `+ai/install-claude-hooks' wires into ~/.claude/settings.json.")

(defvar +ai-docs
  '(:groups (("ai" "AI" (vterm)
              ;; The module's own keys are in this map, not vterm's:
              ;; without it `+ai/claude-leave' and its neighbours reached
              ;; the reference with no key beside them.
              +ai-claude-keys-mode-map +ai-claude-keys-mode vterm-mode-map))
    :sections ((+ai-claude-keys-mode . "AI")
               (agent-shell-mode . "AI")))
  "How the cheat sheet documents this module; see `+docs--module-docs'.")


;;
;;; Claude Code IDE

(use-package! claude-code-ide
  :defer t
  :init
  (setq claude-code-ide-cli-path "claude"
        claude-code-ide-terminal-backend 'vterm
        claude-code-ide-use-side-window t
        claude-code-ide-window-side 'right
        ;; A transcript is mostly prose, and 72 columns is the line length
        ;; that reads best; the code keeps the rest. Diffs go to ediff anyway.
        claude-code-ide-window-width 72
        claude-code-ide-focus-on-open t
        claude-code-ide-use-ide-diff t          ; review edits in ediff
        claude-code-ide-focus-claude-after-ediff t
        claude-code-ide-enable-execute-code nil ; elisp eval is off, SPC l e
        claude-code-ide-vterm-anti-flicker t
        ;; The default swallows height-only resizes to dodge a 2025 CLI bug;
        ;; today it only leaves the TUI drawn for the old window height.
        claude-code-ide-prevent-reflow-glitch nil
        claude-code-ide-show-backend-recommendation nil)
  ;; Keys go to the Claude TUI. C-z switches to Doom's keys and back; the
  ;; C-c keys of `+ai-claude-keys-mode' work in either.
  (after! evil
    (add-to-list 'evil-buffer-regexps '("^\\*claude-code\\[" . emacs)))
  (add-hook! 'vterm-mode-hook
    (defun +ai--claude-buffer-h ()
      "Set up a Claude Code buffer: its keys, a terminal as wide as its window."
      (when (string-match-p "^\\*claude-code\\[" (buffer-name))
        (+ai-claude-keys-mode +1)
        ;; vterm never makes a terminal narrower than 80 columns, so in a
        ;; narrower side window the TUI was cut off at the right edge.
        (setq-local vterm-min-window-width 40)
        (add-hook 'kill-buffer-hook #'+ai--claude-quiet-exit-h nil t))))
  :config
  (+ai--apply-claude-model)
  ;; Tools Claude can call over MCP: xref, tree-sitter, imenu and project
  ;; from the package, the build, the inbox and the note graph from us.
  (claude-code-ide-emacs-tools-setup)
  (+ai--register-claude-tools)
  (when (modulep! :private notes)
    (+ai--register-notes-tools))
  ;; The package places its own window; keep Doom's popup manager away.
  (set-popup-rule! "^\\*claude-code\\[" :ignore t))

;; Stopping a session kills its buffer, which hangs up the pty; Claude
;; answers a hangup by exiting with 129, and the package reports every
;; nonzero exit as an error. If Claude is still alive when its buffer dies,
;; the exit that follows is ours: keep its sentinel from announcing it.
(defun +ai--claude-quiet-exit-h ()
  "Silence the exit report of a Claude session stopped from Emacs."
  (when-let* ((process (get-buffer-process (current-buffer)))
              ((process-live-p process))
              (sentinel (process-sentinel process)))
    (set-process-sentinel
     process
     (lambda (proc event)
       (let ((inhibit-message t)
             (message-log-max nil))
         (funcall sentinel proc event))))))

;; vterm hands C-c to Emacs, and M-SPC, Doom's leader in emacs state, is
;; KRunner's shortcut on KDE. So the way out of the TUI is C-c.
(define-minor-mode +ai-claude-keys-mode
  "A few Emacs keys in a Claude Code buffer; everything else goes to Claude."
  :keymap (make-sparse-keymap))

(map! :map +ai-claude-keys-mode-map
      "C-c SPC" #'doom/leader              ; the leader, as M-SPC would be
      "C-c C-o" #'+ai/claude-leave         ; back to the code, Claude stays
      "C-c C-q" #'claude-code-ide-toggle   ; hide the window, Claude runs on
      "C-c C-k" #'claude-code-ide-stop)    ; end the session

;; Every step of a drag reaches Claude, and the TUI redraws the whole screen
;; for each one, which drags Emacs down. Tell it once the window holds still.
(defvar +ai-claude-resize-delay 0.2
  "Seconds a Claude window must keep its size before Claude is told.")

(defvar-local +ai--claude-resize-timer nil)

(defadvice! +ai--claude-resize-later-a (fn process windows)
  "Delay the terminal resize in Claude buffers until the window settles."
  :around #'vterm--window-adjust-process-window-size
  (if (not (bound-and-true-p +ai-claude-keys-mode))
      (funcall fn process windows)
    (when +ai--claude-resize-timer
      (cancel-timer +ai--claude-resize-timer))
    (setq +ai--claude-resize-timer
          (run-with-timer
           +ai-claude-resize-delay nil
           (lambda (buffer)
             (when (buffer-live-p buffer)
               (with-current-buffer buffer
                 (setq +ai--claude-resize-timer nil)
                 (when-let* ((process (get-buffer-process buffer))
                             ((process-live-p process))
                             (windows (get-buffer-window-list buffer nil t))
                             (size (funcall fn process windows)))
                   (set-process-window-size process (cdr size) (car size))))))
           (current-buffer)))
    nil))


;;
;;; agent-shell (ACP)

(use-package! agent-shell
  :defer t
  :init
  ;; Signs in with the CLI's own account. For a key instead, set
  ;; `agent-shell-anthropic-authentication' with :api-key.
  (setq agent-shell-preferred-agent-config 'claude-code
        agent-shell-display-action '((display-buffer-in-side-window)
                                     (side . right)
                                     (window-width . 72))) ; same as Claude
  :config
  (set-popup-rule! "Agent @ " :ignore t))


;;
;;; gptel on the Claude API

(after! gptel
  (setq gptel-backend
        (gptel-make-anthropic "Claude"
          :stream t
          :key #'+ai--anthropic-api-key
          :models '((claude-opus-5
                     :description "Most capable, the default"
                     :capabilities (media tool-use cache json)
                     :mime-types ("image/jpeg" "image/png" "image/gif"
                                  "image/webp" "application/pdf")
                     :context-window 1000 :input-cost 5 :output-cost 25)
                    (claude-sonnet-5
                     :description "Fast, still very capable"
                     :capabilities (media tool-use cache json)
                     :mime-types ("image/jpeg" "image/png" "image/gif"
                                  "image/webp" "application/pdf")
                     :context-window 1000 :input-cost 2 :output-cost 10)
                    (claude-haiku-4-5
                     :description "Cheap and quick"
                     :capabilities (media tool-use cache)
                     :mime-types ("image/jpeg" "image/png" "image/gif"
                                  "image/webp" "application/pdf")
                     :context-window 200 :input-cost 1 :output-cost 5)))
        gptel-model 'claude-opus-5
        gptel-temperature nil           ; these models reject sampling args
        gptel-max-tokens 16000
        gptel-cache t                   ; cache the prompt prefix
        gptel-include-reasoning 'ignore ; show thinking, don't resend it
        gptel-track-media t
        gptel-default-mode 'org-mode
        gptel-org-branching-context t
        gptel-use-tools t
        gptel-confirm-tool-calls 'auto)
  ;; System prompts, pick one in gptel's menu (SPC o l m).
  (dolist (directive +ai-gptel-directives)
    (setf (alist-get (car directive) gptel-directives) (cdr directive)))
  (+ai--register-gptel-tools)
  (gptel-make-preset 'deep
    :description "Opus 5 with the Emacs tools, for careful work"
    :backend "Claude" :model 'claude-opus-5 :temperature nil
    :tools '("emacs_read_buffer" "emacs_read_file"
             "emacs_list_project_files" "emacs_grep_project"))
  (gptel-make-preset 'quick
    :description "Haiku 4.5, no tools, fast answers"
    :backend "Claude" :model 'claude-haiku-4-5 :tools nil :temperature nil))

;; gptel can use MCP servers (mcp.el): configure `mcp-hub-servers' then
;; M-x gptel-mcp-connect.
(use-package! mcp
  :defer t
  :config
  (require 'gptel-integrations nil t))


;;
;;; Keybindings

(map! :leader
      (:prefix-map ("l" . "LLM: Claude, agents, gptel")
       :desc "AI menu"                  "SPC" #'+ai/menu
       ;; Claude Code IDE
       :desc "Claude: start or focus"   "c" #'claude-code-ide
       :desc "Claude: continue"         "C" #'claude-code-ide-continue
       :desc "Claude: resume session"   "r" #'claude-code-ide-resume
       :desc "Claude: prompt"           "p" #'claude-code-ide-send-prompt
       :desc "Claude: send region"      "s" #'claude-code-ide-insert-at-mentioned
       :desc "Claude: toggle window"    "t" #'claude-code-ide-toggle
       :desc "Claude: switch buffer"    "b" #'claude-code-ide-switch-to-buffer
       :desc "Claude: sessions"         "l" #'claude-code-ide-list-sessions
       :desc "Claude: stop"             "k" #'claude-code-ide-stop
       :desc "Claude: IDE menu"         "M" #'claude-code-ide-menu
       :desc "Claude: plain terminal"   "T" #'+ai/claude-terminal
       :desc "Claude: doctor"           "d" #'+ai/claude-doctor
       :desc "Claude: set model"        "o" #'+ai/set-claude-model
       :desc "Claude: elisp tool"       "e" #'+ai/toggle-execute-code
       ;; agent-shell
       :desc "Agent shell (ACP)"        "a" #'agent-shell
       :desc "Agent shell: new/choose"  "A" #'agent-shell-new-shell
       :desc "Agent shell: compose"     "v" #'agent-shell-prompt-compose
       :desc "Agent shell: send region" "x" #'agent-shell-send-region-to
       ;; gptel is on Doom's SPC o l; the menu gathers it.
       ;; management
       :desc "CLAUDE.md (project)"      "f" #'+ai/open-claude-md
       :desc "Claude settings.json"     "S" #'+ai/open-claude-settings
       :desc "New slash command"        "n" #'+ai/new-slash-command
       :desc "Install Emacs hooks"      "h" #'+ai/install-claude-hooks
       :desc "Log session to org"       "L" #'+ai/log-session))
