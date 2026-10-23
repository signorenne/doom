;;; private/git/config.el -*- lexical-binding: t; -*-
;;
;; Git for the power user, on Doom's magit: the settings that show more
;; and ask less, dates instead of ages, a safety net of work-in-progress
;; refs, and three menus in plain words (SPC g SPC, SPC g h, SPC g n)
;; for what magit spreads over its own. Everything in the menus is a
;; magit command; the few helpers of this module rewrite a commit's
;; date or author and split one, and run git through magit. The notes
;; repository keeps its own commands in the notes module.

;; Doom loads magit in the background after starting, a package a step,
;; and Emacs does not answer keys during a step. magit with everything
;; it pulls in is a long one, so its parts go first, a step each.
(defvar +git-incremental-parts
  '(magit-section magit-git magit-mode magit-process magit-core magit-diff
    magit-apply magit-log magit-wip epa ibuffer projectile)
  "Libraries loaded in the background before magit, each its own step.")

(defvar +git--incremental-split nil
  "Non-nil once magit's parts are in Doom's queue, so a reload does not
put them in twice; org-roam queues magit-section for itself, later.")

(when-let* (((not +git--incremental-split))
            (tail (memq 'magit doom-incremental-packages)))
  (setcdr tail (cons 'magit (cdr tail)))
  (setcar tail (car +git-incremental-parts))
  (setcdr tail (append (cdr +git-incremental-parts) (cdr tail)))
  (setq +git--incremental-split t))

(defvar +git-docs
  '(:groups (("git" "Git" (magit) magit-mode-map magit-status-mode-map
              git-commit-mode-map))
    :sections ((magit-status-mode . "Git")
               (magit-log-mode . "Git")
               (magit-diff-mode . "Git")
               (magit-revision-mode . "Git")
               (magit-refs-mode . "Git")
               (git-commit-mode . "Git")
               (git-rebase-mode . "Git")
               (smerge-mode . "Git")))
  "How the cheat sheet documents this module; see `+docs--module-docs'.")

(defvar +git-commit-types
  '("feat" "fix" "refactor" "perf" "docs" "chore" "test" "style" "build"
    "ci" "revert")
  "The types a commit subject starts with, type(scope): what, the list
bin/check-commit-msg accepts.")

(defvar +git-date-format "%Y-%m-%d %H:%M"
  "How a date is written when a commit's date is changed; git reads it.")


;;
;;; magit

(after! magit
  ;; Doom's magit module let-binds `projectile-verbose' and two of its
  ;; neighbours in its refresh hook. That file is lexically bound, so
  ;; with projectile not yet loaded the three become lexical bindings,
  ;; and projectile's own defcustom then fails with "Defining as
  ;; dynamic an already lexical var" when magit opens before any file.
  ;; Loading projectile first makes them special, as the let means them
  ;; to be.
  (require 'projectile nil t)

  (setq
   ;; Every argument of every menu: --reset-author, --allow-empty, the
   ;; log's -G and -S, --follow, sign-off; Doom stops at 5.
   transient-default-level 7
   ;; Save the file buffers before status, silently: what is staged is
   ;; what is in the buffers.
   magit-save-repository-buffers 'dontask
   ;; Word diffs in every hunk, not only the selected one.
   magit-diff-refine-hunk 'all
   ;; A tab in a diff is drawn eight columns wide unless magit is told
   ;; to ask the file's own mode, so a tab-indented hunk would show at
   ;; an indentation the file does not have, and the + and - lines
   ;; would not line up with each other.
   magit-diff-adjust-tab-width t
   ;; A line indented with tabs where the file uses spaces looks exactly
   ;; like a correct one. This is the change you cannot see otherwise.
   magit-diff-highlight-indentation '((".*" . tabs))
   ;; A file with CRLF endings, which is most of what Delphi writes,
   ;; would show a ^M at the end of every line of every hunk.
   magit-diff-hide-trailing-cr-characters t
   ;; Refs after the summary, not before it: with them in front, every
   ;; summary in a log starts at a different column and the eye cannot
   ;; run down them. They are still there, at the end.
   magit-log-show-refname-after-summary t
   ;; git colours the graph when asked with --color, and magit takes that
   ;; away again past this many commits, because turning the escapes into
   ;; faces is slow. The default, 256, is also the number the log asks
   ;; for, so the colours would go exactly when there are branches worth
   ;; telling apart. --color itself is in the arguments below.
   magit-log-color-graph-limit 2048
   ;; Dates, not ages: history is compared, not felt.
   magit-log-margin '(t "%Y-%m-%d %H:%M " magit-log-margin-width t 18)
   magit-status-margin '(t "%Y-%m-%d %H:%M " magit-log-margin-width nil 18)
   magit-refs-margin '(t "%Y-%m-%d %H:%M " magit-log-margin-width t 18)
   ;; The newest branches first, in every branch prompt.
   magit-list-refs-sortby "-creatordate"
   ;; SPC g l r lists every repository under the projects directory
   ;; with its state; a clone lands there too.
   magit-repository-directories `((,+core-projects-dir . 3))
   magit-clone-default-directory +core-projects-dir
   ;; The status buffer's file lists carry the file icons.
   magit-format-file-function #'magit-format-file-nerd-icons
   ;; S and U in status act without a question.
   magit-no-confirm '(stage-all-changes unstage-all-changes))

  ;; The graph, in colour, in both buffers. --color is a switch magit
  ;; leaves off (-c in the log's own menu), and without it in the
  ;; arguments the graph is drawn in one face however high the limit
  ;; above is. git picks the colours, from log.graphColors.
  ;;
  ;; The status buffer needs --graph as well. Without it its recent
  ;; commits are a flat list and not in topological order, so a commit
  ;; made on a branch sits between two of the trunk's with nothing to
  ;; say so.
  (put 'magit-log-mode 'magit-log-default-arguments
       '("--graph" "--color" "-n256" "--decorate"))
  (put 'magit-status-mode 'magit-log-default-arguments
       '("--graph" "--color" "-n256" "--decorate"))

  ;; Work-in-progress refs before every commit, checkout, reset and after
  ;; every save of a tracked file: a botched rebase or a lost stash is
  ;; one log away (SPC g h L).
  (magit-wip-mode 1)

  ;; Rebase squashes the fixup! commits and stashes round itself unless
  ;; the menu was saved otherwise (C-x C-s in it keeps the user's own).
  (after! transient
    (unless (assq 'magit-rebase transient-values)
      (push '(magit-rebase "--autostash" "--autosquash") transient-values))))

;; The commit subject: 72 columns, the house rule and the hook's; the
;; body wraps at 72 as well.
(after! git-commit
  (setq git-commit-summary-max-length 72
        git-commit-style-convention-checks '(overlong-summary-line
                                             non-empty-second-line)))
(setq-hook! 'git-commit-setup-hook fill-column 72)

;; C-c C-t in the commit buffer: type(scope): with the type asked and
;; the scope read off the staged paths.
(map! :after git-commit
      :map git-commit-mode-map
      "C-c C-t" #'+git/commit-conventional)


;;
;;; Diffs with the code's own colours

;; A magit diff paints every line green or red and leaves the code
;; inside it uncoloured, so a hunk is read as a wall of one colour.
;; delta highlights the code as its language, inside the + and - lines.
;; It is a process per diff, so it stands down on a large one, where it
;; would be the slow part of opening the buffer.
(defvar +git-delta-max-size (* 400 1024)
  "The largest diff delta is asked to colour, in characters.
Past this it is faster to read a plain diff than to wait for a pretty
one; magit falls back to its own painting.")

(defun +git--delta-owns-refinement-h ()
  "Leave the word diff to whichever of the two is drawing it.
delta does its own, and better; magit refining on top of it paints
twice and the two disagree at the edges of a word."
  (setq-local magit-diff-refine-hunk
              (unless (bound-and-true-p magit-delta-mode) 'all)))

(defun +git--delta-only-when-small-a (fn &rest args)
  "Skip delta on a diff larger than `+git-delta-max-size\='.
A diff of a whole release is not worth a second of colouring; magit
paints it the plain way instead."
  (if (> (- (point-max) (point-min)) +git-delta-max-size)
      nil
    (apply fn args)))

(use-package! magit-delta
  :when (executable-find "delta")
  :hook (magit-mode . magit-delta-mode)
  :config
  ;; Nothing is added to `magit-delta-delta-args'. magit reads back the
  ;; diff it just printed, so delta runs with --color-only and must not
  ;; change a single character of the structure: --line-numbers puts a
  ;; gutter where the + and - markers go and --hunk-header-style omit
  ;; drops the @@ line, and magit then fails to parse its own buffer
  ;; with "BUG: Unknown extended header".
  (setq magit-delta-default-dark-theme "TwoDark"  ; Atom One Dark, as doom-one is
        ;; delta draws the + and - markers itself; magit's would double them.
        magit-delta-hide-plus-minus-markers t)
  (add-hook 'magit-delta-mode-hook #'+git--delta-owns-refinement-h)
  (advice-add 'magit-delta-call-delta-and-convert-ansi-escape-sequences
              :around #'+git--delta-only-when-small-a))


;;
;;; Coming back from a magit buffer

;; C-o is the way back from everywhere else. better-jumper records a
;; jump only in a buffer that has a file name, or one whose name it has
;; been told to treat as a target. A magit buffer is neither, so
;; visiting a file or a TODO from the status buffer would leave nothing
;; to come back to. The variable is the package's own, and the only
;; knob it has for this.
(after! better-jumper
  (unless (string-match-p "magit" better-jumper--buffer-targets)
    (setq better-jumper--buffer-targets
          (concat better-jumper--buffer-targets "\\|\\*magit"))))

;; And the jump itself, for the commands that leave a magit buffer for
;; a file: Doom advises its own openers this way, magit's are its own.
(after! magit
  (dolist (command '(magit-diff-visit-file
                     magit-diff-visit-worktree-file
                     magit-find-file
                     magit-log-visit-file))
    (when (fboundp command)
      (advice-add command :around #'doom-set-jump-a))))

;; t in a magit buffer is this module's tag menu: a tag on the
;; commit under the cursor, any commit by its message, a branch's head or
;; HEAD. magit's own menu, still behind its dispatch, tags the same way.
(after! magit
  (define-key magit-mode-map [remap magit-tag] #'+git/tag))
(after! magit-tag
  (transient-replace-suffix 'magit-tag "t" '("t" "tag" +git/tag-create)))


;;
;;; What is left to do, where it is

;; The TODO and FIXME comments of the repository, as one more foldable
;; section in the status buffer: in front of you when you commit, which
;; is when they matter. The same scan SPC p t uses, so the two agree.
(use-package! magit-todos
  :after magit
  :config
  (setq magit-todos-keywords-list '("TODO" "FIXME" "HACK" "XXX" "BUG")
        ;; Under the unstaged and staged lists, not above them: what you
        ;; are about to commit comes first.
        magit-todos-insert-after '(bottom)
        magit-todos-exclude-globs '("*.org" ".git/" "build/" "target/"
                                    "node_modules/" "lib/" "bin/")
        ;; Folded, with the count in the heading: the number is the part
        ;; that is read every time.
        magit-todos-auto-group-items 10
        magit-todos-group-by '(magit-todos-item-first-path-component
                               magit-todos-item-keyword))
  ;; RET on a TODO pops the file into a second window and records no
  ;; jump, so there is nothing to close it with: q in a source buffer
  ;; is evil's macro recorder, and C-o has nowhere to return. Visit it
  ;; in the window the status buffer is in, after marking where we
  ;; were, so C-o returns the way it does from everywhere else. Peeking
  ;; still uses its own window, which is the point of peeking.
  (defadvice! +git--todo-visit-in-place-a (fn &rest args)
    "Visit a TODO in place, leaving a jump to come back to."
    :around #'magit-todos-jump-to-item
    (if (plist-get args :peek)
        (apply fn args)
      (when (fboundp 'better-jumper-set-jump) (better-jumper-set-jump))
      (let ((display-buffer-overriding-action '(display-buffer-same-window)))
        (apply fn args))))

  (magit-todos-mode +1))


;;
;;; Who wrote this line, and when

;; The commit behind the current line at its end, author and date and
;; the summary, after a moment of rest, in every code buffer under git
;; that is not a very large one; SPC t B turns it off and on anywhere.
;; SPC g B is still the whole-buffer blame.
(defvar +git-blame-max-size (* 1024 1024)
  "The largest buffer the blame turns itself on in, in characters.
One `git blame' of the whole file answers for every line, so moving and
typing cost nothing more in a large file; what grows is the reading of
git's answer, once after an edit.")

(defun +git--blame-on-h ()
  "Turn the blame on in a file under git that is not too large."
  (when (and buffer-file-name
             (< (buffer-size) +git-blame-max-size)
             (not (file-remote-p buffer-file-name))
             (locate-dominating-file buffer-file-name ".git"))
    (+git-blame-line-mode 1)))

(add-hook 'prog-mode-hook #'+git--blame-on-h)

;; Loaded ahead while Emacs waits after starting, with what else the first
;; file of a session loads (`+core-warm-up-functions').
(defun +git--warm-up-h (_mode)
  "Load the blame, which the first file under git turns on."
  (+core-load-autoloads '+git-blame-line-mode))

(add-hook '+core-warm-up-functions #'+git--warm-up-h 50)

;; A commit turns "not committed yet" into a commit, with no edit to
;; the buffer that would say so.
(add-hook 'git-commit-post-finish-hook #'+git--blame-forget-all-h)


;;
;;; Keybindings

(map! :leader
      (:prefix "g"
       :desc "Git menu"         "SPC" #'+git/menu
       :desc "History menu"     "h"   #'+git/history
       :desc "Branches menu"    "n"   #'+git/branches
       ;; Doom sets up the popup's own keys (n and p step through the
       ;; changes, c copies the old text) and binds nothing that opens
       ;; it. The fringe says a line changed; this says what it was.
       :desc "Show the change here" "p" #'diff-hl-show-hunk)
      (:prefix "t"
       :desc "Who and when, on this line" "B" #'+git-blame-line-mode))

;; A conflict is worked through where it is: the two motions vim uses,
;; and the menu for which side to keep. Doom turns smerge-mode on by
;; itself when a file holds markers; these make it reachable.
(map! :n "]n" #'+git/next-conflict
      :n "[n" #'+git/previous-conflict)
(map! :leader
      :desc "Conflicts" "g x" #'+git/conflicts)
