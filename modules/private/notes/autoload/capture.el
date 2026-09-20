;;; private/notes/autoload/capture.el -*- lexical-binding: t; -*-

(declare-function org-capture-get "org-capture")
(declare-function org-cliplink-capture "org-cliplink")
(declare-function doom-project-name "doom-projects")

(defun +notes--capture-buffer ()
  "The buffer `org-capture' was called from."
  (or (org-capture-get :original-buffer) (current-buffer)))

;;;###autoload
(defun +notes--capture-src-lang ()
  "Babel language of the buffer `org-capture' was started from, from
core's one table of languages."
  (+core-language (with-current-buffer (+notes--capture-buffer) major-mode)
                  'babel))

;;;###autoload
(defun +notes--capture-project-name ()
  "Name of the project `org-capture' was started from, or \"-\"."
  (with-current-buffer (+notes--capture-buffer)
    (or (doom-project-name) "-")))
