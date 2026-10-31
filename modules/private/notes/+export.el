;;; private/notes/+export.el -*- lexical-binding: t; -*-
;;
;; How org looks, and what it turns into: org-modern and friends, mind
;; maps, the exporters, LaTeX, PlantUML.

;; What the first org buffer turns on, loaded in the background after org
;; as Doom loads org itself: org-modern and its friends, and gptel, which
;; Doom's llm module sets up in every org buffer for its source blocks.
;; The first org file then opens without waiting for them.
(doom-load-packages-incrementally
 '(org-indent org-modern org-modern-indent org-appear evil-org toc-org
   org-fragtog org-eldoc gptel gptel-org))

;; Makes org-modern's block borders line up under `org-indent-mode'.
(use-package! org-modern-indent
  :hook (org-mode . org-modern-indent-mode))

;; Turning `org-indent-mode' on does not indent anything: it puts the
;; buffer on a queue and an idle timer a fifth of a second later indents
;; it in slices. So a note opens flat and then visibly reflows under the
;; cursor, which is worst where you meet many notes quickly, stepping
;; through `SPC n r f'.
;;
;; Doing it at once is cheap for a note but not for a large file, so it
;; is done at once up to a size and left to the agent past it.
(defvar +notes-indent-at-once-max (* 40 1024)
  "The largest buffer indented as soon as it opens, in characters.
Past this `org-indent-mode' is left to its idle agent, which reflows
visibly but does not hold up the window.")

(add-hook! 'org-mode-hook :append
  (defun +notes--indent-at-once-h ()
    "Indent the buffer now rather than a fifth of a second from now."
    (when (and (bound-and-true-p org-indent-mode)
               (< (buffer-size) +notes-indent-at-once-max))
      ;; Not `org-indent-indent-buffer', which says "Setting buffer
      ;; indentation" and then "Indentation of buffer set" every time,
      ;; so every note opened would flash two messages. And the buffer
      ;; comes off the agent's queue, or it is indented again a moment
      ;; later for nothing.
      (org-indent-add-properties (point-min) (point-max))
      (setq org-indent-agentized-buffers
            (delq (current-buffer) org-indent-agentized-buffers))
      ;; What the agent runs once it has done a buffer: org-modern-indent
      ;; waits for it to draw the blocks, and a buffer taken off the queue
      ;; would never get it.
      (run-hook-with-args 'org-indent-post-buffer-init-functions (current-buffer)))))

;; Org looks for LaTeX to colour with no bound on the search: from the
;; line being coloured to the next fragment, which in a file with few is
;; its end, and it throws away what it finds past the region anyway.
;; The search stops a few kilobytes past the region, enough for a
;; fragment that starts in it to end.
(defvar +notes-latex-reach 4096
  "How far past the region being coloured org looks for LaTeX, in characters.")

(defadvice! +notes--latex-within-reach-a (fn limit)
  "Look for LaTeX no further than `+notes-latex-reach' past LIMIT."
  :around #'org-do-latex-and-related
  (save-restriction
    (narrow-to-region (point-min) (min (point-max) (+ limit +notes-latex-reach)))
    (funcall fn limit)))

(use-package! org-fragtog
  :hook (org-mode . org-fragtog-mode))

(after! org-modern
  (setq org-modern-star 'replace
        org-modern-table nil            ; keep tables plain and editable
        org-modern-block-fringe nil))   ; org-modern-indent draws the blocks

;; Callouts: a #+begin_warning block, or note, tip, important, caution,
;; with a title after the kind if wanted. Org gives a special block no
;; face of its kind and sets its delimiter lines' face outright, so the
;; kind's face is laid over the begin and end lines; the body is text as
;; any other. Export is Org's own: <div class="warning"> in HTML.
(defvar +notes-callout-types '("note" "tip" "important" "warning" "caution")
  "The kinds of callout block, each a #+begin_KIND block drawn in the face
+notes-callout-KIND.")

(defface +notes-callout-note '((t :inherit font-lock-function-name-face :weight bold))
  "The begin and end lines of a note callout."
  :group 'org-faces)
(defface +notes-callout-tip '((t :inherit success :weight bold))
  "The begin and end lines of a tip callout."
  :group 'org-faces)
(defface +notes-callout-important '((t :inherit font-lock-keyword-face :weight bold))
  "The begin and end lines of an important callout."
  :group 'org-faces)
(defface +notes-callout-warning '((t :inherit warning :weight bold))
  "The begin and end lines of a warning callout."
  :group 'org-faces)
(defface +notes-callout-caution '((t :inherit error :weight bold))
  "The begin and end lines of a caution callout."
  :group 'org-faces)

(defvar org-structure-template-alist)

(defvar +notes--callout-re nil
  "(KINDS . REGEXP): the begin and end lines of a callout of KINDS, the
kind in group 1, made again when `+notes-callout-types' changes.")

(defun +notes--callout-match (limit)
  "Find the next begin or end line of a callout before LIMIT, in any case:
Org's font lock tells case apart, and #+BEGIN_WARNING is a callout too."
  (unless (eq (car +notes--callout-re) +notes-callout-types)
    (setq +notes--callout-re
          (cons +notes-callout-types
                (concat "^[ \t]*#\\+\\(?:begin\\|end\\)_\\("
                        (regexp-opt +notes-callout-types) "\\)\\(?:[ \t].*\\)?$"))))
  (let ((case-fold-search t))
    (re-search-forward (cdr +notes--callout-re) limit t)))

(defun +notes--callout-face ()
  "The face of the callout just matched, nil for a kind with none."
  (let ((face (intern-soft (concat "+notes-callout-" (downcase (match-string 1))))))
    (and (facep face) face)))

;; After Org's keywords, not among them: org-modern moves Org's block
;; fontifier behind its own, and that fontifier sets a delimiter line's
;; face outright, so a keyword among Org's would be undone. Added once:
;; font-lock adds a mode's keywords again every time it is asked.
(let ((keywords '((+notes--callout-match (0 (+notes--callout-face) prepend)))))
  (unless (assoc keywords (cdr (assq 'org-mode font-lock-keywords-alist)))
    (font-lock-add-keywords 'org-mode keywords 'append)))

;; C-c C-, then the kind's letter, in capitals: the lower n is
;; org-re-reveal's speaker notes. A key already taken is left alone.
(after! org
  (pcase-dolist (`(,key . ,kind) '(("N" . "note") ("T" . "tip") ("I" . "important")
                                   ("W" . "warning") ("X" . "caution")))
    (unless (assoc key org-structure-template-alist)
      (add-to-list 'org-structure-template-alist (cons key kind) t))))

(after! org-appear
  (setq org-appear-autolinks t
        org-appear-autoentities t
        org-appear-autosubmarkers t))


;; org-mind-map defines an export backend when it loads and requires only
;; org, so its file fails to load until something else has loaded ox.
;; Anything that asks whether one of its commands is a command loads the
;; file (interactive-form autoloads), a menu listing it included. So its
;; commands are commands of their own until it loads, which load ox and
;; it, then run the real one: ox waits for the first export instead of
;; coming with org and slowing its load.
(unless (featurep 'org-mind-map)
  (dolist (command '(org-mind-map-write org-mind-map-write-current-tree
                     org-mind-map-write-current-branch))
    (let (stub)
      (setq stub (lambda ()
                   (interactive)
                   (require 'ox)
                   (require 'org-mind-map)
                   (if (eq (symbol-function command) stub)
                       (user-error "org-mind-map did not define %s" command)
                     (call-interactively command))))
      (defalias command stub
        "Load ox and org-mind-map, then run the command of this name."))))

;; Doom's biblio module loads oc-csl, and citeproc with it, with org,
;; which slows org's first load. Org loads a citation processor itself
;; the first time an export or a follow needs it
;; (`org-cite-try-load-processor'); Doom loads it early only to keep it
;; out of its own piecemeal loading of org, which is over by then. So
;; Doom's entry is taken out of what runs as org loads.
(unless (featurep 'org)
  (setf (alist-get 'org after-load-alist)
        (seq-remove (lambda (fn) (string-match-p "oc-csl" (prin1-to-string fn)))
                    (alist-get 'org after-load-alist))))

;; Neither `use-package!' nor `after!': compiling either loads the
;; package to learn its names, and org-mind-map does not load without ox,
;; so compiling this file would warn "Cannot load org-mind-map".
(defvar org-mind-map-engine)
(defvar org-mind-map-include-text)
(defvar org-mind-map-default-graph-attribs)
(with-eval-after-load 'org-mind-map
  (setq org-mind-map-engine "dot"
        org-mind-map-include-text t
        org-mind-map-default-graph-attribs
        '(("autosize" . "false") ("size" . "9,12") ("resolution" . "100")
          ("nodesep" . "0.75") ("overlap" . "false") ("spline" . "true")
          ("rankdir" . "LR")))
  (advice-add 'org-mind-map-default-filename :around #'+notes--mind-map-file-a))

;; A note's mind map is drawn again whenever it is wanted, so it goes into
;; the vault's .cache/maps/, which git ignores, named for the note's file,
;; and the tree's heading after it; not beside the note, where it was
;; committed with it.
(defun +notes--mind-map-file-a (fn treenamep)
  "The vault's .cache/maps/ for the map org-mind-map names with FN."
  (let ((name (funcall fn treenamep))
        (file (buffer-file-name (buffer-base-buffer))))
    (if (not (and file (file-in-directory-p file org-directory)))
        name
      (let ((dir (expand-file-name ".cache/maps/" org-directory)))
        (make-directory dir t)
        (expand-file-name (concat (file-name-base file)
                                  (and (string-match "_diagram\\(-.*\\)?\\'" name)
                                       (match-string 1 name)))
                          dir)))))

(after! ox
  (require 'ox-gfm nil t)
  ;; ox-extra (ignore-headlines) and the KOMA letter class from org-contrib.
  (when (require 'ox-extra nil t)
    (ox-extras-activate '(ignore-headlines)))
  (require 'ox-koma-letter nil t))

(after! ox-latex
  ;; Source blocks go through listings, which needs its two packages
  ;; declared; nothing runs external programs, so no -shell-escape.
  (setq org-latex-pdf-process
        '("latexmk -pdf -interaction=nonstopmode -output-directory=%o %f")
        org-latex-src-block-backend 'listings)
  (dolist (pkg '(("" "listings") ("" "color")))
    (add-to-list 'org-latex-packages-alist pkg t)))

(after! plantuml-mode
  (setq plantuml-executable-path (executable-find "plantuml")
        plantuml-default-exec-mode 'executable))
