;;; private/git/autoload/branch.el -*- lexical-binding: t; -*-
;;
;; Branches, the few moves magit has no single key for: a fresh branch
;; from the remote's main, the merged ones swept away, and what this
;; branch holds that main does not.

(declare-function magit-main-branch "magit-git")
(declare-function magit-get-remote "magit-git")
(declare-function magit-get-current-branch "magit-git")
(declare-function magit-git-lines "magit-git")
(declare-function magit-read-string-ns "magit-utils")
(declare-function magit-run-git "magit-process")
(declare-function magit-diff-range "magit-diff")
(declare-function magit-log-other "magit-log")

(defun +git--main ()
  "The main branch of this repository, main or master, whatever it is
called here."
  (or (magit-main-branch) "main"))

;;;###autoload
(defun +git/branch-from-main (name)
  "Create the branch NAME from the main branch and switch to it.
The main branch is fetched first when it has a remote, so the new branch
starts from what the remote has, whatever branch you are on now."
  (interactive (list (magit-read-string-ns "New branch from main")))
  (let* ((main (+git--main))
         (remote (magit-get-remote main))
         (start (if remote
                    (progn (magit-run-git "fetch" remote main)
                           (concat remote "/" main))
                  main)))
    (magit-run-git "checkout" "-b" name start)
    (message "%s branched from %s" name start)))

;;;###autoload
(defun +git/delete-merged ()
  "Delete every local branch already merged into main, after showing
the list.  Main itself and the current branch stay."
  (interactive)
  (let* ((main (+git--main))
         (current (magit-get-current-branch))
         (merged (seq-remove (lambda (branch)
                               (or (string-prefix-p "*" branch)
                                   (member branch (list main current "master" "main"))))
                             (mapcar #'string-trim (magit-git-lines "branch" "--merged" main)))))
    (cond ((null merged) (message "No branch is merged into %s" main))
          ((y-or-n-p (format "Delete %d merged branch(es): %s? "
                             (length merged) (string-join merged ", ")))
           (apply #'magit-run-git "branch" "-d" merged)
           (message "Deleted %s" (string-join merged ", "))))))

;;;###autoload
(defun +git/diff-main ()
  "The diff between main and this branch: what this branch changes."
  (interactive)
  (magit-diff-range (format "%s...HEAD" (+git--main))))

;;;###autoload
(defun +git/log-since-main ()
  "The commits of this branch that main does not have."
  (interactive)
  (magit-log-other (list (format "%s..HEAD" (+git--main)))))
