;;; private/ai/autoload/claude.el -*- lexical-binding: t; -*-
;;
;; Tools Claude can call over MCP, plus the model flag and terminal helpers.

(defvar +ai-claude-model)
(defvar +ai-tool-search-seconds)
(defvar +ai-compose-mode)
(defvar +core-todo-markers)
(defvar claude-code-ide--session)
(defvar evil-state)
(defvar evil-visual-beginning)
(defvar evil-visual-end)
(declare-function flymake--lookup-type-property "flymake")
(defvar claude-code-ide-cli-extra-flags)
(defvar claude-code-ide-enable-execute-code)
(defvar compilation-ask-about-save)
(declare-function +ai--fenced "chat")
(declare-function claude-code-ide "claude-code-ide")
(declare-function claude-code-ide--cleanup-session "claude-code-ide")
(declare-function claude-code-ide--get-working-directory "claude-code-ide")
(declare-function claude-code-ide--resolve-session "claude-code-ide")
(declare-function claude-code-ide--display-buffer-in-side-window "claude-code-ide")
(declare-function claude-code-ide--session-display-name "claude-code-ide")
(declare-function claude-code-ide-stop "claude-code-ide")
(declare-function claude-code-ide-mcp--active-sessions "claude-code-ide-mcp")
(declare-function claude-code-ide-mcp-session-buffer "claude-code-ide-mcp")
(declare-function claude-code-ide-mcp-session-client "claude-code-ide-mcp")
(declare-function claude-code-ide-mcp-session-last-used "claude-code-ide-mcp")
(declare-function claude-code-ide-mcp-session-port "claude-code-ide-mcp")
(declare-function claude-code-ide-mcp-session-project-dir "claude-code-ide-mcp")
(declare-function evil-emacs-state "evil-states")
(declare-function evil-insert-state "evil-states")
(declare-function vterm-reset-cursor-point "vterm")
(declare-function vterm-send-return "vterm")
(declare-function vterm-send-string "vterm")
(declare-function vterm-yank "vterm")
(declare-function claude-code-ide-mcp-server-get-session-context "claude-code-ide-mcp-server")
(declare-function claude-code-ide-make-tool "claude-code-ide-mcp-server")

;;
;;; MCP tools exposed to Claude

(defun +ai--tool-build-command (root &optional target)
  "Command that builds ROOT, or its TARGET: the cpp module's kit when
that module is on, else make."
  (let ((default-directory root))
    (or (and (modulep! :private cpp)
             (fboundp '+cpp-build-command)
             (+cpp-build-command target))
        (and (file-exists-p (expand-file-name "Makefile" root)) "make")
        (error "No build system detected in %s" root))))

(defun +ai--tool-wait-for-compilation (buffer seconds)
  "Wait up to SECONDS for the compilation in BUFFER."
  (let ((deadline (+ (float-time) seconds)))
    (while (and (< (float-time) deadline)
                (buffer-live-p buffer)
                (with-current-buffer buffer
                  (get-buffer-process buffer)))
      (accept-process-output nil 0.5))))

(defun +ai--tool-compilation-tail (buffer &optional chars)
  "Status of BUFFER plus its last CHARS characters (default 6000)."
  (with-current-buffer buffer
    (let* ((running (and (get-buffer-process buffer) t))
           (text (buffer-substring-no-properties
                  (max (point-min) (- (point-max) (or chars 6000)))
                  (point-max))))
      (format "status: %s\n\n%s" (if running "still running" "finished")
              (string-trim text)))))

;;;###autoload
(defun +ai--tool-root-allowed-p (dir)
  "Non-nil when DIR may be opened to the agents' tools: your home or a
directory in it.  / and the system's directories are too much."
  (file-in-directory-p (file-truename (file-name-as-directory (expand-file-name dir)))
                       (file-truename "~/")))

(defun +ai--tool-root ()
  "The project of the Claude session a tool is called for: the package's
own tools take it from the session, and the buffer current as the call
arrives is whatever you happen to be looking at, another project's.
A root outside your home is refused."
  (let ((root (or (and (fboundp 'claude-code-ide-mcp-server-get-session-context)
                       (plist-get (claude-code-ide-mcp-server-get-session-context)
                                  :project-dir))
                  (+core-project-root 'noerror))))
    (unless (and root (+ai--tool-root-allowed-p root))
      (error "%s is outside your home, too much to open to the tools"
             (abbreviate-file-name (or root "/"))))
    root))

;;;###autoload
(defun +ai--read-json (file)
  "FILE's JSON as an alist, or nil when it is missing or unreadable."
  (when (file-readable-p file)
    (ignore-errors
      (with-temp-buffer
        (insert-file-contents file)
        (json-parse-buffer :object-type 'alist :null-object nil :false-object nil)))))

;;;###autoload
(defun +ai--tools-name-taken (dir)
  "Why the read tools may not run unasked for DIR, or nil: a file that
gives another MCP server the name emacs-tools, or one that cannot be
read.  Ours is passed per session and never written to these files, so
a server found there is someone else's, and the auto-allowed tool names
would reach it too.  Claude reads .mcp.json in DIR and in every
directory above it."
  (let* ((dir (directory-file-name (expand-file-name dir)))
         (managed (if (featurep :system 'macos)
                      "/Library/Application Support/ClaudeCode/"
                    "/etc/claude-code/"))
         (user (expand-file-name "~/.claude.json"))
         (sources `((,user mcpServers)
                    (,user projects ,(intern dir) mcpServers)
                    (,user projects ,(intern (directory-file-name (file-truename dir)))
                           mcpServers)
                    (,(concat managed "managed-mcp.json") mcpServers)
                    (,(concat managed "managed-settings.json") managedMcpServers))))
    (let ((up dir))
      (while up
        (push (list (expand-file-name ".mcp.json" up) 'mcpServers) sources)
        (setq up (unless (equal up (directory-file-name (file-name-directory up)))
                   (directory-file-name (file-name-directory up))))))
    (let (parsed)
      (seq-some
       (lambda (source)
         (let ((file (car source)))
           (when (file-exists-p file)
             (unless (assoc file parsed)
               (push (cons file (condition-case nil
                                    (with-temp-buffer
                                      (insert-file-contents file)
                                      (json-parse-buffer :object-type 'alist
                                                         :null-object nil
                                                         :false-object nil))
                                  (error :unreadable)))
                     parsed))
             (let* ((json (cdr (assoc file parsed)))
                    (servers (and (listp json) (map-nested-elt json (cdr source)))))
               (cond ((or (eq json :unreadable)
                          (and servers (not (listp servers))))
                      (format "%s cannot be read" (abbreviate-file-name file)))
                     ((assq 'emacs-tools servers)
                      (format "%s names another server emacs-tools"
                              (abbreviate-file-name file))))))))
       sources))))

;;;###autoload
(defun +ai--tool-check-path (path)
  "Signal an error unless PATH, relative to the session's project, is in it.
claude-code-ide's own file tools open any path they are given."
  (let* ((root (file-name-as-directory (expand-file-name (+ai--tool-root))))
         (file (expand-file-name path root)))
    (unless (file-in-directory-p (file-truename file) (file-truename root))
      (error "%s is outside the project %s" path (abbreviate-file-name root)))))

(defun +ai--tool-build-project (&optional target wait-seconds)
  "Build the project and return what the compiler said.
TARGET is an optional build target, WAIT-SECONDS how long to wait: the
wait holds Emacs, so it is short by default and capped, and a slow
build is polled with emacs_last_compilation.  Modified buffers are
saved without asking: a y/n prompt while Claude waits would time out
the tool."
  ;; Run from a fresh buffer in the session's root, since the kit reads
  ;; the current buffer's settings before the project's file.
  (with-temp-buffer
    (setq default-directory (file-name-as-directory (+ai--tool-root)))
    (let* ((root default-directory)
           (command (+ai--tool-build-command root target))
           (wait (min 10 (max 2 (or wait-seconds 3))))
           (compilation-ask-about-save nil)
           (buffer (+core-compile "build" command root)))
      (+ai--tool-wait-for-compilation buffer wait)
      (concat (format "command: %s\nroot: %s\nbuffer: %s\n"
                      command (abbreviate-file-name root) (buffer-name buffer))
              (+ai--tool-compilation-tail buffer)))))

(defun +ai--tool-last-compilation ()
  "The status and tail of the build, test or run that started last,
whether this tool, a key or a menu started it."
  (if-let* ((buffer (+core-last-compilation-buffer)))
      ;; Short while it runs: every poll stays in Claude's context.
      (concat (format "buffer: %s\n" (buffer-name buffer))
              (+ai--tool-compilation-tail buffer (if (get-buffer-process buffer) 1500 8000)))
    "No build, test or run has started yet."))

(defun +ai--tool-project-todos ()
  "Return the project's markers, `+core-todo-markers', as file:line:text.
The search holds Emacs while it runs, so it stops after
`+ai-tool-search-seconds' with what it has: in a tree as large as a
home directory it would otherwise freeze Emacs for the whole walk."
  (let ((root (+ai--tool-root)))
    (unless (executable-find "rg") (error "ripgrep (rg) is not installed"))
    (with-temp-buffer
      (let* ((default-directory root)
             (process (make-process
                       :name "ai-todos" :buffer (current-buffer)
                       :command (list "rg" "--line-number" "--no-heading"
                                      "--color=never" "-e" (+core-todo-regexp) ".")
                       :connection-type 'pipe :noquery t :sentinel #'ignore))
             (deadline (+ (float-time) +ai-tool-search-seconds)))
        (while (and (process-live-p process) (< (float-time) deadline))
          (accept-process-output process 0.1 nil t))
        (let ((stopped (process-live-p process)))
          (if stopped
              (delete-process process)
            ;; Ended: what it wrote last may still sit in the pipe.
            (while (accept-process-output process 0 nil t)))
          (concat (if (= (point-min) (point-max))
                      "No TODO/FIXME markers found."
                    (buffer-substring-no-properties (point-min) (min (point-max) 12000)))
                  (when stopped
                    (format "\n(stopped after %d s: the project is too large to search whole)"
                            +ai-tool-search-seconds))))))))

(defun +ai--tool-editor-root (buffer)
  "The project an editor state is described for: the session's, else
BUFFER's.  A root outside your home is refused, as for every tool."
  (let ((root (or (plist-get (claude-code-ide-mcp-server-get-session-context)
                             :project-dir)
                  (with-current-buffer buffer (+core-project-root-or-nil)))))
    (unless root
      (error "Not inside a project, so there is no editor state to give"))
    (setq root (file-name-as-directory (expand-file-name root)))
    (unless (+ai--tool-root-allowed-p root)
      (error "%s is outside your home, too much to open to the tools"
             (abbreviate-file-name root)))
    root))

(defun +ai--tool-editor-diagnostics ()
  "Up to 50 of this buffer's flymake diagnostics, one per line."
  (when (bound-and-true-p flymake-mode)
    (mapconcat
     (lambda (diag)
       (format "line %d: %s: %s"
               (line-number-at-pos (flymake-diagnostic-beg diag))
               (pcase (flymake--lookup-type-property
                       (flymake-diagnostic-type diag) 'flymake-category)
                 ('flymake-error "error")
                 ('flymake-warning "warning")
                 (_ "note"))
               (flymake-diagnostic-text diag '(message))))
     (seq-take (sort (flymake-diagnostics)
                     (lambda (a b) (< (flymake-diagnostic-beg a)
                                      (flymake-diagnostic-beg b))))
               50)
     "\n")))

(defun +ai--tool-editor-state ()
  "Describe the editor window: file, point, view, region, diagnostics."
  (if-let* ((window (+ai--editor-window)))
      (let* ((buffer (window-buffer window))
             (file (buffer-file-name buffer))
             (root (and file (+ai--tool-editor-root buffer))))
        (cond
         ((not file)
          (format "The editor shows %s, which visits no file." (buffer-name buffer)))
         ((not (file-in-directory-p file root))
          (format "The editor shows a file outside the project %s."
                  (abbreviate-file-name root)))
         (t
          (with-current-buffer buffer
            (let* ((point (window-point window))
                   (visual (and (bound-and-true-p evil-local-mode)
                                (eq evil-state 'visual)))
                   (region (cond (visual (cons (marker-position evil-visual-beginning)
                                               (marker-position evil-visual-end)))
                                 ((and mark-active (mark t))
                                  (cons (min point (mark t)) (max point (mark t))))))
                   (diagnostics (+ai--tool-editor-diagnostics)))
              (concat
               (format "file: %s\n" (file-relative-name file root))
               (save-excursion
                 (goto-char point)
                 (format "point: line %d, column %d\n"
                         (line-number-at-pos) (current-column)))
               (format "visible: lines %d-%d\n"
                       (line-number-at-pos (window-start window))
                       (line-number-at-pos (window-end window t)))
               (format "modified: %s\n" (if (buffer-modified-p) "yes" "no"))
               (when region
                 (let* ((beg (car region))
                        (end (cdr region))
                        ;; A region ending at a line's start leaves that line out.
                        (last (if (and (> end beg)
                                       (save-excursion (goto-char end) (bolp)))
                                  (1- end)
                                end))
                        (text (buffer-substring-no-properties beg end)))
                   (format "region: lines %d-%d%s\n%s\n"
                           (line-number-at-pos beg) (line-number-at-pos last)
                           (if (> (length text) 8000) " (cut to 8000 characters)" "")
                           (substring text 0 (min (length text) 8000)))))
               (when (and diagnostics (not (string-empty-p diagnostics)))
                 (format "diagnostics:\n%s\n" diagnostics))))))))
    "No editor window"))

;;;###autoload
(defun +ai--register-claude-tools ()
  "Give Claude the build, compilation and TODO tools."
  (claude-code-ide-make-tool
   :function #'+ai--tool-build-project
   :name "emacs_build_project"
   :description
   (concat "Build the current project the way Emacs does (CMake preset and "
           "target through projection, PlatformIO, or make) and return the "
           "compiler output. Use it after editing code. Waits up to "
           "wait_seconds (default 3), during which the editor is frozen; if "
           "the build is still running, call emacs_last_compilation until it "
           "has finished.")
   :args '((:name "target" :type string :optional t
            :description "Build target; omit for the default one")
           (:name "wait_seconds" :type integer :optional t
            :description "Seconds to wait, 2 to 10, default 3"))
   :category "Build")
  (claude-code-ide-make-tool
   :function #'+ai--tool-last-compilation
   :name "emacs_last_compilation"
   :description
   (concat "Return whether the last Emacs build or test is still running, "
           "and the end of its output: a short end while it runs, so space "
           "the calls a few seconds apart.")
   :args nil
   :category "Build")
  (claude-code-ide-make-tool
   :function #'+ai--tool-project-todos
   :name "emacs_project_todos"
   :description
   (format "List the %s markers in the project, one per line as file:line:text."
           (string-join +core-todo-markers ", "))
   :args nil
   :category "Project")
  (claude-code-ide-make-tool
   :function #'+ai--tool-editor-state
   :name "emacs_editor_state"
   :description
   (concat "Describe what the user is looking at in Emacs: the file, relative "
           "to the project, point's line and column, the visible lines, "
           "whether the buffer is modified, the selected region with its "
           "text, and the file's diagnostics. Call it when the user says "
           "\"this\", \"here\" or \"the selection\".")
   :args nil
   :category "Editor"))


;;
;;; Model flag & toggles

;;;###autoload
(defun +ai--apply-claude-model ()
  "Put `+ai-claude-model' into the CLI flags."
  (when (boundp 'claude-code-ide-cli-extra-flags)
    (let ((flags (replace-regexp-in-string
                  "\\s-*--model[= ]\\S-+" ""
                  (or claude-code-ide-cli-extra-flags ""))))
      (setq claude-code-ide-cli-extra-flags
            (string-trim (if +ai-claude-model
                             (concat flags " --model " +ai-claude-model)
                           flags))))))

;;;###autoload
(defun +ai/set-claude-model (model)
  "Use MODEL for new Claude sessions.  Empty means the CLI default.
The CLI's aliases always name the latest model of each family; a full
model name can still be typed."
  (interactive
   (list (+core-read-or-empty "Claude model" "for the CLI's default"
                              '("fable" "opus" "sonnet" "haiku")
                              +ai-claude-model)))
  (setq +ai-claude-model (unless (string-empty-p model) model))
  (+ai--apply-claude-model)
  (message "Claude model: %s, from the next session on"
           (or +ai-claude-model "default")))

;;;###autoload
(defun +ai/toggle-execute-code ()
  "Allow or forbid Claude to evaluate Emacs Lisp."
  (interactive)
  (require 'claude-code-ide)
  (setq claude-code-ide-enable-execute-code
        (not claude-code-ide-enable-execute-code))
  (message "Claude execute-code tool: %s (new sessions)"
           (if claude-code-ide-enable-execute-code "ENABLED" "disabled")))


;;
;;; Terminal helpers

(defun +ai--terminal-live-p (buffer)
  "Non-nil when BUFFER is a Claude terminal whose Claude runs."
  (and (buffer-live-p buffer)
       (buffer-local-value 'claude-code-ide--session buffer)
       (process-live-p (get-buffer-process buffer))))

;;;###autoload
(defun +ai--terminal-buffer (&optional dir port)
  "A running Claude terminal of DIR's project, default this one, or nil.
A project runs the unnamed one and others, :2 and so on: the one whose
connection to Emacs is on PORT when it is given, else this buffer when
it is one of them, else the one used last."
  (require 'claude-code-ide)
  (let* ((dir (file-name-as-directory
               (expand-file-name (or dir (claude-code-ide--get-working-directory)))))
         (running (seq-filter (lambda (session)
                                (+ai--terminal-live-p
                                 (claude-code-ide-mcp-session-buffer session)))
                              (claude-code-ide-mcp--active-sessions)))
         (here (seq-filter (lambda (session)
                             (equal (file-name-as-directory
                                     (expand-file-name
                                      (claude-code-ide-mcp-session-project-dir session)))
                                    dir))
                           running)))
    (when-let* ((session
                 (or (and port
                          ;; Any project's: one started in a worktree
                          ;; reports the worktree as its directory.
                          (seq-find (lambda (session)
                                      (eql (claude-code-ide-mcp-session-port session) port))
                                    running))
                     (car (memq (bound-and-true-p claude-code-ide--session) here))
                     (car (sort here (lambda (a b)
                                       (> (or (claude-code-ide-mcp-session-last-used a) 0)
                                          (or (claude-code-ide-mcp-session-last-used b) 0))))))))
      (claude-code-ide-mcp-session-buffer session))))

;;;###autoload
(defun +ai/terminal ()
  "Focus this project's Claude terminal, or start one when none runs.
`claude-code-ide' alone always starts another instance."
  (interactive)
  (require 'claude-code-ide)
  (if-let* ((terminal (+ai--terminal-buffer)))
      ;; This one, not the package's pick: that can be a terminal whose
      ;; Claude died and whose cleanup has not run yet.
      (when-let* ((window (or (get-buffer-window terminal)
                              (claude-code-ide--display-buffer-in-side-window terminal))))
        (select-window window))
    (claude-code-ide)))

;;;###autoload
(defun +ai/terminal-stop ()
  "End a Claude terminal of this project, after asking.
In a terminal, that one; else the only one, the only one in view, or
the one you pick, as `claude-code-ide-stop' chooses.  C-c C-k in the
terminal, a key that elsewhere only drops a draft."
  (interactive)
  (require 'claude-code-ide)
  (let* ((session (or (claude-code-ide--resolve-session 'prompt "End Claude terminal: ")
                      (user-error "No Claude terminal runs for this project")))
         (buffer (claude-code-ide-mcp-session-buffer session)))
    (when (y-or-n-p (format "End %s? "
                            (if (buffer-live-p buffer)
                                (buffer-name buffer)
                              (claude-code-ide--session-display-name session))))
      (if (buffer-live-p buffer)
          ;; From the terminal itself, the package ends that one; no
          ;; prefix argument, or it would ask which once more. Quiet, as
          ;; a chat ends: its "Stopping" names the act another way.
          (let ((current-prefix-arg nil)
                (inhibit-message t)
                (message-log-max nil))
            (with-current-buffer buffer
              (claude-code-ide-stop)))
        (claude-code-ide--cleanup-session session)))))

(defun +ai--terminal-start-with (flags)
  "Start another Claude terminal for this project, its CLI given FLAGS too."
  (require 'claude-code-ide)
  (let ((claude-code-ide-cli-extra-flags
         (string-trim (concat (or claude-code-ide-cli-extra-flags "") " " flags))))
    (claude-code-ide)))

;;;###autoload
(defun +ai/terminal-remote ()
  "Start a Claude terminal for this project with Remote Control, so the
session can be driven from claude.ai or the Claude app as well."
  (interactive)
  (+ai--terminal-start-with "--remote-control"))

;;;###autoload
(defun +ai/terminal-teleport ()
  "Open one of your cloud sessions here, in a Claude terminal: the CLI
lists them to pick from.  It wants a clean git tree, the session's
branch pushed, and the same claude.ai account."
  (interactive)
  (+ai--terminal-start-with "--teleport"))

;;;###autoload
(defun +ai/terminal-worktree (name)
  "Start a Claude terminal in a new git worktree NAME of this project.
An empty NAME lets the CLI make one up."
  (interactive (list (read-string "Worktree name (empty for a generated one): ")))
  (when (string-prefix-p "-" name)
    (user-error "A worktree name cannot start with -, the CLI would take it for an option"))
  (+ai--terminal-start-with (if (string-empty-p name)
                                "--worktree"
                              (concat "--worktree " (shell-quote-argument name)))))

;;
;;; Cloud and background sessions

;;;###autoload
(defun +ai/cloud-task (task)
  "Send TASK to a cloud session on claude.ai and follow it in a terminal.
It runs on Anthropic's machines from the project's pushed branch, so the
Emacs tools are out of its reach."
  (interactive (list (read-string "Cloud task: ")))
  (+ai--check-task task)
  (+core-run-in-vterm "*claude cloud*" (concat "claude --cloud " (shell-quote-argument task))))

(defun +ai--check-task (task)
  "Refuse an empty TASK, or one the CLI would read as an option."
  (when (string-empty-p (string-trim task))
    (user-error "No task"))
  (when (string-prefix-p "-" task)
    (user-error "A task cannot start with -, the CLI would take it for an option")))

;;;###autoload
(defun +ai/agent-dispatch (task)
  "Give TASK to a background agent working in this project.
\\[+ai/agents] lists the agents, \\[+ai/agent-attach] opens one."
  (interactive (list (read-string "Background task: ")))
  (+ai--check-task task)
  (unless (executable-find "claude")
    (user-error "The claude CLI is not on PATH"))
  (let* ((default-directory (+core-project-root 'noerror))
         (buffer (generate-new-buffer " *claude bg*"))
         (process
          (make-process
           :name "claude-bg" :buffer buffer :noquery t :connection-type 'pipe
           :command (list "claude" "--bg" task)
           :sentinel
           (lambda (process _event)
             (unless (process-live-p process)
               (let ((said (with-current-buffer buffer
                             (car (last (split-string (buffer-string) "\n" t))))))
                 (kill-buffer buffer)
                 (if (zerop (process-exit-status process))
                     (message "Background agent started%s" (if said (concat ": " said) ""))
                   (message "claude --bg failed: %s"
                            (or said (format "exit %d" (process-exit-status process)))))))))))
    ;; The task is on the command line; nothing comes on its input.
    (process-send-eof process)))

;;;###autoload
(defun +ai/agents ()
  "Show the background agents, Claude's agent view, in a terminal."
  (interactive)
  (+core-run-in-vterm "*claude agents*" "claude agents"))

(defun +ai--background-agents ()
  "The background sessions `claude agents --json' lists, as alists.
The CLI holds Emacs while it starts, so it gets
`+ai-tool-search-seconds' at most."
  (unless (executable-find "claude")
    (user-error "The claude CLI is not on PATH"))
  (let ((errors (generate-new-buffer " *claude agents errors*")))
    (unwind-protect
        (with-temp-buffer
          (let ((process (make-process :name "claude-agents" :buffer (current-buffer)
                                       :command '("claude" "agents" "--json")
                                       :connection-type 'pipe :noquery t
                                       :stderr errors :sentinel #'ignore))
                (deadline (+ (float-time) +ai-tool-search-seconds)))
            ;; Not the pipe's own "finished" line among the errors.
            (set-process-sentinel (get-buffer-process errors) #'ignore)
            (process-send-eof process)
            (while (and (process-live-p process) (< (float-time) deadline))
              (accept-process-output process 0.1 nil t))
            (when (process-live-p process)
              (delete-process process)
              (user-error "claude agents --json did not answer in %d s"
                          +ai-tool-search-seconds))
            (while (accept-process-output process 0 nil t))
            ;; The error stream is a pipe of its own; let it finish too.
            (when-let* ((pipe (get-buffer-process errors)))
              (while (accept-process-output pipe 0.05 nil t)))
            (goto-char (point-min))
            (let ((sessions (condition-case nil
                                (json-parse-buffer :object-type 'alist :array-type 'list)
                              (error
                               (user-error "claude agents --json: %s"
                                           (with-current-buffer errors
                                             (string-trim (buffer-string))))))))
              (seq-filter (lambda (session)
                            (and (equal (alist-get 'kind session) "background")
                                 (or (alist-get 'id session) (alist-get 'name session))))
                          sessions))))
      (when-let* ((pipe (get-buffer-process errors)))
        (delete-process pipe))
      (kill-buffer errors))))

;;;###autoload
(defun +ai/agent-attach ()
  "Open a background agent in a terminal, to follow or answer it."
  (interactive)
  (let* ((agents (or (+ai--background-agents)
                     (user-error "No background agent runs")))
         (choices (mapcar (lambda (agent)
                            (let ((id (or (alist-get 'id agent) (alist-get 'name agent))))
                              (cons (format "%s  %s (%s, %s)" id
                                            (or (alist-get 'name agent) "")
                                            (or (alist-get 'status agent) "unknown")
                                            (abbreviate-file-name (or (alist-get 'cwd agent) "?")))
                                    id)))
                          agents))
         ;; The CLI opens a session by its id; a name opens a running one only.
         (id (cdr (assoc (completing-read "Attach to: " choices nil t) choices))))
    (+core-run-in-vterm (format "*claude %s*" id)
                        (concat "claude attach " (shell-quote-argument id)))))

;; Normal state in the terminal reads Claude's screen. evil-collection's
;; vterm keys move Claude's cursor with arrow keys, which the TUI takes
;; as its history, so these put point back on the cursor instead.

;;;###autoload
(defun +ai/claude-type ()
  "Type to Claude again: emacs state, point back on Claude's cursor."
  (interactive)
  (vterm-reset-cursor-point)
  (evil-emacs-state))

;;;###autoload
(defun +ai/claude-paste ()
  "Paste the top of the kill ring into Claude, then type to Claude."
  (interactive)
  (vterm-reset-cursor-point)
  (vterm-yank)
  (evil-emacs-state))

;;;###autoload
(defun +ai/claude-guard ()
  "Leave Claude's screen alone and say how to type to Claude."
  (interactive)
  (message "C-z or i to type to Claude"))


;;
;;; Composing a prompt for the terminal

(defvar +ai--compose-history nil
  "Prompts sent from compose buffers, newest first, at most 20.")

(defvar-local +ai--compose-dir nil
  "The project directory whose Claude terminal this buffer writes to.")

(defvar-local +ai--compose-terminal nil
  "The Claude terminal this buffer writes to, or nil for the project's
one that runs when it is sent.")

(defvar-local +ai--compose-index nil
  "The prompt of `+ai--compose-history' that M-p and M-n showed last.")

;;;###autoload
(defun +ai/terminal-compose ()
  "Write a prompt for this project's Claude terminal in a buffer.
From a terminal the prompt is for that one, else for the one used last.
C-c C-c sends it, C-c C-k drops it, M-p and M-n bring back the last
prompts.  An active region comes along as a fenced block."
  (interactive)
  (require 'claude-code-ide)
  (let* ((dir (claude-code-ide--get-working-directory))
         (terminal (+ai--terminal-buffer dir))
         (block (when (use-region-p)
                  (+ai--fenced (buffer-substring-no-properties
                                (region-beginning) (region-end))
                               (+core-language major-mode))))
         ;; One draft per terminal, named as it is: proj, proj:2.
         (buffer (get-buffer-create
                  (format "*claude-compose[%s]*"
                          (if terminal
                              (claude-code-ide--session-display-name
                               (buffer-local-value 'claude-code-ide--session terminal))
                            (file-name-nondirectory (directory-file-name dir)))))))
    (deactivate-mark)
    (with-current-buffer buffer
      (unless +ai-compose-mode
        (if (fboundp 'gfm-mode) (gfm-mode) (markdown-mode))
        (+ai-compose-mode +1))
      (setq default-directory dir
            +ai--compose-dir dir
            +ai--compose-terminal terminal)
      (when block
        (goto-char (point-max))
        (unless (bolp) (insert "\n"))
        (insert block)))
    (pop-to-buffer buffer)
    (goto-char (point-max))
    (when (bound-and-true-p evil-local-mode)
      (evil-insert-state))))

(defun +ai--terminal-send (buffer text)
  "Paste TEXT into the Claude terminal BUFFER and submit it.
A bracketed paste, so a newline in TEXT does not submit early."
  (with-current-buffer buffer
    (vterm-send-string text t)
    ;; As claude-code-ide does, let the paste land before the return.
    (sleep-for 0.1)
    (vterm-send-return)))

(defun +ai--terminal-connected-p (buffer)
  "Non-nil once the Claude in BUFFER has connected to Emacs."
  (when-let* ((session (buffer-local-value 'claude-code-ide--session buffer)))
    (claude-code-ide-mcp-session-client session)))

(defun +ai--compose-send-when-ready (compose dir text deadline)
  "Send TEXT once DIR's new terminal runs and Claude has connected.
Then close COMPOSE; past DEADLINE keep it and say so.  Closing COMPOSE
meanwhile drops the prompt."
  (let ((terminal (+ai--terminal-buffer dir)))
    (cond ((not (buffer-live-p compose)))
          ((and terminal (+ai--terminal-connected-p terminal))
           (+ai--terminal-send terminal text)
           (kill-buffer compose))
          ((> (float-time) deadline)
           (message "Claude did not start"))
          (t (run-at-time 0.5 nil #'+ai--compose-send-when-ready
                          compose dir text deadline)))))

;;;###autoload
(defun +ai/terminal-compose-send ()
  "Send this prompt to the project's Claude terminal and close.
To the one it was written for; when that one has ended, to the one used
last; with none running, start one and send once Claude is up."
  (interactive)
  (let ((text (string-trim (buffer-string)))
        (compose (current-buffer))
        (dir +ai--compose-dir))
    (when (string-empty-p text)
      (user-error "Nothing to send"))
    (setq +ai--compose-history
          (seq-take (cons text (delete text +ai--compose-history)) 20))
    (if-let* ((terminal (if (+ai--terminal-live-p +ai--compose-terminal)
                            +ai--compose-terminal
                          (+ai--terminal-buffer dir))))
        (progn (+ai--terminal-send terminal text)
               (kill-buffer compose))
      (let ((default-directory dir))
        (claude-code-ide))
      (+ai--compose-send-when-ready compose dir text (+ (float-time) 15)))))

;;;###autoload
(defun +ai/terminal-compose-cancel ()
  "Close this compose buffer without sending.
A draft with text in it goes only after asking."
  (interactive)
  (when (or (string-empty-p (string-trim (buffer-string)))
            (y-or-n-p "Drop this prompt? "))
    (kill-buffer (current-buffer))))

;;;###autoload
(defun +ai/terminal-compose-previous (&optional n)
  "Replace the text with the prompt sent N before the one shown."
  (interactive "p")
  (unless +ai--compose-history
    (user-error "No prompt sent yet"))
  (let ((index (+ (or +ai--compose-index -1) (or n 1))))
    (erase-buffer)
    (if (< index 0)
        (setq +ai--compose-index nil)
      (setq +ai--compose-index (min index (1- (length +ai--compose-history))))
      (insert (nth +ai--compose-index +ai--compose-history)))))

;;;###autoload
(defun +ai/terminal-compose-next (&optional n)
  "Replace the text with the prompt sent N after the one shown."
  (interactive "p")
  (+ai/terminal-compose-previous (- (or n 1))))

;;;###autoload
(defun +ai/claude-leave ()
  "Go back to the window you came from; Claude keeps its window."
  (interactive)
  (if-let* ((window (get-mru-window nil nil t)))
      (select-window window)
    (user-error "No other window")))

;;;###autoload
(defun +ai/claude-terminal ()
  "Run claude in a terminal, without the Emacs bridge."
  (interactive)
  (+core-run-in-vterm "*claude*"
                  (if +ai-claude-model
                      (concat "claude --model " +ai-claude-model)
                    "claude")))

;;;###autoload
(defun +ai/claude-doctor ()
  "Run `claude doctor' in a vterm."
  (interactive)
  (+core-run-in-vterm "*claude doctor*" "claude doctor"))

;;;###autoload
(defun +ai--claude-mcp (&rest args)
  "Run claude mcp ARGS in this project, its output in *claude mcp*.
Not a compilation: a build in *compilation* is left alone, and this
never counts as the last build."
  (unless (executable-find "claude")
    (user-error "The claude CLI is not on PATH"))
  (let ((dir (+core-project-root 'noerror))
        (buffer (get-buffer-create "*claude mcp*")))
    (with-current-buffer buffer
      (when-let* ((running (get-buffer-process buffer)))
        (delete-process running))
      (special-mode)
      (setq default-directory dir)
      (setq-local revert-buffer-function
                  (lambda (&rest _) (apply #'+ai--claude-mcp args)))
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert "claude mcp " (mapconcat #'shell-quote-argument args " ") "\n\n")))
    (let* ((default-directory dir)
           (process
            (make-process
             :name "claude-mcp" :buffer buffer :noquery t :connection-type 'pipe
             :command (append '("claude" "mcp") args)
             :filter (lambda (process text)
                       (when (buffer-live-p (process-buffer process))
                         (with-current-buffer (process-buffer process)
                           (let ((inhibit-read-only t))
                             (save-excursion
                               (goto-char (point-max))
                               (insert text))))))
             :sentinel (lambda (process _event)
                         (unless (or (process-live-p process)
                                     (not (buffer-live-p (process-buffer process))))
                           (with-current-buffer (process-buffer process)
                             (let ((inhibit-read-only t))
                               (save-excursion
                                 (goto-char (point-max))
                                 (insert (format "\n[exit %d]\n"
                                                 (process-exit-status process)))))))))))
      ;; Its arguments say it all; nothing comes on its input.
      (process-send-eof process))
    (display-buffer buffer)))

;;;###autoload
(defun +ai/claude-mcp-list ()
  "List the MCP servers the claude CLI knows about, connecting to each."
  (interactive)
  (+ai--claude-mcp "list"))
