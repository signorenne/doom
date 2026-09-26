;;; private/core/autoload/view.el -*- lexical-binding: t; -*-
;;
;; A view of a buffer, kept beside it.
;;
;; A diagram's picture beside its source, an SVG's drawing beside its
;; XML, an image's structure and metadata beside the picture: one piece
;; of machinery, so it lives here once. A buffer says how its view is
;; drawn with `+core-view-enable'. This keeps a side window showing the
;; view of whichever such buffer you are in, draws it again as the text
;; changes when that makes sense, and steps out of the way when you move
;; to a buffer that has none.

(defvar +core-view-side 'right
  "Which side the view takes.")

(defvar +core-view-width 0.5
  "How much of the frame the view takes.")

(defvar +core-view-idle 0.4
  "Seconds of quiet before a live view is drawn again.")

(defvar +core-view-follow t
  "Whether a live view follows your typing, or waits to be asked.")

(defvar +core-view-on-open t
  "Whether a buffer that has a view opens with it beside it.")

(defvar +core-view-buffer-name "*View*"
  "The buffer views are drawn in.")

(defvar-local +core-view-draw nil
  "How this buffer's view is drawn: a function of no arguments, called in
this buffer, returning what to show:

  (image DATA TYPE)   DATA a unibyte string of image TYPE, svg or png
  (text STRING)       text, carrying its own faces
  (process COMMAND)   run COMMAND, a list, and show what it prints

To say the buffer cannot be drawn right now, signal an error: the view
keeps what it last showed and says why in its header, so a half-typed
line never blanks it.")

(defvar-local +core-view-live nil
  "Non-nil when this buffer's view is drawn again as the buffer changes.")

(defvar +core-view--showing nil
  "The buffer whose view is on show.")

(defvar +core-view--tick nil
  "The modification tick of `+core-view--showing' when it was drawn.")

(defvar +core-view--timer nil
  "The pending redraw, so a burst of keys costs one drawing.")

(defvar +core-view--process nil
  "A (process COMMAND) view still being read.")

(defvar +core-view--buffers 0
  "How many live buffers have a view. The selection hook is on only while
this is above zero: a session that never opens one pays nothing.")

(defun +core-view--buffer ()
  (get-buffer-create +core-view-buffer-name))

(defun +core-view--window ()
  "The window showing the view, or nil."
  (get-buffer-window +core-view-buffer-name t))

(defun +core-view--header (source &optional problem)
  "Say in the view's header what it shows, and what is wrong if anything."
  (with-current-buffer (+core-view--buffer)
    (setq header-line-format
          (if problem
              (propertize (format " %s: %s" (buffer-name source) problem)
                          'face 'error)
            (propertize (format " %s" (buffer-name source))
                        'face 'mode-line-buffer-id)))))

(defun +core-view--put-image (source data _type)
  "Show DATA, an image, fitted to the view's window. Its type is read
from the data by `image-mode', so the one the draw function gave is not
needed here; it is part of what a draw function returns so the caller
says what it made."
  (with-current-buffer (+core-view--buffer)
    (let ((inhibit-read-only t))
      (fundamental-mode)
      (set-buffer-multibyte nil)
      (erase-buffer)
      (insert data)
      ;; image-mode, so what `+images.el' does for a picture, fitting it
      ;; to the window and keeping it there as the window changes, is
      ;; done for the view too.
      (image-mode)))
  (+core-view--header source))

(defun +core-view--put-text (source text)
  "Show TEXT in the view."
  (with-current-buffer (+core-view--buffer)
    (let ((inhibit-read-only t))
      (unless (derived-mode-p 'special-mode) (special-mode))
      (set-buffer-multibyte t)
      (erase-buffer)
      (insert text)
      (goto-char (point-min))
      (setq-local truncate-lines t)))
  (+core-view--header source))

(defun +core-view--put-problem (source problem)
  "Keep what the view shows and say PROBLEM in its header. Only when it
has shown nothing for SOURCE yet does the problem take the whole view."
  (if (eq +core-view--showing source)
      (+core-view--header source problem)
    (+core-view--put-text source (propertize problem 'face 'error))
    (+core-view--header source "cannot be drawn")))

(defun +core-view--run (source command)
  "Show what COMMAND prints, without holding up the editor meanwhile."
  (when (process-live-p +core-view--process)
    (delete-process +core-view--process))
  (+core-view--put-text source (propertize "Reading..." 'face 'shadow))
  (let ((out (generate-new-buffer " *view*")))
    (setq +core-view--process
          (make-process
           :name "view" :buffer out :command command :noquery t
           :connection-type 'pipe :stderr nil
           :sentinel
           (lambda (proc _event)
             (unless (process-live-p proc)
               (let ((text (with-current-buffer out (buffer-string))))
                 (kill-buffer out)
                 (when (and (buffer-live-p source) (eq +core-view--showing source))
                   (if (zerop (process-exit-status proc))
                       (+core-view--put-text source (+core-view--decorate text))
                     (+core-view--put-problem
                      source (car (split-string text "\n" t))))))))))))

(defun +core-view--decorate (text)
  "TEXT with its section titles set apart: a line that begins at the
margin is a title, and what is indented under it belongs to it."
  (with-temp-buffer
    (insert text)
    (goto-char (point-min))
    (while (not (eobp))
      (unless (or (eolp) (memq (char-after) '(?\s ?\t)))
        (put-text-property (line-beginning-position) (line-end-position)
                           'face 'font-lock-keyword-face))
      (forward-line 1))
    (buffer-string)))

(defun +core-view--draw (source &optional force)
  "Draw SOURCE's view, unless it is on show already and unchanged."
  (when (and (buffer-live-p source)
             (buffer-local-value '+core-view-draw source))
    (with-current-buffer source
      (let ((tick (buffer-chars-modified-tick)))
        (unless (and (not force)
                     (eq +core-view--showing source)
                     (eql +core-view--tick tick))
          (let ((was +core-view--showing))
            (setq +core-view--showing source
                  +core-view--tick tick)
            (pcase (condition-case err (funcall +core-view-draw)
                     (error (list 'problem (error-message-string err))))
              (`(image ,data ,type) (+core-view--put-image source data type))
              (`(text ,string) (+core-view--put-text source string))
              (`(process ,command) (+core-view--run source command))
              (`(problem ,message)
               ;; A failed drawing does not count as shown, so the next
               ;; edit tries again rather than keeping the error.
               (setq +core-view--showing was +core-view--tick nil)
               (+core-view--put-problem source message)
               (setq +core-view--showing source)))))))))

(defun +core-view--display ()
  "Put the view in its side window, leaving the cursor where it is."
  (display-buffer (+core-view--buffer)
                  `(display-buffer-in-side-window
                    (side . ,+core-view-side)
                    (window-width . ,+core-view-width)
                    (slot . 0)
                    (window-parameters . ((no-other-window . t)
                                          (no-delete-other-windows . t))))))

(defun +core-view--close ()
  "Close the view's window and stop anything it was doing."
  (when (timerp +core-view--timer) (cancel-timer +core-view--timer))
  (when (process-live-p +core-view--process) (delete-process +core-view--process))
  (setq +core-view--timer nil +core-view--showing nil +core-view--tick nil)
  (when-let* ((window (+core-view--window))) (delete-window window)))

(defun +core-view--eligible-window-p (window)
  "Non-nil for a window moving to should move the view: not the
minibuffer, not a side window or popup, not the view itself."
  (and (window-live-p window)
       (not (window-minibuffer-p window))
       (not (window-parameter window 'window-side))
       (not (window-dedicated-p window))
       (not (eq (window-buffer window) (get-buffer +core-view-buffer-name)))))

(defun +core-view--follow-h (&rest _)
  "Show the view of the buffer you have moved to, or step aside when it
has none."
  (let ((window (selected-window)))
    (when (+core-view--eligible-window-p window)
      (let ((buffer (window-buffer window)))
        (cond
         ((buffer-local-value '+core-view-draw buffer)
          (cond ((+core-view--window) (+core-view--draw buffer))
                (+core-view-on-open (+core-view--display) (+core-view--draw buffer))))
         ((+core-view--window) (+core-view--close)))))))

(defun +core-view--schedule (&rest _)
  "Draw again once the typing stops."
  (when (and +core-view-live +core-view-follow (+core-view--window))
    (when (timerp +core-view--timer) (cancel-timer +core-view--timer))
    (let ((buffer (current-buffer)))
      (setq +core-view--timer
            (run-with-idle-timer +core-view-idle nil #'+core-view--draw buffer)))))

(defun +core-view--disable-h ()
  "This buffer no longer has a view: count it out. Run before a change of
major mode too, which wipes the buffer's local variables; a mode that
wants a view gives it one again from its own hook."
  (when +core-view-draw
    (setq +core-view--buffers (max 0 (1- +core-view--buffers)))
    (when (zerop +core-view--buffers)
      (remove-hook 'window-selection-change-functions #'+core-view--follow-h)
      (remove-hook 'window-buffer-change-functions #'+core-view--follow-h))))

(defun +core-view--forget-h ()
  "This buffer is going: close its view if on show, and count it out."
  (when (and +core-view-draw (eq +core-view--showing (current-buffer)))
    (+core-view--close))
  (+core-view--disable-h))

;;;###autoload
(defun +core-view-enable (draw &optional live)
  "Give this buffer a view drawn by DRAW, beside it. LIVE draws it again
as the buffer changes. See `+core-view-draw' for what DRAW returns."
  (unless +core-view-draw
    (setq +core-view--buffers (1+ +core-view--buffers))
    (add-hook 'change-major-mode-hook #'+core-view--disable-h nil t)
    ;; Both: moving to another window selects it, but switching buffer
    ;; in the same window only changes that window's buffer, and a view
    ;; left beside a buffer that has none takes half the screen for nothing.
    (add-hook 'window-selection-change-functions #'+core-view--follow-h)
    (add-hook 'window-buffer-change-functions #'+core-view--follow-h)
    (add-hook 'kill-buffer-hook #'+core-view--forget-h nil t))
  (setq-local +core-view-draw draw
              +core-view-live live)
  (when live
    (add-hook 'after-change-functions #'+core-view--schedule nil t))
  ;; Opened in a window: show the view once the command that opened it
  ;; is done. Visited in the background, by a search or an export: do
  ;; nothing, and put no window on the screen.
  (when +core-view-on-open
    (let ((buffer (current-buffer)))
      (run-with-idle-timer
       0.05 nil
       (lambda ()
         (when (and (buffer-live-p buffer)
                    (eq buffer (window-buffer (selected-window))))
           (+core-view--display)
           (+core-view--draw buffer t)))))))

;;;###autoload
(defun +core/view-toggle ()
  "Show this buffer's view beside it, or close it."
  (interactive)
  (unless +core-view-draw (user-error "This buffer has no view"))
  (if (+core-view--window)
      (progn (+core-view--close) (message "View closed"))
    (+core-view--display)
    (+core-view--draw (current-buffer) t)))

;;;###autoload
(defun +core/view-refresh ()
  "Draw this buffer's view again now."
  (interactive)
  (unless +core-view-draw (user-error "This buffer has no view"))
  (unless (+core-view--window) (+core-view--display))
  (+core-view--draw (current-buffer) t))

;;;###autoload
(defun +core/view-follow-toggle ()
  "Draw a live view again as you type, or only when asked."
  (interactive)
  (setq +core-view-follow (not +core-view-follow))
  (message "The view %s" (if +core-view-follow "follows your typing"
                           "is drawn when you ask")))

;;;###autoload
(defun +core/view-on-open-toggle ()
  "Open a view with every buffer that has one, or wait to be asked."
  (interactive)
  (setq +core-view-on-open (not +core-view-on-open))
  (message "A view %s" (if +core-view-on-open "opens with its buffer"
                         "opens when asked")))
