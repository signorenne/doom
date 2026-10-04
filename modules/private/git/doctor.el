;; -*- lexical-binding: t; no-byte-compile: t; -*-
;;; private/git/doctor.el

(assert! (modulep! :tools magit)
         "This module configures magit: enable (:tools magit)")
(assert! (modulep! :emacs vc)
         "The hub's browse and copy-link entries and the time machine are the vc module's: enable (:emacs vc)")
(assert! (modulep! :private core)
         "The repository list and clones go to core's projects directory: enable (:private core)")

(unless (executable-find "git")
  (error! "git is not installed"))

;; sed pauses the rebase that rewrites an older commit's date or author.
(unless (executable-find "sed")
  (warn! "Couldn't find sed: SPC g h d and SPC g h a cannot reach a commit that is not HEAD"))

;; magit-delta is wired behind `executable-find', so without the binary
;; the whole block stands down and diffs are painted the plain way with
;; nothing saying so.
(unless (executable-find "delta")
  (warn! "Couldn't find delta: diffs are painted by magit, not highlighted as code")
  (explain! "openSUSE: zypper in git-delta"))
