;;; private/device/autoload/device.el -*- lexical-binding: t; -*-
;;
;; A machine that is not this one, reached over ssh. A device is a
;; plist: :name, :host, :user, :port, :key. Everything here builds a
;; command line and returns it; nothing is run, so the caller decides
;; whether it goes to a compilation buffer, a process or a prompt.

;;;###autoload
(defun +device-ssh-argv (device)
  "The ssh command that reaches DEVICE, as a list."
  (append (list "ssh")
          (when-let* ((key (plist-get device :key)))
            (and (not (string-empty-p key)) (list "-i" key)))
          (when-let* ((port (plist-get device :port)))
            (and (not (equal port "22")) (list "-p" port)))
          (list (format "%s@%s"
                        (or (plist-get device :user) "root")
                        (plist-get device :host)))))

;;;###autoload
(defun +device-where (device)
  "DEVICE as user@host, for a message or a prompt."
  (car (last (+device-ssh-argv device))))

;;;###autoload
(defun +device-run (device command)
  "The shell line that runs COMMAND, a string, on DEVICE."
  (mapconcat #'shell-quote-argument
             (append (+device-ssh-argv device) (list command))
             " "))

;;;###autoload
(defun +device-run-argv (device argv)
  "The shell line that runs ARGV, a list, on DEVICE."
  (+device-run device (mapconcat #'shell-quote-argument argv " ")))

;;;###autoload
(defun +device-kill (device program)
  "The shell line that stops PROGRAM on DEVICE, saying nothing when it
was not running."
  (+device-run device (format "pkill -x %s || true" (shell-quote-argument program))))

;;;###autoload
(defun +device-copy (device from to)
  "The shell line that copies the directory FROM on this machine into TO
on DEVICE, over rsync, through the same ssh."
  (let ((ssh (+device-ssh-argv device)))
    (mapconcat #'shell-quote-argument
               (list "rsync" "-avz"
                     "-e" (mapconcat #'shell-quote-argument (butlast ssh) " ")
                     (file-name-as-directory from)
                     (format "%s:%s/" (car (last ssh)) (directory-file-name to)))
               " ")))
