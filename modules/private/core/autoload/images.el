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

(defun +core--image-shown-size (spec)
  "The size SPEC is drawn at, (WIDTH . HEIGHT) in pixels, worked out from
the picture's own size off its header and the spec's sizes, or nil for
a picture whose header is not read, a rotation or a scale. `image-size'
decodes the whole picture to answer, and the centring asked after each
resize: 0.4 s a time for a 15 megapixel PNG, four times as it opened."
  (let ((props (cdr spec)))
    (when-let* ((file (plist-get props :file))
                ((memq (plist-get props :scale) '(nil 1 1.0)))
                ((memq (plist-get props :rotation) '(nil 0 0.0)))
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

(declare-function +core-view-enable "view")

(defvar +core-image-inspector (file-name-concat doom-user-dir "bin/inspect-image")
  "The program that describes an image from the inside.")

(defvar +core-image-inspected
  (rx "." (or "png" "jpg" "jpeg" "gif" "webp" "bmp" "ico" "tif" "tiff") eos)
  "The image files that open with their inspector beside them.")

(defun +core--svg-on-checker (svg)
  "SVG, a unibyte string, laid over a checkerboard, as a new SVG.
A drawing is often transparent: an icon for a light interface is dark
strokes on nothing and vanishes on a dark theme, one for a dark display
is white strokes and vanishes on a light one. The checkerboard is mid
grey, not the usual white and light grey, because the usual one hides a
white icon wherever it crosses a white square, and the icons here are
often white."
  (pcase-let ((`(,w . ,h) (image-size (create-image svg 'svg t) t)))
    (let* ((w (max 1 (round w))) (h (max 1 (round h)))
           ;; The view scales the drawing to fit, and the squares with it,
           ;; so they are sized from the drawing: about two dozen across,
           ;; whether it is a 16 pixel icon or a 2000 pixel poster.
           (square (max 2 (/ (max w h) 24.0)))
           (cell (* 2 square)))
      (encode-coding-string
       (format (concat
                "<svg xmlns=\"http://www.w3.org/2000/svg\" "
                "xmlns:xlink=\"http://www.w3.org/1999/xlink\" "
                "width=\"%d\" height=\"%d\" viewBox=\"0 0 %d %d\">"
                "<defs><pattern id=\"c\" width=\"%g\" height=\"%g\" "
                "patternUnits=\"userSpaceOnUse\">"
                "<rect width=\"%g\" height=\"%g\" fill=\"#707070\"/>"
                "<rect width=\"%g\" height=\"%g\" fill=\"#909090\"/>"
                "<rect x=\"%g\" y=\"%g\" width=\"%g\" height=\"%g\" fill=\"#909090\"/>"
                "</pattern></defs>"
                "<rect width=\"%d\" height=\"%d\" fill=\"url(#c)\"/>"
                "<image width=\"%d\" height=\"%d\" "
                "xlink:href=\"data:image/svg+xml;base64,%s\"/></svg>")
               w h w h cell cell cell cell square square square square square square
               w h w h (base64-encode-string svg t))
       'utf-8))))

(defun +core--svg-draw ()
  "This SVG for core's view, once its XML parses.
Halfway through typing a tag it does not, and librsvg would draw
nothing; the view then keeps the last good drawing and says where the
XML breaks, which `bin/check-data' can tell to the column."
  (let ((xml (buffer-substring-no-properties (point-min) (point-max))))
    (unless (with-temp-buffer
              (insert xml)
              (ignore-errors (libxml-parse-xml-region (point-min) (point-max))))
      (let ((said (with-temp-buffer
                    (insert xml)
                    (call-process-region (point-min) (point-max)
                                         (file-name-concat doom-user-dir "bin/check-data")
                                         t t nil "xml")
                    (string-trim (buffer-string)))))
        (error "%s" (if (string-match "\\`\\([0-9]+\\):[0-9]+: \\(.*\\)" said)
                        (format "line %s: %s" (match-string 1 said) (match-string 2 said))
                      "not well-formed XML yet"))))
    (list 'image (+core--svg-on-checker (encode-coding-string xml 'utf-8)) 'svg)))

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
