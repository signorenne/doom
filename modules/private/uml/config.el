;;; private/uml/config.el -*- lexical-binding: t; -*-
;;
;; PlantUML: completion from a language server, a diagram beside the
;; text that follows your typing, and a template for each kind of
;; diagram this machine actually draws.
;;
;; Doom's :lang plantuml brings the mode and the flycheck checker. What
;; this adds is the rendering path, the preview, the server and the
;; templates.

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

(defvar +uml-preview-scale 1.0
  "How large the diagram is drawn in the preview.")

(defvar +uml-preview-side 'right
  "Which side the preview window takes.")

(defvar +uml-preview-width 0.5
  "How much of the frame the preview takes.")

(defvar +uml-preview-idle 0.4
  "Seconds of quiet before the preview is drawn again.")

(defvar +uml-preview-follow t
  "Whether the preview follows your typing. `SPC m p f' turns it off.")

(defvar +uml-preview-on-open t
  "Whether opening a diagram opens the preview beside it.
A diagram is something you look at while you write it, so the window
comes by itself rather than waiting to be asked for. Set this to nil
and `SPC m p' opens it when you want it.")

(defvar +uml-preview-buffer-name "*UML preview*"
  "The buffer the diagram is drawn in.")

(defvar +uml-templates-dir
  (file-name-concat doom-user-dir "templates/uml/")
  "One file per kind of diagram; see `+uml-diagram-kinds'.")

(declare-function +uml--preview-setup-h "preview")
(declare-function +uml--preview-open-h "preview")
(declare-function +uml--preview-follow-h "preview")


;;
;;; The mode

(after! plantuml-mode
  ;; Render through our own server rather than a JVM per diagram: the
  ;; first costs about a second, every one after it about 30 ms, which
  ;; is what lets the preview follow typing at all.
  (setq plantuml-executable-path (executable-find +uml-executable)
        plantuml-default-exec-mode 'executable
        plantuml-indent-level 2))

;; plantuml-mode's own autoload claims .pu, .uml, .plantuml, .pum and
;; .plu, and Doom's module adds no :mode at all. .puml, which is the
;; extension PlantUML's own documentation uses and every file here has,
;; is in neither list, so those files opened in fundamental-mode: no
;; keys, no completion, no preview. .iuml is an included fragment and
;; .wsd is what the web editor saves.
(add-to-list 'auto-mode-alist
             '("\\.\\(puml\\|iuml\\|wsd\\)\\'" . plantuml-mode))

(add-hook 'plantuml-mode-hook #'+uml--preview-setup-h)
(add-hook 'plantuml-mode-hook #'+uml--preview-open-h)


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
      :desc "Preview, beside the text" "p" #'+uml/preview-toggle
      :desc "Open it with the file, or not" "O" #'+uml/preview-on-open-toggle
      (:prefix ("P" . "preview")
       :desc "Open it"              "p" #'+uml/preview
       :desc "Draw it again now"    "r" #'+uml/preview-refresh
       :desc "Follow my typing"     "f" #'+uml/preview-follow-toggle
       :desc "PNG or SVG"           "F" #'+uml/preview-format-toggle)
      :desc "New diagram"           "n" #'+uml/new-diagram
      :desc "Export to a file"      "e" #'+uml/export
      (:prefix ("s" . "server")
       :desc "Restart it"           "r" #'+uml/server-restart
       :desc "Stop it"              "k" #'+uml/server-stop
       :desc "What is running"      "i" #'+uml/server-status))
