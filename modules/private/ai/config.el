;;; private/ai/config.el -*- lexical-binding: t; -*-
;;
;; Ways to work with agents, all under SPC l (see +ai/menu):
;;   agent-shell      the chat, an Emacs buffer in a side panel over ACP,
;;                    with permission buttons and diffs (SPC l l).
;;   claude-code-ide  Claude Code's own terminal, the fallback (SPC l t).
;;   inline           rewrite, explain, ask, commit message: gptel with a
;;                    key, else the claude CLI (SPC l e, x, a).
;;   gptel            chat and context against the API (SPC l g).
;; Both the chat and the terminal reach the Emacs tools over MCP.

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

(defvar +ai-chat-output-lines 100
  "Lines of a terminal's or a build's output SPC l O puts into the chat.")

(defvar +ai-tool-search-seconds 5
  "Seconds the project TODO search may hold Emacs before it stops with
what it found.")

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

(defvar +ai-notify t
  "Non-nil to send a desktop notification when a hidden chat or terminal
needs you or finishes.")

(defface +ai-status-permission '((t :inherit warning))
  "The modeline's AI entry while a permission is pending."
  :group 'faces)

(defface +ai-status-done '((t :inherit success))
  "The modeline's AI entry when a hidden chat or terminal is done."
  :group 'faces)

(defvar +ai-hook-script (file-name-concat doom-user-dir "bin/claude-emacs-hook")
  "Script that `+ai/install-claude-hooks' wires into ~/.claude/settings.json.")

(defvar +ai-claude-settings-file "~/.claude/settings.json"
  "Claude Code's user settings, where `+ai/install-claude-hooks' writes.")

(defvar +ai-docs
  '(:groups (("ai" "AI" (vterm agent-shell git-commit)
              ;; The module's own keys are in these maps, not vterm's or
              ;; the chat's, so they are listed for `+ai/claude-leave',
              ;; the compose, rewrite and answer commands to show theirs.
              +ai-claude-keys-mode-map +ai-claude-keys-mode vterm-mode-map
              +ai-compose-mode-map +ai-compose-mode
              +ai-rewrite-mode-map +ai-rewrite-mode
              +ai-answer-mode-map +ai-answer-mode
              agent-shell-mode-map git-commit-mode-map))
    :sections ((+ai-claude-keys-mode . "AI")
               (+ai-compose-mode . "AI")
               (+ai-rewrite-mode . "AI")
               (+ai-answer-mode . "AI")
               (agent-shell-mode . "AI")))
  "How the cheat sheet documents this module; see `+docs--module-docs'.")


;;
;;; Status

;; Who needs you, in the modeline: a string remade only when that
;; changes (autoload/status.el), so redisplay formats nothing for it.
(defvar +ai--status-string ""
  "The modeline's AI entry: empty, or the chat or terminal that needs you.")
(put '+ai--status-string 'risky-local-variable t)
(add-to-list 'mode-line-misc-info '+ai--status-string)

;; An agent's turns and edits, for other modules: the git views take the
;; project as it was when a turn began as a baseline, and follow edits
;; (autoload/turn.el, git/autoload/live.el).
(defvar +ai-turn-functions nil
  "Called with ROOT and TREE when an agent's turn begins in the
repository whose toplevel is ROOT; TREE is its working tree then.")

(defvar +ai-edit-functions nil
  "Called with ROOT and FILES when an agent's edit lands in the
repository or directory ROOT; FILES nil means anything under ROOT.")


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
        claude-code-ide-enable-execute-code nil ; elisp eval is off, SPC l t e
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
      "C-c C-k" #'+ai/terminal-stop        ; end the session, after asking
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
;; The package's file tools open any path they are given; these keep them
;; to the session's project, like the rest of the Emacs tools.
(defadvice! +ai--tool-path-first-a (fn file-path &rest args)
  "Refuse FILE-PATH when it is outside the session's project."
  :around '(claude-code-ide-mcp-imenu-list-symbols claude-code-ide-mcp-treesit-info)
  (when file-path
    (+ai--tool-check-path file-path))
  (apply fn file-path args))

(defadvice! +ai--tool-path-second-a (fn first file-path)
  "Refuse FILE-PATH when it is outside the session's project."
  :around '(claude-code-ide-mcp-xref-find-references claude-code-ide-mcp-xref-find-apropos)
  (when file-path
    (+ai--tool-check-path file-path))
  (funcall fn first file-path))

(declare-function claude-code-ide--get-working-directory "claude-code-ide")

;; The terminal's --allowedTools names the tools by server name; when
;; another server shares it, they ask like any other tool.
(defadvice! +ai--claude-allowed-tools-a (command)
  "Drop --allowedTools from COMMAND when another server is named emacs-tools."
  :filter-return #'claude-code-ide--build-claude-command
  (if-let* ((taken (+ai--tools-name-taken (claude-code-ide--get-working-directory))))
      (progn
        (message "%s, so the Emacs tools ask first" taken)
        (replace-regexp-in-string " --allowedTools .*\\'" "" command))
    command))

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
  ;; SPC l s, f, b and the hub's keys; the package autoloads none of them.
  :commands (agent-shell-send-region agent-shell-send-file agent-shell-switch-buffer)
  :init
  ;; Signs in with the CLI's own account. For a key instead, set
  ;; `agent-shell-anthropic-authentication' with :api-key. C-u SPC l n
  ;; picks another agent.
  (setq agent-shell-preferred-agent-config 'claude-code
        agent-shell-display-action `((display-buffer-in-side-window)
                                     (side . right)
                                     ;; Above the Claude terminals, whose
                                     ;; slots start at 0, so both show.
                                     (slot . -1)
                                     (window-width . ,+ai-panel-width))
        ;; Context on request: the region, dired's files or the error at
        ;; point, never the current line by itself.
        agent-shell-context-sources '(files region error)
        ;; A new conversation each time, as VS Code; SPC l r lists the old.
        agent-shell-session-strategy 'new
        ;; Auto, as VS Code starts its sessions: a classifier lets safe
        ;; actions run and stops risky ones. C-<tab> or SPC l o for Manual.
        agent-shell-anthropic-default-session-mode-id "auto")
  ;; The Emacs read tools run unasked (`+ai-auto-allowed-tools'), as VS
  ;; Code's own IDE tools do; every other tool shows its buttons.
  (setq agent-shell-permission-responder-function #'+ai--chat-permission-responder)
  ;; import, the default, sees X11 windows only.
  (when (and (getenv "WAYLAND_DISPLAY") (executable-find "spectacle"))
    (setq agent-shell-screenshot-command '("spectacle" "-b" "-n" "-r" "-o")))
  :config
  ;; Each chat reaches the Emacs tools through claude-code-ide's server,
  ;; and tells the status when it waits for you or finishes unseen.
  (add-hook 'agent-shell-mode-hook #'+ai--chat-tools-h)
  (add-hook 'agent-shell-mode-hook #'+ai--chat-status-h)
  ;; An open buffer of a file the chat edits shows the edit as it lands.
  (add-hook 'agent-shell-mode-hook #'+ai--chat-reload-h)
  ;; Each prompt sent snapshots the project, the git views' "agent turn".
  (add-hook 'agent-shell-mode-hook #'+ai--chat-turn-h)
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
(declare-function evil-normal-state-p "evil-states")

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

(defvar +ai--chat-permission-buffer nil
  "The chat whose request agent-shell is handling, while its responder runs.")

(defadvice! +ai--chat-permission-request-a (fn &rest args)
  "Let the permission responder read the request agent-shell handles."
  :around #'agent-shell--on-request
  (let ((+ai--chat-permission-request (plist-get args :acp-request))
        (+ai--chat-permission-buffer (map-elt (plist-get args :state) :buffer)))
    (apply fn args)))

;; A request that came in moved point onto its buttons in every window of
;; the chat, and so did one the responder answered, onto any still open:
;; a y typed at the prompt answered it. Point stays; SPC l j goes there.
(defadvice! +ai--chat-point-stays-a (fn &rest args)
  "Leave point alone while agent-shell handles a request from the agent."
  :around #'agent-shell-jump-to-latest-permission-button-row
  ;; Non-nil as if it had jumped, or the caller goes to the end instead.
  (or +ai--chat-permission-request
      (apply fn args)))

;; A button's keys sit in a text property keymap, above evil's, so they
;; answered in insert state too. Its y, n and ! answer in normal state
;; only; in another state they go on to evil's maps, and type nothing.
(defun +ai--chat-answer-key-filter (command)
  "COMMAND in normal state, or with evil off; else nil."
  (and (or (not (bound-and-true-p evil-local-mode))
           (evil-normal-state-p))
       command))

(defadvice! +ai--chat-answer-keys-a (&rest args)
  "Let a permission button's y, n and ! answer in normal state only."
  :before #'agent-shell--make-permission-button
  ;; The buttons of a request share one keymap: changed once, in place.
  (when-let* ((keymap (plist-get args :keymap)))
    (dolist (key '(?y ?n ?!))
      (when-let* ((entry (assq key (cdr keymap)))
                  ((not (eq (car-safe (cdr entry)) 'menu-item))))
        (setcdr entry `(menu-item "" ,(cdr entry)
                                  :filter +ai--chat-answer-key-filter))))))


;;
;;; Inline actions (autoload/inline.el)

(defvar +ai-inline-backend 'auto
  "Where rewrite, explain, ask and the commit message go: auto, gptel or
claude-cli.  auto takes gptel once it has a key, or a key-less backend
such as Ollama, else the claude CLI with its own sign-in.")

(defvar +ai-inline-model "sonnet"
  "The model the claude CLI answers inline requests with.")

(defvar +ai-inline-context-lines 30
  "Lines on each side of a region sent along to read, not to rewrite.")

(defface +ai-inline-pending '((t :inherit secondary-selection))
  "The region while a rewrite of it runs."
  :group 'faces)

;; The rewrite's diff: y or C-c C-c accepts, n or C-c C-k rejects. Its
;; labels name no file, and RET and ga, diff-mode's ways to the source,
;; do nothing, so the diff never touches the file itself.
(define-minor-mode +ai-rewrite-mode
  "Keys of the *ai-rewrite* diff: accept, reject, ediff, retry."
  :keymap (make-sparse-keymap))

(map! :map +ai-rewrite-mode-map
      "C-c C-c" #'+ai/inline-rewrite-accept
      "C-c C-k" #'+ai/inline-rewrite-reject
      "RET"     #'ignore)

(after! evil
  (evil-define-minor-mode-key 'normal '+ai-rewrite-mode
    (kbd "y")   #'+ai/inline-rewrite-accept
    (kbd "gy")  #'+ai/inline-rewrite-accept
    (kbd "n")   #'+ai/inline-rewrite-reject
    (kbd "gn")  #'+ai/inline-rewrite-reject
    (kbd "e")   #'+ai/inline-rewrite-ediff
    (kbd "r")   #'+ai/inline-rewrite-retry
    (kbd "RET") #'ignore
    (kbd "ga")  #'ignore))

(define-minor-mode +ai-answer-mode
  "Keys of the *ai-answer* buffer: C-c C-c takes it to the chat."
  :keymap (make-sparse-keymap))

(map! :map +ai-answer-mode-map
      "C-c C-c" #'+ai/inline-answer-to-chat)

;; The diff comes when the answer does, maybe while you type elsewhere, so
;; it never takes the cursor; an answer opens as you ask, and takes it.
(set-popup-rule! "^\\*ai-rewrite\\*" :side 'bottom :size 0.3 :select nil :quit t)
(set-popup-rule! "^\\*ai-answer\\*" :side 'bottom :size 0.3 :select t :quit t)

;; What claude mcp says opens the same way, the cursor left where it was;
;; ESC or q closes it. Kept: the command may still be writing to it. The
;; terminals of the claude, cloud, agent and doctor commands are no
;; popups: Claude's screen reads ESC and q itself, so they keep the
;; window they open in, as the bridge's terminals do.
(set-popup-rule! "^\\*claude mcp\\*$" :side 'bottom :size 0.3 :select nil :quit t :ttl nil)

;; M-g in a commit buffer writes the message. gptel-magit-install binds M-g
;; and M-r again on every magit-mode-hook, so its commands are remapped too;
;; a commit started from a shell never runs that hook, so M-g is bound here.
(after! git-commit
  (map! :map git-commit-mode-map
        "M-g" #'+ai/inline-commit-message
        [remap gptel-magit-generate-message] #'+ai/inline-commit-message
        [remap gptel-magit-generate-message-with-rationale] #'+ai/inline-commit-message))


;;
;;; gptel on the Claude API

(after! gptel
  ;; gptel's own list of Claude models, which moves with gptel.
  (setq gptel-backend (gptel-make-anthropic "Claude"
                        :stream t
                        :key #'+ai-anthropic-api-key)
        gptel-model 'claude-opus-5-5
        gptel-max-tokens 16000
        gptel-cache t                   ; cache the prompt prefix
        gptel-track-media t
        gptel-org-branching-context t)
  ;; System prompts, pick one in gptel's menu (SPC l g m).
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
    :backend "Claude" :model 'claude-haiku-4-5-20251001 :tools nil :temperature nil))

;; gptel can use MCP servers (mcp.el): configure `mcp-hub-servers' then
;; M-x gptel-mcp-connect.
(use-package! mcp
  :defer t
  :config
  (require 'gptel-integrations nil t))


;;
;;; Keybindings

(map! :leader
      (:prefix-map ("l" . "AI: chat, terminal, inline, gptel")
       :desc "AI hub"                     "SPC" #'+ai/menu
       ;; The chat, on the short keys
       :desc "Chat: open or focus"        "l" #'+ai/chat
       :desc "Chat: new, C-u any agent"   "n" #'+ai/chat-new
       :desc "Chat: resume a session"     "r" #'+ai/chat-resume
       :desc "Chat: switch"               "b" #'agent-shell-switch-buffer
       :desc "Chat: hide"                 "q" #'+ai/chat-hide
       :desc "Chat: stop"                 "k" #'+ai/chat-stop
       :desc "Chat: interrupt"            "i" #'+ai/chat-interrupt
       :desc "Chat: mode, model, thought" "o" #'+ai/chat-options
       :desc "Chat: transcript"           "v" #'+ai/chat-transcript
       :desc "Chat: full window"          "w" #'+ai/chat-window
       :desc "Chat: own frame"            "W" #'+ai/chat-frame
       :desc "Chat: fold tool calls"      "z" #'+ai/chat-focus
       :desc "Go to what needs you"       "j" #'+ai/attend
       :desc "Send region to chat"        "s" #'agent-shell-send-region
       :desc "Send file to chat"          "f" #'agent-shell-send-file
       :desc "Mention file and lines"     "@" #'+ai/chat-mention
       :desc "Terminal output to chat"    "O" #'+ai/chat-send-output
       :desc "Compose a chat prompt"      "c" #'agent-shell-prompt-compose
       ;; Inline actions
       :desc "Rewrite region"             "e" #'+ai/inline-rewrite
       :desc "Explain"                    "x" #'+ai/inline-explain
       :desc "Ask"                        "a" #'+ai/inline-ask
       (:prefix ("t" . "Claude terminal")
        :desc "Focus or start"            "c" #'+ai/terminal
        :desc "New instance"              "n" #'claude-code-ide
        :desc "Continue last"             "C" #'claude-code-ide-continue
        :desc "Resume a session"          "r" #'claude-code-ide-resume
        :desc "Toggle window"             "t" #'claude-code-ide-toggle
        :desc "Stop"                      "k" #'claude-code-ide-stop
        :desc "Compose prompt"            "p" #'+ai/terminal-compose
        :desc "Send selection (@)"        "s" #'claude-code-ide-insert-at-mentioned
        :desc "List sessions"             "l" #'claude-code-ide-list-sessions
        :desc "IDE package menu"          "m" #'claude-code-ide-menu
        :desc "Plain terminal"            "T" #'+ai/claude-terminal
        :desc "Set model"                 "o" #'+ai/set-claude-model
        :desc "Toggle the elisp tool"     "e" #'+ai/toggle-execute-code
        :desc "In a new worktree"         "w" #'+ai/terminal-worktree)
       (:prefix ("d" . "remote: cloud, background")
        :desc "Terminal with Remote Control" "r" #'+ai/terminal-remote
        :desc "Open a cloud session here" "w" #'+ai/terminal-teleport
        :desc "Task to the cloud"         "c" #'+ai/cloud-task
        :desc "Task to a background agent" "b" #'+ai/agent-dispatch
        :desc "Background agents"         "a" #'+ai/agents
        :desc "Attach to an agent"        "t" #'+ai/agent-attach)
       (:prefix ("g" . "gptel")
        :desc "Chat buffer"               "g" #'gptel
        :desc "Menu, model, tools"        "m" #'gptel-menu
        :desc "Add to context"            "+" #'gptel-add
        :desc "Add file to context"       "f" #'gptel-add-file)
       (:prefix ("m" . "manage")
        :desc "CLAUDE.md (project)"       "c" #'+ai/open-claude-md
        :desc "Claude settings.json"      "s" #'+ai/open-claude-settings
        :desc "New slash command"         "n" #'+ai/new-slash-command
        :desc "Install Emacs hooks"       "h" #'+ai/install-claude-hooks
        :desc "Log session to org"        "l" #'+ai/log-session
        :desc "claude doctor"             "d" #'+ai/claude-doctor
        :desc "claude mcp list"           "p" #'+ai/claude-mcp-list
        :desc "Chat's ACP traffic"        "t" #'+ai/chat-traffic
        :desc "MCP, hooks, permissions"   "m" #'+ai/claude-config
        :desc "Usage and limits"          "u" #'+ai/claude-usage)))
