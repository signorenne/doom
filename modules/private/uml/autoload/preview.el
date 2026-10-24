;;; private/uml/autoload/preview.el -*- lexical-binding: t; -*-
;;
;; How a diagram is drawn beside its source. The side window, drawing
;; again as you type, following you between diagrams and stepping aside
;; for other buffers are core's view (`+core-view-enable'); this is only
;; what goes in it.

(declare-function +uml-render-async "server")
(declare-function +core-view-enable "view")
(declare-function +core-view-scale "view")
(declare-function +core-svg-picture-start "images")
(declare-function +core-view-redraw "view")
(declare-function +core-view-source "view")
(defvar +core-view-box)

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
  "This diagram, for core's view, drawn without holding up the editor:
the server renders it, starting first when it is not up, and an SVG is
then drawn to fit the view by core's SVG renderer, sharp at any zoom. A
diagram that does not parse keeps the last good drawing, and its line
is marked."
  (let ((source (buffer-substring-no-properties (point-min) (point-max)))
        (format +uml-preview-format)
        (options (+uml--preview-options))
        (box +core-view-box)
        (scale (+core-view-scale)))
    (list 'async
          (lambda (done)
            (let (picture)
              (let ((render
                     (+uml-render-async
                      source format options
                      (lambda (answer)
                        (pcase answer
                          (`(ok ,bytes)
                           (if (eq format 'png)
                               (funcall done (list 'image bytes 'png))
                             (setq picture (+core-svg-picture-start bytes box scale done))))
                          (_ (funcall done answer)))))))
                (lambda ()
                  (funcall render)
                  (when picture (funcall picture)))))))))

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
  (+core-view-redraw (+core-view-source)))
