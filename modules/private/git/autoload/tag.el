;;; private/git/autoload/tag.el -*- lexical-binding: t; -*-
;;
;; Tags, on t in every magit buffer. magit's own menu asked where to put a
;; tag among branch names only, and its name prompt completed to an
;; existing tag when RET was pressed on a new one. Here a tag goes on the
;; commit under the cursor, on any commit found by a word of its message
;; or its hash, on the head of a branch, or on HEAD; the name is typed as
;; it is.

(require 'transient)

(declare-function magit-list-tags "magit-git")
(declare-function magit-git-lines "magit-git")
(declare-function magit-rev-verify "magit-git")
(declare-function magit-run-git-with-editor "magit-process")
(declare-function +git--read-commit "commit")

(defun +git--tag-args ()
  "The switches of whichever tag menu is open, ours or magit's."
  (transient-args '(+git/tag magit-tag)))

(defun +git--read-tag-name (args)
  "A name for a new tag; one that exists only with --force in ARGS."
  (let ((name (string-trim (read-string "Tag name: "))))
    (when (string-empty-p name)
      (user-error "A tag needs a name"))
    (when (and (member name (magit-list-tags))
               (not (member "--force" args)))
      (user-error "There is a tag %s already: -f in the menu moves it" name))
    name))

(defun +git--tag-args-for (prefix)
  "The menu's switches, with --annotate as well under a PREFIX argument."
  (let ((args (+git--tag-args)))
    (if prefix (cons "--annotate" (remove "--annotate" args)) args)))

;;;###autoload
(defun +git/tag-create (name commit &optional args)
  "Tag COMMIT as NAME. COMMIT is the one under the cursor, or any commit
of any branch found by a word of its message or its hash; each is listed
with the branches and tags already on it. With a prefix argument the tag
is annotated."
  (interactive
   (let ((args (+git--tag-args-for current-prefix-arg)))
     (list (+git--read-tag-name args)
           (+git--read-commit "Place the tag on" 'everywhere)
           args)))
  (magit-run-git-with-editor "tag" args name commit))

;;;###autoload
(defun +git/tag-branch (name branch &optional args)
  "Tag the head of BRANCH as NAME, BRANCH picked with its last commit."
  (interactive
   (let* ((args (+git--tag-args-for current-prefix-arg))
          (name (+git--read-tag-name args))
          (heads (magit-git-lines
                  "for-each-ref" "--sort=-committerdate"
                  "--format=%(refname:short)  %(objectname:short)  %(committerdate:short)  %(subject)"
                  "refs/heads" "refs/remotes"))
          (choice (completing-read
                   (format "Tag %s on the head of: " name)
                   (lambda (string pred action)
                     (if (eq action 'metadata)
                         '(metadata (display-sort-function . identity))
                       (complete-with-action action heads string pred)))
                   nil t))
          (branch (car (split-string choice))))
     (unless (magit-rev-verify branch)
       (user-error "No branch %s" choice))
     (list name branch args)))
  (magit-run-git-with-editor "tag" args name branch))

;;;###autoload
(defun +git/tag-head (name &optional args)
  "Tag HEAD, the commit checked out, as NAME."
  (interactive
   (let ((args (+git--tag-args-for current-prefix-arg)))
     (list (+git--read-tag-name args) args)))
  (magit-run-git-with-editor "tag" args name "HEAD"))

;;;###autoload (autoload '+git/tag "private/git/autoload/tag" nil t)
(transient-define-prefix +git/tag ()
  "Tags: where to put one, and what to do with them."
  ["Switches"
   ("-a" "Annotated, with a message" ("-a" "--annotate"))
   ("-f" "Move a tag that exists"    ("-f" "--force"))
   ("-s" "Signed"                    ("-s" "--sign"))]
  [["Tag"
    ("t" "A commit: under the cursor, or by message or hash" +git/tag-create)
    ("b" "The head of a branch"        +git/tag-branch)
    ("h" "HEAD, the commit you are on" +git/tag-head)
    ("r" "A release, the next version" magit-tag-release)]
   ["Share and remove"
    ("P" "Push a tag"                  magit-push-tag)
    ("x" "Delete a tag"                magit-tag-delete)
    ("p" "Prune: tags one side lost, from the other" magit-tag-prune)]])
