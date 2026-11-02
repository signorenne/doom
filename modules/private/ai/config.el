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

(defvar +ai-panel-width 72
  "Width of the chat and terminal side windows.
A transcript is mostly prose, and 72 columns read best; the code keeps
the rest.")

(defvar +ai-auto-allowed-tools
  '("claude-code-ide-mcp-xref-find-references"
    "claude-code-ide-mcp-xref-find-apropos"
    "claude-code-ide-mcp-project-info"
    "claude-code-ide-mcp-imenu-list-symbols"
    "claude-code-ide-mcp-treesit-info"
    "emacs_last_compilation" "emacs_project_todos" "emacs_editor_state"
    "emacs_notes_search" "emacs_notes_list" "emacs_notes_read"
    "emacs_notes_links")
  "Emacs tools that run without asking, in chats and terminals alike.
Names without the mcp__emacs-tools__ prefix.  The others, the build and
the writers to the inbox and the notes, wait for Claude's approval.
Never empty: claude-code-ide would pass a bare --allowedTools.")

(defvar +ai-hook-script (file-name-concat doom-user-dir "bin/claude-emacs-hook")
  "Script that `+ai/install-claude-hooks' wires into ~/.claude/settings.json.")

(defvar +ai-docs
  '(:groups (("ai" "AI" (vterm)
              ;; The module's own keys are in this map, not vterm's, so
              ;; it is listed for `+ai/claude-leave' and its neighbours
              ;; to show their keys.
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
        claude-code-ide-window-width +ai-panel-width
        claude-code-ide-focus-on-open t
        claude-code-ide-use-ide-diff t          ; review edits in ediff
        claude-code-ide-focus-claude-after-ediff t
        claude-code-ide-enable-execute-code nil ; elisp eval is off, SPC l e
        ;; The read tools run unasked; the build and the writers ask.
        claude-code-ide-mcp-allowed-tools
        (mapcar (lambda (name) (concat "mcp__emacs-tools__" name))
                +ai-auto-allowed-tools)
        claude-code-ide-vterm-anti-flicker t
        ;; The default swallows height-only resizes, which leaves the TUI
        ;; drawn for the old window height.
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
        ;; vterm never makes a terminal narrower than 80 columns, which
        ;; would cut the TUI off at the right edge of a narrower window.
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
      "C-c C-k" #'claude-code-ide-stop     ; end the session
      "C-c C-e" #'+ai/terminal-compose     ; write a long prompt in a buffer
      "S-<return>" #'claude-code-ide-insert-newline  ; a newline in the prompt
      "C-<escape>" #'claude-code-ide-send-escape     ; ESC to Claude
      "C-c C-x" #'claude-code-ide-clear-selection)   ; drop the shown selection

;; After C-z, normal state is for reading Claude's screen. The keys that
;; would edit it only say how to type, the ones that insert go back to
;; Claude's prompt, and p pastes into Claude. evil's minor-mode keys rank
;; above vterm's normal-state map and evil-snipe's s, which stays.
(after! evil
  (evil-define-minor-mode-key 'normal '+ai-claude-keys-mode
    (kbd "i") #'+ai/claude-type  (kbd "a") #'+ai/claude-type
    (kbd "I") #'+ai/claude-type  (kbd "A") #'+ai/claude-type
    (kbd "o") #'+ai/claude-type  (kbd "O") #'+ai/claude-type
    (kbd "p") #'+ai/claude-paste (kbd "P") #'+ai/claude-paste
    (kbd "d") #'+ai/claude-guard (kbd "D") #'+ai/claude-guard
    (kbd "x") #'+ai/claude-guard (kbd "X") #'+ai/claude-guard
    (kbd "c") #'+ai/claude-guard (kbd "C") #'+ai/claude-guard
    (kbd "r") #'+ai/claude-guard (kbd "R") #'+ai/claude-guard
    (kbd "u") #'+ai/claude-guard)
  (evil-define-minor-mode-key 'visual '+ai-claude-keys-mode
    (kbd "d") #'+ai/claude-guard (kbd "x") #'+ai/claude-guard))

;; A buffer to write a long prompt in, sent to the terminal in one go.
;; Its keys sit in a minor mode, so other markdown buffers keep theirs.
(define-minor-mode +ai-compose-mode
  "Keys of a buffer composing a prompt for Claude's terminal."
  :keymap (make-sparse-keymap))

(map! :map +ai-compose-mode-map
      "C-c C-c" #'+ai/terminal-compose-send
      "C-c C-k" #'+ai/terminal-compose-cancel
      "M-p"     #'+ai/terminal-compose-previous
      "M-n"     #'+ai/terminal-compose-next)

;; Kept when hidden, so a draft outlives an accidental close.
(set-popup-rule! "^\\*claude-compose\\["
  :side 'bottom :size 0.25 :select t :quit nil :ttl nil)

;; The package binds its terminal keys with `local-set-key', and a vterm
;; buffer's local map is the shared `vterm-mode-map', so they reached every
;; vterm. A map of its own keeps them in the Claude buffer.
(defadvice! +ai--claude-own-keymap-a ()
  "Give the Claude buffer its own local map before the package binds keys."
  :before #'claude-code-ide--setup-terminal-keybindings
  (when (derived-mode-p 'vterm-mode)
    ;; Take back what a session before this advice left in the shared map.
    (dolist (key '("S-<return>" "C-<escape>" "C-c C-x"))
      (let ((command (keymap-lookup vterm-mode-map key)))
        (when (and (symbolp command)
                   (string-prefix-p "claude-code-ide-" (symbol-name command)))
          (keymap-unset vterm-mode-map key t))))
    (when (eq (current-local-map) vterm-mode-map)
      (let ((map (make-sparse-keymap)))
        (set-keymap-parent map vterm-mode-map)
        (use-local-map map)))))

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
  ;; `agent-shell-anthropic-authentication' with :api-key. C-u SPC l n
  ;; picks another agent.
  (setq agent-shell-preferred-agent-config 'claude-code
        agent-shell-display-action `((display-buffer-in-side-window)
                                     (side . right)
                                     (window-width . ,+ai-panel-width))
        ;; Context on request: the region, dired's files or the error at
        ;; point, never the current line by itself.
        agent-shell-context-sources '(files region error)
        ;; A new conversation each time, as VS Code; SPC l r lists the old.
        agent-shell-session-strategy 'new)
  ;; The Emacs read tools run unasked (`+ai-auto-allowed-tools'), as VS
  ;; Code's own IDE tools do; every other tool shows its buttons.
  (setq agent-shell-permission-responder-function #'+ai--chat-permission-responder)
  ;; import, the default, sees X11 windows only.
  (when (and (getenv "WAYLAND_DISPLAY") (executable-find "spectacle"))
    (setq agent-shell-screenshot-command '("spectacle" "-b" "-n" "-r" "-o")))
  :config
  ;; Each chat reaches the Emacs tools through claude-code-ide's server.
  (add-hook 'agent-shell-mode-hook #'+ai--chat-tools-h)
  ;; A chat reports through ACP events, so the hook script stays quiet.
  (setq agent-shell-anthropic-claude-environment
        (agent-shell-make-environment-variables "CLAUDE_EMACS_HOOK_SKIP" "1"))
  (set-popup-rule! "Agent @ " :ignore t)
  ;; A diff opens in the editor window, not beside the chat. The popup
  ;; module's catch-all, if it is ever turned on (+all), would take it.
  (set-popup-rule! "^\\*agent-shell-diff" :ignore t))

(defadvice! +ai--chat-diff-in-editor-a (fn &rest args)
  "Show agent-shell's diff in the editor window, not beside the chat."
  :around #'agent-shell-diff
  (let ((display-buffer-overriding-action
         '(nil (some-window . +ai--editor-window-for-display))))
    (apply fn args)))

;; evil-collection's y / n / ! / v answer the latest permission from
;; anywhere in the chat, so a yank or a search on the transcript did. With
;; them off, the keys answer only with point on the button, where its own
;; keymap (y ! v) and +ai/chat-reject (n) take them.
(setq evil-collection-agent-shell-want-permission-bindings nil)

(defvar +ai--chat-submit-key
  '(menu-item "" agent-shell-submit :filter +ai--chat-at-prompt-filter)
  "RET in normal state: submit in the prompt, evil's RET elsewhere.")

(defvar +ai--chat-reject-key
  '(menu-item "" +ai/chat-reject :filter +ai--chat-on-button-filter)
  "n in normal state: reject on a permission button, evil's n elsewhere.")

(declare-function agent-shell-cycle-session-mode "agent-shell")

;; evil-collection sets the chat's keys after any `after!' of ours runs,
;; so these go on its hook, which runs once its setup is done.
(add-hook! 'evil-collection-setup-hook
  (defun +ai--chat-evil-keys-h (mode &rest _)
    "Fix and extend evil-collection's agent-shell keys."
    (when (eq mode 'agent-shell)
      (evil-define-key* 'normal agent-shell-mode-map
        (kbd "RET") +ai--chat-submit-key
        "n" +ai--chat-reject-key
        ;; evil-collection names agent-shell-queue-request, long gone.
        "gq" #'agent-shell-prompt-queue)
      ;; M-SPC is KRunner's on KDE; C-<tab> in insert state was aya-expand.
      (evil-define-key* '(insert normal) agent-shell-mode-map
        (kbd "C-c SPC") #'doom/leader
        (kbd "C-<tab>") #'agent-shell-cycle-session-mode)
      ;; Two commands evil-collection binds here never existed.
      (evil-define-key* 'normal agent-shell-viewport-view-mode-map
        "gF" #'agent-shell-fork
        "ge" nil))))

;; The responder needs the tool's own name, which the model cannot write;
;; agent-shell keeps only the title, and for a shell command that is the
;; model's description.
(defvar +ai--chat-permission-request nil
  "The ACP request agent-shell is handling, while its responder runs.")

(defadvice! +ai--chat-permission-request-a (fn &rest args)
  "Let the permission responder read the request agent-shell handles."
  :around #'agent-shell--on-request
  (let ((+ai--chat-permission-request (plist-get args :acp-request)))
    (apply fn args)))


;;
;;; gptel on the Claude API

(after! gptel
  (setq gptel-backend
        (gptel-make-anthropic "Claude"
          :stream t
          :key #'+ai-anthropic-api-key
          :models '((claude-opus-5-5
                     :description "Most capable, the default"
                     :capabilities (media tool-use cache json)
                     :mime-types ("image/jpeg" "image/png" "image/gif"
                                  "image/webp" "application/pdf")
                     :context-window 1000 :input-cost 4 :output-cost 20)
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
        gptel-model 'claude-opus-5-5
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
    :description "Opus 5.5 with the Emacs tools, for careful work"
    :backend "Claude" :model 'claude-opus-5-5 :temperature nil
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
       :desc "Claude: start or focus"   "c" #'+ai/terminal
       :desc "Claude: continue"         "C" #'claude-code-ide-continue
       :desc "Claude: resume session"   "r" #'claude-code-ide-resume
       :desc "Claude: compose prompt"   "p" #'+ai/terminal-compose
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
       :desc "Chat: open or focus"      "a" #'+ai/chat
       :desc "Chat: new, C-u any agent" "A" #'+ai/chat-new
       :desc "Agent shell: compose"     "v" #'agent-shell-prompt-compose
       :desc "Chat: send region"        "x" #'agent-shell-send-region
       ;; gptel is on Doom's SPC o l; the menu gathers it.
       ;; management
       :desc "CLAUDE.md (project)"      "f" #'+ai/open-claude-md
       :desc "Claude settings.json"     "S" #'+ai/open-claude-settings
       :desc "New slash command"        "n" #'+ai/new-slash-command
       :desc "Install Emacs hooks"      "h" #'+ai/install-claude-hooks
       :desc "Log session to org"       "L" #'+ai/log-session))
