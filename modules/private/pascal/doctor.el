;; -*- lexical-binding: t; no-byte-compile: t; -*-
;;; private/pascal/doctor.el

(assert! (modulep! :private core)
         "This module uses core's compile runner and project root: enable (:private core)")

(unless (fboundp 'opascal-mode)
  (error! "No opascal-mode, although Emacs ships one: this Emacs is built oddly"))

(unless (executable-find "fpc")
  (warn! "No fpc, so a Free Pascal project cannot be built: zypper in fpc fpc-src"))

(unless (executable-find "lazbuild")
  (warn! "No lazbuild, so a Lazarus project cannot be built: zypper in lazarus"))

;; CodeTools needs the compiler's own sources to resolve the RTL.
(unless (seq-some #'file-directory-p
                  '("/usr/share/fpcsrc" "/usr/lib64/fpc/src" "/usr/share/fpc/src"))
  (warn! "No Free Pascal sources, so go-to-definition stops at the RTL: zypper in fpc-src"))

;; pasls is not packaged anywhere; it is built from the Lazarus sources.
(unless (executable-find "pasls")
  (warn! "No pasls, so a Pascal buffer has no language server; see the module README for how to build it"))

(unless (executable-find "gdb")
  (warn! "No gdb, so SPC k d cannot debug a Pascal program"))
