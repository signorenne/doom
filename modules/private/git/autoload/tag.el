;;; private/git/autoload/tag.el -*- lexical-binding: t; -*-
;;
;; magit's t t asked where to put the tag among branch names only, and its
;; name prompt completed to an existing tag when RET was pressed on a new
;; one. Here the name is typed as it is, and the place is picked from the
;; latest commits by date and subject, see `+git--read-commit'.

(declare-function magit-list-tags "magit-git")
(declare-function +git--read-commit "commit")
(declare-function magit-tag-arguments "magit-tag")
(declare-function magit-run-git-with-editor "magit-process")

;;;###autoload
(defun +git/tag-create (name commit &optional args)
  "Tag COMMIT as NAME. COMMIT is picked from the latest commits by date
and subject, the one under the cursor first. With a prefix argument the
tag is annotated, as magit's own."
  (interactive
   (let ((args (magit-tag-arguments)))
     (when current-prefix-arg
       (cl-pushnew "--annotate" args :test #'equal))
     (let ((name (string-trim (read-string "Tag name: "))))
       (when (string-empty-p name)
         (user-error "A tag needs a name"))
       (when (and (member name (magit-list-tags))
                  (not (member "--force" args)))
         (user-error "There is a tag %s already: -f in the menu moves it" name))
       (list name (+git--read-commit "Place the tag on") args))))
  (magit-run-git-with-editor "tag" args name commit))
