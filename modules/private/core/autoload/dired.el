;;; private/core/autoload/dired.el -*- lexical-binding: t; -*-
;;
;; The file manager: dirvish with a preview pane, a search under the
;; current directory, and quick file creation.

(declare-function dirvish "dirvish")
(declare-function dirvish-subtree-clear "dirvish-subtree")
(declare-function dirvish-subtree-toggle "dirvish-subtree")
(declare-function dirvish-subtree--insert "dirvish-subtree")
(declare-function dirvish-subtree--parent "dirvish-subtree")
(declare-function dirvish-subtree--expanded-p "dirvish-subtree")
(defvar dirvish-subtree--overlays)
(declare-function dirvish-curr "dirvish")
(declare-function dv-curr-layout "dirvish")
(declare-function dirvish-layout-toggle "dirvish")
(declare-function dired-do-find-marked-files "dired-x")
(declare-function dirvish-fd "dirvish-fd")
(declare-function dired-copy-file "dired-aux")

;;;###autoload
(defun +core/dirvish-here (&optional arg)
  "The file manager on this file's directory, cursor on the file, with the
preview pane.  With ARG, ask which directory."
  (interactive "P")
  (let* ((file (and (not arg) (ignore-errors (+core-file-at-point))))
         (dir (cond (arg (read-directory-name "Directory: "))
                    (file (file-name-directory file))
                    (t default-directory))))
    (dirvish dir)
    (when file (dired-goto-file file))))

;;;###autoload
(defun +core/dirvish-directory (dir)
  "The file manager on DIR, asked, with the preview pane: Doom's find
directory key, on dirvish."
  (interactive (list (read-directory-name "Directory: ")))
  (dirvish dir))

;;;###autoload
(defun +core/dirvish-other-pane (&optional dir)
  "A second listing beside this one, on DIR or the same directory: the
two panes of a file manager.  C and R then offer the other pane as
their destination, and marks made there are what p and P paste here.
The preview pane makes way for it; F brings it back.  With a prefix
argument, ask which directory."
  (interactive (list (and current-prefix-arg (read-directory-name "Other pane: "))))
  (let ((dir (or dir (dired-current-directory))))
    ;; The session's preview is its own window; two listings and a
    ;; preview is three panes, so the preview goes.
    (when-let* ((dv (and (fboundp 'dirvish-curr) (dirvish-curr)))
                ((dv-curr-layout dv)))
      (dirvish-layout-toggle))
    (select-window (split-window-right))
    (dired dir)))

;;;###autoload
(defun +core/dired-open-marked ()
  "Open every marked file, or the one under the cursor, each in a buffer."
  (interactive nil dired-mode)
  (dired-do-find-marked-files))

;;;###autoload
(defun +core/dired-search (words)
  "Find files below the cursor's directory, every one of WORDS in their path.
Subdirectories are searched too; no words lists everything below.  The
results are a listing like any other: narrow it as you type with /, open
with RET, mark and copy from it."
  (interactive
   (list (split-string (read-string (format "Find under %s: "
                                            (abbreviate-file-name
                                             (+core--dired-here))))
                       "[ ,]+" t)))
  (require 'dirvish-fd)
  (dirvish-fd (+core--dired-here) words))

(defun +core--dired-here ()
  "The directory the cursor is in: inside an unfolded subdirectory, that
one; else the directory listed."
  (if-let* ((file (and (derived-mode-p 'dired-mode) (dired-get-filename nil t))))
      (file-name-directory (directory-file-name file))
    (dired-current-directory)))

;;;###autoload
(defun +core-leave-dirvish ()
  "Shut a dirvish session before a file is opened from it.
Dirvish tears its header, footer and preview windows down when one of
its own commands opens a file.  A command that just calls `find-file'
is not one of them, and leaves the file squeezed in among them."
  (when (and (derived-mode-p 'dired-mode)
             (fboundp 'dirvish-curr)
             (ignore-errors (dirvish-curr))
             (fboundp 'dirvish-quit))
    (ignore-errors (dirvish-quit))))

;;;###autoload
(defun +core/dired-create (name)
  "Make NAME here: a directory when it ends in a slash, else an empty file."
  (interactive "sNew file, or directory ending in /: ")
  (if (string-suffix-p "/" name)
      (dired-create-directory name)
    (dired-create-empty-file name))
  (revert-buffer))

;;
;;; Quick access

(defvar +core-quick-access)
(defvar +core-quick-access-extra)

;; Autoloaded: config.el builds the entries from it when dirvish loads.
;;;###autoload
(defun +core--quick-access-entries ()
  "The quick access entries: this config's, with the ones added from a
listing on top; an added one wins over a fixed one on the same key."
  (append (seq-remove (lambda (entry) (assoc (car entry) +core-quick-access-extra))
                      +core-quick-access)
          +core-quick-access-extra))

(defun +core--quick-access-apply ()
  "Rebuild the b menu from the entries, through the variable's setter."
  (customize-set-variable 'dirvish-quick-access-entries
                          (+core--quick-access-entries)))

;;;###autoload
(defun +core/quick-access-add (key desc)
  "Add the directory here to the b menu, under KEY, described as DESC,
for this session and the next ones."
  (interactive
   (let ((key (read-string "Key for this directory (one letter): ")))
     (when (or (string-empty-p key) (> (length key) 2))
       (user-error "One letter, or two"))
     (list key (read-string "Shown as: "
                            (file-name-nondirectory
                             (directory-file-name (dired-current-directory)))))))
  (let ((dir (abbreviate-file-name (dired-current-directory))))
    (setq +core-quick-access-extra
          (cons (list key dir desc)
                (seq-remove (lambda (entry) (equal (car entry) key))
                            +core-quick-access-extra)))
    (+core--quick-access-apply)
    (message "b %s goes to %s%s" key dir
             (if (assoc key +core-quick-access) ", in place of the fixed entry" ""))))

;;;###autoload
(defun +core/quick-access-remove (key)
  "Drop an entry added with `+core/quick-access-add' from the b menu.
The fixed entries of the config stay."
  (interactive
   (let ((rows (mapcar (lambda (entry)
                         (cons (format "%s  %s  %s" (car entry) (nth 2 entry) (nth 1 entry))
                               entry))
                       +core-quick-access-extra)))
     (unless rows
       (user-error "No added entries; the fixed ones are in config.el"))
     (list (car (cdr (assoc (completing-read "Drop: " rows nil t) rows))))))
  (setq +core-quick-access-extra
        (seq-remove (lambda (entry) (equal (car entry) key)) +core-quick-access-extra))
  (+core--quick-access-apply)
  (message "b %s dropped" key))


;;
;;; The system clipboard, other apps, and copies of a file

;;;###autoload
(defun +core/files-to-clipboard ()
  "Put the marked files, or this file, on the system clipboard as files.
Paste them in Finder or Dolphin, a mail, a chat, any app that takes
files. Inside Emacs the kill ring gets their paths, one per line."
  (interactive)
  (let ((files (+core-file-at-point t)))
    ;; The kill ring first: writing it also writes the clipboard as
    ;; text, and the files must be the last thing put there.
    (kill-new (mapconcat #'expand-file-name files "\n"))
    (+core-os-files-to-clipboard files)
    (message "On the clipboard, as files: %s"
             (if (cdr files)
                 (format "%d files" (length files))
               (file-name-nondirectory (car files))))))

;;;###autoload
(defun +core/files-from-clipboard ()
  "Copy the files on the system clipboard into this directory.
Files copied in Finder, Dolphin or another app land here; so do paths
copied as text, one per line."
  (interactive nil dired-mode)
  (let ((files (or (+core-os-clipboard-files)
                   (user-error "No files on the clipboard")))
        (dir (dired-current-directory)))
    (dolist (file files)
      (let ((to (expand-file-name (file-name-nondirectory
                                   (directory-file-name file))
                                  dir)))
        (when (and (file-exists-p to)
                   (not (y-or-n-p (format "%s exists here; overwrite? "
                                          (file-name-nondirectory to)))))
          (user-error "Left as it was"))
        (dired-copy-file file to t)))
    (revert-buffer)
    (dired-goto-file (expand-file-name (file-name-nondirectory
                                        (directory-file-name (car files)))
                                       dir))
    (message "Pasted %d file%s here" (length files) (if (cdr files) "s" ""))))

(defun +core--copy-name (file)
  "A name for a copy of FILE beside it: NAME copy.EXT, then NAME copy 2.EXT."
  (let* ((dir (file-name-directory file))
         (base (file-name-base file))
         (ext (file-name-extension file t))
         (n 1) candidate)
    (while (file-exists-p
            (setq candidate (expand-file-name
                             (if (= n 1) (format "%s copy%s" base ext)
                               (format "%s copy %d%s" base n ext))
                             dir)))
      (cl-incf n))
    candidate))

;;;###autoload
(defun +core/dired-duplicate ()
  "Make a copy of the marked files beside them, named NAME copy.EXT."
  (interactive nil dired-mode)
  (let ((files (+core-file-at-point t)) last)
    (dolist (file files)
      (setq last (+core--copy-name (directory-file-name file)))
      (dired-copy-file file last t))
    (revert-buffer)
    (dired-goto-file last)
    (message "Made %d cop%s" (length files) (if (cdr files) "ies" "y"))))

;;;###autoload
(defun +core/copy-file-contents ()
  "Copy the whole text of this file to the kill ring, without opening it."
  (interactive)
  (let ((file (car (+core-file-at-point t))))
    (when (file-directory-p file)
      (user-error "%s is a directory" (file-name-nondirectory file)))
    (unless (file-exists-p file)
      (user-error "%s is not on disk yet; save it first" (file-name-nondirectory file)))
    (when (> (file-attribute-size (file-attributes file)) (* 4 1024 1024))
      (user-error "%s is over 4 MB; open it instead" (file-name-nondirectory file)))
    (with-temp-buffer
      (insert-file-contents file)
      (kill-new (buffer-string))
      (message "Copied %s: %d lines" (file-name-nondirectory file)
               (count-lines (point-min) (point-max))))))

;;
;;; The trash

;;;###autoload
(defun +core/trash ()
  "The trash, in the file manager: what was deleted, newest first.
Mark what you want back and SPC m t puts it where it came from."
  (interactive)
  (let ((dir (+core-os-trash-files-dir))
        (dired-listing-switches (concat dired-listing-switches " -t")))
    ;; macOS lets an app read ~/.Trash only with Full Disk Access, and
    ;; says so as a listing that failed, which reads like a bug.
    (condition-case nil
        (directory-files dir nil nil t 1)
      (file-error
       (user-error (if (featurep :system 'macos)
                       "Emacs may not read the trash: allow it in System Settings, Privacy & Security, Full Disk Access"
                     "The trash cannot be read: %s")
                   dir)))
    (dirvish dir)))

;;;###autoload
(defun +core/restore-from-trash ()
  "Put the marked files, deleted earlier, back where they came from."
  (interactive nil dired-mode)
  (let ((files (dired-get-marked-files)) (back nil) last)
    (unless (string-prefix-p (expand-file-name (+core-os-trash-files-dir))
                             (expand-file-name default-directory))
      (user-error "This is not the trash; SPC f t opens it"))
    (dolist (file files)
      ;; Only what was deleted has a record: a file inside a directory in
      ;; the trash came with it, and one by the same name deleted on its
      ;; own would be taken for it.
      (unless (file-equal-p (file-name-directory (directory-file-name file))
                            (+core-os-trash-files-dir))
        (user-error "%s is inside a directory in the trash: put that back"
                    (file-name-nondirectory (directory-file-name file))))
      (pcase-let ((`(,origin . ,forget)
                   (or (+core-os-trash-origin file)
                       (user-error (if (featurep :system 'macos)
                                       "No record of where %s came from: it was not deleted from Emacs, so Finder's Put Back is the way"
                                     "No record of where %s came from")
                                   (file-name-nondirectory file)))))
        (when (and (file-exists-p origin)
                   (not (y-or-n-p (format "%s exists again; replace it? " origin))))
          (user-error "Left in the trash"))
        (make-directory (file-name-directory origin) t)
        (rename-file file origin t)
        (funcall forget)
        (setq last origin)
        (push origin back)))
    (revert-buffer)
    (message "Put back %d file%s, the last at %s" (length back)
             (if (cdr back) "s" "") (abbreviate-file-name last))))

;;
;;; Folding, the way an Org document folds

;; TAB on an Org heading opens it, then opens it all the way down, then
;; shuts it; S-TAB does the same to the whole document. The listing
;; folds the same way, and reads its state off the buffer rather than
;; counting presses, so it picks up wherever the listing was left.
;; A document has a bottom and a directory tree has not, hence the limit.
;;
;; The opening is walked from the bottom of the region up: a listing
;; inserted under a line leaves the lines above it where they were, so
;; the walk stays true while it works. `dired-goto-file' would be the
;; obvious way round the buffer and it cannot see inside an inserted
;; listing, which has no entry in `dired-subdir-alist'.

(defvar +core-dired-expand-limit 200
  "How many directories at most are opened all the way down at one press.
An Org document ends; a directory tree need not, and a node_modules
would otherwise arrive in full.  Press again for the next batch.")

(defun +core--dired-dirvish ()
  "Complain unless this listing has dirvish's subtrees."
  (unless (and (fboundp 'dirvish-subtree--insert) (fboundp 'dirvish-subtree-clear))
    (user-error "Folding needs dirvish, and this listing is plain dired")))

(defun +core--dired-shut-here-p ()
  "Non-nil when the line holds a directory that is not open."
  (let ((file (dired-get-filename nil t)))
    (and file
         (not (member (file-name-nondirectory file) '("." "..")))
         (file-directory-p file)
         (not (dirvish-subtree--expanded-p)))))

(defun +core--dired-shut-p (beg end)
  "Non-nil when a directory between BEG and END is not open yet."
  (save-excursion
    (goto-char beg)
    (catch 'found
      (while (< (point) (min end (point-max)))
        (when (+core--dired-shut-here-p) (throw 'found t))
        (forward-line 1))
      nil)))

(defun +core--dired-open-pass (beg end budget)
  "Open every shut directory between BEG and END one level, BUDGET at most.
Walked from the bottom up, so opening one does not move the rest."
  (let ((opened 0))
    (save-excursion
      (goto-char (min end (point-max)))
      (forward-line 0)
      (catch 'done
        (while t
          (when (>= opened budget) (throw 'done nil))
          (let ((here (point)))
            (when (+core--dired-shut-here-p)
              (when (ignore-errors (dirvish-subtree--insert) t)
                (cl-incf opened)))
            (goto-char here))
          (when (<= (point) beg) (throw 'done nil))
          (forward-line -1))))
    opened))

(defun +core--dired-open-under (region)
  "Open everything REGION holds, and then what that opened, and so on.
REGION is asked afresh each round and answers (BEG . END), since opening
a directory moves everything below it.  At most
`+core-dired-expand-limit' directories in one go."
  (let ((opened 0) (done nil))
    (while (not done)
      (pcase-let* ((`(,beg . ,end) (funcall region))
                   (round (and beg (< opened +core-dired-expand-limit)
                               (+core--dired-open-pass
                                beg end (- +core-dired-expand-limit opened)))))
        ;; A round that opens nothing would ask the same of the next one
        ;; for ever: a directory that cannot be read stops it.
        (if (or (null round) (zerop round))
            (setq done t)
          (setq opened (+ opened round)))))
    opened))

(defun +core--dired-said (opened)
  "Say how many OPENED, and whether the limit cut it short."
  (message "%d director%s open%s" opened (if (= opened 1) "y" "ies")
           (if (>= opened +core-dired-expand-limit)
               ", the limit; press again for the next lot"
             "")))

;;;###autoload
(defun +core/dired-subtree-cycle ()
  "Open the directory under the cursor, then all the way down, then shut
it: the three steps TAB takes on a heading in an Org document.  On a
file it does what TAB did before, and opens the file."
  (interactive nil dired-mode)
  (+core--dired-dirvish)
  (let ((file (dired-get-filename nil t)))
    (cond
     ((or (null file) (not (file-directory-p file)))
      (dirvish-subtree-toggle))
     ((not (dirvish-subtree--expanded-p))
      (dirvish-subtree--insert)
      (message "%s open" (file-name-nondirectory (directory-file-name file))))
     (t
      ;; The marker holds the directory's own line while its listing
      ;; grows underneath it.
      (let* ((home (point-marker))
             (region (lambda ()
                       (save-excursion
                         (goto-char home)
                         (forward-line 1)
                         (when-let* ((ov (dirvish-subtree--parent)))
                           (cons (overlay-start ov) (overlay-end ov)))))))
        (pcase-let ((`(,beg . ,end) (funcall region)))
          (if (and beg (+core--dired-shut-p beg end))
              (+core--dired-said (+core--dired-open-under region))
            (goto-char home)
            (dirvish-subtree-toggle)
            (message "%s shut"
                     (file-name-nondirectory (directory-file-name file))))))))))

;;;###autoload
(defun +core/dired-fold-cycle ()
  "Open every directory in this listing one level, then all of them all
the way down, then shut them all: the three steps S-TAB takes in an Org
document."
  (interactive nil dired-mode)
  (+core--dired-dirvish)
  (cond
   ((not (bound-and-true-p dirvish-subtree--overlays))
    (let ((opened (+core--dired-open-pass (point-min) (point-max)
                                          +core-dired-expand-limit)))
      (if (zerop opened)
          (user-error "No directory here to open")
        (message "%d director%s open, one level" opened
                 (if (= opened 1) "y" "ies")))))
   ((+core--dired-shut-p (point-min) (point-max))
    (+core--dired-said
     (+core--dired-open-under (lambda () (cons (point-min) (point-max))))))
   (t (dirvish-subtree-clear)
      (message "Every directory shut"))))

;;;###autoload
(defun +core/find-file-in-other-project ()
  "Choose another project, then a file in it.
Doom's key for this asks for the project and then opens a `find-file'
prompt already filled with the project directory, so the first RET takes
the directory and lands in dired: two presses to reach the file list,
and the first of them somewhere you did not mean to go.  This asks for
the project and then offers its files, the way SPC SPC does, and one
RET opens the file."
  (interactive)
  (require 'projectile nil t)
  (unless (fboundp 'projectile-relevant-known-projects)
    (user-error "Projectile is not here to list the projects"))
  (let ((default-directory
         (file-name-as-directory
          (completing-read "Find file in project: "
                           (projectile-relevant-known-projects) nil t))))
    (call-interactively #'projectile-find-file)))
