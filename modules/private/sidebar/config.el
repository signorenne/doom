;;; private/sidebar/config.el -*- lexical-binding: t; -*-
;;
;; A side bar on the left, as VS Code has one: a window that shows one
;; view at a time, switched with H and L or a click on its header. The
;; Explorer is the project's file tree, kept up as files change, with
;; the file operations, under the open file buffers and above the file's
;; outline and history; it took the places of treemacs (SPC o p, SPC e t)
;; and imenu-list (SPC t o). The
;; Source Control view lists the staged and the changed files and the
;; latest commits, and stages and commits with magit's keys; opening a
;; change shows it in place or beside its old version (the git module's
;; views). Everything in it works from the keyboard, evil first.

(defvar +sidebar-views
  '((explorer "Explorer" +sidebar-explorer-mode +sidebar--explorer-render)
    (scm "Source Control" +sidebar-scm-mode +sidebar--scm-render))
  "The side bar's views, in the order H and L step through them: (KEY
LABEL MODE RENDER), RENDER drawing the view in its buffer.")

(defvar +sidebar-width 32
  "Columns of the side bar.")

(defvar +sidebar-refresh-delay 0.3
  "Seconds of rest before the side bar redraws after a change.")

(defvar +sidebar-scm-commits 20
  "How many of the latest commits Source Control lists.")

(defvar +sidebar-outline-delay 1.0
  "Seconds after the last edit before the Explorer's Outline is redrawn.")

(defvar +sidebar-timeline-count 50
  "How many commits of the file the Explorer's Timeline lists.")

(defvar +sidebar-icons t
  "Non-nil for file icons in the side bar.")

(defvar +sidebar-pinned-roots nil
  "Workspace name to the directory the side bar shows there, whatever
file the editor shows; the notes layout pins its vault.")

(defface +sidebar-modified '((t :inherit diff-changed :background unspecified))
  "A file changed since the index, or a folder that holds one."
  :group 'vc)

(defface +sidebar-added '((t :inherit diff-added :background unspecified))
  "A file new to the repository, staged."
  :group 'vc)

(defface +sidebar-untracked '((t :inherit diff-added :background unspecified))
  "A file git does not track yet."
  :group 'vc)

(defface +sidebar-deleted '((t :inherit diff-removed :background unspecified))
  "A file deleted."
  :group 'vc)

(defface +sidebar-conflict '((t :inherit error))
  "A file with a merge conflict."
  :group 'vc)

(defface +sidebar-ignored '((t :inherit shadow))
  "A file or folder git ignores."
  :group 'vc)

(defface +sidebar-tab '((t :inherit shadow))
  "A view's name in the side bar's header."
  :group 'vc)

(defface +sidebar-tab-current '((t :inherit bold))
  "The name of the view on show in the side bar's header."
  :group 'vc)

(defvar +sidebar-docs
  '(:groups (("sidebar" "Side bar" nil +sidebar-explorer-mode-map +sidebar-scm-mode-map))
    :sections ((+sidebar-explorer-mode . "Side bar")
               (+sidebar-scm-mode . "Side bar")))
  "How the cheat sheet documents this module; see `+docs--module-docs'.")

;; s and S stage, as in magit; evil-snipe leaves magit-mode's buffers
;; alone, and these derive from magit-section-mode, not magit-mode.
(after! evil-snipe
  (add-to-list 'evil-snipe-disabled-modes '+sidebar-scm-mode)
  (add-to-list 'evil-snipe-disabled-modes '+sidebar-explorer-mode))

;; The Explorer points at the file the editor shows.
(add-hook '+sidebar-editor-changed-functions #'+sidebar--explorer-follow-h)


;;
;;; Keybindings

(map! :leader
      (:prefix "g"
       :desc "Source Control side bar" "e" #'+sidebar/source-control)
      (:prefix "o"
       :desc "Explorer side bar"        "p" #'+sidebar/explorer
       :desc "This file in the Explorer" "P" #'+sidebar/reveal)
      (:prefix ("e" . "explorer")
       :desc "Side bar on or off"       "t" #'+sidebar/toggle)
      (:prefix "t"
       :desc "The outline of this buffer" "o" #'+sidebar/outline))
