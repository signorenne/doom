;; -*- lexical-binding: t; no-byte-compile: t; -*-
;;; private/qtcreator/doctor.el

(unless (seq-some (lambda (dir) (file-directory-p (expand-file-name dir)))
                  (or (bound-and-true-p +qtcreator-settings-dirs)
                      '("~/.config/QtProject/qtcreator")))
  (print! (warn "No Qt Creator settings on the host; only the containers will be read")))
