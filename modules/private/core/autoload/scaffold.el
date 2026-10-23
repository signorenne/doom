;;; private/core/autoload/scaffold.el -*- lexical-binding: t; -*-

(defvar +core-projects-dir)

;;
;;; Project templates

;; A tree of files with {{PROJECT}} in the names and the text, copied
;; into a new project with the name filled in. Several language modules
;; scaffold this way, so the copier is shared in core.

;;;###autoload
(defvar +core-github-user "signorenne"
  "The GitHub user a new project's homepage names, {{GITHUB_USER}} in
the templates.")

;;;###autoload
(defun +core-copy-template (src dir name)
  "Copy the tree at SRC into DIR, the placeholders replaced with NAME."
  (dolist (file (directory-files-recursively src ".*" nil nil t))
    (let* ((rel (+core-expand-placeholders (file-relative-name file src)
                                           name))
           (target (expand-file-name rel dir)))
      (make-directory (file-name-directory target) t)
      (with-temp-file target
        (insert (+core-expand-placeholders
                 (with-temp-buffer
                   (insert-file-contents file)
                   (buffer-string))
                 name))))))

;;;###autoload
(defun +core-expand-placeholders (text name)
  "Replace the template placeholders in TEXT: NAME, its upper case, and
the GitHub user of `+core-github-user'."
  (thread-last text
               (string-replace "{{PROJECT_UPPER}}" (upcase name))
               (string-replace "{{PROJECT}}" name)
               (string-replace "{{GITHUB_USER}}" +core-github-user)))

;;;###autoload
(defun +core-read-new-project ()
  "Ask where a new project goes and what it is called."
  (let* ((parent (read-directory-name "Create project in: "
                                      +core-projects-dir nil t))
         (name (read-string "Project name: ")))
    (unless (string-match-p "\\`[a-z][a-z0-9_]*\\'" name)
      (user-error "Use lower_snake_case for the name: %s" name))
    (list (expand-file-name name parent) name)))
