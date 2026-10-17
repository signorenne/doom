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
  (explain! (if (featurep :system 'macos)
                "brew install poppler, then enable :tools pdf"
              "openSUSE: zypper in libpoppler-glib-devel, then enable :tools pdf")))

;; epdfinfo is pdf-tools' own program and comes with no package: it is
;; built once against poppler and then found on PATH.
(when (modulep! :tools pdf)
  (unless (executable-find "epdfinfo")
    (warn! "No epdfinfo, so PDFs open in DocView and cannot be annotated")
    (explain! (if (featurep :system 'macos)
                  "Run M-x pdf-tools-install once, with poppler installed: brew install poppler"
                "Run M-x pdf-tools-install once, with libpoppler-glib-devel installed"))))

;; The jars, and the java that runs them. The module sets the classpath
;; to the directory that holds the whole set, since Doom's points at one
;; that holds part of it. Where there is a languagetool command, Doom
;; runs that instead: Homebrew's on a Mac, which brings its own Java.
(when (modulep! :checkers grammar)
  (unless (seq-some #'executable-find '("languagetool-commandline" "languagetool"))
    (unless (executable-find "java")
      (warn! "No java, so LanguageTool cannot run")
      (explain! "openSUSE: zypper in java-25-openjdk-headless, or any JRE"))
    (unless (seq-some (lambda (dir)
                        (file-exists-p
                         (expand-file-name "languagetool-commandline.jar" dir)))
                      '("/usr/share/languagetool"
                        "/usr/share/java/languagetool"
                        "/usr/local/share/languagetool"))
      (warn! "No LanguageTool, so SPC n w c cannot check the grammar")
      (explain! (if (featurep :system 'macos)
                    "brew install languagetool"
                  "openSUSE: zypper in languagetool")))))

;; The CLI loads init.el, where the two are set, but no module config:
;; unset, both default to ~/org, as core and this module do.
(dolist (dir (delete-dups
              (list (bound-and-true-p +core-notes-dir)
                    (or (bound-and-true-p +notes-knowledge-dir)
                        (bound-and-true-p +core-notes-dir)))))
  (let ((dir (expand-file-name (or dir "~/org/"))))
    (unless (file-directory-p dir)
      (warn! "%s doesn't exist yet" (abbreviate-file-name dir))
      (explain! "Run M-x +notes/bootstrap, or press SPC n d b"))))
