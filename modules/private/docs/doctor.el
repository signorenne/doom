;; -*- lexical-binding: t; no-byte-compile: t; -*-
;;; private/docs/doctor.el
;; A static check over the private modules, reading files only: every
;; function a config file, a key, a hook or a menu refers to must be
;; defined, and when it is defined in an autoload file and used from
;; another file it must carry a cookie, or the reference is void in a
;; fresh session. The scan lives in autoload/check.el, which SPC h d C
;; also runs in the session; it needs nothing but Emacs.

(load (file-name-concat doom-user-dir "modules/private/docs/autoload/check.el")
      nil 'nomessage)

(dolist (problem (+docs-autoload-problems))
  (error! "%s" problem))
