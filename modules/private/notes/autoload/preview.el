;;; private/notes/autoload/preview.el -*- lexical-binding: t; -*-
;;
;; A look at the note a link points to without leaving this one: its
;; title, tags and place in the echo area as the cursor stops on the
;; link, and its first lines too in eldoc-box's popup, SPC c H.

(declare-function org-roam-node-from-id "org-roam-node")
(declare-function org-roam-node-from-title-or-alias "org-roam-node")
(declare-function org-roam-node-title "org-roam-node")
(declare-function org-roam-node-tags "org-roam-node")
(declare-function org-roam-node-file "org-roam-node")
(declare-function org-roam-node-point "org-roam-node")
(declare-function org-roam-node-level "org-roam-node")
(defvar org-link-bracket-re)

(defvar +notes-link-preview-lines 20
  "The most lines of the linked note the preview shows.")

(defvar +notes-link-preview-chars 1500
  "The most characters of the linked note the preview shows.")

(defvar +notes--link-preview-cache (make-hash-table :test #'equal)
  "(FILE . POINT) to (MTIME . TEXT): a node's excerpt, read again only
once its file has changed.")

(defun +notes--link-node ()
  "The node the id: or roam: link at point names, or nil.
Only the line around point is searched, so off a link this is cheap."
  (when (org-in-regexp org-link-bracket-re 1)
    (let ((path (match-string-no-properties 1)))
      (cond ((string-prefix-p "id:" path)
             (org-roam-node-from-id (substring path 3)))
            ((string-prefix-p "roam:" path)
             (org-roam-node-from-title-or-alias (substring path 5)))))))

(defun +notes--link-excerpt-1 (level start)
  "The text of the node at START of LEVEL in this buffer: the whole file
for a file node, the subtree below its heading for a heading node; no
property drawers and no #+ keywords, cut to the preview's size."
  (let* ((beg (if (zerop level)
                  (point-min)
                (goto-char start)
                (line-beginning-position 2)))
         (end (if (zerop level)
                  (point-max)
                (goto-char beg)
                (if (re-search-forward (format "^\\*\\{1,%d\\} " level) nil t)
                    (line-beginning-position)
                  (point-max))))
         (lines nil)
         (drawer nil))
    (dolist (line (split-string (buffer-substring-no-properties beg end) "\n"))
      (cond (drawer (when (string-match-p "\\`[ \t]*:END:[ \t]*\\'" line)
                      (setq drawer nil)))
            ((string-match-p "\\`[ \t]*:PROPERTIES:[ \t]*\\'" line) (setq drawer t))
            ((string-match-p "\\`[ \t]*#\\+[[:alnum:]_-]+:" line))
            ((and (null lines) (string-blank-p line)))
            (t (push line lines))))
    (let ((text (string-join (seq-take (nreverse lines) +notes-link-preview-lines) "\n")))
      (string-trim-right
       (if (> (length text) +notes-link-preview-chars)
           (substring text 0 +notes-link-preview-chars)
         text)))))

(defun +notes--link-excerpt (node)
  "The excerpt of NODE, from the cache while its file is unchanged."
  (let* ((file (org-roam-node-file node))
         (key (cons file (org-roam-node-point node)))
         (mtime (file-attribute-modification-time (file-attributes file)))
         (hit (gethash key +notes--link-preview-cache)))
    (if (and hit (equal (car hit) mtime))
        (cdr hit)
      (let ((text (with-temp-buffer
                    (insert-file-contents file)
                    (+notes--link-excerpt-1 (org-roam-node-level node)
                                            (org-roam-node-point node)))))
        (puthash key (cons mtime text) +notes--link-preview-cache)
        text))))

(defun +notes--link-head (node)
  "NODE's title, its tags as #tag, and its path in the vault, on one line."
  (string-join
   (delq nil (list (propertize (org-roam-node-title node) 'face 'bold)
                   (when-let* ((tags (org-roam-node-tags node)))
                     (propertize (mapconcat (lambda (tag) (concat "#" tag)) tags " ")
                                 'face 'org-tag))
                   (propertize (file-relative-name (org-roam-node-file node) org-roam-directory)
                               'face 'shadow)))
   "  "))

;;;###autoload
(defun +notes--link-eldoc (callback &rest _)
  "Describe the note the link at point names, for eldoc: CALLBACK gets the
title line and the note's first lines, the echo area the title line only.
Off a link, nil at once, so the other documentation functions answer."
  (when-let* ((node (+notes--link-node)))
    (let* ((head (+notes--link-head node))
           (body (+notes--link-excerpt node)))
      (funcall callback (if (string-empty-p body) head (concat head "\n" body))
               :echo head)
      t)))

;;;###autoload
(defun +notes--link-eldoc-setup-h ()
  "Preview links in this vault buffer, ahead of every other eldoc source."
  (add-hook 'eldoc-documentation-functions #'+notes--link-eldoc -100 t)
  (unless (bound-and-true-p eldoc-mode)
    (eldoc-mode 1)))
