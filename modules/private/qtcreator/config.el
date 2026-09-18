;;; private/qtcreator/config.el -*- lexical-binding: t; -*-
;;
;; Qt Creator's own files, read. It keeps what it knows in XML: the
;; kits, toolchains, Qt versions and devices in its settings directory,
;; and a CMakeLists.txt.user next to a project saying which of them
;; that project builds with. This module reads both and answers in
;; plists; it writes nothing, and Qt Creator need not be running or
;; even installed for its settings to be worth reading.
;;
;; The cpp module builds kits from what it says here. Nothing here
;; knows what a build is.

(defvar +qtcreator-settings-dirs
  '("~/.config/QtProject/qtcreator")
  "Where Qt Creator keeps its settings on the host.  The homes of the
containers are looked at as well, so a Qt Creator installed in one is
read too.")
