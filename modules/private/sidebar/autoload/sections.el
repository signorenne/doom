;;; private/sidebar/autoload/sections.el -*- lexical-binding: t; -*-
;;
;; The Explorer's other sections, as VS Code's: Open editors, the file
;; buffers of the project, above the tree; Outline, the symbols of the
;; file in the editor, and Timeline, its commits, below it. Each is
;; worked out only while it is open and the side bar on show; Outline
;; follows the editor's edits a second after they rest.

(require 'magit-section)
(declare-function +git-split-commit "../../git/autoload/split")
(defvar +sidebar-outline-delay)
(defvar +sidebar-timeline-count)
(defvar +sidebar--shown-root)

(defvar +sidebar--outline-source nil
  "The buffer whose edits Outline follows.")

(defvar +sidebar--outline-timer nil
  "The one-shot timer that redraws Outline after edits rest.")


;;
;;; Open editors

;;;###autoload
(defun +sidebar--insert-editors (root)
  "The file buffers under ROOT, the latest first, a star on a modified one."
  (magit-insert-section (+sidebar-editors nil t)
    (magit-insert-heading "Open editors")
    (magit-insert-section-body
      (dolist (buffer (buffer-list))
        (when-let* ((file (buffer-file-name buffer)))
          (when (file-in-directory-p file root)
            (magit-insert-section (+sidebar-editor buffer)
              (insert "  " (+sidebar--icon (file-name-nondirectory file))
                      (buffer-name buffer)
                      (if (buffer-modified-p buffer) (propertize " *" 'font-lock-face 'warning) "")
                      (let ((dir (directory-file-name
                                  (file-relative-name (file-name-directory file) root))))
                        (if (equal dir ".") ""
                          (concat " " (propertize dir 'font-lock-face 'shadow))))
                      "\n"))))))))


;;
;;; Outline

(defun +sidebar--outline-entries (index depth)
  "Sections for the imenu INDEX, DEPTH levels in."
  (dolist (entry index)
    (unless (equal (car entry) "*Rescan*")
      (if (imenu--subalist-p entry)
          (magit-insert-section (+sidebar-symbols (car entry))
            (magit-insert-heading
              (concat (make-string (* 2 depth) ?\s)
                      (propertize (substring-no-properties (car entry))
                          'font-lock-face 'font-lock-type-face)))
            (+sidebar--outline-entries (cdr entry) (1+ depth)))
        (magit-insert-section (+sidebar-symbol entry)
          (insert (make-string (* 2 depth) ?\s)
                  (propertize (substring-no-properties (car entry))
                              'font-lock-face 'font-lock-function-name-face)
                  "\n"))))))

;;;###autoload
(defun +sidebar--insert-outline (buffer)
  "The imenu outline of BUFFER, worked out when the section opens."
  (magit-insert-section (+sidebar-outline nil t)
    (magit-insert-heading "Outline")
    (magit-insert-section-body
      (let ((index (and (buffer-live-p buffer)
                        (with-current-buffer buffer
                          (ignore-errors
                            (let ((imenu-auto-rescan t))
                              (imenu--make-index-alist t)))))))
        (+sidebar--outline-follow buffer)
        (if (seq-remove (lambda (entry) (equal (car entry) "*Rescan*")) index)
            (+sidebar--outline-entries index 1)
          (insert (propertize "  No outline\n" 'font-lock-face 'shadow)))))))

(defun +sidebar--outline-changed-h (&rest _)
  "Redraw the Outline once the edits in its buffer rest."
  (unless (timerp +sidebar--outline-timer)
    (setq +sidebar--outline-timer
          (run-with-idle-timer (if-let* ((idle (current-idle-time)))
                                   (time-add idle +sidebar-outline-delay)
                                 +sidebar-outline-delay)
                               nil
                               (lambda ()
                                 (setq +sidebar--outline-timer nil)
                                 (if (+sidebar--explorer-open-p '(+sidebar-outline))
                                     (+sidebar--request 'explorer)
                                   ;; Folded since: stop following.
                                   (+sidebar--outline-follow nil)))))))

;;;###autoload
(defun +sidebar--outline-follow (buffer)
  "Follow BUFFER's edits for the Outline, and no other buffer's; nil
follows none."
  (unless (eq buffer +sidebar--outline-source)
    (when (buffer-live-p +sidebar--outline-source)
      (with-current-buffer +sidebar--outline-source
        (remove-hook 'after-change-functions #'+sidebar--outline-changed-h t)))
    (setq +sidebar--outline-source buffer)
    (when (buffer-live-p buffer)
      (with-current-buffer buffer
        (add-hook 'after-change-functions #'+sidebar--outline-changed-h nil t)))))


;;
;;; Timeline

;;;###autoload
(defun +sidebar--insert-timeline (buffer)
  "The commits of BUFFER's file, worked out when the section opens."
  (magit-insert-section (+sidebar-timeline nil t)
    (magit-insert-heading "Timeline")
    (magit-insert-section-body
      (let* ((file (and (buffer-live-p buffer) (buffer-file-name buffer)))
             (repo (and file (+sidebar--git-root (file-name-directory file))))
             (path (and repo (file-relative-name file repo)))
             (lines (and path
                         (let ((default-directory repo))
                           (ignore-errors
                             (process-lines "git" "log" "--follow"
                                            (format "-%d" +sidebar-timeline-count)
                                            "--format=%h%x00%ad%x00%an%x00%s"
                                            "--date=relative" "--" path))))))
        (if (not lines)
            (insert (propertize "  No history\n" 'font-lock-face 'shadow))
          (dolist (line lines)
            (pcase-let ((`(,hash ,date ,author ,subject) (split-string line "\0")))
              (magit-insert-section (+sidebar-revision (list hash path repo))
                (insert "  " subject " "
                        (propertize (concat date ", " author) 'font-lock-face 'shadow)
                        "\n")))))))))


;;
;;; Commands

;;;###autoload
(defun +sidebar--section-open (section)
  "Open SECTION of Open editors, Outline or Timeline in the editor
window; nil when it is none of those."
  (let ((value (oref section value)))
    (pcase (oref section type)
      ('+sidebar-editor
       (when (buffer-live-p value)
         (select-window (+sidebar--editor-window))
         (switch-to-buffer value))
       t)
      ('+sidebar-symbol
       (let ((buffer +sidebar--outline-source)
             (position (cdr value)))
         (when (buffer-live-p buffer)
           (select-window (+sidebar--editor-window))
           (switch-to-buffer buffer)
           (goto-char (if (overlayp position) (overlay-start position) position))))
       t)
      ('+sidebar-revision
       (pcase-let ((`(,hash ,path ,repo) value))
         (select-window (+sidebar--editor-window))
         (let ((default-directory repo))
           (+git-split-commit hash path)))
       t))))

(defun +sidebar--editor-at-point ()
  "The buffer of the Open editors entry at point, or an error."
  (let ((section (magit-current-section)))
    (unless (and section (eq (oref section type) '+sidebar-editor))
      (user-error "Only in Open editors"))
    (oref section value)))

;;;###autoload
(defun +sidebar/explorer-close ()
  "Kill the buffer of the Open editors entry at point; Emacs asks first
for a modified one."
  (interactive)
  (kill-buffer (+sidebar--editor-at-point))
  (+sidebar--request 'explorer))

;;;###autoload
(defun +sidebar/explorer-save ()
  "Save the buffer of the Open editors entry at point."
  (interactive)
  (with-current-buffer (+sidebar--editor-at-point)
    (save-buffer))
  (+sidebar--request 'explorer))

;;;###autoload
(defun +sidebar/outline ()
  "Show the Explorer with Outline open and point in it; with point there
already, close the side bar."
  (interactive)
  (let ((window (+sidebar--window)))
    (if (and window (eq window (selected-window))
             (eq (buffer-local-value '+sidebar--view (window-buffer window)) 'explorer)
             (let ((section (magit-current-section)))
               (and section
                    (seq-find (lambda (s) (eq (oref s type) '+sidebar-outline))
                              (cons section (magit-section-lineage section))))))
        (+sidebar--close)
      (+sidebar--show 'explorer t)
      (+sidebar--outline-open))))

;;;###autoload
(defun +sidebar--outline-open ()
  "Open the Explorer's Outline section and put point on it."
  (with-current-buffer (+sidebar--buffer 'explorer)
    (when-let* ((outline (and magit-root-section
                              (seq-find (lambda (s) (eq (oref s type) '+sidebar-outline))
                                        (oref magit-root-section children)))))
      (magit-section-show outline)
      (goto-char (oref outline start))
      (when-let* ((window (get-buffer-window (current-buffer))))
        (set-window-point window (point))
        (set-window-start window (point))))))
