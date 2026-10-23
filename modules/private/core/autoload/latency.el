;;; private/core/autoload/latency.el -*- lexical-binding: t; -*-
;;
;; Where a pause came from. Lag that comes now and then is seldom caught
;; by trying again, so this watches while you work and writes down every
;; key that took long to answer, every timer that ran long and every
;; garbage collection, with what was running and in which buffer. Off
;; until asked: watching costs a little of what it measures.

(defvar +core-latency-threshold 0.05
  "Seconds past which a key, a timer or a collection is written down.")

(defconst +core--latency-buffer "*Latency*")

(defvar +core--latency-key-start nil
  "When the command being answered started, and what it was.")

(defvar +core--latency-idle-timer nil
  "Fires as Emacs goes idle, which is when a key has been answered: the
command, its hooks and the redisplay after it all done.")

(defun +core--latency-log (seconds kind what)
  "Write down that WHAT, a KIND of work, took SECONDS."
  (let ((buffer (current-buffer)))
    (with-current-buffer (get-buffer-create +core--latency-buffer)
      (let ((inhibit-read-only t))
        (goto-char (point-max))
        (insert (format "%s %6.0f ms  %-7s %-40s %s, %s\n"
                        (format-time-string "%H:%M:%S")
                        (* 1000 seconds) kind
                        (truncate-string-to-width (format "%s" what) 40)
                        (buffer-name buffer)
                        (buffer-local-value 'major-mode buffer)))))))

(defun +core--latency-pre-h ()
  (setq +core--latency-key-start (cons (float-time) this-command)))

(defun +core--latency-idle ()
  "A key has been answered: write it down if it took long."
  (when +core--latency-key-start
    (let ((seconds (- (float-time) (car +core--latency-key-start))))
      (when (> seconds +core-latency-threshold)
        (+core--latency-log seconds "key" (cdr +core--latency-key-start))))
    (setq +core--latency-key-start nil)))

(defun +core--latency-timer-a (fn timer &rest args)
  "Time TIMER's function, and write it down if it took long."
  (let ((start (float-time)))
    (prog1 (apply fn timer args)
      (let ((seconds (- (float-time) start)))
        (when (> seconds +core-latency-threshold)
          (let ((function (timer--function timer)))
            (+core--latency-log
             seconds "timer"
             (if (symbolp function) function
               (let ((named (seq-filter (lambda (x) (and (symbolp x) (fboundp x)))
                                        (and (byte-code-function-p function)
                                             (append (aref function 2) nil)))))
                 (if named (format "closure: %s" (mapconcat #'symbol-name named " "))
                   "a closure"))))))))))

(defvar +core--latency-gc 0.0
  "`gc-elapsed' when last looked at.")

(defun +core--latency-gc-h ()
  "A collection ran: write it down if it was long."
  (let ((seconds (- gc-elapsed +core--latency-gc)))
    (setq +core--latency-gc gc-elapsed)
    (when (> seconds +core-latency-threshold)
      (+core--latency-log seconds "gc" (format "heap %d MB" (/ (memory-limit) 1024))))))

;;;###autoload
(define-minor-mode +core-latency-watch-mode
  "Write down every key, timer and garbage collection that takes longer
than `+core-latency-threshold', in the *Latency* buffer."
  :global t
  :lighter nil
  :group 'convenience
  (cond
   (+core-latency-watch-mode
    (setq +core--latency-gc gc-elapsed)
    (add-hook 'pre-command-hook #'+core--latency-pre-h)
    (add-hook 'post-gc-hook #'+core--latency-gc-h)
    (advice-add 'timer-event-handler :around #'+core--latency-timer-a)
    (setq +core--latency-idle-timer (run-with-idle-timer 0 t #'+core--latency-idle))
    (with-current-buffer (get-buffer-create +core--latency-buffer)
      (special-mode)
      (let ((inhibit-read-only t))
        (goto-char (point-max))
        (insert (format "%s watching: over %.0f ms is written down\n"
                        (format-time-string "%H:%M:%S") (* 1000 +core-latency-threshold)))))
    (message "Watching for pauses over %.0f ms; SPC h D shows them"
             (* 1000 +core-latency-threshold)))
   (t
    (remove-hook 'pre-command-hook #'+core--latency-pre-h)
    (remove-hook 'post-gc-hook #'+core--latency-gc-h)
    (advice-remove 'timer-event-handler #'+core--latency-timer-a)
    (when (timerp +core--latency-idle-timer) (cancel-timer +core--latency-idle-timer))
    (setq +core--latency-idle-timer nil +core--latency-key-start nil)
    (message "Stopped watching for pauses"))))

;;;###autoload
(defun +core/latency-show ()
  "Show what the watch wrote down."
  (interactive)
  (unless (get-buffer +core--latency-buffer)
    (user-error "Nothing written down; SPC t W turns the watch on"))
  (pop-to-buffer +core--latency-buffer)
  (goto-char (point-max)))
