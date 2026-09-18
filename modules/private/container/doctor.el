;; -*- lexical-binding: t; no-byte-compile: t; -*-
;;; private/container/doctor.el

(unless (executable-find (or (bound-and-true-p +container-program) "distrobox"))
  (warn! "distrobox is not installed: a toolchain that lives in a container cannot be found"))
(unless (executable-find (or (bound-and-true-p +container-runtime) "podman"))
  (warn! "podman is not installed: what is inside a container cannot be read"))
