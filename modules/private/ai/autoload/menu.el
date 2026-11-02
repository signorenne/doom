;;; private/ai/autoload/menu.el -*- lexical-binding: t; -*-

(require 'transient)

(defvar +ai--attention)
(defvar +ai-claude-model)
(defvar +ai-inline-backend)
(defvar agent-shell--state)
(defvar gptel-backend)
(defvar transient--original-buffer)
(declare-function +ai--chat-buffer "chat")
(declare-function agent-shell-get-mode-name "agent-shell")
(declare-function agent-shell-get-model-name "agent-shell")
(declare-function gptel-backend-key "gptel-request")
(declare-function gptel-backend-name "gptel-request")
(declare-function gptel-ollama-p "gptel-ollama")
(declare-function shell-maker-busy "shell-maker")

(defun +ai--menu-chat ()
  "What the hub says about this project's chat; no process is started."
  (if-let* (((featurep 'agent-shell))
            (chat (+ai--chat-buffer)))
      (with-current-buffer chat
        (let ((mode (ignore-errors (agent-shell-get-mode-name agent-shell--state)))
              (model (ignore-errors (agent-shell-get-model-name agent-shell--state))))
          (concat (cond ((eq (nth 1 (assq chat (bound-and-true-p +ai--attention))) 'permission)
                         (propertize "waiting for permission" 'face 'warning))
                        ((shell-maker-busy) "busy")
                        (t "running"))
                  (if mode (format ", %s" mode) "")
                  (if model (format ", %s" model) ""))))
    "none"))

(defun +ai--menu-inline ()
  "Where inline requests go, as far as can be told without asking a key
store: an environment key or a key written in the backend counts."
  (let* ((backend (and (featurep 'gptel) (bound-and-true-p gptel-backend)))
         (key (and backend (gptel-backend-key backend)))
         (ready (or (eq +ai-inline-backend 'gptel)
                    (and (not (eq +ai-inline-backend 'claude-cli))
                         (or (and backend (fboundp 'gptel-ollama-p)
                                  (gptel-ollama-p backend))
                             (and (stringp key) (not (string-empty-p key)))
                             (not (string-empty-p (or (getenv "ANTHROPIC_API_KEY") ""))))))))
    (if ready
        (format "gptel: %s" (if backend (gptel-backend-name backend) "Claude"))
      (concat (if (executable-find "claude")
                  "claude CLI"
                (propertize "no backend" 'face 'error))
              "   gptel: no key"))))

(defmacro +ai--menu-here (&rest body)
  "Run BODY in the buffer the menu was opened from."
  `(with-current-buffer (or (bound-and-true-p transient--original-buffer)
                            (current-buffer))
     ,@body))

(defun +ai--menu-description ()
  "Header for `+ai/menu'."
  (+ai--menu-here
    (format "%s   chat: %s   terminals: %d%s   inline: %s"
            (propertize "AI" 'face 'bold)
            (+ai--menu-chat)
            (seq-count (lambda (buffer)
                         (string-prefix-p "*claude-code[" (buffer-name buffer)))
                       (buffer-list))
            (if +ai-claude-model (format " (%s)" +ai-claude-model) "")
            (+ai--menu-inline))))

;;;###autoload (autoload '+ai/menu "private/ai/autoload/menu" nil t)
(transient-define-prefix +ai/menu ()
  "AI hub: the chat, the Claude terminal, inline actions, gptel and the
agents' files, on the keys they have after SPC l."
  [:description +ai--menu-description
   ["Chat"
    ("l" "Open or focus"         +ai/chat)
    ("n" "New, C-u any agent"    +ai/chat-new)
    ("r" "Resume a session"      +ai/chat-resume)
    ("b" "Switch chat"           agent-shell-switch-buffer)
    ("h" "Hide"                  +ai/chat-hide)
    ("k" "Stop"                  +ai/chat-stop)
    ("i" "Interrupt"             +ai/chat-interrupt)
    ("j" "Go to what needs you"  +ai/attend)
    ("o" "Mode, model, thought"  +ai/chat-options)]
   ["Context"
    ("s" "Send region"           agent-shell-send-region)
    ("f" "Send file"             agent-shell-send-file)
    ("@" "Mention file, lines"   +ai/chat-mention)
    ("c" "Compose prompt"        agent-shell-prompt-compose)]
   ["Session"
    ("v" "Transcript"            +ai/chat-transcript)]
   ["Inline"
    ("e" "Rewrite region"        +ai/inline-rewrite)
    ("x" "Explain"               +ai/inline-explain)
    ("a" "Ask"                   +ai/inline-ask)
    ("C" "Cancel the request"    +ai/inline-cancel)]]
  [["Claude terminal"
    ("tc" "Focus or start"       +ai/terminal)
    ("tn" "New instance"         claude-code-ide)
    ("tC" "Continue last"        claude-code-ide-continue)
    ("tr" "Resume a session"     claude-code-ide-resume)
    ("tt" "Toggle window"        claude-code-ide-toggle)
    ("tk" "Stop"                 claude-code-ide-stop)
    ("tp" "Compose prompt"       +ai/terminal-compose)
    ("ts" "Send selection (@)"   claude-code-ide-insert-at-mentioned)
    ("tl" "List sessions"        claude-code-ide-list-sessions)
    ("tm" "IDE package menu"     claude-code-ide-menu)
    ("tT" "Plain terminal"       +ai/claude-terminal)
    ("to" "Set model"            +ai/set-claude-model)
    ("te" "Toggle elisp tool"    +ai/toggle-execute-code)]
   ["gptel"
    ("gg" "Chat buffer"          gptel)
    ("gm" "Menu, model, tools"   gptel-menu)
    ("g+" "Add to context"       gptel-add)
    ("gf" "Add file to context"  gptel-add-file)]
   ["Manage"
    ("mc" "CLAUDE.md"            +ai/open-claude-md)
    ("ms" "~/.claude/settings"   +ai/open-claude-settings)
    ("mn" "New slash command"    +ai/new-slash-command)
    ("mh" "Install Emacs hooks"  +ai/install-claude-hooks)
    ("ml" "Log session (org)"    +ai/log-session)
    ("md" "claude doctor"        +ai/claude-doctor)
    ("mp" "claude mcp list"      +ai/claude-mcp-list)]
   ["Diagnostics"
    ("mt" "Chat's ACP traffic"   +ai/chat-traffic)
    ("D" "IDE status"            claude-code-ide-check-status)]])

;;;###autoload (autoload '+ai/chat-options "private/ai/autoload/menu" nil t)
(transient-define-prefix +ai/chat-options ()
  "The permission mode, the model and the thought level of this project's
chat, from any buffer."
  [:description (lambda () (+ai--menu-here (format "Chat: %s" (+ai--menu-chat))))
   ["Session"
    ("m" "Set mode"              +ai/chat-set-mode)
    ("c" "Cycle mode"            +ai/chat-cycle-mode)
    ("o" "Model"                 +ai/chat-set-model)
    ("t" "Thought level"         +ai/chat-set-thought-level)]])
