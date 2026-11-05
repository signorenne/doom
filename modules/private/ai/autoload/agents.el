;;; private/ai/autoload/agents.el -*- lexical-binding: t; -*-
;;
;; Managing Claude Code from Emacs: CLAUDE.md, settings, slash commands,
;; hooks and session logs.

(defvar +ai-hook-script)
(defvar +ai-claude-settings-file)
(defvar +ai-edit-functions)
(declare-function +ai--turn-root "turn")
(declare-function +ai--turn-snapshot "turn")
(declare-function +ai--chat-buffer "chat")
(declare-function +ai--chat-start-quietly "chat")
(declare-function +ai--claude-mcp "claude")
(declare-function +ai--read-json "claude")
(declare-function +cpp-preset-names "kit")
(declare-function agent-shell--prompt-input-start "agent-shell-prompt")
(declare-function agent-shell-insert "agent-shell")
(declare-function org-capture "org-capture")

(defun +ai--claude-md-commands (root)
  "Build commands to suggest in a new CLAUDE.md for ROOT: PlatformIO's,
CMake's with the project's first preset when it has presets, else make."
  (cond ((file-exists-p (expand-file-name "platformio.ini" root))
         (concat "- Build: `pio run`, upload: `pio run -t upload`\n"
                 "- Tests: `pio test`\n"
                 "- Index for clangd: `pio run -t compiledb`\n"))
        ((file-exists-p (expand-file-name "CMakeLists.txt" root))
         (concat
          (if-let* ((preset (and (modulep! :private cpp)
                                 (fboundp '+cpp-preset-names)
                                 (car (+cpp-preset-names root)))))
              (format (concat "- Configure: `cmake --preset %s`\n"
                              "- Build: `cmake --build --preset %s`\n"
                              "- Tests: `ctest --preset %s`\n")
                      preset preset preset)
            (concat "- Configure: `cmake -S . -B build`\n"
                    "- Build: `cmake --build build`\n"
                    "- Tests: `ctest --test-dir build`\n"))
          "- The emacs_build_project tool builds from Emacs and "
          "returns the errors.\n"))
        (t "- Build: `make`\n")))

;;;###autoload
(defun +ai/open-claude-md ()
  "Open this project's CLAUDE.md, offering to create one."
  (interactive)
  (let* ((root (+core-project-root 'noerror))
         (file (expand-file-name "CLAUDE.md" root)))
    (unless (file-exists-p file)
      (when (y-or-n-p (format "No CLAUDE.md in %s.  Create one? "
                              (abbreviate-file-name root)))
        (with-temp-file file
          (insert "# " (file-name-nondirectory (directory-file-name root))
                  "\n\n## What this project is\n\n(one paragraph)\n"
                  "\n## Build, test, run\n\n"
                  (+ai--claude-md-commands root)
                  "\n## Conventions\n\n"
                  "- Code style: see .clang-format or .editorconfig\n"
                  "- Commit messages: conventional commits\n"
                  "\n## Gotchas\n\n- \n"))))
    (when (file-exists-p file) (find-file file))))

;;;###autoload
(defun +ai/open-claude-settings (&optional project)
  "Open ~/.claude/settings.json; with prefix PROJECT, the project's own file."
  (interactive "P")
  (find-file (if project
                 (expand-file-name ".claude/settings.json" (+core-project-root 'noerror))
               (expand-file-name "~/.claude/settings.json"))))

;;;###autoload
(defun +ai/new-slash-command (name description &optional global)
  "Create the slash command NAME (.claude/commands/NAME.md) with DESCRIPTION.
With prefix GLOBAL, create it in ~/.claude/commands instead of the project."
  (interactive (let ((name (read-string "Command name (without /): ")))
                 ;; Refused before the description is asked for.
                 (when (string-blank-p name)
                   (user-error "No command name"))
                 (list name (read-string "Description: ") current-prefix-arg)))
  ;; An empty one would write .md, a command with no name.
  (when (string-blank-p name)
    (user-error "No command name"))
  (let* ((dir (if global (expand-file-name "~/.claude/commands/")
                (expand-file-name ".claude/commands/" (+core-project-root 'noerror))))
         (file (expand-file-name (concat name ".md") dir)))
    (make-directory dir t)
    (when (or (not (file-exists-p file))
              (y-or-n-p "Command exists.  Overwrite? "))
      (with-temp-file file
        ;; No description, no front matter: it holds nothing else.
        (unless (string-blank-p description)
          (insert "---\ndescription: " (string-trim description) "\n---\n\n"))
        (insert "<!-- $ARGUMENTS is replaced by what follows /" name " -->\n\n"
                "Do the following for: $ARGUMENTS\n\n1. \n2. \n")))
    (find-file file)
    (message "Use it inside Claude Code as /%s <arguments>" name)))


;;
;;; Letting Claude Code notify Emacs

(defvar +ai--hook-events
  '(("Stop" . "stop") ("Notification" . "notification")
    ("UserPromptSubmit" . "prompt"))
  "Hook events `+ai/install-claude-hooks' installs, and their arguments.")

(defun +ai--hook-entry (event-name)
  "A settings.json entry running the hook script for EVENT-NAME."
  `((hooks . [((type . "command")
               (command . ,(format "%s %s"
                                   (shell-quote-argument +ai-hook-script)
                                   event-name)))])))

;;;###autoload
(defun +ai/install-claude-hooks ()
  "Tell Claude Code to notify Emacs when it stops, needs input or is sent
a prompt. Writes to `+ai-claude-settings-file', keeping a .bak copy.
Safe to re-run."
  (interactive)
  ;; Checked before the file is read, so a missing script gets a clear
  ;; message rather than a parse error from a hand-edited settings.json.
  (unless (file-executable-p +ai-hook-script)
    (user-error "Hook script %s is missing or not executable" +ai-hook-script))
  (let* ((file (expand-file-name +ai-claude-settings-file))
         (settings (if (file-exists-p file)
                       (with-temp-buffer
                         (insert-file-contents file)
                         ;; Keep JSON false/null distinguishable from nil so the
                         ;; rest of the file round-trips unchanged.
                         (json-parse-buffer :object-type 'alist
                                            :array-type 'array
                                            :null-object :null
                                            :false-object :false))
                     nil))
         (hooks (alist-get 'hooks settings))
         (changed nil))
    (dolist (event +ai--hook-events)
      (let* ((key (intern (car event)))
             (existing (alist-get key hooks))
             (already
              (seq-some
               (lambda (entry)
                 (seq-some (lambda (h)
                             (string-match-p (regexp-quote +ai-hook-script)
                                             (or (alist-get 'command h) "")))
                           (alist-get 'hooks entry)))
               (append existing nil))))
        (unless already
          (setf (alist-get key hooks)
                (vconcat (append existing nil)
                         (list (+ai--hook-entry (cdr event)))))
          (setq changed t))))
    (if (not changed)
        (message "Hooks already installed in %s"
                 (abbreviate-file-name file))
      (when (y-or-n-p (format "Write hooks into %s (a .bak is kept)? "
                              (abbreviate-file-name file)))
        (setf (alist-get 'hooks settings) hooks)
        (when (file-exists-p file) (copy-file file (concat file ".bak") t))
        (make-directory (file-name-directory file) t)
        (with-temp-file file
          (insert (json-serialize settings
                                  :null-object :null :false-object :false))
          (json-pretty-print-buffer))
        (message "Hooks installed in %s, backup in settings.json.bak"
                 (abbreviate-file-name file))))))

;;;###autoload
(defun +ai--claude-event (event dir &optional port)
  "Handle hook EVENT for project DIR.  Called by emacsclient.
PORT, the terminal's connection to Emacs, says which of the project's
terminals it is; empty or nil for a claude that has none.
The status and its notification say it only when the terminal is out
of sight."
  (setq port (and port (not (string-empty-p port)) (string-to-number port)))
  (pcase event
    ("stop"
     ;; Pick up edits Claude made on disk in buffers that are not modified.
     (dolist (buf (buffer-list))
       (with-current-buffer buf
         (when (and buffer-file-name
                    (file-in-directory-p buffer-file-name dir)
                    (not (buffer-modified-p))
                    (not (verify-visited-file-modtime buf))
                    (file-exists-p buffer-file-name))
           (revert-buffer :ignore-auto :noconfirm :preserve-modes))))
     (+ai--terminal-event dir 'done port)
     ;; What it wrote is not known file by file: anything under DIR.
     (run-hook-with-args '+ai-edit-functions
                         (or (+ai--turn-root dir) (file-name-as-directory dir))
                         nil))
    ("notification"
     (+ai--terminal-event dir 'permission port))
    ;; A prompt sent: the project as it is now is where the turn starts.
    ("prompt"
     (+ai--turn-snapshot dir)))
  t)


;;
;;; Claude's settings, as VS Code's dialogs show them

(defun +ai--mcp-servers ()
  "Claude's MCP servers for this project, as (LABEL NAME SCOPE), read from
its configuration files rather than `claude mcp list', which connects to
each one first."
  (let* ((dir (directory-file-name (expand-file-name (+core-project-root 'noerror))))
         (user (+ai--read-json (expand-file-name "~/.claude.json")))
         (scopes `(("user" . ,(alist-get 'mcpServers user))
                   ("local" . ,(alist-get 'mcpServers
                                          (alist-get (intern dir) (alist-get 'projects user))))
                   ("project" . ,(alist-get 'mcpServers
                                            (+ai--read-json (expand-file-name ".mcp.json" dir)))))))
    (cl-loop for (scope . servers) in scopes
             append (mapcar (lambda (server)
                              (let ((name (symbol-name (car server))))
                                (list (format "%s (%s)" name scope) name scope)))
                            servers))))

(defun +ai--read-mcp-server (prompt)
  "Ask with PROMPT for one of Claude's MCP servers; return (NAME SCOPE)."
  (let ((servers (or (+ai--mcp-servers)
                     (user-error "No MCP server is configured for Claude here"))))
    (cdr (assoc (completing-read prompt (mapcar #'car servers) nil t) servers))))

;;;###autoload
(defun +ai/claude-mcp-add (name target scope)
  "Give Claude Code the MCP server NAME.
TARGET is its URL, or its command line; SCOPE is local (this project,
you), project (.mcp.json, shared) or user (every project)."
  (interactive
   (list (read-string "Server name: ")
         (read-string "URL, or the command and its arguments: ")
         (completing-read "Scope: " '("local" "project" "user") nil t nil nil "local")))
  (when (or (string-empty-p name) (string-empty-p target))
    (user-error "A name and a URL or a command are needed"))
  (apply #'+ai--claude-mcp "add" "--scope" scope
         (if (string-match-p "\\`https?://" target)
             (list "--transport" "http" name target)
           (cons name (cons "--" (split-string-and-unquote target))))))

;;;###autoload
(defun +ai/claude-mcp-remove (server)
  "Take SERVER, (NAME SCOPE), away from Claude Code, after asking."
  (interactive (list (+ai--read-mcp-server "Remove MCP server: ")))
  (pcase-let ((`(,name ,scope) server))
    (when (y-or-n-p (format "Remove %s from the %s scope? " name scope))
      (+ai--claude-mcp "remove" "--scope" scope name))))

;;;###autoload
(defun +ai/claude-mcp-get (server)
  "Show what Claude knows of SERVER, (NAME SCOPE), and whether it connects."
  (interactive (list (+ai--read-mcp-server "MCP server: ")))
  (+ai--claude-mcp "get" (car server)))

(defun +ai--open-settings-at (key project)
  "Open Claude's settings, the project's with PROJECT, at KEY."
  (+ai/open-claude-settings project)
  (goto-char (point-min))
  (if (re-search-forward (format "\"%s\"[[:space:]]*:" key) nil t)
      (beginning-of-line)
    (message "No %s in %s yet" key (abbreviate-file-name buffer-file-name))))

;;;###autoload
(defun +ai/claude-hooks (&optional project)
  "Open Claude's hooks; with PROJECT (\\[universal-argument]), the project's."
  (interactive "P")
  (+ai--open-settings-at "hooks" project))

;;;###autoload
(defun +ai/claude-permissions (&optional project)
  "Open Claude's permission rules; with PROJECT (\\[universal-argument]), the
project's."
  (interactive "P")
  (+ai--open-settings-at "permissions" project))

;;;###autoload
(defun +ai/claude-usage ()
  "Show your plan's usage and limits, as VS Code's Account & usage: /usage
in this project's chat, which costs nothing.  Not while its prompt holds
text: /usage would be sent with it, as an ordinary turn."
  (interactive)
  (let ((chat (or (+ai--chat-buffer) (+ai--chat-start-quietly))))
    (with-current-buffer chat
      (when-let* ((start (agent-shell--prompt-input-start))
                  ((not (string-blank-p (buffer-substring-no-properties start (point-max))))))
        (user-error "The chat's prompt holds text; send or clear it first")))
    (agent-shell-insert :text "/usage" :submit t :shell-buffer chat)))


;;
;;; Logging

;;;###autoload
(defun +ai/log-session ()
  "Write a session note into the owning project's Progress, or the inbox."
  (interactive)
  (require 'org-capture)
  (org-capture nil "a"))
