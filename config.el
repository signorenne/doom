;;; $DOOMDIR/config.el -*- lexical-binding: t; -*-
;;
;; Loaded after Doom and every module. Only identity and look and feel live
;; here; the rest is in modules/private/* (see the :private block in init.el).
;; The keybinding reference is on SPC h / and F12.

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

;; On a Mac the theme is a pair, dark and light, and follows the system's
;; appearance as the Mac's own apps do: Doom picks one as Emacs starts,
;; and Emacs+ says when the appearance changes, below. Elsewhere it is
;; the dark one. The pair is kept apart: Doom sets `doom-theme' to the
;; one it loads.
(defvar +config-themes '(doom-one . doom-one-light)
  "The dark theme and the light one, worn as a Mac's appearance says.")

(setq doom-theme (if (featurep :system 'macos) +config-themes 'doom-one)
      doom-font (font-spec :family "JetBrains Mono" :size 15)
      doom-variable-pitch-font (font-spec :family "DejaVu Sans" :size 16)
      doom-big-font (font-spec :family "JetBrains Mono" :size 24) ; SPC t b
      ;; Doom draws icons, symbols and emoji from these two.
      doom-symbol-font (font-spec :family "Symbols Nerd Font Mono")
      doom-emoji-font (font-spec :family "Noto Color Emoji"))

(when (boundp 'ns-system-appearance-change-functions)
  (add-hook 'ns-system-appearance-change-functions
            (defun +config--follow-appearance-h (appearance)
              "Wear the light or the dark one of `+config-themes' for APPEARANCE."
              (let ((on (if (eq appearance 'light) (cdr +config-themes) (car +config-themes))))
                ;; Every theme on goes, one picked with SPC h t too, or
                ;; the pair's would be drawn over it.
                (unless (equal custom-enabled-themes (list on))
                  (mapc #'disable-theme custom-enabled-themes)
                  (load-theme on t))))))

;; No line numbers in any buffer: the modeline has the line and the
;; count. SPC t l shows them in one buffer, then relative, then none.
(setq display-line-numbers-type nil)


;;
;;; Windows

;; New splits open below and to the right, and take focus.
(setq evil-split-window-below t
      evil-vsplit-window-right t)


;;
;;; which-key

;; Show the key hints sooner.
(after! which-key
  (setq which-key-idle-delay 0.5
        which-key-idle-secondary-delay 0.05))
