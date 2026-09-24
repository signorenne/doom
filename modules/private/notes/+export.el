;;; private/notes/+export.el -*- lexical-binding: t; -*-
;;
;; How org looks, and what it turns into: org-modern and friends, mind
;; maps, the exporters, LaTeX, PlantUML.

;; Makes org-modern's block borders line up under `org-indent-mode'.
(use-package! org-modern-indent
  :hook (org-mode . org-modern-indent-mode))

;; Turning `org-indent-mode' on does not indent anything: it puts the
;; buffer on a queue and an idle timer a fifth of a second later indents
;; it in slices. So a note opens flat and then visibly reflows under the
;; cursor, which is worst where you meet many notes quickly, stepping
;; through `SPC n r f'.
;;
;; Doing it at once costs 0.5 ms for a note and 90 ms for the cheat
;; sheet, so it is done at once up to a size and left to the agent past
;; it. The largest note here is 4 KB; the only org files over the limit
;; are the sheet and the audits.
(defvar +notes-indent-at-once-max (* 40 1024)
  "The largest buffer indented as soon as it opens, in characters.
Past this `org-indent-mode' is left to its idle agent, which reflows
visibly but does not hold up the window.")

(add-hook! 'org-mode-hook :append
  (defun +notes--indent-at-once-h ()
    "Indent the buffer now rather than a fifth of a second from now."
    (when (and (bound-and-true-p org-indent-mode)
               (< (buffer-size) +notes-indent-at-once-max))
      (org-indent-indent-buffer))))

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
