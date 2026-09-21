;;; private/notes/+export.el -*- lexical-binding: t; -*-
;;
;; How org looks, and what it turns into: org-modern and friends, mind
;; maps, the exporters, LaTeX, PlantUML.

;; Makes org-modern's block borders line up under `org-indent-mode'.
(use-package! org-modern-indent
  :hook (org-mode . org-modern-indent-mode))

(use-package! org-fragtog
  :hook (org-mode . org-fragtog-mode))

(after! org-modern
  (setq org-modern-star 'replace
        org-modern-table nil            ; keep tables plain and editable
        org-modern-block-fringe nil))   ; org-modern-indent draws the blocks

(after! org-appear
  (setq org-appear-autolinks t
        org-appear-autoentities t
        org-appear-autosubmarkers t))


;; org-mind-map defines an export backend when it loads and requires only
;; org, so its file fails to load until something else has loaded ox.
;; Anything that asks whether one of its commands is a command loads the
;; file (interactive-form autoloads), a menu listing it included, so an
;; advice on the commands is too late: ox comes with org, as Doom's own
;; biblio module does with oc-csl.
(after! org
  (require 'ox))

(use-package! org-mind-map
  :defer t
  :config
  (setq org-mind-map-engine "dot"
        org-mind-map-include-text t
        org-mind-map-default-graph-attribs
        '(("autosize" . "false") ("size" . "9,12") ("resolution" . "100")
          ("nodesep" . "0.75") ("overlap" . "false") ("spline" . "true")
          ("rankdir" . "LR"))))

(after! ox
  (require 'ox-gfm nil t)
  ;; ox-extra (ignore-headlines) and the KOMA letter class from org-contrib.
  (when (require 'ox-extra nil t)
    (ox-extras-activate '(ignore-headlines)))
  (require 'ox-koma-letter nil t))

(after! ox-latex
  ;; Source blocks go through listings, which needs its two packages
  ;; declared here; nothing runs external programs, so no -shell-escape.
  (setq org-latex-pdf-process
        '("latexmk -pdf -interaction=nonstopmode -output-directory=%o %f")
        org-latex-src-block-backend 'listings)
  (dolist (pkg '(("" "listings") ("" "color")))
    (add-to-list 'org-latex-packages-alist pkg t)))

(after! plantuml-mode
  (setq plantuml-executable-path (executable-find "plantuml")
        plantuml-default-exec-mode 'executable))
