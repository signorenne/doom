;;; private/cpp/autoload/device.el -*- lexical-binding: t; -*-
;;
;; The device a kit runs on, as Qt Creator's Projects mode has it: a
;; Linux box with a host, a user, a port and a key, read from the
;; settings with the kit. Deploy does what Qt Creator's steps do, the
;; app killed there, the install tree synced over rsync; run starts
;; the installed executable there over ssh. Both from the host, whose
;; ssh holds the key; the install itself runs where the kit runs.

(declare-function +cpp--with-config "kit")
(declare-function +cpp-kit-name "kit")
(declare-function +cpp-kit-qtc "kit")
(declare-function +cpp-kit-run "kit")
(declare-function +cpp-kit-abs-dir "kit")
(declare-function +cpp--kit "kit")
(declare-function +cpp--kit-config "kit")
(declare-function +cpp--kit-shell "container")
(declare-function +cpp--file-api-target "run")
(declare-function +cpp--run-argv "run")
(declare-function +cpp--compile "project")
(declare-function +cpp--setting "project")
(declare-function +cpp--save-project-buffers "project")
(declare-function +qtcreator-active "qtcreator")
(declare-function +device-run "device")
(declare-function +device-run-argv "device")
(declare-function +device-kill "device")
(declare-function +device-copy "device")
(declare-function +device-where "device")

;; Autoloaded: debug.el asks which board the kit runs on.
;;;###autoload
(defun +cpp--device (kit)
  "The device KIT runs on, a plist :name :host :user :port :key, or
nil for a kit that runs where it builds."
  (plist-get (+cpp-kit-qtc kit) :device))

;; Autoloaded: run.el asks before running locally.
;;;###autoload
(defun +cpp--device-run-p (kit)
  "Non-nil when KIT's run configuration runs on a device and the device
is known: what Qt Creator calls a remote Linux run."
  (and (plist-get (+cpp-kit-run kit) :remote)
       (+cpp--device kit)
       t))

;; Autoloaded: debug.el names what it deployed.
;;;###autoload
(defun +cpp--run-target-name (kit root)
  "The executable target KIT runs: the project's choice, Qt Creator's
run configuration, or asked."
  (or (+cpp--setting '+cpp-run-target)
      (plist-get (+cpp-kit-run kit) :target)
      (plist-get (+qtcreator-active root) :run-target)
      (read-string "Run target: ")))

;; Autoloaded: debug.el finds what was deployed there.
;;;###autoload
(defun +cpp--install-place (kit name root)
  "Where target NAME lands when KIT's build is installed, as
(PREFIX . RELATIVE), the prefix on the device and the executable's
path under it, from the file API reply; nil when the reply does not
say, a directory Qt Creator configured but never built."
  (when-let* ((target (+cpp--file-api-target (+cpp-kit-abs-dir kit root) name (+cpp--kit-config kit)))
              (install (alist-get 'install target))
              (destination (alist-get 'path (car (alist-get 'destinations install))))
              (artifact (alist-get 'path (car (alist-get 'artifacts target)))))
    (cons (or (alist-get 'path (alist-get 'prefix install)) "/usr/local")
          (file-name-concat destination (file-name-nondirectory artifact)))))

;;;###autoload
(defun +cpp/run-on-device (&optional args)
  "Run the project's executable on the kit's device, over ssh, with
ARGS: the installed one, at the path the build's install step puts
it, as Qt Creator's remote run does.  Deploy first when the build
changed, SPC k U."
  (interactive)
  (+cpp--save-project-buffers)
  (let* ((root (+core-project-root))
         (kit (+cpp--kit root))
         (device (or (+cpp--device kit)
                     (user-error "%s runs on no device: its Qt Creator kit names none" (+cpp-kit-name kit))))
         (name (+cpp--run-target-name kit root))
         (place (or (+cpp--install-place kit name root)
                    (user-error "Where %s is installed is not known yet; build once (SPC k b)" name)))
         (args (or args (+cpp--setting '+cpp-run-args) (plist-get (+cpp-kit-run kit) :args)))
         (exe (file-name-concat (car place) (cdr place))))
    (+cpp--compile (format "run on %s: %s" (plist-get device :name) name)
                   (+device-run-argv device (cons exe (+cpp--run-argv args)))
                   t)))

;;;###autoload
(defun +cpp/deploy ()
  "Deploy the build to the kit's device the way Qt Creator's steps do:
the app is stopped there, the build is installed into a staging
directory under the build directory with the prefix it is configured
for, and that prefix is synced to the device with rsync.  Shown and
asked before anything runs."
  (interactive)
  (+cpp--save-project-buffers)
  (let* ((root (+core-project-root))
         (kit (+cpp--kit root))
         (device (or (+cpp--device kit)
                     (user-error "%s deploys to no device: its Qt Creator kit names none" (+cpp-kit-name kit))))
         (name (+cpp--run-target-name kit root))
         (place (or (+cpp--install-place kit name root)
                    (user-error "Where %s is installed is not known yet; build once (SPC k b)" name)))
         (prefix (car place))
         (staging (file-name-concat (+cpp-kit-abs-dir kit root) ".deploy"))
         (install (+cpp--kit-shell
                   kit
                   (+cpp--with-config
                    (format "cmake --install %s --prefix %s"
                            (shell-quote-argument (+cpp-kit-abs-dir kit root))
                            (shell-quote-argument (file-name-concat staging (string-remove-prefix "/" prefix))))
                    (+cpp--kit-config kit))
                   root))
         (stop (+device-kill device (file-name-nondirectory (cdr place))))
         (sync (+device-copy device
                             (file-name-concat staging (string-remove-prefix "/" prefix))
                             prefix)))
    (when (y-or-n-p (format "Deploy %s to %s (%s): install, then %s? "
                            name (plist-get device :name) (plist-get device :host) sync))
      (+cpp--compile (format "deploy to %s" (plist-get device :name))
                     (concat install " && " stop " && " sync)))))
