;;; private/core/+hand-off.el -*- lexical-binding: t; -*-
;;
;; Loaded from $DOOMDIR/init.el, before Emacs makes its first frame.

(declare-function server-running-p "server")
(defvar server-name)

(defun +core--open-in-server (files)
  "Open FILES in a new window of the running server; non-nil if it did.
Gives up after five seconds, so a hung server does not leave this Emacs
without a window."
  ;; Emacs.app keeps its own in Contents/MacOS/bin.
  (let ((client (or (executable-find "emacsclient")
                    (expand-file-name "bin/emacsclient" invocation-directory))))
    (zerop (call-process client nil nil nil
                         "-s" server-name "-w" "5" "-c" "-n" "-e"
                         (prin1-to-string
                          `(progn (mapc #'find-file ',files)
                                  (select-frame-set-input-focus (selected-frame))))))))

;; A GUI Emacs started with only file names while a server runs opens
;; them there and quits, so only the server's window appears. A start
;; with options wants a session of its own.
(when (and initial-window-system (not (daemonp)) (not noninteractive)
           (not (seq-some (lambda (arg) (string-match-p "\\`[-+]" arg))
                          (cdr command-line-args))))
  (require 'server)
  (when-let* ((name (getenv "EMACS_SERVER_NAME")))
    (setq server-name name))
  (when (and (server-running-p)
             (+core--open-in-server (mapcar #'expand-file-name (cdr command-line-args))))
    (kill-emacs)))
