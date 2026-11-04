;;; private/notes/autoload/layout.el -*- lexical-binding: t; -*-
;;
;; The notes laid out as a vault app shows them, in a workspace of their
;; own: the file tree at the left, the note, and at the right the roam
;; buffer above the note's outline. SPC n h, again to put them away.

(defvar org-roam-buffer)
(defvar imenu-list-buffer-name)
(defvar imenu-list-minor-mode)
(defvar +sidebar-pinned-roots)
(declare-function org-roam-buffer-persistent-redisplay "org-roam-mode")
(declare-function imenu-list-get-buffer-create "imenu-list")
(declare-function imenu-list-minor-mode "imenu-list")
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
      (get-buffer-window imenu-list-buffer-name)
      (and (fboundp '+sidebar--window) (+sidebar--window))))

(defvar imenu-list-auto-update)
(declare-function imenu-list-start-timer "imenu-list")
(declare-function imenu-list-stop-timer "imenu-list")

;; imenu-list's mode is global, and its idle timer indexes whatever
;; buffer is current, so while the layout is out the timer runs only when
;; an outline is in sight: a workspace switched to without one stops it,
;; one with an outline starts it again. Turning the mode off instead would
;; close every outline, in every frame.
(defun +notes--layout-outline-h (&rest _)
  "Run imenu-list's timer only while an outline shows in a visible frame."
  (cond ((not imenu-list-minor-mode)
         (remove-hook 'persp-activated-functions #'+notes--layout-outline-h))
        ((get-buffer-window imenu-list-buffer-name 'visible)
         (when imenu-list-auto-update
           (imenu-list-start-timer)))
        (t (imenu-list-stop-timer))))

(defun +notes--layout-hide ()
  "Put the tree, the roam buffer and the outline away."
  (dolist (name (list imenu-list-buffer-name org-roam-buffer))
    (when-let* ((window (get-buffer-window name)))
      (delete-window window)))
  ;; The mode is global and turning it off closes every outline, so it
  ;; goes off only when none is left in any frame, an iconified one too.
  (when (and imenu-list-minor-mode
             (not (get-buffer-window imenu-list-buffer-name t)))
    (imenu-list-minor-mode -1))
  (unless imenu-list-minor-mode
    (remove-hook 'persp-activated-functions #'+notes--layout-outline-h))
  (when (and (fboundp '+sidebar--window) (+sidebar--window))
    (+sidebar/quit)))

(defun +notes--layout-show ()
  "Show a note with the tree, the roam buffer and the outline around it."
  (unless (+notes--vault-buffer-p (window-buffer))
    (switch-to-buffer (or (seq-find #'+notes--vault-buffer-p (buffer-list))
                          (find-file-noselect (+notes-daily-file)))))
  (let ((note (selected-window))
        (vault (file-name-as-directory (expand-file-name org-roam-directory))))
    ;; The tree on the vault, a project or not: the side bar's Explorer,
    ;; pinned to the vault in this workspace whatever file shows.
    (if (not (fboundp '+sidebar--show))
        (message "The notes layout's tree needs :private sidebar")
      (setf (alist-get +notes-layout-workspace +sidebar-pinned-roots nil nil #'equal)
            vault)
      (+sidebar--show 'explorer))
    (select-window note)
    ;; Doom's popup rule puts the roam buffer at the right edge, slot 1.
    (display-buffer (get-buffer-create org-roam-buffer))
    (org-roam-buffer-persistent-redisplay)
    ;; imenu-list's own display splits the frame's root window, which
    ;; lands on the note once side windows are there, so the outline is
    ;; shown here, in the slot below the roam buffer. Doom's popup windows
    ;; hand a split to the first window that is not one, the tree, so
    ;; the roam buffer's window is split itself. Turning the mode on then
    ;; finds the outline shown and keeps it on the note.
    (let ((ignore-window-parameters t))
      (display-buffer-in-side-window (imenu-list-get-buffer-create)
                                     '((side . right) (slot . 2))))
    (imenu-list-minor-mode 1)
    (add-hook 'persp-activated-functions #'+notes--layout-outline-h)
    (select-window note)))

;;;###autoload
(defun +notes/layout ()
  "Lay the notes out in the workspace \"notes\": the vault's file tree at
the left, the note, and at the right the roam buffer, which follows the
note, above its outline.  Run again there, put the three away."
  (interactive)
  (require 'org-roam)
  (require 'imenu-list)
  (if (and (equal (+workspace-current-name) +notes-layout-workspace)
           (+notes--layout-shown-p))
      (+notes--layout-hide)
    (+workspace-switch +notes-layout-workspace t)
    (+notes--layout-show)))
