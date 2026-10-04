;;; private/ai/autoload/gptel.el -*- lexical-binding: t; -*-

(declare-function gptel-make-tool "gptel-request")
(declare-function gptel-api-key-from-auth-source "gptel-request")
(declare-function project-files "project")
(declare-function +core-project-root-or-nil "lib")

;;;###autoload
(defun +ai-anthropic-api-key ()
  "Anthropic API key from ANTHROPIC_API_KEY or ~/.authinfo.gpg."
  (or (getenv "ANTHROPIC_API_KEY")
      (gptel-api-key-from-auth-source "api.anthropic.com")))

(defun +ai--gptel-root ()
  "The project the tools may read, or an error when there is none.
`+core-project-root\=' answers `default-directory\=' outside a project, and a
conversation started from the dashboard or from home would have made
the whole home directory readable, .authinfo.gpg with it."
  (let ((root (+core-project-root-or-nil)))
    (unless root
      (error "Not inside a project, so there is nothing the tools may read"))
    (setq root (file-name-as-directory (expand-file-name root)))
    (when (member root (list (expand-file-name "~/") "/"))
      (error "%s is too much to open to the tools" (abbreviate-file-name root)))
    root))

(defun +ai--gptel-project-file (path)
  "PATH as an absolute file under the project, or an error.
The tools read only inside the project: a document in the conversation
could otherwise ask the model for a key file or a decrypted secret, and
the tools run without confirmation."
  (let* ((root (+ai--gptel-root))
         (file (file-truename (expand-file-name path root))))
    (unless (file-in-directory-p file root)
      (error "%s is outside the project %s" path (abbreviate-file-name root)))
    file))

(defun +ai--gptel-read-buffer (name)
  "Text of buffer NAME, up to 60k characters, when it visits a project file."
  (let ((buffer (or (get-buffer name) (error "No buffer named %s" name))))
    (with-current-buffer buffer
      (unless buffer-file-name
        (error "%s visits no file; only project files are read" name))
      (+ai--gptel-project-file buffer-file-name)
      (buffer-substring-no-properties (point-min) (min (point-max) 60000)))))

(defun +ai--gptel-read-file (path)
  "Text of PATH, a project file, up to 60k characters."
  (let ((file (+ai--gptel-project-file path)))
    (unless (file-readable-p file) (error "Cannot read %s" file))
    (with-temp-buffer
      (insert-file-contents file nil 0 60000)
      (buffer-string))))

(defun +ai--gptel-list-project-files (&optional pattern)
  "Project files, one per line, kept to those matching PATTERN."
  (let* ((root (+ai--gptel-root))
         (files (mapcar (lambda (f) (file-relative-name f root))
                        (project-files (project-current nil root)))))
    (when (and pattern (not (string-empty-p pattern)))
      (setq files (seq-filter (lambda (f) (string-match-p pattern f)) files)))
    (mapconcat #'identity (seq-take files 2000) "\n")))

(defun +ai--gptel-grep-project (regexp)
  "Search the project for REGEXP, as file:line:text."
  (unless (executable-find "rg") (error "ripgrep (rg) is not installed"))
  (let ((default-directory (+ai--gptel-root)))
    (with-temp-buffer
      (call-process "rg" nil t nil
                    "--line-number" "--no-heading" "--color=never"
                    "-e" regexp ".")
      (buffer-substring-no-properties (point-min) (min (point-max) 20000)))))

;;;###autoload
(defun +ai--register-gptel-tools ()
  "Give gptel read-only access to buffers, files and the project."
  (gptel-make-tool
   :name "emacs_read_buffer" :category "emacs" :confirm nil
   :function #'+ai--gptel-read-buffer
   :description "Return the text of an open Emacs buffer that visits a project file."
   :args '((:name "name" :type string :description "Buffer name")))
  (gptel-make-tool
   :name "emacs_read_file" :category "emacs" :confirm nil
   :function #'+ai--gptel-read-file
   :description "Return a project file's contents, path relative to the project root."
   :args '((:name "path" :type string
            :description "File path, relative to the project root")))
  (gptel-make-tool
   :name "emacs_list_project_files" :category "emacs" :confirm nil
   :function #'+ai--gptel-list-project-files
   :description "List the project's files, optionally filtered by a regexp."
   :args '((:name "pattern" :type string :optional t
            :description "Regexp the file name must match")))
  (gptel-make-tool
   :name "emacs_grep_project" :category "emacs" :confirm nil
   :function #'+ai--gptel-grep-project
   :description "Search the project, returning file:line:text matches."
   :args '((:name "regexp" :type string
            :description "Regular expression to search for"))))
