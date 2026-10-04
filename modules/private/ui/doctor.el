;; -*- lexical-binding: t; no-byte-compile: t; -*-
;;; private/ui/doctor.el

;; What this module configures belongs to Doom's own :ui modules. Turning
;; one off leaves the settings here talking to nothing, which is quiet
;; rather than broken, so these are assertions where the module is the
;; point and warnings where it is an addition.

(assert! (modulep! :ui doom-dashboard)
         "This module draws the dashboard's banner, greeting and entries: enable (:ui doom-dashboard)")

(unless (modulep! :ui zen)
  (warn! "No (:ui zen): SPC t z and the one-font setting here do nothing"))

(unless (modulep! :ui indent-guides)
  (warn! "No (:ui indent-guides): SPC t i and the off-until-asked rule here do nothing"))

(unless (modulep! :ui treemacs)
  (warn! "No (:ui treemacs): SPC e t and the treemacs settings here do nothing"))

(unless (modulep! :ui smooth-scroll)
  (warn! "No (:ui smooth-scroll): the wheel scrolls by lines, and the pixel wheel's stop at the last line here does nothing"))

(unless (modulep! :checkers syntax +flymake)
  (warn! "No (:checkers syntax +flymake): ]e and [e walk Doom's list, not this buffer's diagnostics"))

;; The fallback font for the arrows, technical and dingbat blocks.
;; `find-font' answers nil in the frameless session the doctor runs in,
;; whatever is installed, so fontconfig is asked instead when it is there.
(let ((family "Noto Sans Symbols 2"))
  (unless (if (executable-find "fc-list")
              (with-temp-buffer
                (call-process "fc-list" nil t nil (concat ":family=" family))
                (> (buffer-size) 0))
            (or (not (display-graphic-p))
                (find-font (font-spec :family family))))
    (warn! "Couldn't find %s: some symbols fall back to a box" family)))
