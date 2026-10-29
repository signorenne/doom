;;; private/butler/autoload/butler.el -*- lexical-binding: t; -*-
;;
;; What the butler knows and how he appears. His hints come from the cheat
;; sheet, so they are always the keys this config actually has; his own
;; words are in `+butler-quips'. In the GUI he floats in a child frame,
;; in a terminal he takes a popup at the bottom. The commands and his
;; menu are in menu.el, so drawing him on the dashboard loads no
;; transient.

(defvar +butler-name)
(defvar +butler-art)
(defvar +butler-head-rows)
(defvar +butler-faces)
(defvar +butler-bodies)
(defvar +butler-bubble-width)
(defvar +butler-bubble-min-width)
(defvar +butler-bubble-max-lines)
(defvar +butler-margin)
(defvar +butler-positions)
(defvar +butler-nudge-step)
(defvar +butler-quips)
(defvar +butler-dashboard-say-ticks)
(defvar +dashboard-name)
(defvar +butler-greetings)
(defvar +butler-address)
(defvar +butler--said)
(defvar +butler--section)
(defvar +butler--position)
(declare-function +docs-cheatsheet-tips "cheatsheet")
(declare-function +docs-cheatsheet-section-for "cheatsheet")
(declare-function posframe-show "posframe")
(declare-function posframe-hide "posframe")
(declare-function posframe-workable-p "posframe")
(declare-function posframe-poshandler-point-bottom-left-corner "posframe")
(declare-function savehist-save "savehist")
(defvar posframe-mouse-banish-function)
(defvar transient--window)

;; The two things read from other packages' insides, each behind one
;; accessor: the window transient shows its menu in, and the child frame
;; posframe made for a buffer, found by the frame parameter posframe sets
;; on purpose.

(defun +butler--transient-window ()
  "The window his menu is shown in, while it is up on this frame."
  (and (bound-and-true-p transient--window)
       (window-live-p transient--window)
       (eq (window-frame transient--window) (selected-frame))
       transient--window))

(defun +butler--posframe-of (buffer)
  "The child frame posframe shows BUFFER in, or nil."
  (seq-find (lambda (frame)
              (let ((info (frame-parameter frame 'posframe-buffer)))
                (and (consp info) (eq (cdr info) buffer))))
            (frame-list)))

;;
;;; What he knows

;; Autoloaded: called from menu.el.
;;;###autoload
(defun +butler--hint (&optional section)
  "A tip from SECTION of the cheat sheet when there is one, else any tip,
as (TIP . SECTION).  The tips are the docs module's: every key row of
the cheat sheet."
  (unless (fboundp '+docs-cheatsheet-tips)
    (user-error "No cheat sheet to read: the docs module is off"))
  (let* ((tips (+docs-cheatsheet-tips))
         (mine (and section
                    (seq-filter (lambda (tip) (equal (car tip) section))
                                tips))))
    (unless tips (user-error "The cheat sheet is empty; nothing to say"))
    (let ((tip (seq-random-elt (or mine tips))))
      (cons (cdr tip) (car tip)))))


;;
;;; The greeting of the hour

(defun +butler--time-of-day (&optional hour)
  "The part of the day HOUR falls in; now, when HOUR is nil."
  (let ((h (or hour (decoded-time-hour (decode-time)))))
    (cond ((< h 5) 'night)
          ((< h 12) 'morning)
          ((< h 18) 'afternoon)
          ((< h 23) 'evening)
          (t 'night))))

;; Autoloaded: called from menu.el.
;;;###autoload
(defun +butler-greeting (&optional hour)
  "The greeting for HOUR, or for now, as one line."
  (format (string-join (seq-random-elt (alist-get (+butler--time-of-day hour)
                                                  +butler-greetings))
                       " ")
          +butler-address))

;; Autoloaded: called from menu.el and from the dashboard.
;;;###autoload
(defun +butler-quip ()
  "A word of his own, calling you what you asked to be called."
  (when +butler-quips
    (format (seq-random-elt +butler-quips) +butler-address)))

;;
;;; How he appears

(defun +butler--wrap (text)
  "TEXT as lines no wider than `+butler-bubble-width', the breaks it
already has kept: an answer of two keys is two lines.  A word wider
than that, a link or a path, is cut where the bubble ends: filling
cannot break it, and it pushed the bubble's right side out."
  (mapcan (lambda (paragraph)
            (with-temp-buffer
              (insert paragraph)
              (let ((fill-column +butler-bubble-width))
                (fill-region (point-min) (point-max)))
              (mapcan #'+butler--cut (split-string (buffer-string) "\n"))))
          (split-string text "\n")))

(defun +butler--cut (line)
  "LINE in pieces no longer than `+butler-bubble-width'."
  (let (pieces)
    (while (> (length line) +butler-bubble-width)
      (push (substring line 0 +butler-bubble-width) pieces)
      (setq line (substring line +butler-bubble-width)))
    (nreverse (cons line pieces))))

(defun +butler--short-footer (footer width)
  "FOOTER in WIDTH columns: a long chain of sections cut back to the
first of them, the one that says where you are, rather than the whole
of it cut off mid word."
  (if (<= (length footer) width)
      footer
    (let ((head (car (split-string footer ", "))))
      (truncate-string-to-width (if (<= (length head) width) head footer) width))))

(defconst +butler--gap 1
  "Blank columns between him and his bubble.  One: he stands beside what
he says, not across the room from it.")

(defun +butler--floor (parent height)
  "The lowest a child frame of HEIGHT may stand in PARENT: clear of the
mode line and of the echo area.  The mode line is measured on the
frame's selected window, since the root window is an internal one, and
no live window at all, as soon as the frame is split in two."
  (let ((window (frame-selected-window parent)))
    (max 0 (- (frame-pixel-height parent) height
              (if (window-live-p window) (window-mode-line-height window) 0)
              (window-pixel-height (minibuffer-window parent))))))

(defun +butler--corner (child parent)
  "Where CHILD stands in PARENT for a named spot, by what CHILD actually
measures, or nil for a spot that is not a corner."
  (let* ((w (frame-pixel-width child))
         (h (frame-pixel-height child))
         (right (max 0 (- (frame-pixel-width parent) w)))
         (bottom (+butler--floor parent h)))
    (pcase +butler--position
      ('bottom-right (cons right bottom))
      ('bottom-left (cons 0 bottom))
      ('top-right (cons right 0))
      ('top-left (cons 0 0))
      ('centre (cons (/ right 2) (/ bottom 2)))
      (_ nil))))

(defconst +butler--snap-share 0.25
  "How near a corner he must be let go of to take it: this share of the
frame from each edge.")

(defvar +butler--last-place nil
  "(X Y WIDTH HEIGHT) of his frame as it was last placed, so a spot of
his own can keep the edge he stands nearest to when what he says
changes size.")

;; Autoloaded: menu.el snaps him after a drag.
;;;###autoload
(defun +butler--nearest-corner ()
  "The corner he is standing in, when he is near enough to one to mean
it: within `+butler--snap-share' of the frame from both its edges."
  (when-let* ((child (+butler--frame))
              ((frame-live-p child))
              (parent (frame-parent child)))
    (pcase-let* ((`(,x . ,y) (frame-position child))
                 (w (frame-pixel-width child))
                 (h (frame-pixel-height child))
                 (fw (frame-pixel-width parent))
                 (fh (frame-pixel-height parent))
                 (near-x (* +butler--snap-share fw))
                 (near-y (* +butler--snap-share fh)))
      (let ((left (< x near-x))
            (right (< (- fw x w) near-x))
            (top (< y near-y))
            (bottom (< (- fh y h) near-y)))
        (cond ((and top left) 'top-left)
              ((and top right) 'top-right)
              ((and bottom left) 'bottom-left)
              ((and bottom right) 'bottom-right))))))

(defun +butler--keep-edge (child parent)
  "Where CHILD goes in PARENT for a spot of his own: the edge he stands
nearest to stays where it is.  A narrower answer would otherwise leave
him the width of the difference short of the edge he was put against."
  (pcase-let* ((`(,x . ,y) (if (consp +butler--position) +butler--position
                             (frame-position child)))
               (`(,ox ,oy ,ow ,oh) (or +butler--last-place (list x y 0 0)))
               (w (frame-pixel-width child))
               (h (frame-pixel-height child))
               (fw (frame-pixel-width parent))
               (fh (frame-pixel-height parent)))
    (cons (max 0 (min (- fw w)
                      (if (< (- fw ox ow) ox) (+ x (- ow w)) x)))
          (max 0 (min (- fh h)
                      (if (< (- fh oy oh) oy) (+ y (- oh h)) y))))))

(defun +butler--snap ()
  "Put him back in his corner by what his frame actually measures.
The size posframe is given is worked out in characters, and a fractional
scale or a rounded font width can leave the frame a few pixels wider or
narrower than that; placed by the reckoning rather than the measure, he
ends up short of the edge he was asked to stand against.  At a spot of
his own he keeps the edge he stands nearest to instead."
  (when-let* ((child (+butler--frame))
              ((frame-live-p child))
              ((frame-visible-p child))
              (parent (frame-parent child))
              (spot (if (symbolp +butler--position)
                        (+butler--corner child parent)
                      (+butler--keep-edge child parent))))
    (unless (equal spot (frame-position child))
      (set-frame-position child (car spot) (cdr spot)))
    (when (consp +butler--position)
      (setq +butler--position spot))
    (setq +butler--last-place (list (car spot) (cdr spot)
                                    (frame-pixel-width child)
                                    (frame-pixel-height child)))))

(defun +butler--fit-lines (lines)
  "LINES cut down to what the bubble may hold: `+butler-bubble-max-lines'
at the most, and never taller than the frame he stands in.  The last
line then says there is more, which R reads in full and c copies whole."
  (let ((room (max 5 (min +butler-bubble-max-lines (- (frame-height) 8)))))
    (if (<= (length lines) room)
        lines
      (append (seq-take lines (1- room))
              (list "... (R reads it all)")))))

(defun +butler--bubble (text &optional footer)
  "The bubble holding TEXT, one string per row: as wide as what it holds,
`+butler-bubble-width' at the widest and `+butler-bubble-min-width' at
the narrowest, and no taller either, so a brief word leaves no empty
room inside it; FOOTER, where it came from, on its own row at the end,
right aligned and in the shadow."
  (let* ((lines (+butler--fit-lines (+butler--wrap text)))
         (footer (and footer (+butler--short-footer footer +butler-bubble-width)))
         ;; As wide as what it holds and no wider: a short word of his
         ;; own takes a short bubble, and the columns beside him are the
         ;; buffer's again.
         (inner (min +butler-bubble-width
                     (max +butler-bubble-min-width
                          (length (or footer ""))
                          (apply #'max 0 (mapcar #'length lines)))))
         (rule (concat "+" (make-string (+ inner 2) ?-) "+"))
         (body (append lines
                       (when footer
                         (list (concat (make-string (max 0 (- inner (length footer))) ?\s)
                                       (propertize (truncate-string-to-width footer inner)
                                                   'face 'shadow '+butler-footer t)))))))
    (append (list rule)
            (mapcar (lambda (l) (format "| %s |" (string-pad l inner))) body)
            (list rule))))

(defun +butler--speech-lines (text &optional footer)
  "The art beside a bubble holding TEXT and FOOTER, one string per row.
A bubble shorter than he is stands against his middle, as a word beside
his head rather than a board nailed to him."
  (let* ((bubble (+butler--bubble text footer))
         (art-width (length (car +butler-art)))
         (rows (max (length +butler-art) (length bubble)))
         (from (max 0 (floor (- (length +butler-art) (length bubble)) 2)))
         (blank (make-string art-width ?\s)))
    (cl-loop for i below rows
             for said = (and (>= i from) (nth (- i from) bubble))
             collect (string-trim-right
                      (concat (or (nth i +butler-art) blank)
                              (make-string +butler--gap ?\s)
                              (or said ""))))))

(defun +butler--insert-speech (text &optional width face margin footer)
  "Insert him saying TEXT, the words in FACE, centred in WIDTH columns,
FOOTER in the corner of the bubble.  MARGIN is (COLUMNS . LINES) of
blank space kept round the block, the same on every side.  Every row
of the art is marked with its number, so `+butler--redraw' can change
his face.  Returns (COLUMNS . LINES), the size of what was inserted."
  (let* ((lines (+butler--speech-lines text footer))
         (widest (apply #'max (mapcar #'length lines)))
         (cols (or (car margin) 0))
         (block (+ widest cols cols))
         (indent (if width (max 0 (floor (- width block) 2)) 0))
         (art-width (length (car +butler-art)))
         (start (point))
         (row 0))
    (insert (make-string (or (cdr margin) 0) ?\n))
    (dolist (line lines)
      (let ((start (+ (point) indent cols)))
        (insert (make-string (+ indent cols) ?\s)
                line
                (make-string (+ cols (- widest (length line))) ?\s)
                "\n")
        (when face
          (let ((from (+ start art-width +butler--gap)) (to (+ start (length line))))
            ;; The footer keeps its shadow.
            (while (< from to)
              (let ((next (or (next-single-property-change from '+butler-footer nil to) to)))
                (unless (get-text-property from '+butler-footer)
                  (put-text-property from next 'face face))
                (setq from next)))))
        (when (< row (length +butler-art))
          (put-text-property start (+ start art-width) '+butler-art row)))
      (cl-incf row))
    (insert (make-string (or (cdr margin) 0) ?\n))
    ;; The whole block is marked, so what he says on the dashboard can be
    ;; found again and swapped for something else.
    (put-text-property start (point) '+butler-speech t)
    ;; The art above is neutral; the buffer may remember a head turned or
    ;; a face held (a dashboard reload keeps its locals), so draw him as
    ;; he is rather than let the next step snap him there.
    (+butler--redraw)
    (cons (+ indent block) (+ (length lines) (* 2 (or (cdr margin) 0))))))

;;
;;; The figure, as it is right now

(defvar-local +butler--head 'middle
  "Which way the head is turned: `left', `middle' or `right'.")

(defvar-local +butler--face 'neutral
  "The face he is making, a name from `+butler-faces'.")

(defvar-local +butler--body 'neutral
  "What the body is doing, a name from `+butler-bodies'.")

(defun +butler--shifted (line by)
  "LINE moved BY columns, the width kept."
  (cond ((> by 0) (substring (concat (make-string by ?\s) line)
                             0 (length line)))
        ((< by 0) (concat (substring line (- by)) (make-string (- by) ?\s)))
        (t line)))

(defun +butler--rows ()
  "Every row of him as he is now: face and body swapped in, head turned."
  (let ((face (alist-get +butler--face +butler-faces))
        (body (alist-get +butler--body +butler-bodies))
        (shift (pcase +butler--head ('left -1) ('right 1) (_ 0))))
    (cl-loop for line in +butler-art
             for row from 0
             collect (if (< row +butler-head-rows)
                         (+butler--shifted (or (alist-get row face) line) shift)
                       (or (alist-get row body) line)))))

(defun +butler--redraw ()
  "Draw him as he is now, wherever his art is in the current buffer."
  (let ((rows (+butler--rows)))
    (save-excursion
      (goto-char (point-min))
      ;; Not an edit: no undo entry, no modified flag, no hooks.
      (with-silent-modifications
        (let (match)
          (while (setq match (text-property-search-forward '+butler-art))
            (let* ((start (prop-match-beginning match))
                   (end (prop-match-end match))
                   (line (nth (prop-match-value match) rows))
                   (props (text-properties-at start)))
              (goto-char start)
              (insert (apply #'propertize line props))
              (delete-region (point) (+ (point) (- end start))))))))))

;;
;;; Gestures

(defvar-local +butler--queue nil
  "The rest of the gesture he is making, as (TRACK VALUE . TICKS).")

(defvar-local +butler--hold 0
  "Ticks left before the next step of the gesture.")

(defvar-local +butler--wait 0
  "Ticks left before he does something again.")

(defvar-local +butler--last nil
  "The gesture he made last, so he does not make it twice running.")

(defun +butler--pick-gesture ()
  "One of `+butler-gestures', the common ones more often, never the same
one twice in a row."
  (let* ((choices (or (seq-remove (lambda (g) (eq (car g) +butler--last))
                                  +butler-gestures)
                      +butler-gestures))
         (total (apply #'+ (mapcar #'cadr choices)))
         (n (random total)))
    (cl-loop for gesture in choices
             do (cl-decf n (cadr gesture))
             when (< n 0)
             return (progn (setq +butler--last (car gesture))
                           (cddr gesture)))))

(defun +butler--stretch (ticks)
  "TICKS made a little longer or shorter, so nothing repeats exactly."
  (if (zerop ticks) 0
    (max 1 (round (* ticks (+ 0.7 (/ (random 61) 100.0)))))))

(defun +butler--step (track value)
  "Set TRACK to VALUE: the face, the body or the head."
  (pcase track
    ('face (setq +butler--face value))
    ('body (setq +butler--body value))
    ('head (setq +butler--head value))))

(defun +butler--next-step ()
  "Take the next step of his gesture, or choose the next gesture.
A finished gesture leaves the face and the body neutral; the head keeps
its turn."
  (if +butler--queue
      (pcase-let ((`(,track ,value . ,ticks) (pop +butler--queue)))
        (+butler--step track value)
        (+butler--redraw)
        (setq +butler--hold (+butler--stretch ticks)))
    (setq +butler--queue (append (+butler--pick-gesture)
                                 '((face neutral . 0) (body neutral . 0)))
          +butler--wait (+ (car +butler-idle-ticks)
                           (random (- (cdr +butler-idle-ticks)
                                      (car +butler-idle-ticks)))))))

(defun +butler--advance (n)
  "N tenths of a second have passed for the butler in the current buffer:
what was being held or waited out runs down by that much, a step is
taken when one is due, and the tenths until the next one are returned.
The one clock: the dashboard calls it once per tick, the popup's timer
with however many ticks it slept, so a hold lasts the same in both."
  (cond ((> +butler--hold 0)
         (setq +butler--hold (max 0 (- +butler--hold n))))
        ((and (null +butler--queue) (> +butler--wait 0))
         (setq +butler--wait (max 0 (- +butler--wait n)))))
  (when (and (zerop +butler--hold)
             (or +butler--queue (zerop +butler--wait)))
    (+butler--next-step))
  (max 1 (cond ((> +butler--hold 0) +butler--hold)
               (+butler--queue 1)
               ((> +butler--wait 0) +butler--wait)
               (t 1))))

;; His place on the dashboard, through what ui offers: the greeting
;; function draws him under the banner, the tick hook keeps him alive
;; there. Both are autoloaded, since the dashboard is drawn before any
;; command of his has loaded this file.

(defvar +butler--dashboard-width nil
  "The width the dashboard last handed him to centre in, for what he
says there after.")

;; Autoloaded: `+ui-dashboard-greeting-function', set in config.el.
;;;###autoload
(defun +butler--dashboard-greeting (width)
  "Insert him saying the greeting of the hour, centred in WIDTH columns,
his words in the dashboard's greeting face."
  (setq +butler--dashboard-width width)
  (+butler--insert-speech (+butler-greeting) width '+ui-greeting))

(defun +butler--dashboard-line ()
  "Something for him to say on the dashboard: a word of his own, a hint
from the cheat sheet, or the greeting of the hour, whichever comes up.
Only what fits the bubble as it stands, so the block keeps its height
and nothing else on the dashboard moves."
  (let* ((choice (seq-random-elt '(greeting quip hint)))
         (text (pcase choice
                 ('quip (+butler-quip))
                 ('hint (car (ignore-errors (+butler--hint nil))))
                 (_ (+butler-greeting)))))
    (if (and text (<= (length (+butler--wrap text)) (- (length +butler-art) 2)))
        text
      (+butler-greeting))))

(defun +butler--dashboard-resay ()
  "Have him say something else on the dashboard, in place of what he
said before.  The block is the same size, so the dashboard does not
shift under it."
  (when-let* ((buffer (and (boundp '+dashboard-name)
                           (get-buffer +dashboard-name))))
    (with-current-buffer buffer
      (save-excursion
        (goto-char (point-min))
        (when-let* ((match (text-property-search-forward '+butler-speech))
                    (start (prop-match-beginning match))
                    (end (prop-match-end match))
                    (width +butler--dashboard-width))
          ;; The dashboard centres its text with a line prefix, which a
          ;; plain insert would not carry: he would land on the left edge.
          (let ((inhibit-read-only t)
                (prefix (get-text-property start 'line-prefix)))
            (with-silent-modifications
              (delete-region start end)
              (goto-char start)
              (+butler--insert-speech (+butler--dashboard-line)
                                      width '+ui-greeting)
              (when prefix
                (add-text-properties start (point)
                                     `(line-prefix ,prefix indent-prefix ,prefix))))))))))

(defvar +butler--dashboard-ticks 0
  "Ticks since he last said something new on the dashboard.")

;; Autoloaded: on `+ui-dashboard-tick-hook', added in config.el.
;;;###autoload
(defun +butler--dashboard-tick-h (ticks)
  "TICKS of the dashboard animation have passed: he moves on by that
much, and every so often he says something else."
  (+butler--advance ticks)
  (when (and (numberp +butler-dashboard-say-ticks)
             (> +butler-dashboard-say-ticks 0))
    (cl-incf +butler--dashboard-ticks ticks)
    (when (>= +butler--dashboard-ticks +butler-dashboard-say-ticks)
      (setq +butler--dashboard-ticks 0)
      (+butler--dashboard-resay))))

(defvar +butler--timer nil
  "The timer that moves him while he is summoned.")

(defun +butler--move-on (ticks)
  "TICKS tenths of a second on, take his next step and set the timer for
the one after it; none when he is off the screen."
  (setq +butler--timer nil)
  (when-let* ((buffer (get-buffer "*butler*"))
              ((get-buffer-window buffer 'visible)))
    (let ((next (with-current-buffer buffer (+butler--advance ticks))))
      (setq +butler--timer
            (run-with-timer (* 0.1 next) nil #'+butler--move-on next)))))

(defun +butler--start-moving ()
  "Set him going in the *butler* buffer, one timer per step."
  (when (timerp +butler--timer) (cancel-timer +butler--timer))
  (setq +butler--timer (run-with-timer 0.1 nil #'+butler--move-on 1)))

;;
;;; Where he stands

;; Autoloaded: called from menu.el.
;;;###autoload
(defun +butler--frame ()
  "The child frame he floats in, while there is one alive."
  (when-let* ((buffer (get-buffer "*butler*"))
              (frame (+butler--posframe-of buffer)))
    (and (frame-live-p frame) frame)))

(defun +butler--menu-edges ()
  "His menu's window as (LEFT TOP RIGHT BOTTOM) in frame pixels, when up."
  (when-let* ((window (+butler--transient-window)))
    (window-pixel-edges window)))

(defconst +butler--border 1
  "Pixels of border round his child frame.")

(defun +butler--place (info)
  "Position handler: where he stands, off his menu, kept in the frame.
INFO is what posframe hands a handler, with his own state added by
`+butler--show'; posframe keeps the last answer while INFO is unchanged,
so what the answer depends on has to be in it."
  (let* ((frame-w (plist-get info :parent-frame-width))
         (frame-h (plist-get info :parent-frame-height))
         ;; The size posframe gives is the text's; the border is round it.
         (w (+ (plist-get info :posframe-width) (* 2 +butler--border)))
         (h (+ (plist-get info :posframe-height) (* 2 +butler--border)))
         (right (- frame-w w))
         (bottom (- frame-h h
                    (plist-get info :mode-line-height)
                    (plist-get info :minibuffer-height)))
         (spot (plist-get info :butler-position))
         (menu (plist-get info :butler-menu))
         (base (pcase spot
                 (`(,x . ,y) (cons x y))
                 ('bottom-left (cons 0 bottom))
                 ('top-right (cons right 0))
                 ('top-left (cons 0 0))
                 ('centre (cons (/ right 2) (/ bottom 2)))
                 ('here (posframe-poshandler-point-bottom-left-corner info))
                 (_ (cons right bottom))))
         (x (car base))
         (y (cdr base)))
    ;; A named spot never covers his menu; he stands above it instead.
    (when (and menu (symbolp spot)
               (< x (nth 2 menu)) (> (+ x w) (nth 0 menu))
               (< y (nth 3 menu)) (> (+ y h) (nth 1 menu)))
      (setq y (- (nth 1 menu) h)))
    (cons (max 0 (min right x))
          (max 0 (min bottom y)))))

(defvar +butler-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map [down-mouse-1] #'+butler/drag)
    map)
  "Keys in his popup: the mouse drags him, the rest is his menu's.")

(define-derived-mode +butler-mode special-mode "Butler"
  "The buffer he appears in.")

;; Autoloaded: called from menu.el.
;;;###autoload
(defun +butler--on-screen-p ()
  "Non-nil while he is showing, in a child frame or a window."
  (or (when-let* ((frame (+butler--frame)))
        (frame-visible-p frame))
      (when-let* ((buffer (get-buffer "*butler*")))
        (get-buffer-window buffer 'visible))))

(defvar +butler--size nil
  "What his buffer holds, as (COLUMNS . LINES): the child frame is made
that size, not asked for it.")

;; Autoloaded: called from menu.el.
;;;###autoload
(defvar +butler--said-footer nil
  "The footer of what he last said, for him to say it again whole: a
redraw without it, when a menu closed, lost the corner and a row.")

(defun +butler--show (text &optional footer)
  "Put TEXT in his bubble, on screen, FOOTER in its corner."
  (setq +butler--said text
        +butler--said-footer footer)
  (with-current-buffer (get-buffer-create "*butler*")
    (unless (derived-mode-p '+butler-mode) (+butler-mode))
    (let ((inhibit-read-only t))
      (erase-buffer)
      (setq +butler--size (+butler--insert-speech text nil nil +butler-margin footer))
      (goto-char (point-min))))
  (if (and (display-graphic-p)
           (require 'posframe nil t)
           (posframe-workable-p))
      ;; posframe would push the mouse off him; it is wanted there, to
      ;; drag him.
      (let ((posframe-mouse-banish-function #'ignore))
        (+butler--float))
    ;; In a terminal, a window as tall as what he says: the popup's own
    ;; size would cut a long answer off, and a window already up would
    ;; keep the size it had.
    (when-let* ((window (display-buffer "*butler*")))
      (fit-window-to-buffer window)))
  (+butler--start-moving))

(defun +butler--float ()
  "Show the *butler* buffer in his child frame, where he stands.  The
frame is given its size in characters, what the buffer holds: asked
for it after a resize, a child frame reports the old one for a while,
and he was placed by that, a gap under him or a corner cut off."
  (posframe-show "*butler*"
                 :poshandler #'+butler--place
                 :poshandler-extra-info
                 (list :butler-position +butler--position
                       :butler-menu (+butler--menu-edges))
                 :width (car +butler--size)
                 :height (cdr +butler--size)
                 :border-width +butler--border
                 :border-color (face-foreground 'shadow nil t)
                 :left-fringe 0 :right-fringe 0
                 :background-color (face-background 'default nil t))
  (+butler--snap)
  ;; The frame may settle a moment later, a resize on GTK not being
  ;; instant; snap again once it has.
  (run-with-timer 0 nil #'+butler--snap)
  ;; A press on him is an event from another frame, and Emacs answers
  ;; one of those with a switch-frame first, which would select his
  ;; frame and, with a menu up, suspend it.  With his focus sent to the
  ;; frame he stands in, his events count as its own and the press
  ;; reaches `+butler/drag'.
  (when-let* ((frame (+butler--frame)))
    (redirect-frame-focus frame (frame-parent frame))))

;; Autoloaded: called from menu.el.
;;;###autoload
(defun +butler--redisplay ()
  "Show him again where he stands now, saying what he last said."
  (when (+butler--on-screen-p)
    (+butler--show +butler--said +butler--said-footer)))

;; Autoloaded: called from menu.el.
;;;###autoload
(defun +butler--withdraw ()
  "Take him off the screen."
  (when (timerp +butler--timer)
    (cancel-timer +butler--timer)
    (setq +butler--timer nil))
  (when-let* ((buffer (get-buffer "*butler*")))
    (when (fboundp 'posframe-hide) (posframe-hide buffer))
    (when-let* ((window (get-buffer-window buffer)))
      (delete-window window))))

(defvar transient-current-command)

;;;###autoload
(defun +butler--menu-closed-h ()
  "On `transient-exit-hook': he steps back into his corner once the menu
he stood clear of is gone, his own or the one his answers were offered
in.  A spot of his own he keeps, and another menu closing, magit's or
the kit's, is none of his business."
  (when (and (memq transient-current-command '(+butler/menu +butler/choices))
             (symbolp +butler--position)
             (+butler--on-screen-p))
    (+butler--redisplay)))

(defvar +butler--frame-size nil
  "The size of the frame he stands in, as last placed.")

;;;###autoload
(defun +butler--follow-frame-h (frame)
  "On `window-size-change-functions': FRAME grown or shrunk, he is placed
again, so a corner stays a corner.  Done a moment later, since this hook
runs inside redisplay."
  (when-let* ((child (+butler--frame)))
    (when (and (eq frame (frame-parent child)) (frame-visible-p child))
      (let ((size (cons (frame-pixel-width frame) (frame-pixel-height frame))))
        (unless (equal size +butler--frame-size)
          (setq +butler--frame-size size)
          (run-with-timer 0 nil #'+butler--redisplay))))))

;; Autoloaded: called from menu.el.
;;;###autoload
(defun +butler--stand (spot)
  "Have him stand at SPOT: a name from `+butler-positions' or (X . Y)."
  (setq +butler--position spot)
  (+butler--remember)
  (+butler--redisplay)
  (when (symbolp spot)
    (message "%s stands %s" +butler-name
             (replace-regexp-in-string "-" " " (symbol-name spot)))))

(defvar +butler--remember-timer nil
  "The timer that writes down where he stands, once he has stopped.")

;; Autoloaded: called from menu.el.
;;;###autoload
(defun +butler--remember ()
  "Write down where he stands, once the moving has stopped.  savehist
keeps the spot, but Doom has it write only when Emacs is closed
properly; a session that ends any other way would otherwise lose it,
and he would be back in his old corner the next morning."
  (when (timerp +butler--remember-timer)
    (cancel-timer +butler--remember-timer))
  (setq +butler--remember-timer
        (run-with-idle-timer
         2 nil (lambda ()
                 (setq +butler--remember-timer nil)
                 (when (bound-and-true-p savehist-mode)
                   (let ((inhibit-message t))
                     (ignore-errors (savehist-save))))))))

(defun +butler--nudge (dx dy)
  "Move him DX, DY pixels from where he actually is."
  (when-let* ((frame (+butler--frame)))
    (let ((at (frame-position frame)))
      (+butler--stand (cons (+ (car at) dx) (+ (cdr at) dy))))))
