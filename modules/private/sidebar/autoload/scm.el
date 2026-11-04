;;; private/sidebar/autoload/scm.el -*- lexical-binding: t; -*-
;;
;; Source Control: the branch, the staged files, the changed ones, the
;; latest commits, each commit unfolding to its files. RET opens a change
;; in place, o beside its old version (the git module's views); s, u and
;; x stage, unstage and discard as in magit, c commits, p pushes, F pulls.

;; magit's staging functions are its own, not autoloaded; the view is
;; magit's data, so it brings magit along.
(require 'magit)
(require 'magit-section)

(declare-function +git-live-open "../../git/autoload/split")
(declare-function +git-split-commit "../../git/autoload/split")
(declare-function magit-commit "magit-commit")
(declare-function magit-push "magit-push")
(declare-function magit-pull "magit-pull")
(declare-function magit-show-commit "magit-diff")
(declare-function magit-find-file "magit-files")
(declare-function magit-stage-1 "magit-apply")
(declare-function magit-unstage-1 "magit-apply")
(declare-function magit-unstage-all "magit-apply")
(declare-function magit-run-git "magit-process")
(defvar +sidebar-scm-commits)
(defvar +sidebar--shown-root)

;;;###autoload
(defun +sidebar/source-control ()
  "Show Source Control in the side bar and go there; there already, close
the side bar."
  (interactive)
  (+sidebar--open 'scm))

;;;###autoload
(define-derived-mode +sidebar-scm-mode magit-section-mode "Source Control"
  "The side bar's Source Control view.
\\{+sidebar-scm-mode-map}"
  :interactive nil
  (+sidebar--view-setup 'scm))

(with-eval-after-load 'evil
  (evil-set-initial-state '+sidebar-scm-mode 'normal)
  (+sidebar--bind-common +sidebar-scm-mode-map)
  (evil-define-key* 'normal +sidebar-scm-mode-map
    (kbd "RET") #'+sidebar/scm-open
    [return] #'+sidebar/scm-open
    "o" #'+sidebar/scm-open-split
    "s" #'+sidebar/scm-stage
    "u" #'+sidebar/scm-unstage
    "x" #'+sidebar/scm-discard
    "S" #'+sidebar/scm-stage-all
    "U" #'+sidebar/scm-unstage-all
    "c" #'magit-commit
    "p" #'magit-push
    "F" #'magit-pull)
  (evil-define-key* 'visual +sidebar-scm-mode-map
    "s" #'+sidebar/scm-stage
    "u" #'+sidebar/scm-unstage
    "x" #'+sidebar/scm-discard))


;;
;;; Drawing

(defun +sidebar--scm-branch ()
  "The branch, and how far it is from its upstream."
  (let* ((branch (or (ignore-errors (process-lines "git" "rev-parse" "--abbrev-ref" "HEAD")) '("?")))
         (upstream (ignore-errors (process-lines "git" "rev-parse" "--abbrev-ref" "@{u}")))
         (counts (and upstream
                      (ignore-errors
                        (split-string (car (process-lines "git" "rev-list" "--left-right"
                                                          "--count" "@{u}...HEAD")))))))
    (concat (propertize (car branch) 'font-lock-face 'magit-branch-local)
            (if upstream
                (format "  %s +%s -%s" (car upstream) (or (nth 1 counts) "?") (or (nth 0 counts) "?"))
              (propertize "  no upstream" 'font-lock-face 'shadow))
            "\n")))

(defun +sidebar--scm-group (kind title files)
  "A section of FILES, (PATH . LETTER), headed TITLE, of KIND."
  (when files
    (magit-insert-section (+sidebar-group kind)
      (magit-insert-heading (format "%s (%d)" title (length files)))
      (dolist (file files)
        (magit-insert-section (+sidebar-file (cons kind (car file)))
          (insert (+sidebar--file-line (car file) (cdr file)) "\n"))))))

(defun +sidebar--scm-commit-files (hash)
  "The files commit HASH changed, as (PATH . LETTER)."
  (mapcar (lambda (line)
            (let ((fields (split-string line "\t")))
              (cons (car (last fields)) (substring (car fields) 0 1))))
          (ignore-errors (process-lines "git" "show" "--name-status" "--format=" hash))))

(defun +sidebar--scm-commits ()
  "The latest commits, each unfolding to its files."
  (let ((commits (ignore-errors
                   (process-lines "git" "log" (format "-%d" +sidebar-scm-commits)
                                  "--format=%h%x00%s%x00%ar"))))
    (magit-insert-section (+sidebar-commits nil)
      (magit-insert-heading "Commits")
      (dolist (line commits)
        (pcase-let ((`(,hash ,subject ,date) (split-string line "\0")))
          (magit-insert-section (+sidebar-commit hash t)
            (magit-insert-heading
              (concat "  " subject " " (propertize date 'font-lock-face 'shadow)))
            (magit-insert-section-body
              (dolist (file (+sidebar--scm-commit-files hash))
                (magit-insert-section (+sidebar-commit-file (cons hash (car file)))
                  (insert (+sidebar--file-line (car file) (cdr file) 4) "\n"))))))))))

;;;###autoload
(defun +sidebar--scm-render ()
  "Draw Source Control for the repository the side bar shows."
  (let ((repo (+sidebar--git-root (+sidebar--root))))
    (setq +sidebar--shown-root (+sidebar--root)
          default-directory (or repo default-directory))
    (+sidebar--watch-gitdir repo)
    (+sidebar--redraw
     (lambda ()
       (magit-insert-section (+sidebar-scm nil)
         (if (not repo)
             (insert (propertize "Not a git repository\n" 'font-lock-face 'shadow))
           (pcase-let ((`(,staged ,unstaged ,untracked ,unmerged ,_ignored)
                        (+sidebar--status repo)))
             (insert (+sidebar--scm-branch))
             (+sidebar--scm-group 'staged "Staged Changes" staged)
             (+sidebar--scm-group 'unstaged "Changes" (append unmerged unstaged untracked))
             (unless (or staged unstaged untracked unmerged)
               (insert (propertize "  No changes\n" 'font-lock-face 'shadow)))
             (+sidebar--scm-commits))))))))


;;
;;; What the commands act on

(defun +sidebar--scm-files (&optional region)
  "The files the command acts on: those of an evil visual selection with
REGION, those of the section whose heading point is on, else the one at
point; as (KIND . PATHS)."
  (let ((section (magit-current-section)))
    (cond
     ((and region (use-region-p))
      (let ((beg (region-beginning)) (end (region-end)) files kind)
        (magit-map-sections
         (lambda (s)
           (when (and (eq (oref s type) '+sidebar-file)
                      (< (oref s start) end) (>= (oref s start) (save-excursion (goto-char beg) (line-beginning-position))))
             (setq kind (car (oref s value)))
             (push (cdr (oref s value)) files))))
        (deactivate-mark)
        (when (fboundp 'evil-normal-state) (evil-normal-state))
        (and files (cons kind (nreverse files)))))
     ((eq (oref section type) '+sidebar-group)
      (cons (oref section value)
            (mapcar (lambda (child) (cdr (oref child value))) (oref section children))))
     ((eq (oref section type) '+sidebar-file)
      (cons (car (oref section value)) (list (cdr (oref section value))))))))

(defun +sidebar--scm-untracked-p (path)
  "Non-nil when PATH is untracked."
  (not (ignore-errors (process-lines "git" "ls-files" "--error-unmatch" "--" path))))


;;
;;; Opening a change

(defun +sidebar--scm-visit (split)
  "Open the change at point in the editor window: in place, or beside
its old version with SPLIT."
  (let* ((section (magit-current-section))
         (type (oref section type))
         (value (oref section value))
         (repo default-directory))
    (pcase type
      ('+sidebar-file
       (let* ((kind (car value)) (path (cdr value))
              (file (expand-file-name path repo)))
         (select-window (+sidebar--editor-window))
         (if (file-exists-p file)
             (+git-live-open file (if (eq kind 'staged) 'head 'index) split)
           (let ((default-directory repo))
             (magit-find-file (if (eq kind 'staged) "HEAD" "{index}") path)))))
      ('+sidebar-commit-file
       (select-window (+sidebar--editor-window))
       (let ((default-directory repo))
         (+git-split-commit (car value) (cdr value))))
      ('+sidebar-commit
       (if split
           (let ((default-directory repo))
             (select-window (+sidebar--editor-window))
             (magit-show-commit value))
         (magit-section-toggle section)))
      (_ (magit-section-toggle section)))))

;;;###autoload
(defun +sidebar/scm-open ()
  "Open the change at point in place; on a heading or a commit, fold it."
  (interactive)
  (+sidebar--scm-visit nil))

;;;###autoload
(defun +sidebar/scm-open-split ()
  "Open the change at point beside its old version; on a commit, its diff."
  (interactive)
  (+sidebar--scm-visit t))


;;
;;; Staging

;;;###autoload
(defun +sidebar/scm-stage ()
  "Stage the file at point, the selected ones, or the section's."
  (interactive)
  (pcase (+sidebar--scm-files t)
    (`(staged . ,_) (message "Already staged"))
    (`(,_ . ,(and files (pred identity))) (magit-stage-1 nil files))
    (_ (message "No file here"))))

;;;###autoload
(defun +sidebar/scm-unstage ()
  "Unstage the file at point, the selected ones, or the section's."
  (interactive)
  (pcase (+sidebar--scm-files t)
    (`(staged . ,(and files (pred identity))) (magit-unstage-1 files))
    (`(,_ . ,(pred identity)) (message "Not staged"))
    (_ (message "No file here"))))

;;;###autoload
(defun +sidebar/scm-discard ()
  "Discard the changes to the file at point, the selected ones, or the
section's, after asking: a tracked file goes back to the index, an
untracked one to the trash."
  (interactive)
  (pcase (+sidebar--scm-files t)
    (`(staged . ,_) (message "Staged: unstage it first (u)"))
    (`(,_ . ,(and files (pred identity)))
     (let ((untracked (seq-filter #'+sidebar--scm-untracked-p files))
           (tracked (seq-remove #'+sidebar--scm-untracked-p files)))
       (when (y-or-n-p (format "Discard changes to %d file%s%s? "
                               (length files) (if (cdr files) "s" "")
                               (if untracked
                                   (format " (%d untracked to the trash)" (length untracked))
                                 "")))
         (dolist (file untracked)
           (move-file-to-trash (expand-file-name file)))
         (if tracked
             (magit-run-git "restore" "--worktree" "--" tracked)
           (+sidebar--request 'scm)))))
    (_ (message "No file here"))))

;;;###autoload
(defun +sidebar/scm-stage-all ()
  "Stage every change."
  (interactive)
  (magit-stage-1 "--all"))

;;;###autoload
(defun +sidebar/scm-unstage-all ()
  "Unstage everything."
  (interactive)
  (magit-unstage-all))
