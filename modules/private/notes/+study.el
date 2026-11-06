;;; private/notes/+study.el -*- lexical-binding: t; -*-
;;
;; Working with sources: citations and reference notes (citar), spaced
;; repetition over headings (org-fc), transclusion into maps.

;; Citations: one .bib file, the PDFs beside it, and a reference note per
;; entry, so a citation in a note and the note about the paper are the same
;; thing. The .bib and the PDFs are the library's, apart from the vault;
;; the notes about them are in the vault.
(defvar +notes-library-dir "~/projects/personal/knowledge_base/"
  "The library of books and papers; init.el sets it.  Only citar reads it,
and nothing here creates anything in it.")

(defvar +notes-bibliography (file-name-concat +notes-library-dir "research/academic/references.bib")
  "The BibTeX library citar reads.")

;; Set before anything loads: Doom copies it into
;; `org-cite-global-bibliography' when oc loads with org, long before the
;; first citar command, so inside `after! citar' it would come too late.
(setq citar-bibliography (list +notes-bibliography))

(after! oc
  (setq org-cite-global-bibliography (list +notes-bibliography)))

(after! citar
  (setq citar-library-paths (list (file-name-concat +notes-library-dir "research/academic/papers"))
        citar-notes-paths (list (file-name-concat org-roam-directory "resources/sources/papers"))
        ;; Show what an entry has: a PDF, a note, a link.
        citar-symbol-separator "  "))

(after! citar-org-roam
  (setq citar-org-roam-subdir "resources/sources/papers"
        citar-org-roam-note-title-template "${author} :: ${title}"
        ;; R, not r: the same note, without the prompt for a source that
        ;; citar has already handed over.
        citar-org-roam-capture-template-key "R"))

;; Spaced repetition, over the notes you already wrote: a card is a heading
;; tagged :fc:, so there is no second pile of material to maintain. The
;; review schedule lives in the heading's properties, which means it is
;; versioned along with the notes.
(use-package! org-fc
  :defer t
  :init
  (setq org-fc-directories (list (expand-file-name org-directory)))
  ;; The package's autoloads load one of its files alone, org-fc-review
  ;; or org-fc-core, and only org-fc.el loads the rest: the awk indexer,
  ;; the card types, the algorithms, and with them the :config below and
  ;; the review keys. So every command loads org-fc, the card types'
  ;; included, which have no autoload of their own.
  (dolist (command '(org-fc-review org-fc-review-all org-fc-review-buffer
                     org-fc-review-quit org-fc-review-edit org-fc-dashboard
                     org-fc-update org-fc-update-all org-fc-help org-fc-demo
                     org-fc-suspend-card org-fc-suspend-tree
                     org-fc-suspend-buffer org-fc-suspend-region
                     org-fc-unsuspend-card org-fc-unsuspend-tree
                     org-fc-unsuspend-buffer org-fc-unsuspend-region
                     org-fc-type-normal-init org-fc-type-double-init
                     org-fc-type-text-input-init org-fc-type-cloze-init))
    (autoload command "org-fc" nil t))
  :config
  ;; The schedule travels in the headings; the rating log is one append
  ;; per review on each machine, which the shared repository would only
  ;; turn into a conflict, so it stays local.
  (setq org-fc-review-history-file
        (file-name-concat doom-data-dir "org-fc-reviews.tsv")))

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

;; The card dashboard is a popup that q and ESC close, not the whole
;; frame: org-fc shows it with `switch-to-buffer', which no popup rule
;; reaches unless told to obey them. Its keys, the ones its first lines
;; name, work in normal state too, where r and p did nothing and n
;; searched.
(set-popup-rule! "^\\*org-fc Dashboard\\*$" :side 'bottom :size 0.4 :select t :quit t :ttl nil)

(defvar org-fc-dashboard-mode-map)
(declare-function org-fc-contexts "org-fc-core")
(declare-function org-fc-dashboard-section-next "org-fc-dashboard")
(declare-function org-fc-dashboard-section-previous "org-fc-dashboard")
(declare-function org-fc-dashboard-section-toggle "org-fc-dashboard")

(defadvice! +notes--fc-dashboard-popup-a (fn &rest args)
  "Show the card dashboard through its popup rule."
  :around #'org-fc-dashboard
  (let ((switch-to-buffer-obey-display-actions t))
    (apply fn args)))

(after! (evil org-fc-dashboard)
  (evil-define-key* '(normal motion) org-fc-dashboard-mode-map
    "r" #'org-fc-dashboard-review
    "n" #'org-fc-dashboard-section-next
    "p" #'org-fc-dashboard-section-previous
    "q" #'quit-window
    (kbd "TAB") #'org-fc-dashboard-section-toggle))

;; The review context is asked by name, and marginalia took all for the
;; Lisp function of that name: each is said in words instead.
(defun +notes--fc-context-annotation (name)
  "What the review context NAME holds, in words."
  (pcase name
    ("all" "  every card in the notes")
    ("buffer" "  the cards of this buffer")
    (_ (when-let* ((context (alist-get (intern-soft name) (org-fc-contexts))))
         (format "  the cards of %s" (plist-get context :paths))))))

(defadvice! +notes--fc-context-words-a (fn &rest args)
  "Ask for a review context with what each holds beside it."
  :around #'org-fc-select-context
  (let ((completion-extra-properties
         (list :category '+notes-fc-context
               :annotation-function #'+notes--fc-context-annotation)))
    (apply fn args)))

;; org-noter loads its EPUB and DjVu modules when their modes are in this
;; list, and each said ATTENTION in the echo area, at the first capture,
;; for a package not installed. Only those installed are listed.
(after! org-noter-core
  (setq org-noter-supported-modes
        (seq-filter (lambda (mode)
                      (pcase mode
                        ('nov-mode (locate-library "nov"))
                        ('djvu-read-mode (locate-library "djvu"))
                        (_ t)))
                    org-noter-supported-modes)))

;; org-fc makes a card's algorithm with an empty list for an argument,
;; which EIEIO takes for an object name, obsolete, and said so in the
;; echo area for every card made. It is made without one.
(defun +notes--fc-constructor-a (constructor)
  "CONSTRUCTOR, without the name org-fc gives it."
  (lambda (&rest slots)
    (apply constructor (if (equal slots '(nil)) nil slots))))

(advice-add 'org-fc-algo-constructor :filter-return #'+notes--fc-constructor-a)

;; Transclusion: a map can show what it links to, rather than only naming it.
;; The text stays in its own note; in the map it is read only, and
;; #+transclude lines are what is saved.
(use-package! org-transclusion
  :defer t
  :config
  (setq org-transclusion-include-first-section t
        org-transclusion-exclude-elements '(property-drawer keyword)))
