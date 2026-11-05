;;; private/uml/config.el -*- lexical-binding: t; -*-
;;
;; PlantUML: completion from a language server, a diagram beside the
;; text that follows your typing, and a template for each kind of
;; diagram.
;;
;; Doom's :lang plantuml brings the mode and the flycheck checker. What
;; this adds is the rendering path, the server and the templates. The
;; window beside the text, redrawing as you type and following you from
;; diagram to diagram, is core's view (`+core-view-enable'), shared with
;; SVG files and images; this module only says how a diagram is drawn.

(defvar +uml-docs
  '(:groups (("uml" "UML" (plantuml-mode) plantuml-mode-map)))
  "How the cheat sheet documents this module; see `+docs--module-docs'.")

(defvar +uml-executable "plantuml"
  "The PlantUML command. It is asked for its own picoweb server.")

(defvar +uml-server-port 8135
  "Where the PlantUML server listens. The first free port from here is used.")

(defvar +uml-server-start-timeout 30
  "Seconds to wait for the server. A first start loads a JVM.")

(defvar +uml-render-timeout 20
  "Seconds to wait for one diagram.")

(defvar +uml-preview-format 'svg
  "`svg' or `png'. SVG carries its own size and this Emacs reads it
through librsvg, so it stays sharp when the window changes.")

(defvar +uml-preview-theme 'auto
  "How the preview is coloured, so a diagram is readable against the theme.
`auto' follows the frame: dark theme, dark diagram with light text.
`light' leaves PlantUML's own colours, `dark' forces the dark palette,
and a string names a PlantUML theme, such as \"cyborg\" or \"carbon-gray\".
The file is never touched by this, and neither is what `SPC m e' writes.")

(defvar +uml-templates-dir
  (file-name-concat doom-user-dir "templates/uml/")
  "One file per kind of diagram; see `+uml-diagram-kinds'.")

(declare-function +uml--view-h "preview")


;;
;;; The mode

(after! plantuml-mode
  ;; Render through our own server rather than a JVM per diagram, which
  ;; is what lets the preview follow typing.
  (setq plantuml-executable-path (executable-find +uml-executable)
        plantuml-default-exec-mode 'executable
        plantuml-indent-level 2))

;; plantuml-mode's own autoload claims .pu, .uml, .plantuml, .pum and
;; .plu, and Doom's module adds no :mode at all. .puml, the extension
;; PlantUML's own documentation uses, is in neither list. .iuml is an
;; included fragment and .wsd is what the web editor saves.
(add-to-list 'auto-mode-alist
             '("\\.\\(puml\\|iuml\\|wsd\\)\\'" . plantuml-mode))

(add-hook 'plantuml-mode-hook #'+uml--view-h)

;; plantuml-mode completes through `plantuml-complete-symbol', an old
;; command that does the completing itself: run by the popup as you
;; type, it types the rest of a keyword unasked or shows the keywords in
;; a *Completions* window. The keywords are the popup's candidates
;; instead, and a word none of them starts goes on to the other sources.
;; The mode's own capf signals off a word and keeps those sources out.
(defvar plantuml-kwdList)

(defun +uml-completion-at-point ()
  "PlantUML's keywords for the word at point."
  (when-let* ((bounds (bounds-of-thing-at-point 'symbol)))
    (list (car bounds) (cdr bounds) plantuml-kwdList :exclusive 'no)))

(defun +uml--completion-h ()
  "Complete with `+uml-completion-at-point', not plantuml-mode's command."
  (setq-local completion-at-point-functions
              (cl-substitute #'+uml-completion-at-point 'plantuml-complete-symbol
                             completion-at-point-functions)))

(add-hook 'plantuml-mode-hook #'+uml--completion-h)

;; The server is not started ahead, with Emacs or with a frame, even when
;; diagrams are among the recent files: that held a JVM for the whole
;; session, diagram or not, to save the first preview a second or two.


;;
;;; The language server

;; plantuml-lsp completes keywords, directives, colours, skinparams and
;; the C4 standard library, and reports what `plantuml -syntax' finds.
;; It is early software, so it is asked for by name and everything works
;; without it: plantuml-mode's own completion stays underneath.
(after! eglot
  (add-to-list 'eglot-server-programs
               `(plantuml-mode
                 . ,(lambda (&rest _)
                      (when-let* ((server (executable-find "plantuml-lsp"))
                                  (exec (executable-find +uml-executable)))
                        (list server "-stdio" "-exec-path" exec))))))

(when (modulep! :tools lsp)
  (add-hook! 'plantuml-mode-local-vars-hook
    (defun +uml--lsp-h ()
      "Start the PlantUML server when there is one to start."
      (when (executable-find "plantuml-lsp") (lsp!)))))


;;
;;; Keybindings

(map! :after plantuml-mode
      :map plantuml-mode-map
      :localleader
      :desc "The preview's menu"    "SPC" #'+core/view-menu
      :desc "Preview, beside the text" "p" #'+core/view-toggle
      (:prefix ("P" . "preview")
       :desc "Draw it again now"    "r" #'+core/view-refresh
       :desc "Follow my typing, or not" "f" #'+core/view-follow-toggle
       :desc "Open it with every diagram, or not" "O" #'+core/view-on-open-toggle
       :desc "Draw as PNG or SVG"   "F" #'+uml/preview-format-toggle)
      :desc "New diagram"           "n" #'+uml/new-diagram
      :desc "Export to a file"      "e" #'+uml/export
      (:prefix ("s" . "server")
       :desc "Restart it"           "r" #'+uml/server-restart
       :desc "Stop it"              "k" #'+uml/server-stop
       :desc "What is running"      "i" #'+uml/server-status))
