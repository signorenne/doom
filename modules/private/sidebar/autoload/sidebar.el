;;; private/sidebar/autoload/sidebar.el -*- lexical-binding: t; -*-
;;
;; The side bar's window and what keeps it current. It works only while
;; a window shows it: an event that changes what it shows marks the
;; view stale and, if the side bar is on show, redraws it after a rest,
;; once, from one timer; hidden, it redraws when shown again. Its hooks
;; and its watch on the repository exist only while it is on show.

(require 'magit-section)
(declare-function +workspace-current-name "workspaces")
(declare-function nerd-icons-icon-for-file "nerd-icons")
(declare-function nerd-icons-icon-for-dir "nerd-icons")
(defvar +sidebar-views)
(defvar +sidebar-width)
(defvar +sidebar-refresh-delay)
(defvar +sidebar-pinned-roots)
(defvar +sidebar-icons)
(defvar +sidebar--status-process)

(defvar-local +sidebar--view nil
  "In a side bar buffer: the key of its view.")

(defvar-local +sidebar--dirty t
  "Non-nil when the view is stale.")

(defvar-local +sidebar--shown-root nil
  "The directory the view last showed.")

(defvar +sidebar--last-view nil
  "The view the side bar showed last.")

(defvar +sidebar--wanted nil
  "Non-nil while the side bar is meant to be open, so a workspace switch
that took its window away brings it back.")

(defvar +sidebar--timer nil
  "The one-shot timer of the next redraw.")

(defvar +sidebar--gitdir-watch nil
  "(GITDIR . WATCH) of the repository the side bar shows.")


;;
;;; Views and their buffers

(defun +sidebar--entry (view)
  "VIEW's (KEY LABEL MODE RENDER)."
  (or (assq view +sidebar-views) (error "No side bar view %s" view)))

;;;###autoload
(defun +sidebar--buffer (view)
  "VIEW's buffer, made in its mode the first time."
  (pcase-let ((`(,_key ,label ,mode ,_render) (+sidebar--entry view)))
    (let ((name (format "*Sidebar: %s*" label)))
      (or (get-buffer name)
          (with-current-buffer (get-buffer-create name)
            (funcall mode)
            (current-buffer))))))

(defun +sidebar--tab-map (view)
  "A keymap that switches the side bar to VIEW on a click of its name."
  (let ((map (make-sparse-keymap)))
    (define-key map [header-line mouse-1]
                (lambda () (interactive) (+sidebar--show view t)))
    map))

(defun +sidebar--header (current)
  "The side bar's header with CURRENT's name set apart."
  (mapconcat (pcase-lambda (`(,key ,label . ,_))
               (propertize (concat " " label " ")
                           'face (if (eq key current) '+sidebar-tab-current '+sidebar-tab)
                           'mouse-face 'highlight
                           'help-echo (format "mouse-1: %s" label)
                           'keymap (+sidebar--tab-map key)))
             +sidebar-views "|"))

(defun +sidebar--hide-mode-line-h ()
  "Draw no modeline in this side bar buffer."
  (setq mode-line-format nil))

;;;###autoload
(defun +sidebar--view-setup (view)
  "Make this buffer VIEW's: called from the view's major mode."
  (setq +sidebar--view view
        truncate-lines t
        header-line-format (+sidebar--header view)
        buffer-read-only t)
  ;; Its width holds, as treemacs' did. Only preserved, it lapsed once a
  ;; resize left it a pixel off, and C-w = then shared it out: 81
  ;; columns after the frame went narrow and back.
  (setq-local window-size-fixed 'width)
  ;; The header names the view; a modeline would be the editor's, cut
  ;; off at the side bar's width. Doom's modeline is put on once the mode
  ;; is set up, hence the hook, after it.
  (add-hook 'after-change-major-mode-hook #'+sidebar--hide-mode-line-h 90 t)
  (setq-local revert-buffer-function (lambda (&rest _) (+sidebar--render))))

;;;###autoload
(defun +sidebar--redraw (insert)
  "Draw the view again with INSERT, which inserts its sections; point
stays on the same section, and folded sections stay folded."
  (let* ((inhibit-read-only t)
         (section (magit-current-section))
         (ident (and section (magit-section-ident section)))
         (offset (and section (count-lines (oref section start) (line-beginning-position))))
         (window-start (let ((window (get-buffer-window (current-buffer))))
                         (and window (window-start window)))))
    (erase-buffer)
    (setq magit-root-section nil)
    (funcall insert)
    (let ((magit-section-cache-visibility nil))
      (magit-section-show magit-root-section))
    (goto-char (point-min))
    (when-let* ((ident)
                (found (magit-get-section ident)))
      (goto-char (oref found start))
      (forward-line offset))
    (when-let* ((window (get-buffer-window (current-buffer)))
                (window-start))
      (set-window-start window (min window-start (point-max)) t))))

(defun +sidebar--render ()
  "Draw this side bar buffer's view now; with a status of the same root
on its way, once it lands. Starting that one over would never draw
while changes come faster than git answers."
  (if (and (process-live-p +sidebar--status-process)
           (equal +sidebar--shown-root (+sidebar--root)))
      (setq +sidebar--dirty t)
    (setq +sidebar--dirty nil)
    (funcall (nth 3 (+sidebar--entry +sidebar--view)))))


;;
;;; The window

;;;###autoload
(defun +sidebar--window (&optional frame)
  "The window of FRAME, or the selected frame, that shows the side bar."
  (seq-find (lambda (window) (buffer-local-value '+sidebar--view (window-buffer window)))
            (window-list frame 'no-mini)))

;;;###autoload
(defun +sidebar--editor-window ()
  "The window files open in: the last used one that is not a side
window, dedicated, or a popup."
  (or (car (sort (seq-filter
                  (lambda (window)
                    (not (or (window-parameter window 'window-side)
                             (window-dedicated-p window)
                             (window-parameter window 'popup)
                             (window-minibuffer-p window))))
                  (window-list nil 'no-mini))
                 (lambda (a b) (> (window-use-time a) (window-use-time b)))))
      (window-main-window)))

;;;###autoload
(defun +sidebar--root ()
  "The directory the side bar shows: the workspace's pin, else the
project of the file in the editor window, else its directory."
  (file-name-as-directory
   (file-truename
    (or (and (fboundp '+workspace-current-name)
             (alist-get (ignore-errors (+workspace-current-name))
                        +sidebar-pinned-roots nil nil #'equal))
        (with-current-buffer (window-buffer (+sidebar--editor-window))
          (or (+core-project-root-or-nil)
              (and buffer-file-name (file-name-directory buffer-file-name))
              default-directory))))))

;;;###autoload
(defun +sidebar--show (view &optional select)
  "Show VIEW in the side bar, opening it if need be; select it with SELECT."
  (let* ((buffer (+sidebar--buffer view))
         (window (+sidebar--window)))
    (if window
        (progn
          (set-window-dedicated-p window nil)
          (set-window-buffer window buffer)
          (set-window-dedicated-p window t))
      (setq window (display-buffer-in-side-window
                    buffer `((side . left) (slot . -1)
                             (window-width . ,+sidebar-width)
                             (preserve-size . (t . nil))
                             (dedicated . t)))))
    (+sidebar--own-window window)
    (setq +sidebar--last-view view
          +sidebar--wanted t)
    (+sidebar--hooks t)
    ;; The Explorer watches and follows only while it shows.
    (unless (eq view 'explorer)
      (when (fboundp '+sidebar--explorer-left)
        (+sidebar--explorer-left)))
    (with-current-buffer buffer
      (when (or +sidebar--dirty (not (equal +sidebar--shown-root (+sidebar--root))))
        (+sidebar--render)))
    (when select
      (select-window window))
    window))

(defun +sidebar--own-window (window)
  "Give the side bar's WINDOW its parameters: delete-other-windows keeps
it, and closing it any way closes the side bar. A layout restored from
a saved state, a workspace's, rebuilds the window without them."
  (set-window-parameter window 'no-delete-other-windows t)
  (set-window-parameter window 'delete-window #'+sidebar--delete-window))

;;;###autoload
(defun +sidebar--delete-window (window)
  "Close the side bar's WINDOW for good, however it is closed: a
workspace switch does not bring it back."
  (setq +sidebar--wanted nil)
  (let ((ignore-window-parameters t))
    (delete-window window))
  (+sidebar--hooks nil))

(defun +sidebar--close ()
  "Close the side bar and go back to the editor window."
  (setq +sidebar--wanted nil)
  (when-let* ((window (+sidebar--window)))
    (let ((editor (+sidebar--editor-window)))
      (delete-window window)
      (when (window-live-p editor)
        (select-window editor))))
  (+sidebar--hooks nil))

;;;###autoload
(defun +sidebar--open (view)
  "Show VIEW and select it; close the side bar if it is there already."
  (let ((window (+sidebar--window)))
    (if (and window (eq window (selected-window))
             (eq (buffer-local-value '+sidebar--view (window-buffer window)) view))
        (+sidebar--close)
      (+sidebar--show view t))))


;;
;;; Keeping it current

;;;###autoload
(defun +sidebar--request (&optional view)
  "Mark VIEW, or every view, stale; redraw the one on show after a rest."
  (dolist (entry +sidebar-views)
    (when (or (null view) (eq view (car entry)))
      (when-let* ((buffer (get-buffer (format "*Sidebar: %s*" (nth 1 entry)))))
        (with-current-buffer buffer
          (setq +sidebar--dirty t)))))
  (when (and (+sidebar--window) (not (timerp +sidebar--timer)))
    (setq +sidebar--timer
          (run-with-idle-timer (if-let* ((idle (current-idle-time)))
                                   (time-add idle +sidebar-refresh-delay)
                                 +sidebar-refresh-delay)
                               nil #'+sidebar--refresh-shown))))

(defun +sidebar--refresh-shown ()
  "Redraw the view on show if it is stale."
  (setq +sidebar--timer nil)
  (when-let* ((window (+sidebar--window)))
    (with-current-buffer (window-buffer window)
      (when +sidebar--dirty
        (+sidebar--render)))))

(defvar +sidebar--followed nil
  "The editor's buffer the side bar followed last.")

(defun +sidebar--windows-h (frame)
  "Follow what the editor window shows, when that changed: a window that
only comes and goes beside it, which-key's after a prefix key, moves
nothing. Let go of everything once no window shows the side bar."
  (when (eq frame (selected-frame))
    (if-let* ((window (+sidebar--window frame)))
        (with-current-buffer (window-buffer window)
          (+sidebar--own-window window)
          (unless (equal +sidebar--shown-root (+sidebar--root))
            (+sidebar--request))
          (let ((editor (window-buffer (+sidebar--editor-window))))
            (unless (eq editor +sidebar--followed)
              (setq +sidebar--followed editor)
              (run-hook-with-args '+sidebar-editor-changed-functions editor))))
      (+sidebar--hooks nil))))

(defvar +sidebar-editor-changed-functions nil
  "Called with the editor window's buffer when the windows change while
the side bar is on show.")

(defun +sidebar--changed-h (&rest _)
  "Something the side bar shows may have changed."
  (+sidebar--request))

(defun +sidebar--saved-h ()
  "A file was saved: its state in git, and in Open editors, changed."
  (+sidebar--request))

(defun +sidebar--buffers-changed-h (&rest _)
  "A file's buffer was killed or modified: Open editors, if open, changes."
  (when (and buffer-file-name
             (+sidebar--explorer-open-p '(+sidebar-editors)))
    (+sidebar--request 'explorer)))

(defun +sidebar--workspace-h (&rest _)
  "Bring the side bar back after a workspace switch took its window."
  (when +sidebar--wanted
    (run-at-time 0 nil
                 (lambda ()
                   (when +sidebar--wanted
                     (if-let* ((window (+sidebar--window)))
                         (+sidebar--own-window window)
                       (+sidebar--show (or +sidebar--last-view (caar +sidebar-views))))
                     (+sidebar--request))))))

;;;###autoload
(defun +sidebar--watch-gitdir (root)
  "Watch ROOT's git dir, the index and HEAD, while the side bar shows it."
  (let ((gitdir (and root
                     (let ((default-directory root))
                       (with-temp-buffer
                         (and (zerop (call-process "git" nil (list t nil) nil
                                                   "rev-parse" "--absolute-git-dir"))
                              (string-trim-right (buffer-string))))))))
    (unless (equal gitdir (car +sidebar--gitdir-watch))
      (+sidebar--unwatch-gitdir)
      (when gitdir
        (setq +sidebar--gitdir-watch
              (cons gitdir (ignore-errors
                             (file-notify-add-watch gitdir '(change)
                                                    #'+sidebar--changed-h))))))))

(defun +sidebar--unwatch-gitdir ()
  "Stop watching the repository's git dir."
  (when (cdr +sidebar--gitdir-watch)
    (file-notify-rm-watch (cdr +sidebar--gitdir-watch)))
  (setq +sidebar--gitdir-watch nil))

(defun +sidebar--hooks (on)
  "Add the side bar's hooks with ON, else take them away; the workspace
hook stays while the side bar is wanted."
  ;; Shown again, it follows the editor's buffer once more.
  (setq +sidebar--followed nil)
  (if on
      (progn
        (add-hook 'window-buffer-change-functions #'+sidebar--windows-h)
        (add-hook 'magit-post-refresh-hook #'+sidebar--changed-h)
        (add-hook 'after-save-hook #'+sidebar--saved-h)
        (add-hook '+ai-edit-functions #'+sidebar--changed-h)
        (add-hook 'kill-buffer-hook #'+sidebar--buffers-changed-h)
        (add-hook 'first-change-hook #'+sidebar--buffers-changed-h)
        (add-hook 'persp-activated-functions #'+sidebar--workspace-h))
    (remove-hook 'window-buffer-change-functions #'+sidebar--windows-h)
    (remove-hook 'magit-post-refresh-hook #'+sidebar--changed-h)
    (remove-hook 'after-save-hook #'+sidebar--saved-h)
    (remove-hook '+ai-edit-functions #'+sidebar--changed-h)
    (remove-hook 'kill-buffer-hook #'+sidebar--buffers-changed-h)
    (remove-hook 'first-change-hook #'+sidebar--buffers-changed-h)
    (unless +sidebar--wanted
      (remove-hook 'persp-activated-functions #'+sidebar--workspace-h))
    (+sidebar--unwatch-gitdir)
    ;; Hidden, nothing watches: whatever changes meanwhile is caught by a
    ;; full drawing when shown.
    (when (fboundp '+sidebar--explorer-left)
      (+sidebar--explorer-left))
    (dolist (entry +sidebar-views)
      (when-let* ((buffer (get-buffer (format "*Sidebar: %s*" (nth 1 entry)))))
        (with-current-buffer buffer
          (+sidebar--drop-status)
          (setq +sidebar--dirty t))))
    (when (timerp +sidebar--timer)
      (cancel-timer +sidebar--timer)
      (setq +sidebar--timer nil))))


;;
;;; git's view of the files

;;;###autoload
(defun +sidebar--git-root (dir)
  "The git toplevel of DIR as a directory name, or nil."
  (when (and dir (file-directory-p dir) (not (file-remote-p dir)))
    (let ((default-directory dir))
      (with-temp-buffer
        (when (zerop (call-process "git" nil (list t nil) nil "rev-parse" "--show-toplevel"))
          (let ((top (string-trim-right (buffer-string))))
            (unless (string-empty-p top)
              (file-name-as-directory (expand-file-name top)))))))))

(defvar-local +sidebar--status-process nil
  "The git status this view waits on.")

(defun +sidebar--drop-status ()
  "Drop the git status this view waits on."
  (when (process-live-p +sidebar--status-process)
    (let ((old +sidebar--status-process))
      (setq +sidebar--status-process nil)
      (delete-process old))))

;;;###autoload
(defun +sidebar--with-status (repo then)
  "Read git's status of REPO in the background, then call THEN in this
buffer with it, as `+sidebar--status-parse' gives it; at once with nil
when REPO is nil. A status still on its way is dropped for the new one;
one that lands once no window shows the view only marks it stale.
It runs with GIT_OPTIONAL_LOCKS=0, so it never rewrites the index the
side bar watches."
  (+sidebar--drop-status)
  (if (not repo)
      (funcall then nil)
    (let* ((buffer (current-buffer))
           (chunks nil)
           (default-directory repo)
           (process-environment (cons "GIT_OPTIONAL_LOCKS=0" process-environment)))
      (setq +sidebar--status-process
            (make-process
             :name "sidebar-status" :buffer nil :noquery t :connection-type 'pipe
             :coding 'utf-8-unix
             :stderr (make-pipe-process :name "sidebar-status-errors" :buffer nil
                                        :noquery t :filter #'ignore :sentinel #'ignore)
             :command '("git" "status" "--porcelain=v2" "-z"
                        "--untracked-files=normal" "--ignored=matching")
             :filter (lambda (_proc string) (push string chunks))
             :sentinel
             (lambda (proc _event)
               (unless (process-live-p proc)
                 (when (buffer-live-p buffer)
                   (with-current-buffer buffer
                     (when (eq proc +sidebar--status-process)
                       (setq +sidebar--status-process nil)
                       (if (not (get-buffer-window buffer t))
                           (setq +sidebar--dirty t)
                         (funcall then (+sidebar--status-parse
                                        (apply #'concat (nreverse chunks))))
                         ;; Changed while git was at it.
                         (when +sidebar--dirty
                           (+sidebar--request +sidebar--view)))))))))))))

(defun +sidebar--status-parse (out)
  "git's status OUT, porcelain v2 with -z, as (STAGED UNSTAGED UNTRACKED
UNMERGED IGNORED): lists of (PATH . LETTER), paths from the toplevel; an
untracked or ignored folder is one entry ending in a slash."
  (let (staged unstaged untracked unmerged ignored)
    (progn
      (let ((entries (split-string out "\0" t)))
        (while entries
          (let ((entry (pop entries)))
            (cond
             ((string-match "\\`1 \\(.\\)\\(.\\) \\(?:[^ ]+ \\)\\{6\\}\\(.*\\)\\'" entry)
              (let ((x (match-string 1 entry)) (y (match-string 2 entry))
                    (path (match-string 3 entry)))
                (unless (equal x ".") (push (cons path x) staged))
                (unless (equal y ".") (push (cons path y) unstaged))))
             ((string-match "\\`2 \\(.\\)\\(.\\) \\(?:[^ ]+ \\)\\{7\\}\\(.*\\)\\'" entry)
              (let ((x (match-string 1 entry)) (y (match-string 2 entry))
                    (path (match-string 3 entry)))
                ;; The path it was renamed from comes as an entry of its own.
                (pop entries)
                (unless (equal x ".") (push (cons path x) staged))
                (unless (equal y ".") (push (cons path y) unstaged))))
             ((string-match "\\`u .. \\(?:[^ ]+ \\)\\{8\\}\\(.*\\)\\'" entry)
              (push (cons (match-string 1 entry) "C") unmerged))
             ((string-prefix-p "? " entry)
              (push (cons (substring entry 2) "U") untracked))
             ((string-prefix-p "! " entry)
              (push (cons (substring entry 2) "I") ignored)))))))
    (mapcar (lambda (list) (sort list (lambda (a b) (string< (car a) (car b)))))
            (list staged unstaged untracked unmerged ignored))))

;;;###autoload
(defun +sidebar--letter-face (letter)
  "The face of a file with status LETTER."
  (pcase letter
    ((or "M" "R" "T") '+sidebar-modified)
    ((or "A" "C") (if (equal letter "C") '+sidebar-conflict '+sidebar-added))
    ("D" '+sidebar-deleted)
    ("U" '+sidebar-untracked)
    ("I" '+sidebar-ignored)
    (_ 'default)))

;;;###autoload
(defun +sidebar--icon (name &optional dir)
  "The icon of file NAME, or of a folder with DIR, and a space."
  (if (and +sidebar-icons (display-graphic-p) (require 'nerd-icons nil t))
      ;; font-lock would take a plain face away in these buffers.
      (let ((icon (if dir (nerd-icons-icon-for-dir name) (nerd-icons-icon-for-file name))))
        (concat (propertize icon 'font-lock-face (get-text-property 0 'face icon)) " "))
    ""))

;;;###autoload
(defun +sidebar--file-line (path letter &optional indent)
  "A line for the file at PATH with status LETTER, INDENT columns in:
its name, its folder dimmed, the letter at the right edge."
  (let ((name (file-name-nondirectory path))
        (dir (file-name-directory path))
        (face (+sidebar--letter-face letter)))
    (concat (make-string (or indent 2) ?\s)
            (+sidebar--icon name)
            (propertize name 'font-lock-face face)
            (if dir (concat " " (propertize (directory-file-name dir) 'font-lock-face 'shadow)) "")
            (propertize " " 'display '(space :align-to (- right 2)))
            (propertize letter 'font-lock-face face))))


;;
;;; Commands the views share

;;;###autoload
(defun +sidebar/next-view ()
  "Show the side bar's next view."
  (interactive)
  (+sidebar--step-view 1))

;;;###autoload
(defun +sidebar/previous-view ()
  "Show the side bar's previous view."
  (interactive)
  (+sidebar--step-view -1))

(defun +sidebar--step-view (step)
  "Show the view STEP places on from the one on show."
  (let* ((keys (mapcar #'car +sidebar-views))
         (here (or (cl-position +sidebar--view keys) 0)))
    (+sidebar--show (nth (mod (+ here step) (length keys)) keys) t)))

;;;###autoload
(defun +sidebar/refresh ()
  "Draw the view again now, or once the git status on its way lands."
  (interactive)
  (+sidebar--render))

;;;###autoload
(defun +sidebar/quit ()
  "Close the side bar."
  (interactive)
  (+sidebar--close))

(defvar +sidebar--fold-commands
  '(("TAB" . magit-section-toggle) ("<tab>" . magit-section-toggle)
    ("<backtab>" . magit-section-cycle-global)
    ("z a" . magit-section-toggle) ("z o" . magit-section-show)
    ("z c" . magit-section-hide) ("z O" . magit-section-show-children)
    ("z C" . magit-section-hide-children)
    ("z r" . magit-section-show-level-4-all) ("z m" . magit-section-show-level-1-all)
    ("z 1" . magit-section-show-level-1-all) ("z 2" . magit-section-show-level-2-all)
    ("z 3" . magit-section-show-level-3-all) ("z 4" . magit-section-show-level-4-all))
  "The magit-section command each folding key of the side bar runs, in
normal state, through `+sidebar/fold'.")

(defvar +sidebar--fold-remaps
  '(magit-section-toggle magit-section-cycle magit-section-cycle-global
    magit-section-show magit-section-hide magit-section-toggle-children
    magit-section-show-children magit-section-hide-children
    magit-section-show-headings
    magit-section-show-level-1 magit-section-show-level-2
    magit-section-show-level-3 magit-section-show-level-4
    magit-section-show-level-1-all magit-section-show-level-2-all
    magit-section-show-level-3-all magit-section-show-level-4-all
    magit-mouse-toggle-section)
  "magit's folding commands. In the side bar each runs through
`+sidebar/fold', whatever reaches it: a key, C-<tab>, a click on a
heading or in the fringe.")

;;;###autoload
(defun +sidebar/fold ()
  "Fold or unfold as the key pressed does in magit, then watch exactly the
folders now on show.  It runs in place of each of magit's folding
commands, whichever key or click asked for one."
  (interactive)
  ;; The command the key or click is bound to, before the remapping that
  ;; brought it here. Not looked up from the keys: in normal state here
  ;; those of z o come in as z alone.
  (when (memq this-original-command +sidebar--fold-remaps)
    (call-interactively this-original-command))
  (when (eq +sidebar--view 'explorer)
    (+sidebar--sync-watches)))

;;;###autoload
(defun +sidebar--bind-common (map)
  "Bind the keys every view shares in MAP, for evil's normal state, and
send every folding command of magit's through `+sidebar/fold'."
  (apply #'evil-define-key* 'normal map
         (mapcan (lambda (entry) (list (kbd (car entry)) (cdr entry)))
                 +sidebar--fold-commands))
  (dolist (command +sidebar--fold-remaps)
    (define-key map (vector 'remap command) #'+sidebar/fold))
  (evil-define-key* 'normal map
    "gj" #'magit-section-forward-sibling
    "gk" #'magit-section-backward-sibling
    "^" #'magit-section-up
    "gh" #'magit-section-up
    "H" #'+sidebar/previous-view
    "L" #'+sidebar/next-view
    "gr" #'+sidebar/refresh
    "q" #'+sidebar/quit))
