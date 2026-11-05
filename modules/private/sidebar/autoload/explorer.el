;;; private/sidebar/autoload/explorer.el -*- lexical-binding: t; -*-
;;
;; The Explorer: the project's files as a tree, folders first. A folder
;; lists its files the first time it is opened; git's state colours the
;; names, and a folder holding a change is coloured too. The folders on
;; screen are watched, and only those, so a file another program writes
;; there shows up; the file in the editor is unfolded to and pointed at.
;; Files are made, renamed, copied and moved to the trash from here.

(require 'magit-section)
(declare-function dired-rename-file "dired-aux")
(defvar +sidebar--shown-root)
(defvar +sidebar--view)
(defvar +sidebar--dirty)
(defvar +sidebar--last-view)
(defvar +sidebar-views)
(defvar +sidebar--status-process)

(defvar-local +sidebar--explorer-states nil
  "Absolute path to git's letter for it, and folders holding a change
to `changed', for the last drawing.")

(defvar-local +sidebar--explorer-pending nil
  "A file to point at once the Explorer is drawn.")

(defvar-local +sidebar--outline-pending nil
  "Non-nil to open Outline once the Explorer is drawn.")

(defvar-local +sidebar--explorer-source nil
  "The editor's buffer when the Explorer was last drawn, whose outline and
history it shows.")

(defvar +sidebar--explorer-watches (make-hash-table :test #'equal)
  "Folder on show to its file-notify watch.")

;;;###autoload
(defun +sidebar/explorer ()
  "Show the Explorer in the side bar, pointing at the file in the editor,
and go there; there already, close the side bar."
  (interactive)
  (let ((file (buffer-file-name (window-buffer (+sidebar--editor-window)))))
    (+sidebar--open 'explorer)
    (when (and file (+sidebar--window) (eq (selected-window) (+sidebar--window)))
      (+sidebar--explorer-point-at file))))

;;;###autoload
(defun +sidebar/reveal ()
  "Show the Explorer with point on the file in the editor, its folders
unfolded, and go there."
  (interactive)
  (let ((file (buffer-file-name (window-buffer (+sidebar--editor-window)))))
    (+sidebar--show 'explorer t)
    (if file
        (+sidebar--explorer-point-at file)
      (message "This buffer has no file"))))

;;;###autoload
(defun +sidebar/toggle ()
  "Open the side bar on its last view, staying where you are; close it if
it is open."
  (interactive)
  (if (+sidebar--window)
      (+sidebar--close)
    (+sidebar--show (or +sidebar--last-view (caar +sidebar-views)))))

;;;###autoload
(define-derived-mode +sidebar-explorer-mode magit-section-mode "Explorer"
  "The side bar's Explorer view.
\\{+sidebar-explorer-mode-map}"
  :interactive nil
  (+sidebar--view-setup 'explorer)
  (add-hook 'kill-buffer-hook #'+sidebar--unwatch-all nil t))

(with-eval-after-load 'evil
  (evil-set-initial-state '+sidebar-explorer-mode 'normal)
  (+sidebar--bind-common +sidebar-explorer-mode-map)
  (evil-define-key* 'normal +sidebar-explorer-mode-map
    (kbd "RET") #'+sidebar/explorer-open
    [return] #'+sidebar/explorer-open
    "o" #'+sidebar/explorer-open-side
    "a" #'+sidebar/explorer-new
    "r" #'+sidebar/explorer-rename
    "d" #'+sidebar/explorer-delete
    "c" #'+sidebar/explorer-copy
    "y" #'+sidebar/explorer-copy-name
    "Y" #'+sidebar/explorer-copy-relative-path
    "gy" #'+sidebar/explorer-copy-path
    "x" #'+sidebar/explorer-close
    "s" #'+sidebar/explorer-save))
(define-key +sidebar-explorer-mode-map [mouse-1] #'+sidebar/explorer-click)


;;
;;; git's colours

(defun +sidebar--explorer-git-states (status repo)
  "REPO's files and folders by absolute path, from git's STATUS: git's
letter, and `changed' for the folders holding a change."
  (let ((states (make-hash-table :test #'equal)))
    (pcase-let ((`(,staged ,unstaged ,untracked ,unmerged ,ignored) status))
      (dolist (entry (append staged unstaged untracked unmerged ignored))
        (let ((path (expand-file-name (car entry) repo)))
          ;; The worktree's letter wins over the index's for a file that
          ;; has both: it is what the buffer shows.
          (puthash (if (string-suffix-p "/" (car entry)) (file-name-as-directory path) path)
                   (cdr entry) states)
          (unless (equal (cdr entry) "I")
            (let ((dir (file-name-directory (directory-file-name path))))
              (while (and dir (file-in-directory-p dir repo)
                          (not (equal (gethash dir states) 'changed)))
                (puthash dir 'changed states)
                (setq dir (unless (equal (file-name-as-directory dir) (file-name-as-directory repo))
                            (file-name-directory (directory-file-name dir))))))))))
    states))

(defun +sidebar--explorer-state (path)
  "PATH's letter, or `changed' for a folder holding a change; a file in
an untracked or ignored folder has the folder's."
  (when +sidebar--explorer-states
    (or (gethash path +sidebar--explorer-states)
        (let ((dir (file-name-directory (directory-file-name path))) found)
          (while (and dir (not found) (file-in-directory-p dir +sidebar--shown-root))
            (let ((state (gethash dir +sidebar--explorer-states)))
              (when (member state '("U" "I"))
                (setq found state)))
            (setq dir (unless (equal dir +sidebar--shown-root)
                        (file-name-directory (directory-file-name dir)))))
          found))))


;;
;;; Drawing

(defun +sidebar--explorer-entries (dir)
  "DIR's entries, folders first, each sorted without regard to case, as
\(PATH . FOLDER-P); .git left out."
  (let (dirs files)
    (dolist (name (ignore-errors (directory-files dir nil nil t)))
      (unless (member name '("." ".." ".git"))
        (let ((path (expand-file-name name dir)))
          (if (file-directory-p path)
              (push (cons (file-name-as-directory path) t) dirs)
            (push (cons path nil) files)))))
    (cl-flet ((sorted (list) (sort list (lambda (a b) (string< (downcase (car a)) (downcase (car b)))))))
      (append (sorted dirs) (sorted files)))))

(defun +sidebar--explorer-line (path depth folder)
  "A line for PATH, DEPTH levels in: its icon and name in its git colour,
and for a file its letter at the right edge."
  (let* ((name (file-name-nondirectory (directory-file-name path)))
         (state (+sidebar--explorer-state path))
         (face (cond ((eq state 'changed) '+sidebar-modified)
                     (state (+sidebar--letter-face state))
                     (t 'default))))
    (concat (make-string (* 2 depth) ?\s)
            (+sidebar--icon name folder)
            (propertize name 'font-lock-face face)
            (when (and (stringp state) (not folder) (not (equal state "I")))
              (concat (propertize " " 'display '(space :align-to (- right 2)))
                      (propertize state 'font-lock-face face))))))

(defun +sidebar--explorer-folder (dir depth &optional open)
  "A section for folder DIR, DEPTH levels in, open with OPEN; its entries
are listed when it is first opened."
  (magit-insert-section (+sidebar-dir dir (not open))
    (magit-insert-heading
      (if (zerop depth)
          (propertize (upcase (file-name-nondirectory (directory-file-name dir)))
                      'font-lock-face 'magit-section-heading)
        (+sidebar--explorer-line dir depth t)))
    (magit-insert-section-body
      (dolist (entry (+sidebar--explorer-entries dir))
        (if (cdr entry)
            (+sidebar--explorer-folder (car entry) (1+ depth))
          (magit-insert-section (+sidebar-path (car entry))
            (insert (+sidebar--explorer-line (car entry) (1+ depth) nil) "\n")))))))

;;;###autoload
(defun +sidebar--explorer-render ()
  "Draw the Explorer for the directory the side bar shows."
  (let* ((root (+sidebar--root))
         (repo (+sidebar--git-root root))
         (source (window-buffer (+sidebar--editor-window))))
    (setq +sidebar--shown-root root
          +sidebar--explorer-source source
          default-directory root)
    (+sidebar--watch-gitdir repo)
    (+sidebar--with-status
     repo
     (lambda (status)
       (setq +sidebar--explorer-states (and status (+sidebar--explorer-git-states status repo)))
       ;; Outline follows its buffer's edits only while it is open:
       ;; drawing it open sets that up again.
       (+sidebar--outline-follow nil)
       (+sidebar--redraw
        (lambda ()
          (magit-insert-section (+sidebar-explorer nil)
            (+sidebar--insert-editors root)
            (+sidebar--explorer-folder root 0 t)
            (+sidebar--insert-outline source)
            (+sidebar--insert-timeline source))))
       (+sidebar--sync-watches)
       (when-let* ((file +sidebar--explorer-pending))
         (setq +sidebar--explorer-pending nil)
         (+sidebar--explorer-point-at file))
       (when +sidebar--outline-pending
         (setq +sidebar--outline-pending nil)
         (+sidebar--outline-open))))))


;;
;;; Following the editor

(defun +sidebar--explorer-root-section ()
  "The section of the root folder."
  (and magit-root-section
       (seq-find (lambda (section) (eq (oref section type) '+sidebar-dir))
                 (oref magit-root-section children))))

;;;###autoload
(defun +sidebar--explorer-drawn-p ()
  "Non-nil when this Explorer buffer is drawn and no status is on its
way to draw it again."
  (and magit-root-section (not (process-live-p +sidebar--status-process))))

;;;###autoload
(defun +sidebar--explorer-point-at (file)
  "Unfold FILE's folders in the Explorer and put point on it, in the side
bar's window, which stays unselected if it was; once it is drawn."
  (with-current-buffer (+sidebar--buffer 'explorer)
    (let ((root +sidebar--shown-root)
          (file (file-truename file)))
      (cond
       ((not (+sidebar--explorer-drawn-p))
        (setq +sidebar--explorer-pending file))
       ((and root (file-in-directory-p file root))
        (let ((section (+sidebar--explorer-root-section))
              (path root)
              (parts (split-string (file-relative-name file root) "/" t)))
          (while (and section (cdr parts))
            (magit-section-show section)
            (setq path (file-name-as-directory (expand-file-name (pop parts) path)))
            (setq section (seq-find (lambda (s) (equal (oref s value) path))
                                    (oref section children))))
          (when section
            (magit-section-show section)
            (when-let* ((target (seq-find (lambda (s) (equal (oref s value) file))
                                          (oref section children))))
              (goto-char (oref target start))
              (when-let* ((window (get-buffer-window (current-buffer))))
                (set-window-point window (point)))))
          (+sidebar--sync-watches)))))))

;;;###autoload
(defun +sidebar--explorer-follow-h (buffer)
  "Point at BUFFER's file in the Explorer when it shows, after redisplay;
with Open editors, Outline or Timeline open, draw them for BUFFER."
  (when-let* ((explorer (get-buffer "*Sidebar: Explorer*"))
              ((get-buffer-window explorer)))
    (with-current-buffer explorer
      (when (and (not (eq buffer +sidebar--explorer-source))
                 (+sidebar--explorer-open-p '(+sidebar-editors +sidebar-outline +sidebar-timeline)))
        (+sidebar--request 'explorer)))
    (when-let* ((file (buffer-file-name buffer)))
      (if (buffer-local-value '+sidebar--dirty explorer)
          (with-current-buffer explorer
            (setq +sidebar--explorer-pending file))
        (run-at-time 0 nil #'+sidebar--explorer-point-at file)))))

;;;###autoload
(defun +sidebar--explorer-open-p (types)
  "Non-nil when one of the Explorer's top sections of TYPES is open."
  (when-let* ((explorer (get-buffer "*Sidebar: Explorer*")))
    (with-current-buffer explorer
      (and magit-root-section
           (seq-find (lambda (s) (and (memq (oref s type) types) (not (oref s hidden))))
                     (oref magit-root-section children))))))


;;
;;; Watching the folders on show

;;;###autoload
(defun +sidebar--sync-watches ()
  "Watch exactly the Explorer's folders on show."
  (when-let* ((explorer (get-buffer "*Sidebar: Explorer*")))
    (with-current-buffer explorer
      (let ((shown (make-hash-table :test #'equal)))
        (when magit-root-section
          (cl-labels ((walk (section)
                        (when (and (eq (oref section type) '+sidebar-dir)
                                   (not (oref section hidden)))
                          (puthash (oref section value) t shown)
                          (mapc #'walk (oref section children)))))
            (mapc #'walk (oref magit-root-section children))))
        (maphash (lambda (dir watch)
                   (unless (gethash dir shown)
                     (ignore-errors (file-notify-rm-watch watch))
                     (remhash dir +sidebar--explorer-watches)))
                 +sidebar--explorer-watches)
        (maphash (lambda (dir _)
                   (unless (gethash dir +sidebar--explorer-watches)
                     (when-let* ((watch (ignore-errors
                                          (file-notify-add-watch
                                           dir '(change)
                                           (lambda (_event) (+sidebar--request 'explorer))))))
                       (puthash dir watch +sidebar--explorer-watches))))
                 shown)))))

;;;###autoload
(defun +sidebar--unwatch-all ()
  "Stop watching every folder."
  (maphash (lambda (_dir watch) (ignore-errors (file-notify-rm-watch watch)))
           +sidebar--explorer-watches)
  (clrhash +sidebar--explorer-watches))

;;;###autoload
(defun +sidebar--explorer-left ()
  "The Explorer is off the screen: watch no folder, follow no buffer for
Outline, forget a reveal or an Outline asked for, and draw it afresh
when it shows again."
  (+sidebar--unwatch-all)
  (+sidebar--outline-follow nil)
  (when-let* ((explorer (get-buffer "*Sidebar: Explorer*")))
    (with-current-buffer explorer
      (setq +sidebar--dirty t
            +sidebar--explorer-pending nil
            +sidebar--outline-pending nil))))


;;
;;; What the commands act on

(defun +sidebar--explorer-path ()
  "The file or folder at point."
  (when-let* ((section (magit-current-section)))
    (and (memq (oref section type) '(+sidebar-dir +sidebar-path))
         (oref section value))))

(defun +sidebar--explorer-dir ()
  "The folder a new file goes in: the one at point, or the folder of the
file at point, else the root."
  (let ((path (+sidebar--explorer-path)))
    (cond ((null path) +sidebar--shown-root)
          ((directory-name-p path) path)
          (t (file-name-directory path)))))

(defun +sidebar--explorer-file-path ()
  "The file or folder at point, or an error."
  (or (+sidebar--explorer-path) (user-error "No file here")))


;;
;;; Opening

;;;###autoload
(defun +sidebar/explorer-open ()
  "Open the file at point in the editor window; fold or unfold a folder."
  (interactive)
  (let ((path (+sidebar--explorer-path))
        (section (magit-current-section)))
    (cond ((and section (+sidebar--section-open section)))
          ((and path (not (directory-name-p path)))
           (select-window (+sidebar--editor-window))
           (find-file path))
          (section
           (magit-section-toggle section)
           (+sidebar--sync-watches)))))

;;;###autoload
(defun +sidebar/explorer-open-side ()
  "Open the file at point in a new window right of the editor window."
  (interactive)
  (let ((path (+sidebar--explorer-file-path)))
    (when (directory-name-p path)
      (user-error "A folder: RET folds it"))
    (select-window (split-window (+sidebar--editor-window) nil 'right))
    (find-file path)))

;;;###autoload
(defun +sidebar/explorer-click (event)
  "Open the file clicked on, or fold the folder."
  (interactive "e")
  (mouse-set-point event)
  (+sidebar/explorer-open))


;;
;;; Files

(defun +sidebar--explorer-done (message &rest args)
  "Say MESSAGE with ARGS and draw the Explorer again."
  (apply #'message message args)
  (+sidebar--request 'explorer))

(defun +sidebar--explorer-blank-p (name)
  "Non-nil when NAME, a path as typed, is empty or has a blank part."
  (or (string-blank-p name)
      (seq-some #'string-blank-p (split-string name "/" t))))

(defun +sidebar--explorer-target (prompt from verb)
  "A new path for FROM, read with PROMPT; refused when it is FROM again or
names nothing, with what to type for VERB, move or copy."
  (let ((to (expand-file-name (read-file-name prompt (file-name-directory from)
                                              nil nil (file-name-nondirectory from)))))
    (when (or (equal (directory-file-name to) from)
              (+sidebar--explorer-blank-p (file-name-nondirectory (directory-file-name to))))
      (user-error "Type a new name, or a path to %s %s to" verb (file-name-nondirectory from)))
    to))

;;;###autoload
(defun +sidebar/explorer-new ()
  "Make a file in the folder at point and open it; a name ending in a
slash makes a folder."
  (interactive)
  (let* ((dir (+sidebar--explorer-dir))
         (name (read-string (format "New in %s (end with / for a folder): "
                                    (abbreviate-file-name dir))))
         (path (if (+sidebar--explorer-blank-p name)
                   (user-error "Type a name for the new file, or one ending in / for a folder")
                 (expand-file-name name dir))))
    (when (file-exists-p path)
      (user-error "%s exists" (abbreviate-file-name path)))
    (if (directory-name-p path)
        (progn (make-directory path t)
               (+sidebar--explorer-done "Made %s" (abbreviate-file-name path)))
      (make-empty-file path t)
      (with-current-buffer (+sidebar--buffer 'explorer)
        (setq +sidebar--explorer-pending path))
      (+sidebar--request 'explorer)
      (select-window (+sidebar--editor-window))
      (find-file path))))

;;;###autoload
(defun +sidebar/explorer-rename ()
  "Rename or move the file or folder at point; its buffers follow it."
  (interactive)
  (require 'dired-aux)
  (let* ((from (directory-file-name (+sidebar--explorer-file-path)))
         (to (+sidebar--explorer-target "Rename or move to: " from "move")))
    (when (file-exists-p to)
      (user-error "%s exists" (abbreviate-file-name to)))
    (make-directory (file-name-directory to) t)
    (dired-rename-file from to nil)
    (+sidebar--explorer-done "Moved to %s" (abbreviate-file-name to))))

;;;###autoload
(defun +sidebar/explorer-delete ()
  "Move the file or folder at point to the trash, after asking, and offer
to kill the buffers of what went."
  (interactive)
  (let* ((path (+sidebar--explorer-file-path))
         (name (file-name-nondirectory (directory-file-name path)))
         (folder (directory-name-p path)))
    (when (equal path +sidebar--shown-root)
      (user-error "The root folder stays: trash it from a file manager"))
    (when (y-or-n-p (format "Move %s to the trash? " name))
      ;; Found first: once the folder is gone, nothing is in it.
      (let ((visiting (seq-filter
                       (lambda (buffer)
                         (when-let* ((file (buffer-file-name buffer)))
                           (if folder (file-in-directory-p file path) (equal file path))))
                       (buffer-list)))
            (delete-by-moving-to-trash t))
        (if folder
            (delete-directory path t t)
          (delete-file path t))
        (dolist (buffer visiting)
          (when (y-or-n-p (format "Kill buffer %s too%s? " (buffer-name buffer)
                                  (if (buffer-modified-p buffer)
                                      ", its unsaved changes lost"
                                    "")))
            (with-current-buffer buffer (set-buffer-modified-p nil))
            (kill-buffer buffer))))
      (+sidebar--explorer-done "Moved %s to the trash" name))))

;;;###autoload
(defun +sidebar/explorer-copy ()
  "Copy the file or folder at point, a folder with everything in it."
  (interactive)
  (let* ((from (directory-file-name (+sidebar--explorer-file-path)))
         (to (+sidebar--explorer-target "Copy to: " from "copy")))
    (when (file-exists-p to)
      (user-error "%s exists" (abbreviate-file-name to)))
    (if (file-directory-p from)
        (copy-directory from to t t)
      (make-directory (file-name-directory to) t)
      (copy-file from to nil t))
    (+sidebar--explorer-done "Copied to %s" (abbreviate-file-name to))))

(defun +sidebar--explorer-kill (text)
  "Put TEXT in the kill ring and say so."
  (kill-new text)
  (message "Copied %s" text))

;;;###autoload
(defun +sidebar/explorer-copy-name ()
  "Copy the name of the file or folder at point."
  (interactive)
  (+sidebar--explorer-kill (file-name-nondirectory (directory-file-name (+sidebar--explorer-file-path)))))

;;;###autoload
(defun +sidebar/explorer-copy-relative-path ()
  "Copy the path of the file or folder at point from the root."
  (interactive)
  (+sidebar--explorer-kill (file-relative-name (+sidebar--explorer-file-path) +sidebar--shown-root)))

;;;###autoload
(defun +sidebar/explorer-copy-path ()
  "Copy the absolute path of the file or folder at point."
  (interactive)
  (+sidebar--explorer-kill (+sidebar--explorer-file-path)))
