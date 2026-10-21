;;; private/ui/autoload/minimap.el -*- lexical-binding: t; -*-
;;
;; A minimap: the buffer in a tiny font in a narrow window on the right,
;; the part on screen marked, the line point is on marked, a click to go
;; there.
;;
;; It is a copy of the buffer's text, not a second view of the same text.
;; demap, which this replaces, showed an indirect buffer, and an indirect
;; buffer shares its text's change counters with its base: every overlay
;; moved in the file, hl-line's at each line, the paren highlight, the
;; server's hints, marked the minimap's window out of date, and its
;; hundreds of lines were laid out again at every key. Measured beside a
;; C++ file: 8 ms a move for demap, 1.5 for a copy. The copy is taken
;; again once the typing pauses; the marks follow every move, and the
;; minimap's own window follows them a move later, or at rest.

(defvar +ui-minimap-width 16
  "Columns of the minimap's window.")

(defvar +ui-minimap-idle 0.1
  "Seconds of rest before the minimap catches up with what a move could
not do at once: a new buffer, its own window to scroll.")

(defvar +ui-minimap-copy-idle 0.5
  "Seconds of rest after an edit before the text is copied again.")

(defvar +ui-minimap-colour-max-size (* 1024 1024)
  "The largest buffer whose colours are worked out in full for the
minimap. Past it the minimap shows the colours of what has been seen.")

(defface +ui-minimap-face '((t :height 30))
  "The minimap's text."
  :group 'faces)

(defface +ui-minimap-region-face '((t :extend t))
  "The part of the buffer on screen, in the minimap: a gray a little off
the background, worked out from the theme by `+ui--minimap-faces-h'."
  :group 'faces)

(defface +ui-minimap-line-face '((t :extend t))
  "The line point is on, in the minimap: a gray a little further off."
  :group 'faces)

(defvar +ui-minimap-grays '(0.08 . 0.2)
  "How far from the background towards the text the part on screen and
the line point is on are drawn in the minimap, from 0 to 1.")

(defun +ui--minimap-gray (amount)
  "The theme's background moved AMOUNT of the way to its text, or nil."
  (require 'color)
  (let ((bg (color-name-to-rgb (face-background 'default nil t)))
        (fg (color-name-to-rgb (face-foreground 'default nil t))))
    (when (and bg fg)
      (apply #'color-rgb-to-hex
             (append (cl-mapcar (lambda (b f) (+ b (* amount (- f b)))) bg fg) '(2))))))

(defun +ui--minimap-faces-h (&rest _)
  "Draw the minimap's marks in grays of the theme loaded: the theme's
own highlight and cursor were a loud blue over the small text."
  (when-let* ((region (+ui--minimap-gray (car +ui-minimap-grays)))
              (line (+ui--minimap-gray (cdr +ui-minimap-grays))))
    (set-face-attribute '+ui-minimap-region-face nil :background region)
    (set-face-attribute '+ui-minimap-line-face nil :background line)))

(add-hook 'doom-load-theme-hook #'+ui--minimap-faces-h)

(defconst +ui--minimap-name "*Minimap*")

(defvar +ui--minimap-source nil
  "The buffer the minimap shows.")

(defvar +ui--minimap-tick nil
  "The source's modification tick when it was copied.")

(defvar +ui--minimap-timer nil
  "The pending catch-up, so a burst of keys costs one.")

(defvar +ui--minimap-region nil
  "The overlay marking the part on screen.")

(defvar +ui--minimap-line nil
  "The overlay marking the line point is on.")

(defvar +ui-minimap-map
  (let ((map (make-sparse-keymap)))
    (define-key map [mouse-1] #'+ui/minimap-jump)
    (define-key map [down-mouse-1] #'ignore)
    map)
  "Keys in the minimap.")

(defun +ui--minimap-buffer ()
  (let ((buffer (get-buffer +ui--minimap-name)))
    (or buffer
        (with-current-buffer (get-buffer-create +ui--minimap-name)
          (setq-local mode-line-format nil
                      header-line-format nil
                      cursor-type nil
                      cursor-in-non-selected-windows nil
                      truncate-lines t
                      line-spacing nil
                      buffer-read-only t)
          (buffer-face-set '+ui-minimap-face)
          (use-local-map +ui-minimap-map)
          (current-buffer)))))

(defun +ui--minimap-window ()
  (get-buffer-window +ui--minimap-name))

(defun +ui--minimap-source-p (window)
  "Non-nil when WINDOW shows a buffer the minimap should follow."
  (and (window-live-p window)
       (not (window-minibuffer-p window))
       (not (window-parameter window 'window-side))
       (let ((buffer (window-buffer window)))
         (and (not (eq buffer (get-buffer +ui--minimap-name)))
              (with-current-buffer buffer
                (or buffer-file-name (derived-mode-p 'prog-mode 'text-mode 'conf-mode)))))))

(defun +ui--minimap-copy (source)
  "Put SOURCE's text, and its colours, in the minimap."
  (with-current-buffer source
    (when (< (buffer-size) +ui-minimap-colour-max-size)
      (ignore-errors (font-lock-ensure))))
  (with-current-buffer (+ui--minimap-buffer)
    (let ((inhibit-read-only t))
      (erase-buffer)
      (insert-buffer-substring source)
      ;; The colours only: what folds, replaces or answers keys in the
      ;; file would do it here as well.
      (remove-list-of-text-properties
       (point-min) (point-max)
       '(display invisible keymap local-map mouse-face help-echo field
         read-only line-prefix wrap-prefix cursor-intangible composition))))
  (setq +ui--minimap-source source
        +ui--minimap-tick (buffer-chars-modified-tick source)))

(defun +ui--minimap-current-p (window)
  "Non-nil when the minimap holds WINDOW's buffer as it is now."
  (and (+ui--minimap-source-p window)
       (eq (window-buffer window) +ui--minimap-source)
       (eq +ui--minimap-tick (buffer-chars-modified-tick +ui--minimap-source))))

(defun +ui--minimap-mark (window &optional start no-scroll)
  "Mark in the minimap the part of the buffer WINDOW shows and its line.
START is where WINDOW starts when it is being scrolled, and its end is
then worked out; with NO-SCROLL the minimap's own window is left where
it is, and caught up at rest if the part on screen has left it."
  (let ((minimap (+ui--minimap-window))
        ;; While WINDOW is being scrolled its end is still the old one's:
        ;; after a jump, G or gg, the part marked ran from the new start
        ;; back to the old end, most of the file. A window's height of
        ;; lines from the new start instead.
        (end (if start
                 (with-current-buffer (window-buffer window)
                   (save-excursion
                     (goto-char start)
                     (forward-line (window-body-height window))
                     (point)))
               (window-end window)))
        (start (or start (window-start window)))
        (point (window-point window)))
    (with-current-buffer (+ui--minimap-buffer)
      (let ((start (min start (point-max))) (end (min end (point-max))))
        (unless (overlayp +ui--minimap-region)
          (setq +ui--minimap-region (make-overlay 1 1))
          (overlay-put +ui--minimap-region 'face '+ui-minimap-region-face))
        (unless (overlayp +ui--minimap-line)
          (setq +ui--minimap-line (make-overlay 1 1))
          (overlay-put +ui--minimap-line 'face '+ui-minimap-line-face)
          (overlay-put +ui--minimap-line 'priority 10))
        (move-overlay +ui--minimap-region start end)
        (save-excursion
          (goto-char (min point (point-max)))
          (move-overlay +ui--minimap-line (line-beginning-position)
                        (min (point-max) (1+ (line-end-position)))))
        ;; Whether the part on screen is still in the minimap's view, from
        ;; where its window started and ended when last drawn: asking
        ;; `pos-visible-in-window-p' laid out its hundreds of small lines,
        ;; twice, a third of a move's time.
        (when (and minimap
                   (not (and (<= (window-start minimap) start)
                             (< (max start (1- end)) (window-end minimap)))))
          (if no-scroll
              (+ui--minimap-soon)
            (set-window-point minimap (/ (+ start end) 2))
            (with-selected-window minimap (recenter))))))))

(defun +ui--minimap-catch-up ()
  "Follow the selected window: its buffer, its text, what it shows."
  (setq +ui--minimap-timer nil)
  (let ((window (selected-window)))
    (when (and (+ui--minimap-window) (+ui--minimap-source-p window))
      (let ((source (window-buffer window)))
        (if (or (not (eq source +ui--minimap-source))
                (not (eq +ui--minimap-tick (buffer-chars-modified-tick source))))
            ;; A changed text waits for a longer rest than a moved window.
            (if (or (not (eq source +ui--minimap-source))
                    (>= (float-time (or (current-idle-time) 0)) +ui-minimap-copy-idle))
                (progn (+ui--minimap-copy source) (+ui--minimap-mark window))
              (+ui--minimap-later (- +ui-minimap-copy-idle +ui-minimap-idle)))
          (+ui--minimap-mark window))))))

(defun +ui--minimap-later (&optional delay)
  "Catch up once the keys stop, DELAY seconds into the rest."
  (unless (timerp +ui--minimap-timer)
    (setq +ui--minimap-timer
          (if (> (float-time (or (current-idle-time) 0)) 0.05)
              ;; Already resting: an idle timer would wait for the next rest.
              (run-at-time (or delay +ui-minimap-idle) nil #'+ui--minimap-catch-up)
            (run-with-idle-timer (or delay +ui-minimap-idle) nil #'+ui--minimap-catch-up)))))

(defun +ui--minimap-soon ()
  "Catch up as soon as the redisplay under way is over: the part on
screen has left the minimap's view, a jump, and waiting for the keys to
stop left the minimap on the old place, its mark out of sight.  A held
j crosses the view's edge once in a few hundred lines."
  (when (timerp +ui--minimap-timer)
    (cancel-timer +ui--minimap-timer))
  (setq +ui--minimap-timer (run-at-time 0 nil #'+ui--minimap-catch-up)))

(defun +ui--minimap-moved-h (&rest _)
  "A command ran or a window changed: mark the move at once when the
minimap holds the buffer as it is, else catch up once the keys stop.
Marking costs two overlays moved, a fraction of a millisecond; a copy
waits for rest.  Only while the minimap is on show: its window gone with
a workspace or the side windows, every command still set a timer, a
redisplay each.  Its buffer gone, the hooks go too."
  (cond ((+ui--minimap-window)
         (if (+ui--minimap-current-p (selected-window))
             (+ui--minimap-mark (selected-window))
           (+ui--minimap-later)))
        ((not (get-buffer +ui--minimap-name)) (+ui--minimap-hooks nil))))

(defun +ui--minimap-scrolled-h (window start)
  "WINDOW is being scrolled to START: mark the part it is about to show.
A command's own hook sees the window before redisplay scrolls it, so a
held j at the bottom would mark the screen it just left."
  (when (and (eq window (selected-window))
             (+ui--minimap-window)
             (+ui--minimap-current-p window))
    (+ui--minimap-mark window start 'no-scroll)))

(defun +ui--minimap-hooks (on)
  (let ((fn (if on #'add-hook #'remove-hook)))
    (funcall fn 'post-command-hook #'+ui--minimap-moved-h)
    (funcall fn 'window-selection-change-functions #'+ui--minimap-moved-h)
    (funcall fn 'window-buffer-change-functions #'+ui--minimap-moved-h)
    (funcall fn 'window-scroll-functions #'+ui--minimap-scrolled-h)))

;;;###autoload
(defun +ui/minimap ()
  "Show the minimap on the right, or close it."
  (interactive)
  (if-let* ((window (+ui--minimap-window)))
      (progn (+ui--minimap-hooks nil)
             (when (timerp +ui--minimap-timer) (cancel-timer +ui--minimap-timer))
             (setq +ui--minimap-timer nil +ui--minimap-source nil
                   +ui--minimap-region nil +ui--minimap-line nil)
             (delete-window window)
             (kill-buffer +ui--minimap-name))
    (let ((origin (selected-window)))
      (+ui--minimap-faces-h)
      (when (+ui--minimap-source-p origin)
        (+ui--minimap-copy (window-buffer origin)))
      (let ((window (display-buffer
                     (+ui--minimap-buffer)
                     `(display-buffer-in-side-window
                       (side . right) (slot . 1)
                       (window-width . ,+ui-minimap-width)
                       (window-parameters . ((no-other-window . t)
                                             (no-delete-other-windows . t)))))))
        (set-window-dedicated-p window t)
        (set-window-fringes window 0 0))
      (when (+ui--minimap-source-p origin) (+ui--minimap-mark origin))
      (+ui--minimap-hooks t))))

;;;###autoload
(defun +ui/minimap-jump (event)
  "Show in the window beside it the place clicked in the minimap."
  (interactive "e")
  (when-let* ((pos (posn-point (event-start event)))
              (source +ui--minimap-source)
              ((buffer-live-p source))
              (window (get-buffer-window source)))
    (select-window window)
    (goto-char (min pos (point-max)))
    (recenter)
    (+ui--minimap-later)))
