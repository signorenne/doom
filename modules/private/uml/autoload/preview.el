;;; private/uml/autoload/preview.el -*- lexical-binding: t; -*-
;;
;; How a diagram is drawn beside its source. The side window, drawing
;; again as you type, following you between diagrams and stepping aside
;; for other buffers are core's view (`+core-view-enable'); this is only
;; what goes in it.

(declare-function +uml-render "server")
(declare-function +core-view-enable "view")

(defun +uml--preview-options ()
  "The PlantUML flags that make a diagram readable against this theme.

PlantUML writes its background as a CSS style on the SVG root, and the
renderer here ignores that, so the image arrives transparent over the
Emacs background. On a dark theme that leaves PlantUML's dark text on a
dark background. `-darkmode' switches the diagram's own palette to light
strokes and text, which reads correctly against it.

None of this touches the file: the source stays as you wrote it, and
`+uml/export' writes it without these."
  (pcase +uml-preview-theme
    ('light nil)
    ('dark '("-darkmode"))
    ((and (pred stringp) name) (list "-theme" name))
    (_ (and (eq (frame-parameter nil 'background-mode) 'dark)
            '("-darkmode")))))

;;;###autoload
(defun +uml--draw ()
  "This diagram, for core's view. A diagram that does not parse signals,
so the view keeps the last good drawing and says what is wrong."
  (list 'image
        (+uml-render (buffer-substring-no-properties (point-min) (point-max))
                     +uml-preview-format (+uml--preview-options))
        +uml-preview-format))

;;;###autoload
(defun +uml--view-h ()
  "Give a diagram its preview, drawn again as you type."
  (+core-view-enable #'+uml--draw t))

;;;###autoload
(defun +uml/preview-format-toggle ()
  "Draw the preview as SVG or as PNG.
SVG stays sharp at any size; PNG is what a few diagram kinds render
more faithfully."
  (interactive)
  (setq +uml-preview-format (if (eq +uml-preview-format 'svg) 'png 'svg))
  (message "The preview is drawn as %s" (upcase (symbol-name +uml-preview-format)))
  (+core/view-refresh))
