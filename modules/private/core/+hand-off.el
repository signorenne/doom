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

(defun +core--start-args ()
  "The arguments this Emacs was started with, the program's name left out.
By the time the config loads Emacs has taken the ones it handled itself,
--debug-init and -q among them, out of `command-line-args'; on Linux the
kernel keeps them all."
  (let ((file "/proc/self/cmdline"))
    (if (file-readable-p file)
        (cdr (split-string (with-temp-buffer
                             (set-buffer-multibyte nil)
                             (insert-file-contents-literally file)
                             (buffer-string))
                           "\0" t))
      (cdr command-line-args))))

(defvar +core-own-session nil
  "Non-nil when this GUI Emacs was started with an option: it keeps a
session of its own and never hands its files to a running server.")

;; A GUI Emacs started with only file names while a server runs opens
;; them there and quits, so only the server's window appears. A start
;; with any option wants a session of its own, here and when the server
;; is looked for again once Emacs is up (config.el).
(when (and initial-window-system (not (daemonp)) (not noninteractive))
  (setq +core-own-session
        (seq-some (lambda (arg) (string-match-p "\\`[-+]" arg)) (+core--start-args)))
  (unless +core-own-session
    (require 'server)
    (when-let* ((name (getenv "EMACS_SERVER_NAME")))
      (setq server-name name))
    (when (and (server-running-p)
               (+core--open-in-server (mapcar #'expand-file-name (cdr command-line-args))))
      (kill-emacs))))
