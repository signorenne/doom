;;; private/git/autoload/commit.el -*- lexical-binding: t; -*-
;;
;; Commits: the conventional subject, and rewriting one that exists,
;; its date, its author, or splitting it. A commit that is not HEAD is
;; reached by a rebase that stops there, amended, and the rebase goes
;; on; git does the same by hand, in three commands.

(defvar +git-commit-types)              ; config.el
(defvar +git-date-format)
(declare-function magit-staged-files "magit-git")
(declare-function magit-commit-at-point "magit-git")
(declare-function magit-read-branch-or-commit "magit-git")
(declare-function magit-rev-parse "magit-git")
(declare-function magit-rev-verify "magit-git")
(declare-function magit-rev-format "magit-git")
(declare-function magit-rev-abbrev "magit-git")
(declare-function magit-get "magit-git")
(declare-function magit-run-git "magit-process")
(declare-function magit-rebase-in-progress-p "magit-sequence")
(declare-function magit-merge-in-progress-p "magit-merge")
(declare-function magit-reset-soft "magit-reset")
(declare-function magit-toplevel "magit-git")
(declare-function org-read-date "org")
(declare-function org-time-string-to-time "org")


;;
;;; The subject

(defun +git--staged-files ()
  "The staged files, relative to the repository."
  (magit-staged-files))

(defun +git--scopes (files)
  "Scope candidates for FILES, the likeliest first: a private module's
name for modules/private/NAME/..., the first directory otherwise, and
the base name of a file at the top of the repository."
  (let (scopes)
    (dolist (file files)
      (let ((parts (split-string file "/" t)))
        (push (cond ((and (equal (car parts) "modules")
                          (equal (cadr parts) "private")
                          (nth 2 parts))
                     (nth 2 parts))
                    ((cdr parts) (car parts))
                    (t (file-name-sans-extension (car parts))))
              scopes)))
    (seq-sort-by (lambda (scope) (- (seq-count (lambda (s) (equal s scope)) scopes)))
                 #'<
                 (seq-uniq scopes))))

;;;###autoload
(defun +git/commit-conventional (type scope)
  "Start the commit subject with TYPE(SCOPE): the shape the house rule
and bin/check-commit-msg want.  TYPE is one of `+git-commit-types';
SCOPE is offered from the staged paths, the likeliest first, and may
be emptied for a commit that has none."
  (interactive
   (let* ((scopes (+git--scopes (+git--staged-files)))
          (type (completing-read "Type: " +git-commit-types nil t))
          (scope (string-trim
                  (completing-read "Scope (empty for none): " scopes nil nil
                                   (car scopes)))))
     (list type scope)))
  (goto-char (point-min))
  (insert (if (string-empty-p scope)
              (format "%s: " type)
            (format "%s(%s): " type scope)))
  (when (fboundp 'evil-insert-state) (evil-insert-state)))


;;
;;; Reaching a commit

(defun +git--commit-to-change (verb)
  "The commit at point, else one asked for with VERB."
  (or (magit-commit-at-point)
      (magit-read-branch-or-commit verb)))

(defun +git--head-p (commit)
  "Non-nil when COMMIT is HEAD."
  (equal (magit-rev-parse commit) (magit-rev-parse "HEAD")))

(defun +git--check-ready ()
  "Refuse while a rebase or a merge waits for a hand."
  (when (or (magit-rebase-in-progress-p) (magit-merge-in-progress-p))
    (user-error "A rebase or merge is in progress; finish it first")))

(defun +git--stop-at (commit)
  "Start a rebase that stops at COMMIT, its changes committed, so it can
be amended.  The working tree is stashed round the rebase.  Returns
non-nil when the rebase stopped there."
  (let* ((hash (magit-rev-parse commit))
         (short (substring hash 0 7))
         (parent (and (magit-rev-verify (concat hash "^")) (concat hash "^")))
         (process-environment
          (append (list (format "GIT_SEQUENCE_EDITOR=sed -i %s"
                                (shell-quote-argument
                                 (format "s/^pick \\(%s[0-9a-f]*\\)/edit \\1/" short)))
                        "GIT_EDITOR=true")
                  process-environment)))
    (magit-run-git "rebase" "-i" "--autostash" (or parent "--root"))
    (and (magit-rebase-in-progress-p)
         (equal (magit-rev-parse "HEAD") hash))))

(defun +git--go-on ()
  "Continue the rebase that `+git--stop-at' started."
  (let ((process-environment (cons "GIT_EDITOR=true" process-environment)))
    (magit-run-git "rebase" "--continue"))
  (when (magit-rebase-in-progress-p)
    (message "The rebase stopped on its way; finish it in magit (r r continues)")))

(defmacro +git--amending (commit &rest body)
  "Run BODY, which amends HEAD, with COMMIT as HEAD: directly when it is,
else inside a rebase stopped at it, continued afterwards."
  (declare (indent 1))
  (let ((c (make-symbol "commit")))
    `(let ((,c ,commit))
       (+git--check-ready)
       (if (+git--head-p ,c)
           (progn ,@body)
         (unless (+git--stop-at ,c)
           (user-error "The rebase did not stop at %s; see the magit status"
                       (magit-rev-abbrev ,c)))
         ,@body
         (+git--go-on)))))


;;
;;; Date and author

(defun +git--author-date (commit)
  "COMMIT's author date, in `+git-date-format'."
  (magit-rev-format "%ad" commit (concat "--date=format:" +git-date-format)))

(defun +git--read-date (default)
  "A date for git, read the org way when org is there: +3d 10:00,
2026-09-01 14:00, or DEFAULT untouched."
  (if (and (require 'org nil t) (fboundp 'org-read-date))
      (org-read-date t nil nil "Date: "
                     (and default (ignore-errors (org-time-string-to-time default))))
    (read-string (format "Date (%s): " +git-date-format) default)))

;;;###autoload
(defun +git/commit-set-date (commit date)
  "Give COMMIT, at point or asked, the author and committer DATE.
HEAD is amended in place; an older commit through a rebase that stops
at it and goes on, which rewrites the commits after it, as any rebase
does.  DATE is read the org way: +3d 10:00, 2026-09-01 14:00."
  (interactive
   (let ((commit (+git--commit-to-change "Change the date of")))
     (list commit (+git--read-date (+git--author-date commit)))))
  (+git--amending commit
    (let ((process-environment (cons (concat "GIT_COMMITTER_DATE=" date)
                                     process-environment)))
      (magit-run-git "commit" "--amend" "--no-edit" (concat "--date=" date))))
  (message "%s is dated %s" (magit-rev-abbrev commit) date))

;;;###autoload
(defun +git/commit-set-author (commit author)
  "Give COMMIT, at point or asked, the AUTHOR, as Name <email>.
HEAD is amended in place, an older commit through a rebase that stops
at it and goes on."
  (interactive
   (let ((commit (+git--commit-to-change "Change the author of")))
     (list commit
           (read-string "Author (Name <email>): "
                        (magit-rev-format "%an <%ae>" commit)
                        nil
                        (format "%s <%s>" (magit-get "user.name") (magit-get "user.email"))))))
  (when (string-empty-p (string-trim author))
    (user-error "An author is a name and an address"))
  (+git--amending commit
    (magit-run-git "commit" "--amend" "--no-edit" (concat "--author=" author)))
  (message "%s is by %s" (magit-rev-abbrev commit) author))


;;
;;; Taking a commit apart

;;;###autoload
(defun +git/uncommit ()
  "Undo the last commit and keep its changes staged, to commit again
differently.  The commit stays in the reflog and the WIP log."
  (interactive)
  (+git--check-ready)
  (let ((subject (magit-rev-format "%s" "HEAD")))
    (magit-reset-soft "HEAD^")
    (message "Uncommitted, the changes are staged: %s" subject)))

;;;###autoload
(defun +git/commit-split (commit)
  "Take COMMIT, at point or asked, apart: its changes come back
unstaged, to be staged and committed in pieces.  HEAD is undone in
place; an older commit through a rebase that stops at it.  Then stage
a piece (s), commit it (c c), again, and continue the rebase (r r)."
  (interactive (list (+git--commit-to-change "Split")))
  (+git--check-ready)
  (let ((subject (magit-rev-format "%s" commit)))
    (if (+git--head-p commit)
        (magit-run-git "reset" "HEAD^")
      (unless (+git--stop-at commit)
        (user-error "The rebase did not stop at %s; see the magit status"
                    (magit-rev-abbrev commit)))
      (magit-run-git "reset" "HEAD^"))
    (message "%s is undone, its changes unstaged: stage and commit the pieces, then %s"
             subject
             (if (magit-rebase-in-progress-p) "r r continues the rebase" "you are done"))))
