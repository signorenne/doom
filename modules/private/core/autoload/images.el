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
(declare-function +core-view--schedule "view")
(declare-function +core-view--decorate "view")
(declare-function +core-view-source "view")
(declare-function +core/view-refresh "view")
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

(defvar-local +core--svg-facts nil
  "Whether the view shows this SVG's facts instead of its drawing.")

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

(defvar-local +core-svg-here t
  "Whether the element the cursor is in is outlined in the drawing.")

(defvar +core--svg-here-reach 65536
  "How far back, in characters, the element at point is looked for.")

(declare-function nxml-backward-up-element "nxml-mode")

(defun +core--svg-start-tag-at (pos limit)
  "Where the start tag POS is inside begins, or nil when it is in none:
the < before POS, opening an element, with no > after it before POS."
  (save-excursion
    (goto-char pos)
    (when-let* ((start (search-backward "<" limit t)))
      (and (looking-at "<[[:alpha:]_]")
           (not (search-forward ">" pos t))
           start))))

(defun +core--svg-here ()
  "Where the start tag of the element the cursor is in begins, or nil.
Inside a start tag, that element; elsewhere the element around point as
nxml-mode knows it, and in a buffer too large for nxml-mode the start
tag before point. Never the root, whose outline would be the drawing's
whole edge."
  (let* ((limit (max (point-min) (- (point) +core--svg-here-reach)))
         (start (or (+core--svg-start-tag-at (point) limit)
                    (if (derived-mode-p 'nxml-mode)
                        ;; Within reach only: past the last child of a
                        ;; large drawing, nxml walks back over all of it
                        ;; to find the root, 95 ms in a 1.7 MB file.
                        (ignore-errors
                          (save-excursion
                            (save-restriction
                              (narrow-to-region limit (point-max))
                              (nxml-backward-up-element)
                              (point))))
                      (save-excursion
                        (and (re-search-backward "<[[:alpha:]_]" limit t) (point))))))
         (root (save-excursion
                 (goto-char (point-min))
                 (and (re-search-forward "<svg[ \t\n>]" nil t) (match-beginning 0)))))
    (and start (not (eql start root)) start)))

(defun +core--svg-moved-h ()
  "Draw again, once the cursor rests, when it has moved to another
element: the drawing's state says which, so resting in the same one
draws nothing."
  (when +core-svg-here (+core-view--schedule)))

;;;###autoload
(defun +core/svg-here-toggle ()
  "Outline the element the cursor is in, or stop."
  (interactive)
  (setq +core-svg-here (not +core-svg-here))
  (message "The element at the cursor is %s" (if +core-svg-here "outlined" "not outlined"))
  (when (fboundp '+core/view-refresh) (ignore-errors (+core/view-refresh))))

(defun +core--svg-copy (xml geometry &optional here scale)
  "XML as it is drawn in the view, as UTF-8: the backdrop first inside
the root, so it sits under everything, and the element whose start tag
is at HERE, an index in XML, outlined in the cursor's colour, a line
about 3 device pixels wide at SCALE device pixels per user unit. The
file is never touched."
  (let ((end (+core--svg-root-end xml)))
    (when (and here end (> here end))
      (when-let* ((name-end (string-match "[ \t\n/>]" xml (1+ here))))
        (setq xml (concat (substring xml 0 name-end) " data-nexenne-here=\"\""
                          (substring xml name-end)))))
    (encode-coding-string
     (if end
         (concat (substring xml 0 end)
                 (+core--svg-backdrop geometry)
                 (when here
                   (format (concat "<style>[data-nexenne-here], [data-nexenne-here] * "
                                   "{ stroke: %s !important; stroke-width: %gpx !important; }"
                                   "</style>")
                           (or (face-background 'cursor nil t) "#fcb291")
                           (/ 3.0 (max scale 1e-6))))
                 (substring xml end))
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
    (cond
     (+core--svg-facts
      (list 'async
            (lambda (done)
              (+core-view-pipe
               (list +core-image-inspector "--svg") (encode-coding-string xml 'utf-8)
               (lambda (result)
                 (funcall done
                          (if (car result)
                              (list 'text (+core-view--decorate
                                           (decode-coding-string (cdr result) 'utf-8)))
                            (list 'problem (or (cdr result) "the report failed") nil))))))))
     ((not (eq (dom-tag dom) 'svg))
      (if dom
          (list 'problem "the root element is not <svg>" nil)
        (+core--svg-problem xml)))
     (t
      (let* ((geometry (+core--svg-geometry dom))
             (natural (cons (round (nth 0 geometry)) (round (nth 1 geometry))))
             (box +core-view-box)
             (here (and +core-svg-here (+core--svg-here)))
             ;; Device pixels to a user unit, as rsvg-convert fits the
             ;; viewBox to the box.
             (units (min (/ (float (car box)) (nth 4 geometry))
                         (/ (float (cdr box)) (nth 5 geometry))))
             (copy (+core--svg-copy xml geometry (and here (- here (point-min))) units))
             (scale (+core-view-scale)))
        (list 'async
              (lambda (done)
                (+core-svg-picture-start copy box scale done natural))))))))

;;;###autoload
(defun +core-svg-picture-start (svg box scale done &optional natural)
  "Draw SVG, UTF-8 bytes, to fit BOX, device pixels, by
`+core-svg-renderer' in its own process, and call DONE with the view's
result: the picture at SCALE, or the problem. NATURAL is the drawing's
own size, read off SVG when not given. Returns a function that stops
the drawing. Without the renderer Emacs draws it, once, and DONE is
called at once."
  (let ((natural
         (or natural
             (when-let* ((dom (with-temp-buffer
                                (insert (decode-coding-string svg 'utf-8))
                                (ignore-errors
                                  (libxml-parse-xml-region (point-min) (point-max)))))
                         ((eq (dom-tag dom) 'svg))
                         (geometry (+core--svg-geometry dom)))
               (cons (round (nth 0 geometry)) (round (nth 1 geometry)))))))
    (if (not (executable-find +core-svg-renderer))
        (progn
          (unless +core--svg-said-slow
            (setq +core--svg-said-slow t)
            (message "SVG is drawn in the editor: %s would draw it without pausing typing"
                     +core-svg-renderer))
          (funcall done (append (list 'image svg 'svg) (and natural (list :natural natural))))
          nil)
      (+core-view-pipe
       (list +core-svg-renderer "-f" "png" "-a"
             "-w" (number-to-string (min 8192 (max 1 (car box))))
             "-h" (number-to-string (min 8192 (max 1 (cdr box)))))
       svg
       (lambda (result)
         (funcall done
                  (if (car result)
                      (append (list 'image (cdr result) 'png :scale scale)
                              (and natural (list :natural natural)))
                    (list 'problem (or (cdr result) "the drawing failed") nil))))))))

;;;###autoload
(defun +core--svg-view-h ()
  "Give an SVG file its drawing beside it, drawn again as you type, with
the element the cursor is in outlined."
  (when (and buffer-file-name (string-match-p "\\.svg\\'" buffer-file-name))
    (+core-view-enable #'+core--svg-draw t)
    (setq-local +core-view-state-function
                (lambda () (and +core-svg-here (+core--svg-here))))
    (add-hook 'post-command-hook #'+core--svg-moved-h nil t)))

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


;;
;;; What the view can do with an SVG besides drawing it

(defun +core--svg-buffer ()
  "The SVG buffer a command means, from it or from its view."
  (let ((buffer (+core-view-source)))
    (unless (eq (buffer-local-value '+core-view-draw buffer) #'+core--svg-draw)
      (user-error "The view does not show an SVG"))
    buffer))

;;;###autoload
(defun +core/view-background ()
  "Draw the SVG over the next background: checkerboard, light, dark."
  (interactive)
  (let ((buffer (+core--svg-buffer)))
    (setq +core-svg-background
          (pcase +core-svg-background ('checker 'light) ('light 'dark) (_ 'checker)))
    (message "SVG drawn over %s" (pcase +core-svg-background
                                   ('checker "the checkerboard") ('light "light") (_ "dark")))
    (with-current-buffer buffer (+core/view-refresh))))

;;;###autoload
(defun +core/svg-facts-toggle ()
  "Show this SVG's facts in the view instead of its drawing, or the
drawing again: size, what it is made of, ids, what it embeds, fonts."
  (interactive)
  (with-current-buffer (+core--svg-buffer)
    (setq +core--svg-facts (not +core--svg-facts))
    (+core/view-refresh)))

;;;###autoload
(defun +core/svg-export (file width)
  "Write this SVG as a PNG to FILE, WIDTH pixels wide, by
`+core-svg-renderer' in the background. What is written is the drawing
as you wrote it, without the view's backdrop or outline."
  (interactive
   (with-current-buffer (+core--svg-buffer)
     (let* ((dom (with-temp-buffer
                   (insert-buffer-substring (+core--svg-buffer))
                   (ignore-errors (libxml-parse-xml-region (point-min) (point-max)))))
            (natural (if (eq (dom-tag dom) 'svg) (car (+core--svg-geometry dom)) 512))
            (default (concat (file-name-sans-extension
                              (or buffer-file-name (expand-file-name "drawing")))
                             ".png")))
       (list (read-file-name "Write the PNG to: " (file-name-directory default) nil nil
                             (file-name-nondirectory default))
             (read-number "Width in pixels: " (* 2 (round natural)))))))
  (unless (executable-find +core-svg-renderer)
    (user-error "No %s on PATH; SPC h r d says how to install it" +core-svg-renderer))
  (setq file (expand-file-name file))
  (when (and (file-exists-p file)
             (not (y-or-n-p (format "%s exists; replace it? " (abbreviate-file-name file)))))
    (user-error "Nothing written"))
  (let ((xml (with-current-buffer (+core--svg-buffer)
               (buffer-substring-no-properties (point-min) (point-max)))))
    (+core-view-pipe
     (list +core-svg-renderer "-f" "png" "-a" "-w" (number-to-string (max 1 width))
           "-o" file)
     (encode-coding-string xml 'utf-8)
     (lambda (result)
       (if (car result)
           (message "Wrote %s, %d pixels wide" (abbreviate-file-name file) width)
         (message "Could not write %s: %s" (abbreviate-file-name file)
                  (or (cdr result) "the drawing failed")))))
    (message "Writing %s..." (abbreviate-file-name file))))


;;
;;; Pictures Emacs cannot read itself

(defvar +core-image-cache-dir (file-name-concat doom-cache-dir "images/")
  "Where a picture converted for the viewer is kept, so it is converted
once, not each time it is opened.")

(defvar +core--image-cache-swept nil
  "Whether this session has cleared old conversions out of the cache.")

(defun +core--image-cache-file (file)
  "Where FILE's conversion is kept: named for its path, size and time, so
a changed file is converted again."
  (let ((attrs (file-attributes file)))
    (file-name-concat
     +core-image-cache-dir
     (concat (secure-hash 'sha1 (format "%s|%s|%s" (file-truename file)
                                        (file-attribute-size attrs)
                                        (float-time (file-attribute-modification-time attrs))))
             ".png"))))

(defun +core--image-sweep-cache ()
  "Delete conversions older than 30 days, in the background, once a
session."
  (unless +core--image-cache-swept
    (setq +core--image-cache-swept t)
    (ignore-errors
      (make-process :name "image-cache-sweep" :noquery t :buffer nil
                    :command (list "find" +core-image-cache-dir "-name" "*.png"
                                   "-mtime" "+30" "-delete")))))

;;;###autoload
(defun +core--image-convert (source data-type)
  "Put SOURCE, a picture Emacs cannot read, in this buffer as a PNG, for
`image-converter-add-handler'. SOURCE is a file, or the picture's bytes
when DATA-TYPE, its MIME type, is non-nil. vips reads AVIF, HEIF and JPEG
XL with libheif and libjxl and the rest through ImageMagick, which is the
fallback when vips is missing. A converted file is kept, so the next
opening only reads it."
  (let* ((input (if data-type
                    (let ((coding-system-for-write 'no-conversion))
                      (make-temp-file "image-input-" nil
                                      (concat "." (cadr (split-string (symbol-name data-type) "/")))
                                      source))
                  (expand-file-name source)))
         (cache (if data-type
                    (make-temp-file "image-output-" nil ".png")
                  (+core--image-cache-file input))))
    (unwind-protect
        (progn
          (when (or data-type (not (file-exists-p cache)))
            (make-directory (file-name-directory cache) t)
            ;; The lightest compression: the file stays on this disk, and
            ;; the default compresses a 6 megapixel picture for 0.6 s of
            ;; the first opening, against 0.35 s.
            (let ((partial (concat cache ".part.png")))
              (unless (zerop
                       (cond ((executable-find "vips")
                              (call-process "vips" nil nil nil "copy" input
                                            (concat partial "[compression=1]")))
                             ((executable-find "magick")
                              (call-process "magick" nil nil nil (concat input "[0]")
                                            "-define" "png:compression-level=1" partial))
                             (t (error "Neither vips nor ImageMagick is installed to read %s"
                                       (file-name-nondirectory input)))))
                (ignore-errors (delete-file partial))
                (error "Could not read %s" (file-name-nondirectory input)))
              (rename-file partial cache t))
            (+core--image-sweep-cache))
          (set-buffer-multibyte nil)
          (insert-file-contents-literally cache))
      (when data-type
        (ignore-errors (delete-file input))
        (ignore-errors (delete-file cache))))))


;;
;;; Moving pictures

(declare-function image-multi-frame-p "image")
(declare-function image-current-frame "image")
(declare-function image-animate "image")
(declare-function image-animate-timer "image")
(declare-function image-animate-get-speed "image")

(defvar +core-image-autoplay t
  "Whether a moving picture, a GIF or an animated WebP, plays as it
opens, looping, the way a browser shows it.")

(defvar-local +core--image-playing nil
  "Whether this buffer's moving picture is playing, so it plays on when
the picture is drawn again: fitted, zoomed, the window resized.")

(defun +core--image-stop (spec)
  "Stop SPEC's animation, if it has one going."
  (when-let* ((spec) (timer (image-animate-timer spec)))
    (cancel-timer timer)))

;;;###autoload
(defun +core--image-animate-h ()
  "Play a moving picture as it opens, and say in the header line which
frame it is on and the keys that move through it."
  (let ((buffer (current-buffer)))
    ;; After the fit, which draws the picture again, at the end of the
    ;; command that opened it.
    (run-at-time
     0 nil
     (lambda ()
       (when (buffer-live-p buffer)
         (with-current-buffer buffer
           (when-let* ((spec (+core--image-spec))
                       ((image-multi-frame-p spec)))
             (setq-local header-line-format '(:eval (+core--image-frames-line)))
             (add-hook 'kill-buffer-hook
                       (lambda () (+core--image-stop (+core--image-spec))) nil t)
             (when +core-image-autoplay
               (setq +core--image-playing t)
               (image-animate spec nil t)))))))))

(defun +core--image-frames-line ()
  "The header line of a moving picture: its frame, whether it plays, and
the keys."
  (when-let* ((spec (+core--image-spec))
              (frames (image-multi-frame-p spec)))
    (let ((speed (image-animate-get-speed spec)))
      (concat " "
              (propertize (format "frame %d of %d" (1+ (image-current-frame spec)) (car frames))
                          'face 'mode-line-buffer-id)
              (propertize (concat "   " (if (image-animate-timer spec) "playing" "paused")
                                  (unless (eql speed 1) (format ", speed %s" speed)))
                          'face 'success)
              (propertize "    RET play or pause   , . a frame   F go to   { } speed   a r reverse"
                          'face 'shadow)))))

;;;###autoload
(defun +core--image-keep-playing-a (fn &rest args)
  "Draw the picture again with FN and ARGS and, when it was playing, play
the new one from the same frame. Emacs's animation belongs to the picture
it was started on, which a fit or a zoom replaces, so it stopped there
and kept running on a picture no longer shown."
  (let* ((old (+core--image-spec))
         (frame (and old (image-multi-frame-p old) (image-current-frame old))))
    (+core--image-stop old)
    (prog1 (apply fn args)
      (when-let* ((+core--image-playing)
                  (new (+core--image-spec))
                  ((image-multi-frame-p new)))
        (image-animate new frame t)))))

;;;###autoload
(defun +core--image-pause-a (&rest _)
  "Pause before stepping a frame by hand: the playing would move it on."
  (when +core--image-playing
    (setq +core--image-playing nil)
    (+core--image-stop (+core--image-spec))))

;;;###autoload
(defun +core/image-play-toggle ()
  "Play the moving picture, looping, or pause it where it is."
  (interactive nil image-mode)
  (let ((spec (or (+core--image-spec) (user-error "No picture here"))))
    (unless (image-multi-frame-p spec) (user-error "This picture does not move"))
    (if (image-animate-timer spec)
        (progn (setq +core--image-playing nil) (+core--image-stop spec))
      (setq +core--image-playing t)
      (image-animate spec (image-current-frame spec) t))
    (force-mode-line-update)))
