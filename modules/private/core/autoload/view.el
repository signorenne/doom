;;; private/core/autoload/view.el -*- lexical-binding: t; -*-
;;
;; A view of a buffer, kept beside it.
;;
;; A diagram's picture beside its source, an SVG's drawing beside its
;; XML, an image's structure and metadata beside the picture: one piece
;; of machinery shared by all of them. A buffer says how its view is
;; drawn with `+core-view-enable'. This keeps a side window showing the
;; view of whichever such buffer you are in, draws it again as the text
;; changes when that makes sense, and steps out of the way when you move
;; to a buffer that has none.

(declare-function +core-image-uncenter "images")
(declare-function evil-define-key* "evil-core")
(declare-function flymake-make-diagnostic "flymake")
(declare-function flymake-diag-region "flymake")

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

  (image DATA TYPE . PROPS)  DATA a unibyte string of image TYPE, svg or png
  (text STRING)              text, carrying its own faces
  (process COMMAND)          run COMMAND, a list, and show what it prints
  (async START)              START, a function of one argument DONE, begins
                             the work and returns a function that cancels
                             it, or nil; DONE is called later with one of
                             the other results
  (problem MESSAGE LINE)     it cannot be drawn: MESSAGE, about source LINE
                             when that is known, else nil

PROPS may hold :scale, the scale DATA is shown at, for a picture rendered
to `+core-view-box' (which is in device pixels), and :natural, the
drawing's own (WIDTH . HEIGHT), which the view's 1 key shows it at.

To say the buffer cannot be drawn right now, return a problem or signal
an error: the view keeps what it last showed and says why in its header,
so a half-typed line never blanks it.")

(defvar +core-view-box nil
  "While a draw function runs, the (WIDTH . HEIGHT) in device pixels its
picture should fit: the view's window at the current zoom. Emacs shows
an image pixel per point, two device pixels on a Retina screen, so a
picture rendered to this and returned with :scale `+core-view-scale' is
as sharp as the screen allows.")

(defvar +core-view-problem-functions nil
  "Run with SOURCE, MESSAGE and LINE when SOURCE's drawing fails, and with
SOURCE, nil and nil when it succeeds. LINE is the source line at fault,
or nil when the drawing did not say.")

(defvar +core-view-zoom nil
  "The view's zoom: nil fits the picture to the window, a number is the
size relative to that fit. It stays as the picture is drawn again, so a
detail zoomed into stays in view while you edit, and goes back to the fit
when the view shows another buffer.")

(defvar-local +core-view-live nil
  "Non-nil when this buffer's view is drawn again as the buffer changes.")

(defvar-local +core-view-side-here nil
  "Which side this buffer's view takes, or nil for `+core-view-side'.
A picture beside its source goes right; an image's insides go left, so
the picture itself sits on the right the same way.")

(defvar-local +core-view-closed nil
  "Non-nil once you closed this buffer's view. It stays closed for this
buffer, `+core-view-on-open' or not, until you open it again.")

(defvar +core-view--showing nil
  "The buffer whose view is on show.")

(defvar +core-view--tick nil
  "The modification tick of `+core-view--showing' when it was drawn.")

(defvar +core-view--timer nil
  "The pending redraw, so a burst of keys costs one drawing.")

(defvar +core-view--cancel nil
  "Cancels the drawing still under way, or nil.")

(defvar +core-view--generation 0
  "Counts the drawings asked for. One that finishes after a newer one was
asked for is dropped: a slow drawing never covers a newer one.")

(defvar +core-view--drawn nil
  "The buffer whose drawing the view holds, not a word of waiting.")

(defvar +core-view--shown nil
  "The picture on show, as a plist: :data, :type, :props, and :box, the
`+core-view-box' it was rendered for. A zoom or a resize shows it again
at once, scaled, while a sharp one is drawn.")

(defvar +core-view--pan '(0.5 . 0.5)
  "The point of the picture in the middle of the window, as fractions of
its width and height. Kept as fractions so a new drawing at another size
shows the same place.")

(defvar +core-view--zoom-timer nil
  "The sharp redraw after a zoom or a resize, so a burst costs one.")

(defvar +core-view--buffers 0
  "How many live buffers have a view. The selection hook is on only while
this is above zero: a session that never opens one pays nothing.")

;;;###autoload
(defun +core/view-close ()
  "Close the view, from wherever you are, the view itself included. The
buffer it showed keeps it closed until you open it again."
  (interactive)
  (when (buffer-live-p +core-view--showing)
    (with-current-buffer +core-view--showing
      (setq +core-view-closed t)))
  (+core-view--close))

(defvar +core-view-panel-mode-map (make-sparse-keymap)
  "Keys in the view itself.")

(define-minor-mode +core-view-panel-mode
  "The view beside a buffer: q closes it rather than burying it, which
would leave some other buffer in the side window."
  :keymap +core-view-panel-mode-map
  ;; Here, not where the buffer is made: each change of its major mode
  ;; wipes its local hooks, and this comes on after every one.
  (when +core-view-panel-mode
    (add-hook 'kill-buffer-hook #'+core-view--killed-h nil t)
    (add-hook 'window-size-change-functions #'+core-view--resized-h nil t))
  ;; evil gathers a buffer's state keys when its major mode starts, and
  ;; this comes on after that; without asking again, q stays the major
  ;; mode's `quit-window'.
  (when (fboundp 'evil-normalize-keymaps)
    (evil-normalize-keymaps)))

(with-eval-after-load 'evil
  (evil-define-key* 'normal +core-view-panel-mode-map "q" #'+core/view-close))
(define-key +core-view-panel-mode-map "q" #'+core/view-close)

(defun +core-view--buffer ()
  "The view's buffer, made when there is none."
  (or (get-buffer +core-view-buffer-name)
      (get-buffer-create +core-view-buffer-name)))

(defun +core-view--killed-h ()
  "The view's buffer is going: forget what it showed, so the next view
is drawn rather than left blank as unchanged."
  (setq +core-view--showing nil +core-view--tick nil
        +core-view--drawn nil +core-view--shown nil))

(defun +core-view--window ()
  "The window showing the view, or nil."
  (get-buffer-window +core-view-buffer-name t))

(defun +core-view--header (source &optional problem)
  "Say in the view's header what it shows, and what is wrong if anything.
The view takes SOURCE's directory too, so SPC SPC, SPC . or a search run
from inside it work in SOURCE's project, not the one the view was first
made in."
  (with-current-buffer (+core-view--buffer)
    (setq default-directory (buffer-local-value 'default-directory source))
    (setq header-line-format
          (if problem
              (propertize (format " %s: %s" (buffer-name source) problem)
                          'face 'error)
            (propertize (format " %s" (buffer-name source))
                        'face 'mode-line-buffer-id)))))

;;;###autoload
(defun +core-view-scale (&optional window)
  "The scale a picture rendered to `+core-view-box' is shown at: one over
the screen's device pixels per point, of WINDOW or the view's window."
  (let ((frame (window-frame (or window (+core-view--window) (selected-window)))))
    (/ 1.0 (if (fboundp 'frame-scale-factor) (frame-scale-factor frame) 1))))

(defun +core-view--fit ()
  "The view window's body, (WIDTH . HEIGHT) in points. Before it has a
window, the share of the frame it will take."
  (if-let* ((window (+core-view--window)))
      (cons (max 1 (window-body-width window t)) (max 1 (window-body-height window t)))
    (cons (max 1 (round (* (frame-pixel-width) +core-view-width)))
          (max 1 (frame-pixel-height)))))

(defun +core-view--box ()
  "The `+core-view-box' for the next drawing."
  (let ((fit (+core-view--fit))
        (factor (/ (or +core-view-zoom 1) (+core-view-scale))))
    (cons (round (* (car fit) factor)) (round (* (cdr fit) factor)))))

(defun +core-view--png-size (data)
  "The (WIDTH . HEIGHT) of DATA off its header when it is a PNG, else nil."
  (when (and (> (length data) 24) (string-prefix-p "\211PNG" data))
    (let ((word (lambda (i) (logior (ash (aref data i) 24) (ash (aref data (1+ i)) 16)
                                    (ash (aref data (+ i 2)) 8) (aref data (+ i 3))))))
      (cons (funcall word 16) (funcall word 20)))))

(defun +core-view--spec ()
  "The image spec for `+core-view--shown' at the current zoom and window.
A picture rendered for another box is scaled to this one meanwhile; one
with no :scale is left to Emacs to size, from its :natural size when
known."
  (let* ((data (plist-get +core-view--shown :data))
         (type (plist-get +core-view--shown :type))
         (props (plist-get +core-view--shown :props))
         (scale (plist-get props :scale))
         (natural (plist-get props :natural))
         (fit (+core-view--fit))
         (zoom (or +core-view-zoom 1)))
    (cond
     (scale
      (let* ((was (plist-get +core-view--shown :box))
             (box (+core-view--box))
             (ratio (if was (min (/ (float (car box)) (car was))
                                 (/ (float (cdr box)) (cdr was)))
                      1)))
        (create-image data type t :scale (* scale ratio))))
     (natural
      (let ((fitted (min (/ (float (car fit)) (max 1 (car natural)))
                         (/ (float (cdr fit)) (max 1 (cdr natural))))))
        (create-image data type t :width (max 1 (round (* (car natural) fitted zoom))))))
     (t (create-image data type t
                      :max-width (round (* (car fit) zoom))
                      :max-height (round (* (cdr fit) zoom)))))))

(defun +core-view--spec-size (spec)
  "The size SPEC is shown at in points, from the PNG header when it can
be, so placing it does not decode it a second time."
  (let ((props (cdr spec)))
    (if-let* ((scale (plist-get props :scale))
              (size (+core-view--png-size (plist-get props :data))))
        (cons (round (* (car size) scale)) (round (* (cdr size) scale)))
      (image-size spec t))))

(defun +core-view--place ()
  "Show `+core-view--shown' in the view: in the middle of the window when
it is smaller, at `+core-view--pan' when it is larger."
  (with-current-buffer (+core-view--buffer)
    (let* ((inhibit-read-only t)
           (spec (+core-view--spec))
           (size (+core-view--spec-size spec))
           (fit (+core-view--fit))
           (window (+core-view--window))
           (left (max 0 (/ (- (car fit) (car size)) 2)))
           (top (max 0 (/ (- (cdr fit) (cdr size)) 2))))
      (+core-image-uncenter)
      (erase-buffer)
      (insert-image spec)
      (goto-char (point-min))
      (with-silent-modifications
        (put-text-property (point-min) (point-max) 'line-prefix `(space :width (,left))))
      (unless (zerop top)
        (let ((shim (make-overlay (point-min) (point-min) nil t)))
          (overlay-put shim '+core-image-shim t)
          (overlay-put shim 'before-string
                       (concat (propertize " " 'display `(space :width 1 :height (,top)))
                               "\n"))))
      (when window
        (let ((x (max 0 (min (- (car size) (car fit))
                             (round (- (* (car +core-view--pan) (car size)) (/ (car fit) 2))))))
              (y (max 0 (min (- (cdr size) (cdr fit))
                             (round (- (* (cdr +core-view--pan) (cdr size)) (/ (cdr fit) 2)))))))
          (set-window-hscroll window (round x (frame-char-width (window-frame window))))
          (set-window-vscroll window y t))))))

(define-minor-mode +core-view-image-mode
  "The view holds a picture: its keys zoom and pan it, the way the image
viewer's do."
  :keymap (make-sparse-keymap)
  (when (fboundp 'evil-normalize-keymaps)
    (evil-normalize-keymaps)))

(defun +core-view--put-image (source data type &optional props)
  "Show DATA, an image of TYPE with PROPS, in the view, at the zoom and
place the last one was, when it is SOURCE's again."
  (setq +core-view--shown (list :data data :type type :props props
                                :box (and (plist-get props :scale) +core-view-box)))
  (with-current-buffer (+core-view--buffer)
    (unless (derived-mode-p 'special-mode) (special-mode))
    (setq-local cursor-type nil
                truncate-lines t
                evil-normal-state-cursor nil
                evil-motion-state-cursor nil)
    (when (bound-and-true-p outline-minor-mode) (outline-minor-mode -1))
    (+core-view-panel-mode 1)
    (+core-view-image-mode 1))
  (+core-view--header source)
  (+core-view--place))

(defun +core-view--put-text (source text)
  "Show TEXT in the view."
  (setq +core-view--shown nil)
  (with-current-buffer (+core-view--buffer)
    (let ((inhibit-read-only t))
      ;; A picture drawn before leaves its centring overlay, the gap
      ;; above it, which neither a mode nor erasing takes away.
      (+core-image-uncenter)
      (unless (derived-mode-p 'special-mode) (special-mode))
      (set-buffer-multibyte t)
      (erase-buffer)
      (insert text)
      (goto-char (point-min))
      (kill-local-variable 'cursor-type)
      (kill-local-variable 'evil-normal-state-cursor)
      (kill-local-variable 'evil-motion-state-cursor)
      (setq-local truncate-lines t)
      ;; A line at the margin is a section's title: fold them like an
      ;; outline, TAB or za on the title, S-TAB for all of them.
      (setq-local outline-regexp "[^ \t\n]"
                  outline-minor-mode-cycle t)
      (outline-minor-mode 1)
      (+core-view-image-mode -1)
      (+core-view-panel-mode 1)))
  (when-let* ((window (+core-view--window)))
    (set-window-hscroll window 0)
    (set-window-vscroll window 0 t))
  (+core-view--header source))

(defun +core-view--put-problem (source problem)
  "Keep what the view shows and say PROBLEM in its header. Only when it
holds no drawing of SOURCE yet does the problem take the whole view."
  (if (eq +core-view--drawn source)
      (+core-view--header source problem)
    (+core-view--put-text source (propertize problem 'face 'error))
    (+core-view--header source "cannot be drawn")))

(defun +core-view--process-start (command)
  "A START for an (async START) result that runs COMMAND and shows what
it prints, or its first line as the problem when it fails."
  (lambda (done)
    (let ((out (generate-new-buffer " *view*")))
      (condition-case err
          (let ((process
                 (make-process
                  :name "view" :buffer out :command command :noquery t
                  :connection-type 'pipe
                  :sentinel
                  (lambda (proc _event)
                    (unless (process-live-p proc)
                      (let ((text (with-current-buffer out (buffer-string))))
                        (kill-buffer out)
                        (funcall done
                                 (if (zerop (process-exit-status proc))
                                     (list 'text (+core-view--decorate text))
                                   (list 'problem (or (car (split-string text "\n" t))
                                                      "it stopped and said nothing")
                                         nil)))))))))
            (lambda () (when (process-live-p process) (delete-process process))))
        ;; A program that cannot start at all (no python3): say so,
        ;; and leave no output buffer behind for each try.
        (error (kill-buffer out)
               (funcall done (list 'problem (error-message-string err) nil))
               nil)))))

;;;###autoload
(defun +core-view-pipe (command input done)
  "Run COMMAND, a list, with INPUT, a unibyte string or nil, on its
standard input, without holding up the editor. DONE gets (t . OUTPUT),
what it printed as a unibyte string, or (nil . MESSAGE) when it failed:
the first line it said on standard error, else on standard output, or
nil when it said nothing.
Returns a function that stops it, for an (async START) result.

INPUT goes through a file of its own rather than the pipe: Emacs feeds a
pipe a few kilobytes at a time and waits in between, 0.7 s of a frozen
editor for a 1.7 MB drawing, where writing the file takes milliseconds."
  (let ((out (generate-new-buffer " *view-pipe*"))
        (err (generate-new-buffer " *view-pipe-err*"))
        (file (when input
                (let ((coding-system-for-write 'no-conversion))
                  (make-temp-file "view-input-" nil nil input)))))
    (with-current-buffer out (set-buffer-multibyte nil))
    (condition-case problem
        (let* ((stderr (make-pipe-process :name "view-pipe-err" :buffer err
                                          :noquery t :sentinel #'ignore))
               (process
                (make-process
                 :name "view-pipe" :buffer out :noquery t
                 :command (if file
                              (append (list "sh" "-c" "f=$1; shift; exec \"$@\" < \"$f\""
                                            "sh" file)
                                      command)
                            command)
                 :connection-type 'pipe :coding 'binary :stderr stderr
                 :sentinel
                 (lambda (proc _event)
                   (unless (process-live-p proc)
                     (when file (ignore-errors (delete-file file)))
                     ;; What it said last on standard error can still be
                     ;; on its way when it has exited.
                     (when (process-live-p stderr) (accept-process-output stderr 0))
                     (let ((output (with-current-buffer out (buffer-string)))
                           (said (if (buffer-live-p err)
                                     (with-current-buffer err (string-trim (buffer-string)))
                                   "")))
                       (kill-buffer out)
                       (when (buffer-live-p err) (kill-buffer err))
                       (when (process-live-p stderr) (delete-process stderr))
                       (funcall done
                                (if (and (eq (process-status proc) 'exit)
                                         (zerop (process-exit-status proc)))
                                    (cons t output)
                                  (cons nil (car (split-string
                                                  (if (string-empty-p said)
                                                      (decode-coding-string output 'utf-8)
                                                    said)
                                                  "\n" t)))))))))))
          (unless file (process-send-eof process))
          (lambda () (when (process-live-p process) (delete-process process))))
      (error (kill-buffer out) (kill-buffer err)
             (when file (ignore-errors (delete-file file)))
             (funcall done (cons nil (error-message-string problem)))
             nil))))

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

(defun +core-view--cancel-pending ()
  "Stop the drawing still under way, if any."
  (when +core-view--cancel
    (let ((cancel +core-view--cancel))
      (setq +core-view--cancel nil)
      (ignore-errors (funcall cancel)))))

(defun +core-view--show (source result generation)
  "Show RESULT, what SOURCE's draw function returned for drawing number
GENERATION, unless a newer drawing was asked for since."
  (when (and (eql generation +core-view--generation)
             (buffer-live-p source)
             (eq +core-view--showing source))
    (pcase result
      (`(async ,start)
       (unless (eq +core-view--drawn source)
         (+core-view--put-text source (propertize "Drawing..." 'face 'shadow)))
       (let ((cancel (funcall start (lambda (result)
                                      (when (eql generation +core-view--generation)
                                        (setq +core-view--cancel nil))
                                      (+core-view--show source result generation)))))
         (when (eql generation +core-view--generation)
           (setq +core-view--cancel cancel))))
      (`(process ,command)
       (+core-view--put-text source (propertize "Reading..." 'face 'shadow))
       (setq +core-view--drawn nil)
       (+core-view--show source (list 'async (+core-view--process-start command))
                         generation))
      (`(image ,data ,type . ,props)
       (+core-view--put-image source data type props)
       (setq +core-view--drawn source)
       (run-hook-with-args '+core-view-problem-functions source nil nil))
      (`(text ,string)
       (+core-view--put-text source string)
       (setq +core-view--drawn source)
       (run-hook-with-args '+core-view-problem-functions source nil nil))
      (`(problem ,message . ,rest)
       ;; A failed drawing does not count as shown, so the next look at
       ;; the buffer tries again rather than keeping the error.
       (setq +core-view--tick nil)
       (+core-view--put-problem source message)
       (run-hook-with-args '+core-view-problem-functions source message (car rest))))))

(defun +core-view--draw (source &optional force)
  "Draw SOURCE's view, unless it is on show already and unchanged."
  (when (and (buffer-live-p source)
             (buffer-local-value '+core-view-draw source))
    (with-current-buffer source
      (let ((tick (buffer-chars-modified-tick)))
        (unless (and (not force)
                     (eq +core-view--showing source)
                     (eql +core-view--tick tick))
          (unless (eq +core-view--showing source)
            (setq +core-view-zoom nil +core-view--pan '(0.5 . 0.5)))
          (+core-view--cancel-pending)
          (setq +core-view--showing source
                +core-view--tick tick
                +core-view--generation (1+ +core-view--generation))
          (let ((generation +core-view--generation)
                (+core-view-box (+core-view--box)))
            (+core-view--show source
                              (condition-case err (funcall +core-view-draw)
                                (error (list 'problem (error-message-string err) nil)))
                              generation)))))))

(defun +core-view--redraw-soon (&optional delay)
  "Draw the view again, sharp, once zooming or resizing has paused for
DELAY seconds. Only a picture rendered for its box needs it; one Emacs
sizes itself is exact already."
  (when (timerp +core-view--zoom-timer) (cancel-timer +core-view--zoom-timer))
  (when (plist-get (plist-get +core-view--shown :props) :scale)
    (setq +core-view--zoom-timer
          (run-with-idle-timer (or delay 0.3) nil
                               (lambda ()
                                 (setq +core-view--zoom-timer nil)
                                 (when (buffer-live-p +core-view--showing)
                                   (+core-view--draw +core-view--showing t)))))))

(defun +core-view--resized-h (_window)
  "Fit the picture to the view's new size at once, and sharp after."
  (when +core-view--shown
    (+core-view--place)
    (+core-view--redraw-soon)))

(defun +core-view--display (source)
  "Put the view in its side window, on SOURCE's side, leaving the cursor
where it is. A view you can move into: to scroll and search an image's
report, or to zoom a diagram with the picture's own keys. The window is
the view's alone: a file opened from inside it goes to the window it
stands beside. It was not, and SPC SPC there put the next picture in the
side window, its report in a new one on the other side, and the source
in a sliver between them."
  (let ((side (or (buffer-local-value '+core-view-side-here source) +core-view-side))
        (window (+core-view--window)))
    (when (and window (not (eq (window-parameter window 'window-side) side)))
      (delete-window window))
    (display-buffer (+core-view--buffer)
                    `(display-buffer-in-side-window
                      (side . ,side)
                      (window-width . ,+core-view-width)
                      (slot . 0)
                      (dedicated . t)
                      (window-parameters . ((no-delete-other-windows . t)
                                            (+core-view . t)))))
    ;; A picture beside the view just lost half its window. Fitted again
    ;; now rather than when image-mode notices, it is never drawn
    ;; spilling out of its window.
    (when-let* ((window (get-buffer-window source)))
      (with-current-buffer source
        (when (derived-mode-p 'image-mode)
          (ignore-errors (image-fit-to-window window)))))))

;; The view's window is its own, so a buffer shown from inside it would
;; split the other window in two. A command run from inside the view
;; that shows another buffer (find-file, a buffer switch) runs as if
;; from the window beside it, which it then leaves selected. Only a
;; command: a timer showing something while you read the view leaves
;; you where you are.
(defun +core-view--step-out-a (buffer-or-name &rest _)
  "Select the window beside the view before BUFFER-OR-NAME is shown, when
a command run from inside the view shows it."
  (let ((window (selected-window)))
    (when-let* ((this-command)
                ((window-parameter window '+core-view))
                ((not (and buffer-or-name
                           (eq (get-buffer buffer-or-name) (window-buffer window)))))
                (beside (get-mru-window nil nil t)))
      (select-window beside))))

(advice-add 'display-buffer :before #'+core-view--step-out-a)
(advice-add 'switch-to-buffer :before #'+core-view--step-out-a)

(defun +core-view--close ()
  "Close the view's window and stop anything it was doing."
  (when (timerp +core-view--timer) (cancel-timer +core-view--timer))
  (when (timerp +core-view--zoom-timer) (cancel-timer +core-view--zoom-timer))
  (+core-view--cancel-pending)
  (setq +core-view--timer nil +core-view--zoom-timer nil +core-view--showing nil
        +core-view--tick nil +core-view--drawn nil +core-view--shown nil)
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
         ((and (buffer-local-value '+core-view-draw buffer)
               (not (buffer-local-value '+core-view-closed buffer)))
          (when (or (+core-view--window) +core-view-on-open)
            (+core-view--display buffer)
            (+core-view--draw buffer)))
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
    ;; On show and left without a view once the new mode is set up (a
    ;; picture turned into text): the view closes rather than stays.
    (when (eq +core-view--showing (current-buffer))
      (let ((buffer (current-buffer)))
        (run-at-time 0 nil (lambda ()
                             (when (and (eq +core-view--showing buffer)
                                        (not (and (buffer-live-p buffer)
                                                  (buffer-local-value '+core-view-draw buffer))))
                               (+core-view--close))))))
    (when (zerop +core-view--buffers)
      (remove-hook 'window-selection-change-functions #'+core-view--follow-h)
      (remove-hook 'window-buffer-change-functions #'+core-view--follow-h))))

(defun +core-view--forget-h ()
  "This buffer is going: close its view if on show, and count it out."
  (when (and +core-view-draw (eq +core-view--showing (current-buffer)))
    (+core-view--close))
  (+core-view--disable-h))

;;
;;; What failed, on its line

(defvar-local +core-view--problem nil
  "Why this buffer's last drawing failed, (MESSAGE . LINE), or nil.")

(defvar-local +core-view--report nil
  "flymake's report function for this buffer's last check.")

(defun +core-view--flymake-send ()
  "Tell flymake what the last drawing said: an error on its line, or
nothing. A problem with no line stays in the view's header only."
  (when +core-view--report
    (funcall +core-view--report
             (when-let* ((problem +core-view--problem)
                         (line (cdr problem))
                         (region (flymake-diag-region (current-buffer) line)))
               (list (flymake-make-diagnostic (current-buffer) (car region) (cdr region)
                                              :error (car problem))))
             ;; The whole buffer each time: flymake clears a backend's
             ;; old errors only at its first report, and adds the later
             ;; ones to them unless told which part they replace.
             :region (cons (point-min) (point-max)))))

(defun +core-view--flymake (report-fn &rest _)
  "A flymake backend for what the drawing says is wrong. The drawing
comes after flymake asks, so this answers with what is known and answers
again, through the same REPORT-FN, when the drawing is done."
  (setq +core-view--report report-fn)
  (+core-view--flymake-send))

(defun +core-view--problem-h (source message line)
  "Keep SOURCE's flymake in step with its drawing's MESSAGE and LINE."
  (when (buffer-live-p source)
    (with-current-buffer source
      (when (memq #'+core-view--flymake flymake-diagnostic-functions)
        (setq +core-view--problem (and message (cons message line)))
        (+core-view--flymake-send)))))

;;;###autoload
(defun +core-view-enable (draw &optional live side)
  "Give this buffer a view drawn by DRAW, beside it. LIVE draws it again
as the buffer changes; SIDE is `left' or `right', `+core-view-side' when
nil. See `+core-view-draw' for what DRAW returns."
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
              +core-view-live live
              +core-view-side-here side)
  (when live
    (add-hook 'after-change-functions #'+core-view--schedule nil t)
    ;; Where the drawing breaks is marked on its line, counted in the
    ;; header with the buffer's other problems, and reached with the
    ;; keys that go to the next problem.
    (add-hook '+core-view-problem-functions #'+core-view--problem-h)
    (add-hook 'flymake-diagnostic-functions #'+core-view--flymake nil t)
    (flymake-mode 1))
  ;; Opened in a window: the view comes up as the command that opened it
  ;; ends, before anything is drawn, with a word in it until its drawing
  ;; is ready. Shown later, it would take half the window from a picture
  ;; already drawn across all of it, which would jump as it is fitted
  ;; again. Opened from outside a command, by emacsclient, the timer
  ;; shows it. Visited in the background, by a search or an export: no
  ;; view and no window.
  (when +core-view-on-open
    (let ((buffer (current-buffer)))
      (letrec ((open (lambda ()
                       (remove-hook 'post-command-hook open)
                       (when (and (buffer-live-p buffer)
                                  (eq buffer (window-buffer (selected-window))))
                         (unless (+core-view--window)
                           (+core-view--put-text buffer (propertize "Drawing..." 'face 'shadow)))
                         (+core-view--display buffer)))))
        (add-hook 'post-command-hook open))
      (run-with-idle-timer
       0.05 nil
       (lambda ()
         (when (and (buffer-live-p buffer)
                    (eq buffer (window-buffer (selected-window))))
           (+core-view--display buffer)
           (+core-view--draw buffer)))))))

;;;###autoload
(defun +core/view-toggle ()
  "Show this buffer's view beside it, or close it. In the view itself,
close it."
  (interactive)
  (unless (or +core-view-draw (eq (current-buffer) (get-buffer +core-view-buffer-name)))
    (user-error "This buffer has no view"))
  (if (+core-view--window)
      (progn (+core/view-close) (message "View closed"))
    (setq +core-view-closed nil)
    (+core-view--display (current-buffer))
    (+core-view--draw (current-buffer) t)))

;;;###autoload
(defun +core/view-refresh ()
  "Draw this buffer's view again now."
  (interactive)
  (unless +core-view-draw (user-error "This buffer has no view"))
  (setq +core-view-closed nil)
  (unless (+core-view--window) (+core-view--display (current-buffer)))
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


;;
;;; Zooming and moving the picture

(defun +core-view--zoom-by (factor)
  "Zoom the view's picture by FACTOR: at once, scaled, then sharp."
  (unless +core-view--shown (user-error "The view holds no picture"))
  (setq +core-view-zoom (max 0.1 (min 32 (* (or +core-view-zoom 1) factor))))
  (+core-view--place)
  (+core-view--redraw-soon 0.15))

;;;###autoload
(defun +core/view-zoom-in ()
  "Zoom into the view's picture."
  (interactive)
  (+core-view--zoom-by 1.25))

;;;###autoload
(defun +core/view-zoom-out ()
  "Zoom out of the view's picture."
  (interactive)
  (+core-view--zoom-by 0.8))

;;;###autoload
(defun +core/view-fit ()
  "The whole picture in the view's window."
  (interactive)
  (setq +core-view-zoom nil +core-view--pan '(0.5 . 0.5))
  (when +core-view--shown
    (+core-view--place)
    (+core-view--redraw-soon 0.15)))

;;;###autoload
(defun +core/view-original ()
  "The picture at its own size, a point to each of its pixels."
  (interactive)
  (let ((natural (plist-get (plist-get +core-view--shown :props) :natural))
        (fit (+core-view--fit)))
    (unless natural (user-error "This picture does not say its own size"))
    (setq +core-view-zoom (/ 1.0 (min (/ (float (car fit)) (max 1 (car natural)))
                                      (/ (float (cdr fit)) (max 1 (cdr natural))))))
    (+core-view--place)
    (+core-view--redraw-soon 0.15)))

(defun +core-view--pan-by (dx dy)
  "Move the middle of the view by DX and DY eighths of its window."
  (when-let* ((+core-view--shown)
              (size (+core-view--spec-size (+core-view--spec)))
              (fit (+core-view--fit)))
    (setq +core-view--pan
          (cons (max 0.0 (min 1.0 (+ (car +core-view--pan)
                                     (/ (* dx (car fit)) 8.0 (max 1 (car size))))))
                (max 0.0 (min 1.0 (+ (cdr +core-view--pan)
                                     (/ (* dy (cdr fit)) 8.0 (max 1 (cdr size))))))))
    (+core-view--place)))

;;;###autoload
(defun +core/view-pan-left (&optional n)
  "Look further left in the view's picture."
  (interactive "p")
  (+core-view--pan-by (- (or n 1)) 0))

;;;###autoload
(defun +core/view-pan-right (&optional n)
  "Look further right in the view's picture."
  (interactive "p")
  (+core-view--pan-by (or n 1) 0))

;;;###autoload
(defun +core/view-pan-up (&optional n)
  "Look further up in the view's picture."
  (interactive "p")
  (+core-view--pan-by 0 (- (or n 1))))

;;;###autoload
(defun +core/view-pan-down (&optional n)
  "Look further down in the view's picture."
  (interactive "p")
  (+core-view--pan-by 0 (or n 1)))

(let ((keys '(("+" . +core/view-zoom-in) ("=" . +core/view-zoom-in)
              ("-" . +core/view-zoom-out) ("f" . +core/view-fit)
              ("1" . +core/view-original)
              ("h" . +core/view-pan-left) ("l" . +core/view-pan-right)
              ("k" . +core/view-pan-up) ("j" . +core/view-pan-down))))
  (dolist (key keys)
    (define-key +core-view-image-mode-map (car key) (cdr key)))
  (with-eval-after-load 'evil
    (dolist (key keys)
      (evil-define-key* 'normal +core-view-image-mode-map (car key) (cdr key)))))
