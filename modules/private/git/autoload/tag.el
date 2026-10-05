;;; private/git/autoload/tag.el -*- lexical-binding: t; -*-
;;
;; magit's t t asked where to put the tag among branch names only, so a
;; commit was reached by its hash or by standing on it first; and the name
;; prompt completed to an existing tag when RET was pressed on a new one.
;; Here the name is typed as it is, and the prompt for the place lists the
;; latest commits with their dates and subjects, the one under the cursor
;; first; typing a word of a message finds it.

(declare-function magit-commit-at-point "magit-git")
(declare-function magit-git-lines "magit-git")
(declare-function magit-list-refnames "magit-git")
(declare-function magit-list-tags "magit-git")
(declare-function magit-rev-verify "magit-git")
(declare-function magit-tag-arguments "magit-tag")
(declare-function magit-run-git-with-editor "magit-process")

(defvar +git-tag-commits 500
  "How many of the latest commits the tag prompt lists.")

(defun +git--tag-targets ()
  "What a tag can go on: the commit at point, the latest commits as
\"HASH  DATE  SUBJECT\", then the branches and tags."
  (let ((fields "--format=%h  %ad  %s"))
    (delete-dups
     (append (when-let* ((at (magit-commit-at-point)))
               (magit-git-lines "log" "-1" fields "--date=short" at))
             (magit-git-lines "log" (format "-%d" +git-tag-commits)
                              fields "--date=short")
             (magit-list-refnames nil t)))))

(defun +git--read-tag-target ()
  "A commit to tag, read from `+git--tag-targets' in their order."
  (let* ((targets (+git--tag-targets))
         (choice (completing-read
                  "Place the tag on (a commit, a branch or a tag): "
                  (lambda (string pred action)
                    (if (eq action 'metadata)
                        '(metadata (display-sort-function . identity)
                                   (cycle-sort-function . identity))
                      (complete-with-action action targets string pred)))
                  nil nil nil 'magit-revision-history (car targets)))
         (rev (car (split-string choice))))
    (unless (and rev (magit-rev-verify rev))
      (user-error "No commit, branch or tag %s" choice))
    rev))

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
       (list name (+git--read-tag-target) args))))
  (magit-run-git-with-editor "tag" args name commit))
