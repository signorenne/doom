;;; private/core/autoload/view-menu.el -*- lexical-binding: t; -*-
;;
;; The view's keys in one menu, from the view or from the buffer it
;; shows: ? in the view, SPC m SPC beside an SVG or a diagram.

(require 'transient)

(defvar +core-view--shown)
(declare-function +core-view-source "view")

(defun +core--view-menu-draws-p (draw)
  "Non-nil when the view the menu is about is drawn by DRAW, a name.
A name, not the function: only compared, never called."
  (when-let* ((source (ignore-errors (+core-view-source))))
    (eq (buffer-local-value '+core-view-draw source) draw)))

(defun +core--view-menu-svg-p ()
  "Non-nil when the view the menu is about draws an SVG."
  (+core--view-menu-draws-p '+core--svg-draw))

(defun +core--view-menu-diagram-p ()
  "Non-nil when the view the menu is about draws a PlantUML diagram."
  (+core--view-menu-draws-p '+uml--draw))

(defun +core--view-menu-uml-format ()
  "Draw the diagram as PNG or SVG, from the view or from the diagram."
  (interactive)
  (with-current-buffer (+core-view-source)
    (call-interactively #'+uml/preview-format-toggle)))

(defun +core--view-menu-uml-export ()
  "Write the diagram to a file, from the view or from the diagram."
  (interactive)
  (with-current-buffer (+core-view-source)
    (call-interactively #'+uml/export)))

;;;###autoload (autoload '+core/view-menu "private/core/autoload/view-menu" nil t)
(transient-define-prefix +core/view-menu ()
  "What the view beside this buffer can do."
  [["Picture"
    ("+" "zoom in" +core/view-zoom-in :transient t)
    ("-" "zoom out" +core/view-zoom-out :transient t)
    ("0" "fit the window" +core/view-fit :transient t)
    ("1" "its own size" +core/view-original :transient t)
    ("b" "background: checker, light, dark" +core/view-background
     :transient t :if +core--view-menu-svg-p)]
   ["View"
    ("p" "show or hide it" +core/view-toggle)
    ("r" "draw it again now" +core/view-refresh)
    ("F" "follow my typing, or not" +core/view-follow-toggle)
    ("O" "open it with the file, or not" +core/view-on-open-toggle)
    ("c" "close it" +core/view-close)]
   ["SVG" :if +core--view-menu-svg-p
    ("h" "outline the element here, or not" +core/svg-here-toggle)
    ("i" "its facts, or its drawing" +core/svg-facts-toggle)
    ("e" "write it as a PNG" +core/svg-export)]
   ["Diagram" :if +core--view-menu-diagram-p
    ("P" "draw as PNG or SVG" +core--view-menu-uml-format)
    ("e" "write it to a file" +core--view-menu-uml-export)]])
