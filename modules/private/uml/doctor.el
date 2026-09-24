;; -*- lexical-binding: t; no-byte-compile: t; -*-
;;; private/uml/doctor.el

(assert! (modulep! :lang plantuml)
         "This module builds on (:lang plantuml): enable it")

;; plantuml renders, and serves its own picoweb server for the preview.
(unless (executable-find "plantuml")
  (error! "No plantuml: nothing can be rendered")
  (explain! "openSUSE: zypper in plantuml"))

;; PlantUML is a Java program whichever way it is installed.
(unless (executable-find "java")
  (warn! "No java, so plantuml cannot run")
  (explain! "openSUSE: zypper in java-25-openjdk-headless, or any JRE"))

;; Most diagram kinds are laid out by graphviz. Sequence and timing
;; diagrams are not, which is why a broken install looks like "some
;; diagrams work".
(unless (executable-find "dot")
  (warn! "No dot: class, state, component and C4 diagrams cannot be laid out")
  (explain! "openSUSE: zypper in graphviz"))

;; The language server is optional on purpose: without it the mode's own
;; completion stays, so this is a note about what is missing rather than
;; something broken.
(unless (executable-find "plantuml-lsp")
  (warn! "No plantuml-lsp: no completion for keywords, colours or the C4 library")
  (explain! "go install github.com/ptdewey/plantuml-lsp@latest, "
            "then link ~/go/bin/plantuml-lsp into ~/.local/bin"))
