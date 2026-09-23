;;; private/ai/autoload/menu.el -*- lexical-binding: t; -*-

(require 'transient)

(defvar +ai-claude-model)
(defvar claude-code-ide-enable-execute-code)
(defvar gptel-model)

(defun +ai--menu-description ()
  "Header for `+ai/menu'."
  (format "%s   claude: %s%s   gptel: %s"
          (propertize "AI" 'face 'bold)
          (if (executable-find "claude")
              "ready"
            (propertize "CLI missing" 'face 'error))
          (if +ai-claude-model (format " (%s)" +ai-claude-model) "")
          (if (boundp 'gptel-model) gptel-model "starts on first use")))

;;;###autoload (autoload '+ai/menu "private/ai/autoload/menu" nil t)
(transient-define-prefix +ai/menu ()
  "AI hub: Claude Code IDE, agent shells, gptel and agent management."
  [:description +ai--menu-description
   ["Claude Code IDE"
    ("c" "Start or focus"       claude-code-ide)
    ("C" "Continue last"        claude-code-ide-continue)
    ("r" "Resume session..."    claude-code-ide-resume)
    ("p" "Send prompt"          claude-code-ide-send-prompt)
    ("s" "Send selection (@)"   claude-code-ide-insert-at-mentioned)
    ("t" "Toggle window"        claude-code-ide-toggle)
    ("b" "Switch to buffer"     claude-code-ide-switch-to-buffer)
    ("l" "List sessions"        claude-code-ide-list-sessions)
    ("k" "Stop session"         claude-code-ide-stop)
    ("M" "IDE package menu"     claude-code-ide-menu)]
   ["Agent shell (ACP)"
    ("a" "Claude shell (DWIM)"  agent-shell)
    ("A" "New shell, any agent" agent-shell-new-shell)
    ("v" "Compose prompt"       agent-shell-prompt-compose)
    ("x" "Send region"          agent-shell-send-region-to)
    ("X" "Send file"            agent-shell-send-file-to)
    ("B" "Switch shell buffer"  agent-shell-switch-buffer)
    ("R" "Resume ACP session"   agent-shell-resume-session)
    ("i" "Interrupt"            agent-shell-interrupt)]
   ["gptel (Claude API)"
    ("g" "Chat buffer"          gptel)
    ("G" "Menu, model, tools"   gptel-menu)
    ("E" "Explain, quickly"     gptel-quick)
    ("w" "Rewrite region"       gptel-rewrite)
    ("+" "Add to context"       gptel-add)
    ("F" "Add file to context"  gptel-add-file)]]
  [["Manage"
    ("f" "CLAUDE.md"            +ai/open-claude-md)
    ("S" "~/.claude/settings"   +ai/open-claude-settings)
    ("n" "New slash command"    +ai/new-slash-command)
    ("h" "Install Emacs hooks"  +ai/install-claude-hooks)
    ("L" "Log session (org)"    +ai/log-session)]
   ["Diagnostics"
    ("o" "Set Claude model"     +ai/set-claude-model)
    ("e" "Toggle elisp tool"    +ai/toggle-execute-code)
    ("T" "Plain claude terminal" +ai/claude-terminal)
    ("d" "claude doctor"        +ai/claude-doctor)
    ("m" "claude mcp list"      +ai/claude-mcp-list)
    ("D" "IDE status"           claude-code-ide-check-status)]])
