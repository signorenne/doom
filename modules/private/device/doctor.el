;; -*- lexical-binding: t; no-byte-compile: t; -*-
;;; private/device/doctor.el

(unless (executable-find "ssh")
  (warn! "ssh is not installed: a device cannot be reached"))
(unless (executable-find "rsync")
  (warn! "rsync is not installed: nothing can be copied to a device"))
