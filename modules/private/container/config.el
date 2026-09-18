;;; private/container/config.el -*- lexical-binding: t; -*-
;;
;; The containers a toolchain may live in. distrobox keeps them and
;; podman runs them; this module answers which one holds a program,
;; what a command must look like to run there, and where the container
;; keeps its home. The cpp module builds its kits on it; nothing here
;; knows what a kit is.

(defvar +container-program "distrobox"
  "The command that lists and enters the containers.")

(defvar +container-runtime "podman"
  "The container runtime underneath: asked what is inside a container,
and the TRAMP method that reaches into one.")
