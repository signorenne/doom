;;; private/device/autoload/device.el -*- lexical-binding: t; -*-
;;
;; A machine that is not this one, reached over ssh. A device is a
;; plist: :name, :host, :user, :port, :key. Everything here builds a
;; command line and returns it; nothing is run, so the caller decides
;; whether it goes to a compilation buffer, a process or a prompt.

;;;###autoload
(defun +device-ssh-argv (device)
  "The ssh command that reaches DEVICE, as a list."
  ;; No question is ever asked: these run in a compilation buffer or a
  ;; process nobody types into, where a password prompt would wait for
  ;; ever. Without a key that works the command fails and says so; a
  ;; host that does not answer fails in ten seconds.
  (append (list "ssh" "-o" "BatchMode=yes" "-o" "ConnectTimeout=10")
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
was not running.  The kernel keeps a process's name to 15 characters,
so a longer one is matched by those: in full, nothing ever matched."
  (+device-run device (format "pkill -x %s || true"
                              (shell-quote-argument (truncate-string-to-width program 15)))))

;;;###autoload
(defun +device-copy (device from to)
  "The shell line that copies the directory FROM on this machine into TO
on DEVICE, over rsync, through the same ssh."
  (let ((ssh (+device-ssh-argv device)))
    (mapconcat #'shell-quote-argument
               (list "rsync" "-avz"
                     "-e" (mapconcat #'+device--rsync-word (butlast ssh) " ")
                     (file-name-as-directory from)
                     (format "%s:%s/" (car (last ssh)) (directory-file-name to)))
               " ")))

(defun +device--rsync-word (arg)
  "ARG as one word of the ssh command rsync is given with -e.  rsync
splits that command itself, on spaces and quotes, and keeps a backslash
as it is, so the shell's quoting would hand ssh BatchMode\\=yes."
  (if (string-match-p "\\`[-A-Za-z0-9_./=@:+,%]+\\'" arg)
      arg
    ;; In single quotes, where rsync reads a doubled one as one.
    (concat "'" (string-replace "'" "''" arg) "'")))
