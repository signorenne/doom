;;; private/notes/autoload/layout.el -*- lexical-binding: t; -*-
;;
;; The notes laid out as a vault app shows them, in a workspace of their
;; own: the side bar at the left, the vault's tree above the note's
;; outline, the note, and the roam buffer at the right. SPC n h, again to
;; put them away.

(defvar org-roam-buffer)
(defvar +sidebar-pinned-roots)
(declare-function org-roam-buffer-persistent-redisplay "org-roam-mode")
(declare-function +sidebar--outline-open "../../sidebar/autoload/sections")
(declare-function +sidebar--window "../../sidebar/autoload/sidebar")
(declare-function +sidebar--show "../../sidebar/autoload/sidebar")
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
  "Non-nil when one of the layout's panels is in this frame."
  (or (get-buffer-window org-roam-buffer)
      (and (fboundp '+sidebar--window) (+sidebar--window))))

(defun +notes--layout-hide ()
  "Put the side bar and the roam buffer away."
  (when-let* ((window (get-buffer-window org-roam-buffer)))
    (delete-window window))
  (when (and (fboundp '+sidebar--window) (+sidebar--window))
    (+sidebar/quit)))

(defun +notes--layout-show ()
  "Show a note with the tree and its outline, and the roam buffer."
  (unless (+notes--vault-buffer-p (window-buffer))
    (switch-to-buffer (or (seq-find #'+notes--vault-buffer-p (buffer-list))
                          (find-file-noselect (+notes-daily-file)))))
  (let ((note (selected-window))
        (vault (file-name-as-directory (expand-file-name org-roam-directory))))
    ;; The tree on the vault, a project or not, and the note's outline
    ;; under it: the side bar's Explorer, pinned to the vault in this
    ;; workspace whatever file shows.
    (if (not (fboundp '+sidebar--show))
        (message "The notes layout's tree needs :private sidebar")
      (setf (alist-get +notes-layout-workspace +sidebar-pinned-roots nil nil #'equal)
            vault)
      (+sidebar--show 'explorer)
      (+sidebar--outline-open))
    (select-window note)
    ;; Doom's popup rule puts the roam buffer at the right edge, slot 1.
    (display-buffer (get-buffer-create org-roam-buffer))
    (org-roam-buffer-persistent-redisplay)
    (select-window note)))

;;;###autoload
(defun +notes/layout ()
  "Lay the notes out in the workspace \"notes\": the side bar at the left,
the vault's tree above the note's outline, the note, and at the right
the roam buffer, which follows the note.  Run again there, put them away."
  (interactive)
  (require 'org-roam)
  (if (and (equal (+workspace-current-name) +notes-layout-workspace)
           (+notes--layout-shown-p))
      (+notes--layout-hide)
    (+workspace-switch +notes-layout-workspace t)
    (+notes--layout-show)))
