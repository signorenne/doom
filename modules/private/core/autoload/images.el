;;; private/core/autoload/images.el -*- lexical-binding: t; -*-
;;
;; An image file is opened to be looked at, so the buffer behaves like a
;; viewer: the picture in the middle of the window rather than in the
;; corner, and it stays in the middle as the window changes, as the
;; zoom changes, and as another file is stepped to.

(declare-function image-get-display-property "image-mode")
(declare-function image-toggle-display-image "image-mode")
(declare-function image-bob "image-mode")
(declare-function image-transform-reset-to-original "image-mode")
(declare-function image-forward-hscroll "image-mode")
(declare-function image-backward-hscroll "image-mode")
(declare-function image-next-line "image-mode")
(declare-function image-previous-line "image-mode")

(defvar-local +core--image-centring nil
  "The last (LEFT . TOP) the picture was centred with, so a command that
moved nothing does not draw it again.")

(defun +core--image-shims ()
  "The overlays holding the empty space above the picture. Found by
their mark rather than kept in a variable: a redraw that replaces the
buffer's text resets the variables, and the overlay outlives both."
  (seq-filter (lambda (o) (overlay-get o '+core-image-shim))
              (overlays-in (point-min) (point-max))))

(defun +core--image-spec ()
  "The image this buffer shows, or nil."
  (let ((spec (ignore-errors (image-get-display-property))))
    (and (eq (car-safe spec) 'image) spec)))

;; Autoloaded: the file manager's preview reads it as well.
;;;###autoload
(defun +core--image-header-size (file)
  "The (WIDTH . HEIGHT) of FILE read off its header, a PNG or a JPEG,
else nil. Asking Emacs decodes the whole picture only to learn that, and
it is decoded again to be drawn: a quarter second for a large one."
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (insert-file-contents-literally file nil 0 65536)
    (let ((byte (lambda (i) (or (char-after i) 0)))
          (word (lambda (i) (logior (ash (or (char-after i) 0) 8)
                                    (or (char-after (1+ i)) 0)))))
      (cond
       ((and (> (buffer-size) 24)
             (equal (buffer-substring 1 9) "\211PNG\r\n\032\n")
             (equal (buffer-substring 13 17) "IHDR"))
        (cons (logior (ash (funcall word 17) 16) (funcall word 19))
              (logior (ash (funcall word 21) 16) (funcall word 23))))
       ((equal (buffer-substring 1 (min 3 (point-max))) "\377\330")
        ;; The segments, to the first start of frame: its height, then
        ;; its width, after the length and the precision.
        (let ((pos 3) size)
          (while (and (not size) (< (+ pos 8) (point-max))
                      (= (funcall byte pos) #xff))
            (let ((marker (funcall byte (1+ pos))))
              (cond ((= marker #xff) (setq pos (1+ pos)))
                    ((or (= marker 1) (<= #xd0 marker #xd9)) (setq pos (+ pos 2)))
                    ((memq marker '(#xc0 #xc1 #xc2 #xc3 #xc5 #xc6 #xc7
                                    #xc9 #xca #xcb #xcd #xce #xcf))
                     (setq size (cons (funcall word (+ pos 7))
                                      (funcall word (+ pos 5)))))
                    (t (setq pos (+ pos 2 (funcall word (+ pos 2))))))))
          size))))))

;; Autoloaded: the fit in +images.el asks it before any of this is loaded.
;;;###autoload
(defun +core--image-shown-size (spec)
  "The size SPEC is drawn at, (WIDTH . HEIGHT) in pixels, worked out from
the picture's own size off its header and the spec's sizes, or nil for
a picture whose header is not read, a rotation or a scale. `image-size'
decodes the whole picture to answer, and the centring asked after each
resize: 0.4 s a time for a 15 megapixel PNG, four times as it opened."
  (let ((props (cdr spec)))
    (when-let* ((file (plist-get props :file))
                ((memql (plist-get props :scale) '(nil 1 1.0)))
                ((memql (plist-get props :rotation) '(nil 0 0.0)))
                (size (+core--image-header-size file))
                ((> (car size) 0))
                ((> (cdr size) 0)))
      (let* ((iw (car size))
             (ih (cdr size))
             (dw (plist-get props :width))
             (dh (plist-get props :height))
             (mw (plist-get props :max-width))
             (mh (plist-get props :max-height))
             ;; Emacs's scale_image_size: the other side from the
             ;; picture's own, rounded up.
             (scale (lambda (side from to) (ceiling (* side to) from)))
             w h)
        (when (and (or (null dw) (natnump dw)) (or (null dh) (natnump dh)))
          ;; As Emacs sizes it: a width or a height given keeps the
          ;; shape, then the maxima shrink it to fit.
          (cond ((and dw dh) (setq w dw h dh))
                (dw (setq w dw h (funcall scale dw iw ih)))
                (dh (setq h dh w (funcall scale dh ih iw)))
                (t (setq w iw h ih)))
          (unless (and dw dh)
            (when (and (natnump mw) (< mw w)) (setq w mw h (funcall scale mw iw ih)))
            (when (and (natnump mh) (< mh h)) (setq h mh w (funcall scale mh ih iw))))
          (cons w h))))))

;;;###autoload
(defun +core-image-center ()
  "Put the picture in the middle of its window instead of the corner.
The width goes in a `line-prefix', which costs nothing and moves with
the line; the height goes in an overlay above it."
  (when (derived-mode-p 'image-mode)
    (when-let* ((window (get-buffer-window (current-buffer) t))
                (spec (+core--image-spec))
                (size (or (+core--image-shown-size spec)
                          (ignore-errors (image-size spec t)))))
      (let* ((edges (window-inside-pixel-edges window))
             (left (max 0 (floor (- (- (nth 2 edges) (nth 0 edges)) (car size)) 2)))
             (top (max 0 (floor (- (- (nth 3 edges) (nth 1 edges)) (cdr size)) 2)))
             (state (cons left top)))
        (unless (equal state +core--image-centring)
          (setq +core--image-centring state)
          (with-silent-modifications
            (put-text-property (point-min) (point-max) 'line-prefix
                               `(space :width (,left)))
            (let ((shims (+core--image-shims)))
              (mapc #'delete-overlay (if (zerop top) shims (cdr shims)))
              (unless (zerop top)
                (let ((shim (or (car shims)
                                (make-overlay (point-min) (point-min) nil t))))
                  (overlay-put shim '+core-image-shim t)
                  ;; A line of its own, as tall as the gap: a newline
                  ;; drawn as the space itself would end no line, and
                  ;; the picture would sit beside it rather than below.
                  (overlay-put shim 'before-string
                               (concat (propertize " " 'display
                                                   `(space :width 1 :height (,top)))
                                       "\n")))))))))))

;;;###autoload
(defun +core-image-uncenter ()
  "Take the centring off, so the buffer is plain text again.
C-c C-c turns the picture into its source, and the space that held the
picture in the middle would hold every line of the source there too."
  (with-silent-modifications
    (remove-text-properties (point-min) (point-max) '(line-prefix nil)))
  (mapc #'delete-overlay (+core--image-shims))
  (setq +core--image-centring nil))

;;;###autoload
(defun +core--image-center-h ()
  "Centre the picture after whatever just moved or resized it, and take
the centring off when the buffer stops holding one."
  (ignore-errors
    (if (and (derived-mode-p 'image-mode) (+core--image-spec))
        (+core-image-center)
      (when +core--image-centring (+core-image-uncenter)))))

;;;###autoload
(defun +core/image-fit ()
  "Fill the window with the picture, the size it opens at.
`image-transform-fit-both' only ever shrinks, so on a small icon it
answers with the icon: 66 pixels in a window a thousand wide.  This is
the fit the eye means."
  (interactive nil image-mode)
  (setq-local image-transform-resize 'fit-window)
  (image-toggle-display-image)
  (image-bob)                           ; a fitted picture has nowhere to be scrolled to
  (setq +core--image-centring nil)
  (+core-image-center))

;;;###autoload
(defun +core/image-original ()
  "The picture at the size it really is."
  (interactive nil image-mode)
  (image-transform-reset-to-original)
  (image-bob)
  (setq +core--image-centring nil)
  (+core-image-center))

;;;###autoload
(defun +core--image-refit-recenter-a (window)
  "Centre again after WINDOW's picture was fitted to it. The fit comes
a moment after the window changes size, so the centring done at the
change was for the picture as it was: while a side window is laid out
its height is 0 for a moment, and a diagram was centred as a sliver,
then fitted to the full height and left low and to the left."
  (when (window-live-p window)
    (with-current-buffer (window-buffer window)
      (+core--image-recenter-a))))

;;;###autoload
(defun +core--image-recenter-a (&rest _)
  "Centre again after a zoom.  `image-size' answers from a cache keyed on
the plist, and a zoom changes that plist in place, so the answer is the
size before the zoom until the picture is flushed."
  (when (derived-mode-p 'image-mode)
    (when-let* ((spec (+core--image-spec)))
      (ignore-errors (image-flush spec)))
    (setq +core--image-centring nil)
    (ignore-errors (+core-image-center))))


;;
;;; Panning

(defvar +core-image-pan-step 8
  "How far h j k l move a picture larger than its window.
`image-forward-hscroll' and its neighbours move one character a press,
which is ten pixels or so: a thousand presses to cross a large picture.
This many at a time crosses it in a dozen.")

;;;###autoload
(defun +core/image-pan-right (&optional n)
  "Move the picture left under the window, `+core-image-pan-step' at a time."
  (interactive "p" image-mode)
  (image-forward-hscroll (* (or n 1) +core-image-pan-step)))

;;;###autoload
(defun +core/image-pan-left (&optional n)
  "Move the picture right under the window."
  (interactive "p" image-mode)
  (image-backward-hscroll (* (or n 1) +core-image-pan-step)))

;;;###autoload
(defun +core/image-pan-down (&optional n)
  "Move the picture up under the window."
  (interactive "p" image-mode)
  (image-next-line (* (or n 1) +core-image-pan-step)))

;;;###autoload
(defun +core/image-pan-up (&optional n)
  "Move the picture down under the window."
  (interactive "p" image-mode)
  (image-previous-line (* (or n 1) +core-image-pan-step)))


;;
;;; The picture beside the source, and what is inside a picture

(require 'dom)
(declare-function +core-view-enable "view")
(declare-function +core-view-pipe "view")
(declare-function +core-view-scale "view")
(defvar +core-view-box)

(defvar +core-image-inspector (file-name-concat doom-user-dir "bin/inspect-image")
  "The program that describes an image from the inside.")

(defvar +core-image-inspected
  (rx "." (or "png" "jpg" "jpeg" "gif" "webp" "bmp" "ico" "tif" "tiff") eos)
  "The image files that open with their inspector beside them.")

(defvar +core-svg-renderer "rsvg-convert"
  "The program that draws an SVG for the view, in its own process, so a
large drawing never holds up typing. librsvg's own: the same drawing as
Emacs's, which draws it in the editor when this is missing.")

(defvar +core-svg-background 'checker
  "What the view draws an SVG over: `checker', `light' or `dark'.")

(defvar +core-view-backgrounds '((light . "#f5f1e8") (dark . "#1c1915"))
  "The plain backgrounds behind a drawing, those of nexenne-day and
nexenne-night, so a drawing is seen as it will be in either.")

(defvar +core--svg-said-slow nil
  "Whether the view said once that SVG drawing is slower without
`+core-svg-renderer'.")

(defun +core--svg-length (value)
  "VALUE, an SVG length, in pixels, or nil for a percentage or nothing."
  (when (and (stringp value)
             (string-match "\\`[ \t]*\\([0-9.]+\\(?:e[-+]?[0-9]+\\)?\\)[ \t]*\\([a-z]*\\)[ \t]*\\'"
                           value))
    (let ((n (string-to-number (match-string 1 value))))
      (pcase (match-string 2 value)
        ((or "" "px") n)
        ("pt" (* n (/ 96.0 72)))
        ("pc" (* n 16))
        ("in" (* n 96))
        ("cm" (* n (/ 96 2.54)))
        ("mm" (* n (/ 96 25.4)))
        (_ nil)))))

(defun +core--svg-geometry (dom)
  "The drawing's own size and its viewBox, from its root element DOM:
(WIDTH HEIGHT VX VY VW VH). Read off the source, never by drawing it:
a size asked of Emacs is a whole render, 0.4 s for a large one."
  (let* ((attrs (dom-attributes dom))
         (box (when-let* ((v (alist-get 'viewBox attrs))
                          (nums (mapcar #'string-to-number
                                        (split-string v "[ ,\t\n]+" t)))
                          ((= (length nums) 4))
                          ((> (nth 2 nums) 0))
                          ((> (nth 3 nums) 0)))
                nums))
         (w (+core--svg-length (alist-get 'width attrs)))
         (h (+core--svg-length (alist-get 'height attrs))))
    ;; As a browser sizes it: a side missing takes the viewBox's shape,
    ;; and with neither side nor viewBox it is 300 by 150.
    (cond ((and w h))
          ((and w box) (setq h (* w (/ (float (nth 3 box)) (nth 2 box)))))
          ((and h box) (setq w (* h (/ (float (nth 2 box)) (nth 3 box)))))
          (box (setq w (nth 2 box) h (nth 3 box)))
          (t (setq w (or w 300) h (or h 150))))
    (append (list (max 1 w) (max 1 h))
            (or box (list 0 0 (max 1 w) (max 1 h))))))

(defun +core--svg-root-end (xml)
  "Where the root <svg> start tag ends in XML, after its >, or nil when
there is none or it closes itself."
  (when-let* ((start (string-match "<svg[ \t\n>]" xml)))
    (let ((i (+ start 4)) (n (length xml)) quote end)
      (while (and (not end) (< i n))
        (let ((c (aref xml i)))
          (cond (quote (when (eq c quote) (setq quote nil)))
                ((memq c '(?\" ?\')) (setq quote c))
                ((eq c ?>) (setq end (1+ i)))))
        (setq i (1+ i)))
      (and end (not (eq (aref xml (- end 2)) ?/)) end))))

(defun +core--svg-backdrop (geometry)
  "What goes under the drawing, as SVG: a mid grey checkerboard, or a
plain background, over the whole viewBox in GEOMETRY.
A drawing is often transparent: an icon for a light interface is dark
strokes on nothing and vanishes on a dark theme, one for a dark display
is white strokes and vanishes on a light one. The checkerboard is mid
grey, not the usual white and light grey, because the usual one hides a
white icon wherever it crosses a white square, and the icons here are
often white."
  (pcase-let ((`(,_ ,_ ,vx ,vy ,vw ,vh) geometry))
    (if-let* ((colour (alist-get +core-svg-background +core-view-backgrounds)))
        (format "<rect x=\"%g\" y=\"%g\" width=\"%g\" height=\"%g\" fill=\"%s\"/>"
                vx vy vw vh colour)
      ;; About two dozen squares across, whether it is a 16 pixel icon
      ;; or a 2000 pixel poster: the view scales them with the drawing.
      (let* ((square (/ (max vw vh) 24.0))
             (cell (* 2 square)))
        (format (concat "<defs><pattern id=\"nexenne-checker\" x=\"%g\" y=\"%g\" "
                        "width=\"%g\" height=\"%g\" patternUnits=\"userSpaceOnUse\">"
                        "<rect width=\"%g\" height=\"%g\" fill=\"#707070\"/>"
                        "<rect width=\"%g\" height=\"%g\" fill=\"#909090\"/>"
                        "<rect x=\"%g\" y=\"%g\" width=\"%g\" height=\"%g\" fill=\"#909090\"/>"
                        "</pattern></defs>"
                        "<rect x=\"%g\" y=\"%g\" width=\"%g\" height=\"%g\" "
                        "fill=\"url(#nexenne-checker)\"/>")
                vx vy cell cell cell cell square square square square square square
                vx vy vw vh)))))

(defun +core--svg-copy (xml geometry)
  "XML as it is drawn in the view: the backdrop first inside the root, so
it sits under everything, as UTF-8. The file is never touched."
  (let ((end (+core--svg-root-end xml)))
    (encode-coding-string
     (if end
         (concat (substring xml 0 end) (+core--svg-backdrop geometry) (substring xml end))
       xml)
     'utf-8)))

(defun +core--svg-problem (xml)
  "An (async START) that says where XML stops being well formed, as
`bin/check-data' tells it, to the line, in its own process."
  (list 'async
        (lambda (done)
          (+core-view-pipe
           (list (file-name-concat doom-user-dir "bin/check-data") "xml")
           (encode-coding-string xml 'utf-8)
           (lambda (result)
             (let ((said (or (cdr result) "")))
               (funcall done
                        (if (string-match "\\`\\([0-9]+\\):[0-9]+: \\(.*\\)" said)
                            (list 'problem (format "line %s: %s" (match-string 1 said)
                                                   (match-string 2 said))
                                  (string-to-number (match-string 1 said)))
                          (list 'problem "not well-formed XML yet" nil)))))))))

(defun +core--svg-draw ()
  "This SVG for core's view, drawn by `+core-svg-renderer' in its own
process to fit `+core-view-box'. Halfway through typing a tag the XML
does not parse and librsvg would draw nothing; the view then keeps the
last good drawing and says where the XML breaks."
  (let* ((xml (buffer-substring-no-properties (point-min) (point-max)))
         (dom (with-temp-buffer
                (insert xml)
                (ignore-errors (libxml-parse-xml-region (point-min) (point-max))))))
    (if (not (eq (dom-tag dom) 'svg))
        (if dom
            (list 'problem "the root element is not <svg>" nil)
          (+core--svg-problem xml))
      (let* ((geometry (+core--svg-geometry dom))
             (natural (cons (round (nth 0 geometry)) (round (nth 1 geometry))))
             (copy (+core--svg-copy xml geometry))
             (box +core-view-box)
             (scale (+core-view-scale)))
        (if (not (executable-find +core-svg-renderer))
            (progn
              (unless +core--svg-said-slow
                (setq +core--svg-said-slow t)
                (message "SVG is drawn in the editor: %s would draw it without pausing typing"
                         +core-svg-renderer))
              (list 'image copy 'svg :natural natural))
          (list 'async
                (lambda (done)
                  (+core-view-pipe
                   (list +core-svg-renderer "-f" "png" "-a"
                         "-w" (number-to-string (min 8192 (max 1 (car box))))
                         "-h" (number-to-string (min 8192 (max 1 (cdr box)))))
                   copy
                   (lambda (result)
                     (funcall done
                              (if (car result)
                                  (list 'image (cdr result) 'png
                                        :scale scale :natural natural)
                                (list 'problem (or (cdr result) "the drawing failed")
                                      nil))))))))))))

;;;###autoload
(defun +core--svg-view-h ()
  "Give an SVG file its drawing beside it, drawn again as you type."
  (when (and buffer-file-name (string-match-p "\\.svg\\'" buffer-file-name))
    (+core-view-enable #'+core--svg-draw t)))

(defun +core--image-inspect ()
  "What is inside this image, for core's view: `bin/inspect-image',
which runs in the background so a large file never holds up the editor."
  (list 'process (list +core-image-inspector buffer-file-name)))

;;;###autoload
(defun +core--image-inspector-h ()
  "Give an image file its insides beside it, on the left, so the picture
sits on the right the way an SVG's drawing does."
  (when (and buffer-file-name
             (string-match-p +core-image-inspected (downcase buffer-file-name)))
    (+core-view-enable #'+core--image-inspect nil 'left)))
