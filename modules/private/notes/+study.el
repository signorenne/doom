;;; private/notes/+study.el -*- lexical-binding: t; -*-
;;
;; Working with sources: citations and reference notes (citar), spaced
;; repetition over headings (org-fc), transclusion into maps.

;; Citations: one .bib file, the PDFs beside it, and a reference note per
;; entry, so a citation in a note and the note about the paper are the same
;; thing.
(defvar +notes-bibliography (file-name-concat org-directory "refs.bib")
  "The BibTeX library citar reads.")

;; Set before anything loads: Doom copies it into
;; `org-cite-global-bibliography' when oc loads with org, long before the
;; first citar command, so inside `after! citar' it came too late.
(setq citar-bibliography (list +notes-bibliography))

(after! oc
  (setq org-cite-global-bibliography (list +notes-bibliography)))

(after! citar
  (setq citar-library-paths (list (file-name-concat org-directory "papers"))
        citar-notes-paths (list (file-name-concat org-roam-directory "refs"))
        ;; Show what an entry has: a PDF, a note, a link.
        citar-symbol-separator "  "))

(after! citar-org-roam
  (setq citar-org-roam-subdir "refs"
        citar-org-roam-note-title-template "${author} :: ${title}"
        ;; R, not r: the same note, without the prompt for a source that
        ;; citar has already handed over. See `org-roam-capture-templates'.
        citar-org-roam-capture-template-key "R"))

;; Spaced repetition, over the notes you already wrote: a card is a heading
;; tagged :fc:, so there is no second pile of material to maintain. The
;; review schedule lives in the heading's properties, which means it is
;; versioned along with the notes.
(use-package! org-fc
  :defer t
  :init
  (setq org-fc-directories (list (expand-file-name org-directory)))
  :config
  ;; The schedule travels in the headings; the rating log is one append
  ;; per review on each machine, which the shared repository would only
  ;; turn into a conflict, so it stays local.
  (setq org-fc-review-history-file
        (file-name-concat doom-data-dir "org-fc-reviews.tsv"))
  (require 'org-fc-hydra nil t))

;; org-fc's review keys live in minor mode maps, which evil's normal state
;; would otherwise win over: RET would follow a link instead of flipping.
;; Minor mode keys need evil's own API, and a normalize when the mode flips.
(after! (evil org-fc)
  (evil-define-minor-mode-key '(normal visual) 'org-fc-review-flip-mode
    (kbd "RET") #'org-fc-review-flip
    (kbd "n")   #'org-fc-review-flip
    (kbd "s")   #'org-fc-review-suspend-card
    (kbd "p")   #'org-fc-review-edit
    (kbd "q")   #'org-fc-review-quit)
  (evil-define-minor-mode-key '(normal visual) 'org-fc-review-rate-mode
    (kbd "a") #'org-fc-review-rate-again
    (kbd "h") #'org-fc-review-rate-hard
    (kbd "g") #'org-fc-review-rate-good
    (kbd "e") #'org-fc-review-rate-easy
    (kbd "s") #'org-fc-review-suspend-card
    (kbd "p") #'org-fc-review-edit
    (kbd "q") #'org-fc-review-quit)
  (add-hook 'org-fc-review-flip-mode-hook #'evil-normalize-keymaps)
  (add-hook 'org-fc-review-rate-mode-hook #'evil-normalize-keymaps))

;; Transclusion: a map can show what it links to, rather than only naming it.
;; The text stays in its own note; here it is read only, and #+transclude
;; lines are what is saved.
(use-package! org-transclusion
  :defer t
  :config
  (setq org-transclusion-include-first-section t
        org-transclusion-exclude-elements '(property-drawer keyword)))
