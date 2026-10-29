;;; private/git/autoload/menu.el -*- lexical-binding: t; -*-
;;
;; Three menus in plain words. magit spreads the same commands over a
;; dozen of its own transients, each under its key; these gather them
;; by what you are trying to do. SPC g SPC is the hub, SPC g h the
;; history (rewriting commits), SPC g n the branches. A command in two
;; of them has the same key in both: u uncommits, r rebases, b switches.

(require 'transient)

;;;###autoload (autoload '+git/history "private/git/autoload/menu" nil t)
(transient-define-prefix +git/history ()
  "Rewrite history: the commit at point, or HEAD, or a range."
  [:description "History: the commit at point, or HEAD"
   ["Change this commit"
    ("w" "Reword its message"          magit-rebase-reword-commit)
    ("e" "Edit it: stop there, amend"  magit-rebase-edit-commit)
    ("d" "Change its date"             +git/commit-set-date)
    ("a" "Change its author"           +git/commit-set-author)
    ("s" "Split it into pieces"        +git/commit-split)
    ("k" "Drop it"                     magit-rebase-remove-commit)]
   ["The last commit"
    ("A" "Amend: the staged changes, edit the message" magit-commit-amend)
    ("E" "Extend: the staged changes, same message"    magit-commit-extend)
    ("W" "Reword the last message"     magit-commit-reword)
    ("u" "Uncommit, the changes stay staged" +git/uncommit)]
   ["Several commits"
    ("i" "Reorder, squash, edit freely" magit-rebase-interactive)
    ("f" "Fixup: the staged changes into a commit" magit-commit-fixup)
    ("F" "Instant fixup, no rebase to finish"      magit-commit-instant-fixup)
    ("S" "Squash the fixup! commits in"            magit-rebase-autosquash)
    ("c" "Cherry-pick from elsewhere"  magit-cherry-pick)
    ("v" "Revert, a new undoing commit" magit-revert)
    ("r" "Rebase onto..."              magit-rebase)]]
  [["A rebase in progress"
    ("C" "Continue"                    magit-rebase-continue)
    ("n" "Skip this commit"            magit-rebase-skip)
    ("x" "Abort, back to the start"    magit-rebase-abort)]
   ["Recover"
    ("l" "The reflog: where HEAD has been" magit-reflog-current)
    ("L" "The WIP log: every save and step" magit-wip-log-current)
    ("R" "Reset to a commit..."        magit-reset)]])

;;;###autoload (autoload '+git/branches "private/git/autoload/menu" nil t)
(transient-define-prefix +git/branches ()
  "Branches: make one, work with one, compare it with main."
  [["Make one"
    ("n" "New from here, switch to it"          magit-branch-and-checkout)
    ("m" "New from main, fetched first, switch" +git/branch-from-main)
    ("N" "New, stay where you are"              magit-branch-create)
    ("s" "Spin off: my commits onto a new one"  magit-branch-spinoff)
    ("o" "Orphan, no history"                   magit-branch-orphan)]
   ["Work with"
    ("b" "Switch, a remote one is tracked"      magit-branch-checkout)
    ("R" "Rename"                               magit-branch-rename)
    ("u" "Upstream and push target"             magit-branch-configure)
    ("p" "Push, setting the upstream if missing" magit-push-current-to-upstream)
    ("k" "Delete"                               magit-branch-delete)
    ("K" "Delete every merged one"              +git/delete-merged)
    ("x" "Reset it to..."                       magit-branch-reset)]
   ["Against main"
    ("d" "What this branch changes"             +git/diff-main)
    ("l" "My commits since main"                +git/log-since-main)
    ("y" "Cherries: not upstream yet"           magit-cherry)
    ("a" "Every branch and its state"           magit-show-refs)
    ("M" "Merge into this one..."               magit-merge)
    ("r" "Rebase this one onto..."              magit-rebase)]
   ["Remote"
    ("f" "Fetch every remote"                   magit-fetch-all)
    ("F" "Pull"                                 magit-pull)]])

;;;###autoload (autoload '+git/menu "private/git/autoload/menu" nil t)
(transient-define-prefix +git/menu ()
  "Git: every day, the menus, the repositories, the tools.
The keys agree with SPC g where both have the command, b switches a
branch and B blames as there; what magit spreads over its own
transients is one key away on /, its dispatch."
  [["Every day"
    ("g" "Status"              magit-status)
    ("c" "Commit"              magit-commit)
    ("u" "Uncommit the last"   +git/uncommit)
    ("p" "Push"                magit-push)
    ("f" "Fetch"               magit-fetch)
    ("F" "Pull"                magit-pull)
    ("l" "Log"                 magit-log)
    ("G" "Every branch in one graph" magit-log-all-branches)
    ("d" "Diff"                magit-diff)
    ("b" "Switch branch"       magit-branch-checkout)
    ("B" "Blame this file"     magit-blame-addition)
    ("L" "This file's history, the region's lines if any" magit-log-buffer-file)
    ("a" "This function's history" magit-log-trace-definition)
    ("v" "This file as it was before" magit-blob-previous)
    ("t" "Time machine"        git-timemachine-toggle
     :if (lambda () (fboundp 'git-timemachine-toggle)))]
   ["Menus"
    ("h" "History: rewrite commits" +git/history)
    ("n" "Branches"            +git/branches)
    ("x" "Conflicts"           +git/conflicts)
    ("z" "Stashes"             magit-stash)
    ("M" "Remotes"             magit-remote)
    ("T" "Tags"                +git/tag)
    ("/" "Everything else: magit's dispatch" magit-dispatch)]
   ["Repositories"
    ("C" "Clone"               magit-clone)
    ("I" "Init here"           magit-init)
    ("o" "Browse this on the forge" +vc/browse-at-remote
     :if (lambda () (fboundp '+vc/browse-at-remote)))
    ("y" "Copy a link to this" +vc/browse-at-remote-kill
     :if (lambda () (fboundp '+vc/browse-at-remote-kill)))
    ("i" "Ignore a file"       magit-gitignore)]
   ["This buffer"
    ("]" "Next change"         +vc-gutter/next-hunk :transient t)
    ("[" "Previous change"     +vc-gutter/previous-hunk :transient t)
    ("." "Show the change here" diff-hl-show-hunk)
    ("s" "Stage this change"   +vc-gutter/stage-hunk)
    ("r" "Revert this change"  +vc-gutter/save-and-revert-hunk)]
   ["Tools"
    ("w" "Worktrees"           magit-worktree)
    ("!" "Run a git command"   magit-git-command)
    ("$" "The process log"     magit-process-buffer)]])

;;
;;; Conflicts

;; Doom turns smerge-mode on by itself when a file is opened with
;; conflict markers in it, and puts the commands on the localleader,
;; where nobody finds them in the middle of a rebase. They are gathered
;; in a menu instead, with the two motions on ]n and [n as vim has them.

(declare-function diff-hl-show-hunk "diff-hl-show-hunk")
(declare-function smerge-next "smerge-mode")
(declare-function smerge-prev "smerge-mode")
(declare-function smerge-keep-upper "smerge-mode")
(declare-function smerge-keep-lower "smerge-mode")
(declare-function smerge-keep-base "smerge-mode")
(declare-function smerge-keep-all "smerge-mode")
(declare-function smerge-keep-current "smerge-mode")
(declare-function smerge-resolve "smerge-mode")
(declare-function smerge-refine "smerge-mode")
(declare-function smerge-combine-with-next "smerge-mode")
(declare-function smerge-ediff "smerge-mode")
(declare-function smerge-vc-next-conflict "smerge-mode")
(defvar smerge-mode)

(declare-function smerge-match-conflict "smerge-mode")
(declare-function magit-rebase-in-progress-p "magit-sequence")

(defun +git--conflicted-p ()
  "Non-nil when this buffer has conflict markers in it."
  (bound-and-true-p smerge-mode))

(defun +git--conflict-has-base-p ()
  "Non-nil when the conflict at point shows the base between its sides:
git writes it with zdiff3, which the git module asks for, or diff3."
  (and (+git--conflicted-p)
       (save-excursion
         (ignore-errors (smerge-match-conflict) (match-beginning 2)))))

(defun +git--rebasing-p ()
  "Non-nil while a rebase is in progress here, which swaps the sides."
  (and (featurep 'magit)
       (ignore-errors (magit-rebase-in-progress-p))))

(declare-function vc-find-conflicted-file "vc")

(defun +git--keep-then-next (keep)
  "Resolve the conflict at point with KEEP, then move to the next one,
in this file or, once it has none, saved, in the next that has one."
  (funcall keep)
  (if (bound-and-true-p smerge-mode)
      (ignore-errors (smerge-next))
    (save-buffer)
    (ignore-errors (vc-find-conflicted-file))))

;;;###autoload
(defun +git/conflict-keep-upper ()
  "Keep the upper side of this conflict, then go to the next."
  (interactive)
  (+git--keep-then-next #'smerge-keep-upper))

;;;###autoload
(defun +git/conflict-keep-lower ()
  "Keep the lower side of this conflict, then go to the next."
  (interactive)
  (+git--keep-then-next #'smerge-keep-lower))

;;;###autoload
(defun +git/conflict-keep-base ()
  "Keep the base of this conflict, as it was before either side, then
go to the next."
  (interactive)
  (+git--keep-then-next #'smerge-keep-base))

;;;###autoload
(defun +git/conflict-keep-current ()
  "Keep the side point is in, then go to the next conflict."
  (interactive)
  (+git--keep-then-next #'smerge-keep-current))

;;;###autoload
(defun +git/conflict-keep-all ()
  "Keep both sides of this conflict, then go to the next."
  (interactive)
  (+git--keep-then-next #'smerge-keep-all))

;;;###autoload
(defun +git/next-conflict ()
  "The next conflict in this file, or the next file that has one."
  (interactive)
  (require 'smerge-mode)
  (if (bound-and-true-p smerge-mode)
      (condition-case nil (smerge-next)
        (error (smerge-vc-next-conflict)))
    (smerge-vc-next-conflict)))

;;;###autoload
(defun +git/previous-conflict ()
  "The conflict before this one."
  (interactive)
  (require 'smerge-mode)
  (unless (bound-and-true-p smerge-mode)
    (user-error "No conflict in this buffer"))
  (smerge-prev))

;; The sides are named by what they are: in a merge, a cherry-pick or a
;; revert the upper is yours and the lower the change coming in; in a
;; rebase it is the other way round.
;;;###autoload (autoload '+git/conflicts "private/git/autoload/menu" nil t)
(transient-define-prefix +git/conflicts ()
  "What to do with a conflict: which side to keep, and where the next one is.
Keeping a side moves to the next conflict, the menu staying open."
  :refresh-suffixes t
  [:description
   (lambda ()
     (cond ((not (bound-and-true-p smerge-mode))
            "No conflict here; n finds the next file with one")
           ((+git--rebasing-p)
            "Conflict, while rebasing: upper is the branch rebased onto, lower your commit")
           (t "Conflict: upper is yours, lower the change coming in")))
   ["Keep, then the next"
    ("u" +git/conflict-keep-upper :if +git--conflicted-p :transient t
     :description (lambda () (if (+git--rebasing-p)
                                 "The branch rebased onto, upper"
                               "Yours, upper")))
    ("l" +git/conflict-keep-lower :if +git--conflicted-p :transient t
     :description (lambda () (if (+git--rebasing-p)
                                 "Your commit, lower"
                               "The change coming in, lower")))
    ("b" "The base, before either" +git/conflict-keep-base
     :if +git--conflicted-p :inapt-if-not +git--conflict-has-base-p :transient t)
    ("a" "Both, one after the other" +git/conflict-keep-all
     :if +git--conflicted-p :transient t)
    ("c" "The one point is in" +git/conflict-keep-current
     :if +git--conflicted-p :transient t)]
   ["Look closer"
    ("e" "Ediff this one"        smerge-ediff :if +git--conflicted-p)
    ("R" "Refine: what differs inside it" smerge-refine :if +git--conflicted-p)
    ("r" "Resolve it, if it is obvious"   smerge-resolve :if +git--conflicted-p)
    ("C" "Join it to the next"   smerge-combine-with-next :if +git--conflicted-p)]
   ["Move"
    ("n" "Next conflict, or the next file" +git/next-conflict :transient t)
    ("p" "The one before"        +git/previous-conflict :transient t)
    ("g" "The status buffer"     magit-status)]])
