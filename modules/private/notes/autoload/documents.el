;;; private/notes/autoload/documents.el -*- lexical-binding: t; -*-

(defvar +notes-documents)
(defvar +notes-knowledge-directories)
(defvar +notes-knowledge-dir)
(declare-function org-id-new "org-id")
(declare-function org-roam-db-sync "org-roam-db")
(declare-function +notes-repo-p "git")
(declare-function +notes/init-repo "git")
(defvar +notes-templates-dir)
(defvar-local +notes--writing-mode nil
  "Non-nil while `+notes/writing-mode' is on in this buffer.")

;;;###autoload
(defun +notes--ensure-directories ()
  "Create the vault, `org-directory', and the folders of
`+notes-knowledge-directories' in `+notes-knowledge-dir', the same folder."
  ;; The graph's root as set, not `org-roam-directory': a daily note's
  ;; capture binds that to the dailies' folder, and the whole tree was
  ;; made again inside capture/journal/.
  (let ((root (expand-file-name org-directory))
        (graph (expand-file-name +notes-knowledge-dir)))
    (make-directory root t)
    (make-directory graph t)
    (dolist (dir +notes-knowledge-directories)
      (make-directory (expand-file-name dir graph) t))
    root))

;;;###autoload
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
      ;; A document in the graph is a node, so it gets an ID.
      (require 'org-id)
      (with-temp-file path
        (if (file-exists-p template)
            (progn
              (insert-file-contents template)
              (goto-char (point-min))
              (while (search-forward "{{DATE}}" nil t)
                (replace-match (format-time-string "%Y-%m-%d") t t))
              (goto-char (point-min))
              ;; org-id-new matches strings itself, so it runs before
              ;; the replacement, not inside it.
              (while (search-forward "{{ID}}" nil t)
                (let ((id (save-match-data (org-id-new))))
                  (replace-match id t t))))
          (insert (format ":PROPERTIES:\n:ID: %s\n:END:\n#+title: %s\n#+filetags: :%s:\n#+startup: overview\n\n"
                          (org-id-new) (capitalize name) name))))
      path)))

;;;###autoload
(defun +notes-ensure-documents (&rest _)
  "Create the directories and any missing document.
Runs before `org-capture' writes to one, and other modules call it
before writing into the notes."
  (+notes--ensure-directories)
  (dolist (doc +notes-documents)
    (+notes--create-document (car doc))))

;;;###autoload
(defun +notes/bootstrap ()
  "Set up the vault: its folders, any missing document, and a git
repository when it is not one yet.  Run again, it changes nothing."
  (interactive)
  (+notes--ensure-directories)
  (let ((created (delq nil (mapcar (lambda (doc) (+notes--create-document (car doc)))
                                   +notes-documents)))
        (new-repo (not (+notes-repo-p))))
    (when new-repo
      (+notes/init-repo))
    ;; The documents are nodes; the finder knows them at once.
    (require 'org-roam)
    (org-roam-db-sync)
    (message "%s ready%s%s. SPC n SPC opens the notes menu"
             (abbreviate-file-name org-directory)
             (if created
                 (format ", created %s"
                         (mapconcat (lambda (file) (file-relative-name file org-directory))
                                    created ", "))
               "")
             (if new-repo ", now a git repository" ""))))

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
    ;; whatever it was, so zen would never go off again: say which way.
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
