;;; $DOOMDIR/config.el -*- lexical-binding: t; -*-
;;
;; Loaded after Doom and every module. This file holds only identity and
;; look and feel; the rest is in the private modules. The keybinding
;; reference is on SPC h / and F12.

;;
;;; Identity

(setq user-full-name "Nicolò Plebani"
      user-mail-address "nicolo@nexenne.com")   ; org export, magit, mail

;; How you would like to be called. The dashboard spells the first out
;; in the letters of its font, as a banner; the butler calls you the
;; second, in the greeting of the hour and in every word he has for you.
(setq +ui-banner-name "signorenne"
      +butler-address "sir")


;;
;;; Fonts and theme

;; On macOS the theme is a dark and light pair that follows the system
;; appearance: Doom picks one at startup, and Emacs+ reports each change.
;; Elsewhere it is the dark one. The pair has its own variable because
;; Doom sets `doom-theme' to the one it loads.
(defvar +config-themes '(nexenne-night . nexenne-day)
  "The dark theme and the light one, worn as a Mac's appearance says.
The config's own, in themes/: made for long reading, measured for it.")

(setq doom-theme (if (featurep :system 'macos) +config-themes (car +config-themes))
      doom-font (font-spec :family "JetBrains Mono" :size 15)
      doom-variable-pitch-font (font-spec :family "DejaVu Sans" :size 16)
      doom-big-font (font-spec :family "JetBrains Mono" :size 24) ; SPC t b
      ;; Doom draws icons, symbols and emoji from these two; a Mac's
      ;; emoji are Apple's own.
      doom-symbol-font (font-spec :family "Symbols Nerd Font Mono")
      doom-emoji-font (font-spec :family (if (featurep :system 'macos)
                                             "Apple Color Emoji"
                                           "Noto Color Emoji")))

(when (boundp 'ns-system-appearance-change-functions)
  (add-hook 'ns-system-appearance-change-functions
            (defun +config--follow-appearance-h (appearance)
              "Wear the light or the dark one of `+config-themes' for APPEARANCE."
              (let ((on (if (eq appearance 'light) (cdr +config-themes) (car +config-themes))))
                ;; Disable every enabled theme, one picked with SPC h t
                ;; too, so no two are drawn over each other.
                (unless (equal custom-enabled-themes (list on))
                  (mapc #'disable-theme custom-enabled-themes)
                  (load-theme on t))))))

;; Line numbers in code and text; SPC t l turns a buffer's to relative,
;; then none. The column is as wide as the file's last line needs from
;; the start, so the text does not shift sideways while scrolling.
(setq display-line-numbers-type t)
(setq-default display-line-numbers-width-start t)


;;
;;; Windows

;; New splits open below and to the right, and take focus.
(setq evil-split-window-below t
      evil-vsplit-window-right t)


;;
;;; which-key

;; Show the key hints sooner.
(after! which-key
  (setq which-key-idle-delay 0.3
        which-key-idle-secondary-delay 0.05))
