;; -*- lexical-binding: t; no-byte-compile: t; -*-
;;; private/sidebar/doctor.el

(assert! (modulep! :tools magit)
         "The side bar's views are drawn with magit-section: enable :tools magit")

(unless (executable-find "git")
  (warn! "No git: Source Control has nothing to show"))
