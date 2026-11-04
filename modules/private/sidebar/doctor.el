;; -*- lexical-binding: t; no-byte-compile: t; -*-
;;; private/sidebar/doctor.el

(assert! (modulep! :tools magit)
         "The side bar's views are drawn with magit-section: enable :tools magit")

(when (modulep! :ui treemacs)
  (warn! "(:ui treemacs) is on again: it and the side bar both want SPC o p")
  (explain! "Comment treemacs out in init.el; the side bar's Explorer replaces it"))

(unless (executable-find "git")
  (warn! "No git: Source Control has nothing to show"))
