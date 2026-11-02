;;; private/ai/autoload/claude.el -*- lexical-binding: t; -*-
;;
;; Tools Claude can call over MCP, plus the model flag and terminal helpers.

(defvar +ai-claude-model)
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
(declare-function claude-code-ide "claude-code-ide")
(declare-function claude-code-ide--get-buffer-name "claude-code-ide")
(declare-function claude-code-ide--get-working-directory "claude-code-ide")
(declare-function claude-code-ide-switch-to-buffer "claude-code-ide")
(declare-function claude-code-ide-mcp-session-client "claude-code-ide-mcp")
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
  "Return the project's markers, `+core-todo-markers', as file:line:text."
  (let ((root (+ai--tool-root)))
    (unless (executable-find "rg") (error "ripgrep (rg) is not installed"))
    (with-temp-buffer
      (let ((default-directory root))
        (call-process "rg" nil t nil
                      "--line-number" "--no-heading" "--color=never"
                      "-e" (+core-todo-regexp) "."))
      (if (= (point-min) (point-max))
          "No TODO/FIXME markers found."
        (buffer-substring-no-properties (point-min) (min (point-max) 12000))))))

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
   (list (completing-read
          "Claude model (empty for the default): "
          '("fable" "opus" "sonnet" "haiku")
          nil nil (or +ai-claude-model ""))))
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

(defun +ai--terminal-buffer (&optional dir)
  "The Claude terminal of DIR's project, default this one, while it runs."
  (let ((buffer (get-buffer (claude-code-ide--get-buffer-name
                             (or dir (claude-code-ide--get-working-directory))))))
    (and buffer (process-live-p (get-buffer-process buffer)) buffer)))

;;;###autoload
(defun +ai/terminal ()
  "Focus this project's Claude terminal, or start one when none runs.
`claude-code-ide' alone always starts another instance."
  (interactive)
  (require 'claude-code-ide)
  (if (+ai--terminal-buffer)
      (claude-code-ide-switch-to-buffer)
    (claude-code-ide)))

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

(defvar-local +ai--compose-index nil
  "The prompt of `+ai--compose-history' that M-p and M-n showed last.")

;;;###autoload
(defun +ai/terminal-compose ()
  "Write a prompt for this project's Claude terminal in a buffer.
C-c C-c sends it, C-c C-k drops it, M-p and M-n bring back the last
prompts.  An active region comes along as a fenced block."
  (interactive)
  (require 'claude-code-ide)
  (let* ((dir (claude-code-ide--get-working-directory))
         (block (when (use-region-p)
                  (format "```%s\n%s\n```\n" (+core-language major-mode)
                          (buffer-substring-no-properties
                           (region-beginning) (region-end)))))
         (buffer (get-buffer-create
                  (format "*claude-compose[%s]*"
                          (file-name-nondirectory (directory-file-name dir))))))
    (deactivate-mark)
    (with-current-buffer buffer
      (unless +ai-compose-mode
        (if (fboundp 'gfm-mode) (gfm-mode) (markdown-mode))
        (+ai-compose-mode +1))
      (setq default-directory dir
            +ai--compose-dir dir)
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
With no terminal running, start one and send once Claude is up."
  (interactive)
  (let ((text (string-trim (buffer-string)))
        (compose (current-buffer))
        (dir +ai--compose-dir))
    (when (string-empty-p text)
      (user-error "Nothing to send"))
    (setq +ai--compose-history
          (seq-take (cons text (delete text +ai--compose-history)) 20))
    (if-let* ((terminal (+ai--terminal-buffer dir)))
        (progn (+ai--terminal-send terminal text)
               (kill-buffer compose))
      (let ((default-directory dir))
        (claude-code-ide))
      (+ai--compose-send-when-ready compose dir text (+ (float-time) 15)))))

;;;###autoload
(defun +ai/terminal-compose-cancel ()
  "Close this compose buffer without sending."
  (interactive)
  (kill-buffer (current-buffer)))

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
(defun +ai/claude-mcp-list ()
  "List the MCP servers the claude CLI knows about."
  (interactive)
  (let ((default-directory (+core-project-root 'noerror)))
    (compile "claude mcp list")))
