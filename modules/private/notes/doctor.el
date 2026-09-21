;; -*- lexical-binding: t; no-byte-compile: t; -*-
;;; private/notes/doctor.el

(assert! (modulep! :lang org +roam)
         "This module needs (:lang org +roam)")
(assert! (modulep! :lang org +pretty)
         "This module needs (:lang org +pretty) for org-modern")

(unless (sqlite-available-p)
  (error! "org-roam needs an Emacs built with SQLite support"))

(dolist (tool '(("awk" . "org-fc indexes the cards with it")
                ("rg" . "makes org-roam and the searches much faster")
                ("fd" . "makes org-roam list its files faster")
                ("dot" . "graphviz, needed by the mind maps")
                ("pandoc" . "needed by the pandoc exporter")
                ("latexmk" . "needed to export to PDF")))
  (unless (executable-find (car tool))
    (warn! "Couldn't find %s: %s" (car tool) (cdr tool))))

(unless (modulep! :tools pdf)
  (warn! "Without (:tools pdf) papers open in DocView, which cannot annotate")
  (explain! "openSUSE: zypper in libpoppler-glib-devel, then enable :tools pdf"))

;; epdfinfo is pdf-tools' own program and comes with no package: it is
;; built once against poppler and then found on PATH.
(when (modulep! :tools pdf)
  (unless (executable-find "epdfinfo")
    (warn! "No epdfinfo, so PDFs open in DocView and cannot be annotated")
    (explain! "Run M-x pdf-tools-install once, with libpoppler-glib-devel installed")))

;; The jars, and the java that runs them. The module sets the classpath
;; to the directory that holds the whole set, since Doom's points at one
;; that holds part of it.
(when (modulep! :checkers grammar)
  (unless (executable-find "java")
    (warn! "No java, so LanguageTool cannot run")
    (explain! "openSUSE: zypper in java-25-openjdk-headless, or any JRE"))
  (unless (seq-some (lambda (dir)
                      (file-exists-p
                       (expand-file-name "languagetool-commandline.jar" dir)))
                    '("/usr/share/languagetool"
                      "/usr/share/java/languagetool"
                      "/usr/local/share/languagetool"))
    (warn! "No LanguageTool jars, so SPC n w c cannot check the grammar")
    (explain! "openSUSE: zypper in languagetool")))

;; Written out rather than read from `+core-notes-dir': a doctor file
;; runs in the CLI before any config has loaded, so the variable is not
;; there to ask. Keep the two in step.
(unless (file-directory-p (expand-file-name "~/org"))
  (warn! "~/org doesn't exist yet")
  (explain! "Run M-x +notes/bootstrap, or press SPC n d b"))
