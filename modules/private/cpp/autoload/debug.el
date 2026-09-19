;;; private/cpp/autoload/debug.el -*- lexical-binding: t; -*-
;;
;; Debugging something that does not run here. gdb's DAP takes an
;; attach request with a target, which it turns into "target remote",
;; so anything that speaks the gdb protocol on a port can be stepped
;; through from this Emacs: gdbserver on the board, the debug server a
;; PlatformIO board is flashed through, qemu with -g. The symbols are
;; read from the executable as it was built here, and the debugger is
;; the kit's, which for a cross build lives in the container.

(require 'cl-lib)

(declare-function dape "dape")
(declare-function +cpp--kit "kit")
(declare-function +cpp--kit-process "container")
(declare-function +cpp-kit-name "kit")
(declare-function +cpp-kit-sysroot "kit")
(declare-function +cpp-kit-compiler "kit")
(declare-function +cpp-kit-qtc "kit")
(declare-function +cpp-kit-abs-dir "kit")
(declare-function +cpp--pick-executable "run")
(declare-function +cpp--run-argv "run")
(declare-function +cpp--setting "project")
(declare-function +cpp--save-project-buffers "project")
(declare-function +cpp--install-place "device")
(declare-function +cpp--run-target-name "device")
(declare-function +cpp--device "device")
(declare-function +device-run "device")
(declare-function +device-ssh-argv "device")
(declare-function +device-where "device")
(declare-function +core-project-root "lib")
(defvar +cpp-modes)
(defvar +cpp-debug-port)
(defvar +cpp-gdb)

(defun +cpp--gdb-program (kit)
  "The gdb that understands KIT's executables: the cross gdb beside its
compiler when there is one, else the gdb on the PATH."
  (or (+cpp--setting '+cpp-gdb)
      (when-let* ((compiler (and kit (+cpp-kit-compiler kit)))
                  ((string-match "\\`\\(.*-\\)g\\(cc\\|++\\)\\'"
                                 (file-name-nondirectory compiler)))
                  (cross (concat (file-name-directory compiler)
                                 (match-string 1 (file-name-nondirectory compiler))
                                 "gdb")))
        (and (or (file-exists-p cross) (+cpp-kit-container kit)) cross))
      "gdb"))

(defun +cpp--gdb-argv (kit &optional program)
  "The command that starts gdb for KIT with its DAP interpreter, where
the kit runs.  A cross build is given its sysroot, so the libraries the
board loads are read from the SDK rather than from this machine, and
PROGRAM is read for its symbols before the session starts: gdb 14, the
one an SDK of this age ships, takes no program with an attach request
and would step through a stripped-looking target without it."
  (let* ((gdb (+cpp--gdb-program kit))
         (sysroot (and kit (+cpp-kit-sysroot kit)))
         (argv (append (list gdb)
                       (when (and sysroot (not (string-empty-p sysroot)))
                         (list "-ex" (format "set sysroot %s" sysroot)))
                       (when program
                         (list "-ex" (format "file %s" program)))
                       (list "--interpreter=dap"))))
    (if kit (+cpp--kit-process kit argv) argv)))

;;;###autoload
(defun +cpp--debug-attach (kit program target &optional name)
  "Step through PROGRAM, built here, running behind TARGET, a
\"host:port\" something is serving the gdb protocol on.  NAME says what
it is, for the session's title."
  (require 'dape)
  (let ((argv (+cpp--gdb-argv kit program)))
    (dape (list 'modes +cpp-modes
                'command (car argv)
                'command-args (cdr argv)
                :type "gdb"
                :request "attach"
                :program program
                :target target
                :name (or name (format "attach %s" target))))))

;;;###autoload
(defun +cpp/debug-remote (target)
  "Attach to a gdb server already listening at TARGET, \"host:port\":
gdbserver on a board, the server a PlatformIO board is debugged
through, qemu started with -g.  The symbols come from the executable
as it was built here."
  (interactive
   (list (read-string "Attach to (host:port): "
                      (format "localhost:%s" (or (bound-and-true-p +cpp-debug-port) 2345)))))
  (+cpp--save-project-buffers)
  (let* ((root (+core-project-root))
         (kit (and (+cpp--kind-p 'cmake) (+cpp--kit root)))
         (program (if kit (+cpp--pick-executable kit) (+cpp--read-program))))
    (+cpp--debug-attach kit program target)))

;;
;;; On the device

(defvar +cpp--gdbserver-process nil
  "The gdbserver started on the device for this session, if any.")

(defun +cpp--gdbserver-stop ()
  "Stop the gdbserver this Emacs started on the device."
  (when (process-live-p +cpp--gdbserver-process)
    (delete-process +cpp--gdbserver-process))
  (setq +cpp--gdbserver-process nil))

(defun +cpp--gdbserver-watch ()
  "Stop the gdbserver when the session that needed it ends.  dape has no
hook for that, so the two commands that end a session carry it."
  (dolist (command '(dape-quit dape-kill))
    (advice-add command :after #'+cpp--gdbserver-stop-a)))

(defun +cpp--gdbserver-stop-a (&rest _)
  "After dape has finished with it, the gdbserver goes too."
  (+cpp--gdbserver-stop)
  (dolist (command '(dape-quit dape-kill))
    (advice-remove command #'+cpp--gdbserver-stop-a)))

(defun +cpp--gdbserver-start (device command)
  "Run COMMAND, a gdbserver line, on DEVICE, and keep the process.
It is a process rather than a compilation buffer so the session can
stop it, and its output is kept for when it refuses to start."
  (+cpp--gdbserver-stop)
  (let ((buffer (get-buffer-create "*gdbserver*")))
    (with-current-buffer buffer (erase-buffer))
    (setq +cpp--gdbserver-process
          (start-process-shell-command "gdbserver" buffer
                                       (+device-run device command)))
    (set-process-query-on-exit-flag +cpp--gdbserver-process nil)
    (+cpp--gdbserver-watch)
    +cpp--gdbserver-process))

;;;###autoload
(defun +cpp/debug-on-device ()
  "Debug the project's executable on the kit's device.  gdbserver is
started there over ssh on the installed binary, and gdb attaches to it
from here with the symbols of the one built here.  Deploy first, SPC k
U, or the two will not be the same program."
  (interactive)
  (+cpp--save-project-buffers)
  (let* ((root (+core-project-root))
         (kit (+cpp--kit root))
         (device (or (+cpp--device kit)
                     (user-error "%s runs on no device: its Qt Creator kit names none"
                                 (+cpp-kit-name kit))))
         (name (+cpp--run-target-name kit root))
         (place (or (+cpp--install-place kit name root)
                    (user-error "Where %s is installed is not known yet; build once (SPC k b)" name)))
         (remote (file-name-concat (car place) (cdr place)))
         (local (+cpp--pick-executable kit))
         (port (or (+cpp--setting '+cpp-debug-port) +cpp-debug-port))
         (args (or (+cpp--setting '+cpp-run-args) ""))
         (line (format "gdbserver :%s %s%s" port (shell-quote-argument remote)
                       (if (string-empty-p args) "" (concat " " args)))))
    (unless (y-or-n-p (format "Debug %s on %s: %s? " name (+device-where device) line))
      (user-error "Left alone"))
    (+cpp--gdbserver-start device line)
    ;; gdbserver must be listening before gdb knocks.
    (sit-for 1)
    (unless (process-live-p +cpp--gdbserver-process)
      (user-error "gdbserver did not start on %s; see *gdbserver*" (+device-where device)))
    (+cpp--debug-attach kit local
                        (format "%s:%s" (plist-get device :host) port)
                        (format "%s on %s" name (plist-get device :name)))))

;;;###autoload
(defun +cpp/debug-stop-device ()
  "Stop the gdbserver started on the device, and the session with it."
  (interactive)
  (+cpp--gdbserver-stop)
  (when (fboundp 'dape-quit) (ignore-errors (dape-quit)))
  (message "gdbserver stopped"))
