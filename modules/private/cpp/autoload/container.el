;;; private/cpp/autoload/container.el -*- lexical-binding: t; -*-
;;
;; Where a kit runs. A compiler that is not on the host lives in a
;; container, which the container module finds and enters; the SDK it
;; belongs to has an environment script next to its sysroots. Here:
;; the SDK probes kit.el asks when it locates a kit, and the two forms
;; of a command run where the kit runs, a shell line and a process
;; argv. What a container is stays in the container module.

(declare-function +cpp-kit-container "kit")
(declare-function +cpp-kit-env-script "kit")
(declare-function +cpp-kit-env "kit")
(declare-function +container-run "container")
(declare-function +container-enter "container")
(declare-function +container-single-quoted "container")
(declare-function +container-double-quoted "container")
(declare-function +container-forget "container")

;;
;;; The SDK a kit belongs to

(defvar +cpp--env-scripts (make-hash-table :test #'equal)
  "(CONTAINER . SDK-ROOT) to the environment script found there.")

;; Autoloaded: build-type.el tells the SDKs of two tool sets apart with it.
;;;###autoload
(defun +cpp--sdk-root (path)
  "The SDK PATH belongs to: the directory above its sysroots, or nil."
  (when (and path (string-match "\\`\\(.*?\\)/sysroots/" path))
    (match-string 1 path)))

;; Autoloaded: called from `+cpp--kit-locate' in kit.el.
;;;###autoload
(defun +cpp--env-script-for (container path)
  "The environment-setup script of the SDK that PATH is in, on CONTAINER
or the host.  Yocto SDKs, which Qt Creator kits for embedded targets use,
keep one next to their sysroots; it is what the toolchain file reads."
  (when-let* ((sdk (+cpp--sdk-root path)))
    (let* ((key (cons container sdk))
           (hit (gethash key +cpp--env-scripts 'unknown)))
      (if (not (eq hit 'unknown))
          hit
        (let ((script
               (if container
                   ;; Entering the container takes half a second, so its
                   ;; answer is kept across sessions; `+cpp/forget-kits'
                   ;; asks again.
                   (or (doom-store-get key "+cpp")
                       (when-let* (((fboundp '+container-run))
                                   (found (+container-run
                                           container
                                           (list "sh" "-c"
                                                 (format "ls -d %s/environment-setup-* 2>/dev/null | head -1"
                                                         (shell-quote-argument sdk)))))
                                   ((string-prefix-p "/" found)))
                         (doom-store-put key found nil "+cpp")
                         found))
                 (car (file-expand-wildcards (concat sdk "/environment-setup-*"))))))
          (puthash key script +cpp--env-scripts)
          script)))))

;; Autoloaded: called from `+cpp/forget-kits' in kit.el.
;;;###autoload
(defun +cpp--forget-containers ()
  "Drop what was found about the SDK scripts, and about the containers
themselves, for a container started or an SDK installed since."
  (clrhash +cpp--env-scripts)
  (doom-store-clear "+cpp")
  (when (fboundp '+container-forget) (+container-forget)))

;;
;;; A command, where the kit runs

;; Qt Creator's kits for the PC target put the target's libraries on the
;; loader's path. Nothing started here survives that: a program of the
;; container's own loads the target's C library into its loader and
;; crashes, as clangd did on opening a file, and one built for the
;; target has no interpreter in the container to start with. So those
;; variables stay out of every command a kit runs.
(defconst +cpp--loader-variables '("LD_LIBRARY_PATH" "LD_PRELOAD" "LD_AUDIT")
  "What changes which libraries the dynamic loader loads.")

;;;###autoload
(defun +cpp--kit-environment (kit)
  "KIT's environment, Qt Creator's NAME=VALUE and NAME+=VALUE lines,
without `+cpp--loader-variables'."
  (seq-remove (lambda (entry)
                (and (string-match "\\`\\([A-Za-z_][A-Za-z0-9_]*\\)\\+?=" entry)
                     (member (match-string 1 entry) +cpp--loader-variables)))
              (+cpp-kit-env kit)))

;; Both forms are built from the same two pieces: the host-side prefix
;; that enters the container, which the container module gives, and the
;; inner bash line that sets the environment up.

(defun +cpp--kit-prefix (kit)
  "Argv that starts a command where KIT runs; nil for a kit on the host."
  (when-let* ((container (+cpp-kit-container kit))
              ((fboundp '+container-enter)))
    (+container-enter container)))

(defun +cpp--env-exports (env)
  "ENV, Qt Creator's list of NAME=VALUE and NAME+=VALUE lines, as bash
exports: a value may name another variable as ${NAME}, which the shell
fills in, and += appends behind a colon."
  (mapconcat (lambda (entry)
               (cond ((string-match "\\`\\([A-Za-z_][A-Za-z0-9_]*\\)\\+=\\(.*\\)\\'" entry)
                      (format "export %s=\"${%s}:%s\"" (match-string 1 entry) (match-string 1 entry)
                              (+container-double-quoted (match-string 2 entry))))
                     ((string-match "\\`\\([A-Za-z_][A-Za-z0-9_]*\\)=\\(.*\\)\\'" entry)
                      (format "export %s=\"%s\"" (match-string 1 entry)
                              (+container-double-quoted (match-string 2 entry))))
                     (t "")))
             env "; "))

(defun +cpp--kit-inner (kit body &optional directory)
  "BODY as one bash line for KIT: a cd to DIRECTORY when given, then the
environment, Qt Creator's when the kit has one, exported line by line,
else the SDK script sourced, then BODY."
  (concat (if directory
              (format "cd %s && " (shell-quote-argument (expand-file-name directory)))
            "")
          (cond ((+cpp--kit-environment kit)
                 (concat (+cpp--env-exports (+cpp--kit-environment kit)) "; "))
                ((+cpp-kit-env-script kit)
                 (format "source %s && " (shell-quote-argument (+cpp-kit-env-script kit))))
                (t ""))
          body))

;;;###autoload
(defun +cpp--kit-shell (kit command &optional directory)
  "Shell COMMAND as it must run for KIT: inside its container, from
DIRECTORY (default `default-directory'), with the SDK environment sourced,
when the kit has them; as it is otherwise.  The container sees the home
directory under its own path as well as the host's, and a cache holds the
host's, so the command is run from that one."
  (if (not (or (+cpp--kit-environment kit) (+cpp-kit-env-script kit) (+cpp-kit-container kit)))
      command
    (let ((inner (+cpp--kit-inner kit command
                                  (and (+cpp-kit-container kit)
                                       (or directory default-directory)))))
      (concat (mapconcat #'shell-quote-argument
                         (append (+cpp--kit-prefix kit) (list "bash" "-c"))
                         " ")
              " " (+container-single-quoted inner)))))

;;;###autoload
(defun +cpp--kit-process (kit argv)
  "Program and arguments ARGV as a process must be started for KIT.
The list form of `+cpp--kit-shell', for eglot and dape: the process
starts in `default-directory', which the container shares."
  (if (not (or (+cpp--kit-environment kit) (+cpp-kit-env-script kit) (+cpp-kit-container kit)))
      argv
    (append (+cpp--kit-prefix kit)
            (list "bash" "-c"
                  (+cpp--kit-inner
                   kit
                   (concat "exec " (mapconcat #'shell-quote-argument argv " ")))))))
