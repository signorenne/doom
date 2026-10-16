;;; private/notes/autoload/documents.el -*- lexical-binding: t; -*-

(defvar +notes-documents)
(defvar +notes-directories)
(defvar +notes-knowledge-directories)
(declare-function org-id-new "org-id")
(defvar +notes-templates-dir)
(defvar +notes-bibliography)
(defvar-local +notes--writing-mode nil
  "Non-nil while `+notes/writing-mode' is on in this buffer.")

;;;###autoload
(defun +notes--ensure-directories ()
  "Create `org-directory' with `+notes-directories', and
`org-roam-directory' with `+notes-knowledge-directories'."
  (let ((root (expand-file-name org-directory))
        (graph (expand-file-name org-roam-directory)))
    (make-directory root t)
    (make-directory graph t)
    (dolist (dir +notes-directories)
      (make-directory (expand-file-name dir root) t))
    (dolist (dir +notes-knowledge-directories)
      (make-directory (expand-file-name dir graph) t))
    root))

(defun +notes--document-path (name)
  "Absolute path of the predefined document NAME."
  (let ((file (cdr (assoc name +notes-documents))))
    (unless file (user-error "Unknown document %S" name))
    (expand-file-name file org-directory)))

(defun +notes--create-document (name)
  "Create document NAME from its template if it doesn't exist.
Return its path when it was created, nil when it was already there."
  (let* ((path (+notes--document-path name))
         (template (expand-file-name (concat name ".org") +notes-templates-dir)))
    (unless (file-exists-p path)
      (make-directory (file-name-directory path) t)
      (with-temp-file path
        (if (file-exists-p template)
            (progn
              (insert-file-contents template)
              (goto-char (point-min))
              (while (search-forward "{{DATE}}" nil t)
                (replace-match (format-time-string "%Y-%m-%d") t t))
              ;; A document in the graph is a node, so it gets an ID.
              (require 'org-id)
              (goto-char (point-min))
              ;; org-id-new matches strings itself, so it runs before
              ;; the replacement, not inside it.
              (while (search-forward "{{ID}}" nil t)
                (let ((id (save-match-data (org-id-new))))
                  (replace-match id t t))))
          (insert (format "#+title: %s\n#+filetags: :%s:\n#+startup: overview\n\n"
                          (capitalize name) name))))
      path)))

;;;###autoload
(defun +notes-ensure-documents (&rest _)
  "Create the directories and any missing document.
Runs before `org-capture' writes to one, and other modules call it
before writing into the notes."
  (+notes--ensure-directories)
  (dolist (doc +notes-documents)
    (+notes--create-document (car doc))))

(defun +notes--create-bibliography ()
  "Create the empty BibTeX library citar reads, unless it exists.
Returns its path when it was created."
  (unless (file-exists-p +notes-bibliography)
    (make-directory (file-name-directory +notes-bibliography) t)
    (with-temp-file +notes-bibliography
      (insert "@Comment{The library citar reads. Paste BibTeX entries here;\n"
              "  SPC n B lists them, SPC m @ cites one.}\n"))
    +notes-bibliography))

;;;###autoload
(defun +notes/bootstrap ()
  "Create `org-directory', its subdirectories, any missing document and
the bibliography."
  (interactive)
  (+notes--ensure-directories)
  (let ((created (delq nil (append (mapcar (lambda (doc) (+notes--create-document (car doc)))
                                           +notes-documents)
                                   (list (+notes--create-bibliography))))))
    (message "%s ready%s. SPC n SPC opens the notes menu"
             (abbreviate-file-name org-directory)
             (if created
                 (format ", created %s"
                         (mapconcat #'file-name-nondirectory created ", "))
               ""))))

;;;###autoload
(defun +notes/open-document (name)
  "Open document NAME, creating it from its template when missing."
  (interactive
   (list (completing-read "Document: " (mapcar #'car +notes-documents) nil t)))
  (+notes--ensure-directories)
  (+notes--create-document name)
  (find-file (+notes--document-path name)))

;;;###autoload
(defun +notes/writing-mode ()
  "Toggle prose editing: zen mode and soft wrapping.  The font stays the
one everything else is written in; a proportional face moves the
tables and the indentation about."
  (interactive)
  (let ((on (not (bound-and-true-p +notes--writing-mode))))
    (setq-local +notes--writing-mode on)
    (visual-line-mode (if on +1 -1))
    ;; A minor mode called from Lisp with no argument turns itself on,
    ;; whatever it was, so zen never went off again: say which way.
    (when (fboundp '+zen/toggle)
      (+zen/toggle (if on +1 -1)))
    (message "Writing mode %s" (if on "on" "off"))))

;;
;;; Tables

;;;###autoload
(defun +notes/align-tables ()
  "Widen every table in this buffer until each column holds its text.
Org aligns the table under the cursor when you leave a cell; a file
written a row at a time, or edited by something that is not Org, ends up
with columns narrower than the words in them. This walks the file and
lines all of them up, separators included."
  (interactive nil org-mode)
  (unless (derived-mode-p 'org-mode)
    (user-error "Tables are aligned in an Org buffer"))
  (let ((tables 0))
    (save-excursion
      (org-table-map-tables (lambda () (cl-incf tables) (org-table-align)) t))
    (message "%d table%s aligned" tables (if (= tables 1) "" "s"))))
