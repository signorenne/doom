;;; private/notes/autoload/layout.el -*- lexical-binding: t; -*-
;;
;; The notes laid out in a workspace of their own: the note, given the
;; room, and the roam buffer at its right. SPC n h, again to put the roam
;; buffer away.

(defvar org-roam-buffer)
(defvar +sidebar-pinned-roots)
(declare-function org-roam-buffer-persistent-redisplay "org-roam-mode")
(declare-function +sidebar--window "../../sidebar/autoload/sidebar")
(declare-function +sidebar/quit "../../sidebar/autoload/sidebar")
(declare-function +workspace-current-name "workspaces")
(declare-function +workspace-switch "workspaces")
(declare-function +notes-daily-file "write")

(defvar +notes-layout-workspace "notes"
  "The workspace the notes layout lives in.")

(defun +notes--vault-buffer-p (buffer)
  "Non-nil when BUFFER visits a file of the vault."
  (when-let* ((file (buffer-file-name buffer)))
    (file-in-directory-p file org-roam-directory)))

(defun +notes--layout-shown-p ()
  "Non-nil when the roam buffer is in this frame."
  (get-buffer-window org-roam-buffer))

(defun +notes--layout-hide ()
  "Put the roam buffer away."
  (when-let* ((window (get-buffer-window org-roam-buffer)))
    (delete-window window)))

(defun +notes--layout-show ()
  "Show a note with the roam buffer, the side bar put away."
  (unless (+notes--vault-buffer-p (window-buffer))
    (switch-to-buffer (or (seq-find #'+notes--vault-buffer-p (buffer-list))
                          (find-file-noselect (+notes-daily-file)))))
  (let ((note (selected-window))
        (vault (file-name-as-directory (expand-file-name org-roam-directory))))
    ;; The note gets the side bar's room. Opened here by hand, the side
    ;; bar shows the vault whatever file is in front.
    (when (boundp '+sidebar-pinned-roots)
      (setf (alist-get +notes-layout-workspace +sidebar-pinned-roots nil nil #'equal)
            vault))
    (when (and (fboundp '+sidebar--window) (+sidebar--window))
      (+sidebar/quit))
    (select-window note)
    ;; Doom's popup rule puts the roam buffer at the right edge, slot 1.
    (display-buffer (get-buffer-create org-roam-buffer))
    (org-roam-buffer-persistent-redisplay)
    (select-window note)))

;;;###autoload
(defun +notes/layout ()
  "Lay the notes out in the workspace \"notes\": the note, and at its
right the roam buffer, which follows the note.  Run again there, put the
roam buffer away."
  (interactive)
  (require 'org-roam)
  (if (and (equal (+workspace-current-name) +notes-layout-workspace)
           (+notes--layout-shown-p))
      (+notes--layout-hide)
    (+workspace-switch +notes-layout-workspace t)
    (+notes--layout-show)))
