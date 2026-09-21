;;; private/ai/autoload/claude.el -*- lexical-binding: t; -*-
;;
;; Tools Claude can call over MCP, plus the model flag and terminal helpers.

(defvar +ai-claude-model)
(defvar +core-todo-markers)             ; core/autoload/lib.el
(defvar claude-code-ide-cli-extra-flags)
(defvar claude-code-ide-enable-execute-code)
(defvar compilation-in-progress)
(defvar compilation-ask-about-save)
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

(defun +ai--tool-build-project (&optional target wait-seconds)
  "Build the project and return what the compiler said.
TARGET is an optional build target, WAIT-SECONDS how long to wait: the
wait holds Emacs, so it is short by default and capped, and a slow
build is polled with emacs_last_compilation.  Modified buffers are
saved without asking: a y/n prompt while Claude waits would time out
the tool."
  (let* ((root (+core-project-root 'noerror))
         (command (+ai--tool-build-command root target))
         (wait (min 120 (max 2 (or wait-seconds 20))))
         (compilation-ask-about-save nil)
         (buffer (+core-compile "build" command root)))
    (+ai--tool-wait-for-compilation buffer wait)
    (concat (format "command: %s\nroot: %s\nbuffer: %s\n"
                    command (abbreviate-file-name root) (buffer-name buffer))
            (+ai--tool-compilation-tail buffer))))

(defun +ai--tool-last-compilation ()
  "The status and tail of the build, test or run that started last,
whether this tool, a key or a menu started it."
  (if-let* ((buffer (+core-last-compilation-buffer)))
      (concat (format "buffer: %s\n" (buffer-name buffer))
              (+ai--tool-compilation-tail buffer 8000))
    "No build, test or run has started yet."))

(defun +ai--tool-project-todos ()
  "Return the project's markers, `+core-todo-markers', as file:line:text."
  (let ((root (+core-project-root 'noerror)))
    (unless (executable-find "rg") (error "ripgrep (rg) is not installed"))
    (with-temp-buffer
      (let ((default-directory root))
        (call-process "rg" nil t nil
                      "--line-number" "--no-heading" "--color=never"
                      "-e" (+core-todo-regexp) "."))
      (if (= (point-min) (point-max))
          "No TODO/FIXME markers found."
        (buffer-substring-no-properties (point-min) (min (point-max) 12000))))))

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
           "wait_seconds (default 20); if the build is still running, call "
           "emacs_last_compilation afterwards.")
   :args '((:name "target" :type string :optional t
            :description "Build target; omit for the default one")
           (:name "wait_seconds" :type integer :optional t
            :description "Seconds to wait, 2 to 120, default 20"))
   :category "Build")
  (claude-code-ide-make-tool
   :function #'+ai--tool-last-compilation
   :name "emacs_last_compilation"
   :description
   (concat "Return whether the last Emacs build or test is still running, "
           "and the end of its output.")
   :args nil
   :category "Build")
  (claude-code-ide-make-tool
   :function #'+ai--tool-project-todos
   :name "emacs_project_todos"
   :description
   (format "List the %s markers in the project, one per line as file:line:text."
           (string-join +core-todo-markers ", "))
   :args nil
   :category "Project"))


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
  "Use MODEL for new Claude sessions.  Empty means the CLI default."
  (interactive
   (list (completing-read
          "Claude model (empty for the default): "
          '("opus" "sonnet" "haiku" "claude-opus-5" "claude-sonnet-5")
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
