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

(defvar-local +core--image-shim nil
  "The overlay holding the empty space above the picture.")

(defun +core--image-spec ()
  "The image this buffer shows, or nil."
  (let ((spec (ignore-errors (image-get-display-property))))
    (and (eq (car-safe spec) 'image) spec)))

;;;###autoload
(defun +core-image-center ()
  "Put the picture in the middle of its window instead of the corner.
The width goes in a `line-prefix', which costs nothing and moves with
the line; the height goes in an overlay above it."
  (when (derived-mode-p 'image-mode)
    (when-let* ((window (get-buffer-window (current-buffer) t))
                (spec (+core--image-spec))
                (size (ignore-errors (image-size spec t))))
      (let* ((edges (window-inside-pixel-edges window))
             (left (max 0 (floor (- (- (nth 2 edges) (nth 0 edges)) (car size)) 2)))
             (top (max 0 (floor (- (- (nth 3 edges) (nth 1 edges)) (cdr size)) 2)))
             (state (cons left top)))
        (unless (equal state +core--image-centring)
          (setq +core--image-centring state)
          (with-silent-modifications
            (put-text-property (point-min) (point-max) 'line-prefix
                               `(space :width (,left)))
            (cond
             ((zerop top)
              (when (overlayp +core--image-shim)
                (delete-overlay +core--image-shim)
                (setq +core--image-shim nil)))
             (t
              (unless (overlayp +core--image-shim)
                (setq +core--image-shim (make-overlay (point-min) (point-min) nil t)))
              (overlay-put +core--image-shim 'before-string
                           (propertize "\n" 'display
                                       `(space :width 1 :height (,top))))))))))))

;;;###autoload
(defun +core-image-uncenter ()
  "Take the centring off, so the buffer is plain text again.
C-c C-c turns the picture into its source, and the space that held the
picture in the middle would hold every line of the source there too."
  (with-silent-modifications
    (remove-text-properties (point-min) (point-max) '(line-prefix nil)))
  (when (overlayp +core--image-shim)
    (delete-overlay +core--image-shim))
  (setq +core--image-shim nil
        +core--image-centring nil))

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
  "Give an image file its inspector beside it."
  (when (and buffer-file-name
             (string-match-p +core-image-inspected (downcase buffer-file-name)))
    (+core-view-enable #'+core--image-inspect)))
