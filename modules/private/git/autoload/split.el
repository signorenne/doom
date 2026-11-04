;;; private/git/autoload/split.el -*- lexical-binding: t; -*-
;;
;; The old version beside the file: read-only on the left, the file on
;; the right and editable, each hunk padded with empty lines on its
;; shorter side so the two sides line up, and scrolled together. The
;; engine of live.el diffs it as it does the live view; this file draws
;; the hunks on two sides. A commit's change to a file is shown the same
;; way, two read-only versions, drawn once.

(declare-function magit-find-file-noselect "magit-files")
(declare-function magit-rev-verify "magit-git")
(defvar +git-split-mode-map)
(defvar +git-split-base-mode-map)
(defvar +git-live-mode)
(defvar +git-live-baseline)
(defvar +git--live-base-file)
(defvar +git--live-baseline-functions)
(defvar +git--live-draw-function)
(defvar +git--live-hunks)
(defvar +git--live-kind)
(defvar +git--live-label)
(defvar +git--live-overlays)
(defvar +git--live-refine-function)

;; The engine and its variables are live.el's; a split may be the first
;; thing a session asks for, so live.el is loaded with this file.
(let ((engine (symbol-function '+git-live-mode)))
  (when (autoloadp engine)
    (autoload-do-load engine '+git-live-mode)))

(defvar-local +git--split-base nil
  "In the right side's buffer: the old version's buffer on the left.")

(defvar-local +git--split-file nil
  "In the old version's buffer: the right side's buffer.")

(defvar-local +git--split-overlays nil
  "In the old version's buffer: the overlays drawn there.")

(defvar-local +git--split-expect nil
  "The window start the other side just gave this buffer's window, so
the scroll it causes is not sent back.")

(defvar-local +git--split-static nil
  "In the right side of a commit's change: its hunks, drawn once.")

(defvar +git--split-pairs nil
  "Right sides of the splits on show.")

(defun +git--split-hunks ()
  "This right side's hunks."
  (if (eq +git--live-kind 'static) +git--split-static +git--live-hunks))


;;
;;; Drawing on two sides

(defun +git--split-filler (count at)
  "COUNT empty lines that pad a side, drawn at AT."
  (concat (and (= at (point-max))
               (save-excursion (goto-char at) (not (bolp)))
               "\n")
          (propertize (make-string count ?\n) 'face '+git-split-filler)))

(defun +git--split-overlay (beg end face pad)
  "An overlay from BEG to END in FACE, padded below by PAD lines; above
when it is empty."
  (let ((overlay (make-overlay beg end nil nil nil)))
    (overlay-put overlay '+git-live t)
    (overlay-put overlay 'priority -60)
    (when (< beg end)
      (overlay-put overlay 'face face))
    (when (> pad 0)
      (overlay-put overlay (if (= beg end) 'before-string 'after-string)
                   (+git--split-filler pad beg)))
    overlay))

(defun +git--split-draw (hunks)
  "Draw HUNKS on the right side, this buffer, and on the left."
  (setq +git--live-overlays
        (+git--live-reconcile
         +git--live-overlays
         (mapcar (pcase-lambda (`(,hunk ,beg . ,end))
                   (list beg end
                         (+git--hunk-new-count hunk) (+git--hunk-old-count hunk)
                         (+git--hunk-old-start hunk) (+git--hunk-old-text hunk)))
                 (+git--live-spans hunks))
         (pcase-lambda (`(,beg ,end ,new ,old ,_start ,old-text))
           (let ((overlay (+git--split-overlay beg end '+git-live-added
                                               (max 0 (- old new)))))
             (overlay-put overlay '+git-live-old old-text)
             overlay))))
  (when (buffer-live-p +git--split-base)
    (with-current-buffer +git--split-base
      (setq +git--split-overlays
            (+git--live-reconcile
             +git--split-overlays
             (mapcar (pcase-lambda (`(,hunk ,beg . ,end))
                       (list beg end
                             (+git--hunk-old-count hunk) (+git--hunk-new-count hunk)
                             (+git--hunk-old-text hunk)))
                     (+git--live-spans hunks t))
             (pcase-lambda (`(,beg ,end ,old ,new ,_text))
               (+git--split-overlay beg end '+git-live-removed (max 0 (- new old)))))))))

(defun +git--split-refine (overlay)
  "Mark the changed words of OVERLAY's hunk on both sides."
  (pcase-let* ((`(,_new ,old ,start ,_text) (overlay-get overlay '+git-live-identity))
               (base +git--split-base))
    (mapc #'delete-overlay (overlay-get overlay '+git-live-words))
    (when (buffer-live-p base)
      (let* ((old-beg (with-current-buffer base
                        (save-excursion
                          (goto-char (point-min))
                          (forward-line (1- start))
                          (point-marker))))
             (old-end (with-current-buffer base
                        (save-excursion
                          (goto-char old-beg)
                          (forward-line old)
                          (point-marker))))
             (words (+git--live-refine-pair old-beg old-end
                                            (copy-marker (overlay-start overlay))
                                            (copy-marker (overlay-end overlay)))))
        (overlay-put overlay '+git-live-words (append (car words) (cdr words)))))))


;;
;;; Scrolling together

(defun +git--split-map (line hunks from-old)
  "The line of the other side that LINE of one side lines up with:
LINE is of the new side, or of the old side with FROM-OLD."
  (let ((delta 0) (result nil))
    (while (and hunks (not result))
      (let* ((hunk (pop hunks))
             (new (+git--hunk-new-count hunk))
             (old (+git--hunk-old-count hunk))
             (new-first (if (zerop new) (1+ (+git--hunk-new-start hunk)) (+git--hunk-new-start hunk)))
             (old-first (if (zerop old) (1+ (+git--hunk-old-start hunk)) (+git--hunk-old-start hunk)))
             (here (if from-old old-first new-first))
             (there (if from-old new-first old-first))
             (here-count (if from-old old new))
             (there-count (if from-old new old)))
        (cond ((< line here) (setq result (+ line delta)))
              ((< line (+ here here-count))
               (setq result (+ there (if (> there-count 0)
                                         (min (- line here) (1- there-count))
                                       0))))
              (t (setq delta (- (+ there there-count) (+ here here-count)))))))
    (max 1 (or result (+ line delta)))))

(defun +git--split-scrolled-h (window start)
  "Scroll the other side's window to the line WINDOW's START lines up with."
  (if (eql start +git--split-expect)
      (setq +git--split-expect nil)
    (let* ((right (or +git--split-file (current-buffer)))
           (other (if +git--split-file +git--split-file +git--split-base))
           (other-window (and (buffer-live-p other)
                              (get-buffer-window other (window-frame window)))))
      (when other-window
        (let ((target (+git--split-map (line-number-at-pos start t)
                                       (with-current-buffer right (+git--split-hunks))
                                       (and +git--split-file t))))
          (with-current-buffer other
            (let ((pos (save-excursion
                         (save-restriction
                           (widen)
                           (goto-char (point-min))
                           (forward-line (1- target))
                           (point)))))
              (unless (= pos (window-start other-window))
                (setq +git--split-expect pos)
                (set-window-start other-window pos)
                ;; A point left behind out of sight would pull the window
                ;; back to it the moment it is selected.
                (let ((point (window-point other-window))
                      (half (save-excursion
                              (goto-char pos)
                              (forward-line (/ (window-body-height other-window) 2))
                              (point))))
                  (unless (and (>= point pos) (< point half))
                    (set-window-point other-window pos)))))))))))


;;
;;; The old version's buffer

(define-minor-mode +git-split-base-mode
  "The old version beside a file: read-only, q to close the split."
  :lighter nil
  :keymap +git-split-base-mode-map)

(defun +git--split-make-base (name mode)
  "A read-only buffer named NAME for an old version in major MODE.
The mode's hooks do not run, so no language server or checker starts
on it; font-lock is turned on by hand, as the global mode never sees it."
  (let ((buffer (generate-new-buffer name)))
    (with-current-buffer buffer
      (let ((delay-mode-hooks t))
        (ignore-errors (funcall mode)))
      (setq delayed-mode-hooks nil)
      (font-lock-mode 1)
      (setq buffer-read-only t
            truncate-lines t)
      (+git-split-base-mode 1)
      (add-hook 'kill-buffer-hook #'+git--split-base-killed-h nil t)
      (add-hook 'window-scroll-functions #'+git--split-scrolled-h nil t)
      (add-hook 'clone-indirect-buffer-hook #'+git--split-base-cloned-h nil t)
      (when (fboundp 'evil-normal-state)
        (evil-normal-state)))
    buffer))

(defun +git--split-fill (buffer file coding)
  "Put FILE's text, read in CODING, into the old version's BUFFER."
  (with-current-buffer buffer
    (mapc #'delete-overlay +git--split-overlays)
    (setq +git--split-overlays nil)
    (let ((inhibit-read-only t)
          (coding-system-for-read coding))
      (erase-buffer)
      (insert-file-contents file))
    (set-buffer-modified-p nil)))

(defun +git--split-base-name ()
  "The old version's buffer name: this buffer's, and the baseline's."
  (format "*base: %s (%s)*" (buffer-name) +git--live-label))

(defun +git--split-rename-base-h ()
  "Name the old version after a baseline of the same text."
  (when (buffer-live-p +git--split-base)
    (let ((name (+git--split-base-name)))
      (with-current-buffer +git--split-base
        (rename-buffer name t)))))

(defun +git--split-reload-base-h ()
  "Make or refill the old version's buffer: the baseline changed."
  (let ((name (+git--split-base-name)))
    (unless (buffer-live-p +git--split-base)
      (setq +git--split-base (+git--split-make-base name major-mode))
      (let ((right (current-buffer)))
        (with-current-buffer +git--split-base
          (setq +git--split-file right))))
    (with-current-buffer +git--split-base
      (rename-buffer name t))
    (+git--split-fill +git--split-base +git--live-base-file (+git--live-coding))
    ;; The old text is new: the word marks drawn on it went with it.
    (dolist (overlay +git--live-overlays)
      (mapc #'delete-overlay (overlay-get overlay '+git-live-words))
      (overlay-put overlay '+git-live-words nil)
      (overlay-put overlay '+git-live-refined nil))))

(defun +git--split-show ()
  "Put the old version in a window to the left of this buffer's."
  (let* ((right (or (get-buffer-window (current-buffer)) (selected-window)))
         (left (split-window right nil 'left)))
    (set-window-buffer left +git--split-base)
    (set-window-dedicated-p left t)
    (set-window-start left (with-current-buffer +git--split-base (point-min)))
    (cl-pushnew (current-buffer) +git--split-pairs)
    (add-hook 'window-buffer-change-functions #'+git--split-check-h)))


;;
;;; Ending a split

(defun +git--split-kill-base ()
  "Close and kill this right side's old version."
  (setq +git--split-pairs (delq (current-buffer) +git--split-pairs))
  (unless +git--split-pairs
    (remove-hook 'window-buffer-change-functions #'+git--split-check-h))
  (when-let* ((base +git--split-base))
    (setq +git--split-base nil)
    (when (buffer-live-p base)
      (with-current-buffer base
        (setq +git--split-file nil))
      (dolist (window (get-buffer-window-list base nil t))
        (ignore-errors (delete-window window)))
      (kill-buffer base))))

(defun +git--split-end-static ()
  "End a commit's change shown on two sides."
  (mapc #'+git--live-delete-overlay +git--live-overlays)
  (remove-hook 'window-scroll-functions #'+git--split-scrolled-h t)
  (remove-hook 'window-scroll-functions #'+git--live-scrolled-h t)
  (setq +git--live-overlays nil
        +git--split-static nil
        +git--live-kind nil
        +git--live-refine-function #'+git--live-refine-inline)
  (+git--split-kill-base))

(defun +git--split-end (buffer)
  "End BUFFER's split, as a right side."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (cond ((eq +git--live-kind 'static) (+git--split-end-static))
            ((bound-and-true-p +git-split-mode) (+git-split-mode -1))))))

(defun +git--split-base-killed-h ()
  "End the split of an old version that is being killed."
  (when-let* ((right +git--split-file))
    (setq +git--split-file nil)
    (+git--split-end right)))

(defun +git--split-base-cloned-h ()
  "Leave the split to the old version this buffer was cloned from, and
take away what it drew."
  (save-restriction
    (widen)
    (dolist (overlay (overlays-in (point-min) (point-max)))
      (when (or (overlay-get overlay '+git-live) (overlay-get overlay '+git-live-word))
        (delete-overlay overlay))))
  (remove-hook 'kill-buffer-hook #'+git--split-base-killed-h t)
  (remove-hook 'window-scroll-functions #'+git--split-scrolled-h t)
  (remove-hook 'clone-indirect-buffer-hook #'+git--split-base-cloned-h t)
  (dolist (variable '(+git--split-file +git--split-overlays +git--split-expect
                      +git-split-base-mode))
    (kill-local-variable variable))
  (when (fboundp 'evil-normalize-keymaps)
    (evil-normalize-keymaps)))

(defun +git--split-check-h (_frame)
  "End the splits one of whose sides no window shows any more; after
redisplay, as windows are not deleted from within it."
  (dolist (right +git--split-pairs)
    (let ((base (and (buffer-live-p right) (buffer-local-value '+git--split-base right))))
      (unless (and base (buffer-live-p base)
                   (get-buffer-window right t) (get-buffer-window base t))
        (run-at-time 0 nil #'+git--split-end right)))))


;;
;;; The split view

;;;###autoload
(define-minor-mode +git-split-mode
  "This buffer beside its old version: the old one read-only on the left,
lines lined up, scrolled together, kept up as the buffer is edited."
  :lighter nil
  :keymap +git-split-mode-map
  (cond
   ((not +git-split-mode)
    (remove-hook '+git--live-baseline-functions #'+git--split-reload-base-h t)
    (remove-hook '+git--live-label-functions #'+git--split-rename-base-h t)
    (remove-hook 'window-scroll-functions #'+git--split-scrolled-h t)
    (+git--live-stop)
    (setq +git--live-draw-function #'+git--live-draw-inline
          +git--live-refine-function #'+git--live-refine-inline)
    (+git--split-kill-base))
   ((when-let* ((why (+git--live-refusal)))
      (setq +git-split-mode nil)
      (message "%s" why)))
   (t
    (when (bound-and-true-p +git-live-mode)
      (+git-live-mode -1))
    (setq +git--live-draw-function #'+git--split-draw
          +git--live-refine-function #'+git--split-refine)
    (add-hook '+git--live-baseline-functions #'+git--split-reload-base-h nil t)
    (add-hook '+git--live-label-functions #'+git--split-rename-base-h nil t)
    (add-hook 'window-scroll-functions #'+git--split-scrolled-h nil t)
    (+git--live-start 'split)
    (+git--split-show)))
  (when (fboundp 'evil-normalize-keymaps)
    (evil-normalize-keymaps)))

;;;###autoload
(defun +git/split ()
  "Show this file beside its old version, kept up as you edit; again, or
q on the old version, to close it."
  (interactive)
  (cond (+git--split-file (+git--split-end +git--split-file))
        ((eq +git--live-kind 'static) (+git--split-end (current-buffer)))
        (t (+git-split-mode (if +git-split-mode -1 1))
           (when +git-split-mode
             (message "Beside %s" +git--live-label)))))

;;;###autoload
(defun +git-live-open (file baseline &optional split)
  "Visit FILE in the selected window, which the caller makes the editor
window, with its changes against BASELINE in place, or beside it with
SPLIT."
  (let ((buffer (find-file-noselect file)))
    (switch-to-buffer buffer)
    (with-current-buffer buffer
      (setq-local +git-live-baseline baseline)
      (cond ((if split (bound-and-true-p +git-split-mode) (bound-and-true-p +git-live-mode))
             (+git--live-schedule t))
            (split (+git-split-mode 1))
            (t (+git-live-mode 1))))
    buffer))

;;;###autoload
(defun +git-split-commit (rev file &optional old-file)
  "Show what REV changed in FILE, a path from the toplevel: REV's parent
on the left, read as OLD-FILE when REV renamed it, REV on the right,
both read-only, lined up."
  (require 'magit)
  (let* ((default-directory (or (+git--live-toplevel default-directory) default-directory))
         (old-file (or old-file file))
         (parent (magit-rev-verify (concat rev "^")))
         ;; The file before REV, unless REV added it.
         (before (and parent
                      (zerop (call-process "git" nil nil nil "cat-file" "-e"
                                           (concat parent ":" old-file)))
                      (concat parent ":" old-file)))
         (right (magit-find-file-noselect rev file))
         (left (generate-new-buffer (format "*base: %s (%s)*" (file-name-nondirectory file)
                                            (if parent (substring parent 0 7) "none"))))
         (hunks (+git--live-parse
                 (with-temp-buffer
                   (apply #'call-process "git" nil (list t nil) nil "--no-pager" "diff"
                          "--no-color" "--no-ext-diff" "--histogram" "-U0"
                          (if before
                              ;; Blob against blob: a rename or a copy is a change
                              ;; like any other.
                              (list before (concat rev ":" file))
                            ;; Added, against the empty tree for a root commit.
                            (list (or parent
                                      (car (process-lines "git" "hash-object" "-t" "tree"
                                                          "/dev/null")))
                                  rev "--" file)))
                   (buffer-string)))))
    (with-current-buffer left
      (when before
        (insert (with-current-buffer (magit-find-file-noselect parent old-file)
                  (buffer-substring-no-properties (point-min) (point-max)))))
      (let ((delay-mode-hooks t))
        (ignore-errors (funcall (buffer-local-value 'major-mode right))))
      (setq delayed-mode-hooks nil)
      (font-lock-mode 1)
      (setq buffer-read-only t truncate-lines t +git--split-file right)
      (set-buffer-modified-p nil)
      (+git-split-base-mode 1)
      (add-hook 'kill-buffer-hook #'+git--split-base-killed-h nil t)
      (add-hook 'window-scroll-functions #'+git--split-scrolled-h nil t)
      (add-hook 'clone-indirect-buffer-hook #'+git--split-base-cloned-h nil t))
    (switch-to-buffer right)
    (with-current-buffer right
      (when (eq +git--live-kind 'static)
        (+git--split-end-static))
      (setq +git--split-base left
            +git--split-static hunks
            +git--live-kind 'static
            +git--live-refine-function #'+git--split-refine)
      (add-hook 'window-scroll-functions #'+git--split-scrolled-h nil t)
      (add-hook 'window-scroll-functions #'+git--live-scrolled-h nil t)
      (+git--split-draw hunks)
      (+git--split-show)
      (+git--live-schedule-refine))
    right))
