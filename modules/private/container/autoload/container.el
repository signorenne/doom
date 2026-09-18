;;; private/container/autoload/container.el -*- lexical-binding: t; -*-
;;
;; Containers on this machine, and running something in one. distrobox
;; keeps them, podman runs them, and the two are asked different
;; questions: distrobox lists and enters them, podman says what is
;; inside one. Nothing here knows what the command is for.

(defvar +container-program)
(defvar +container-runtime)

;;
;;; What is there

;;;###autoload
(defun +container-list (&optional all)
  "The running containers on this machine, by name; with ALL the
stopped ones too.  Nil when distrobox is not installed."
  (when (executable-find +container-program)
    (with-temp-buffer
      (call-process +container-program nil t nil "list" "--no-color")
      (goto-char (point-min))
      (forward-line 1)                  ; the header
      (let (names)
        (while (re-search-forward
                "^[^|]*|[ \t]*\\([^ \t|]+\\)[ \t]*|[ \t]*\\([^|]*?\\)[ \t]*|" nil t)
          (when (or all (string-prefix-p "Up" (match-string 2)))
            (push (match-string 1) names)))
        (nreverse names)))))

;;;###autoload
(defun +container-run (container argv)
  "The first line ARGV prints when run in CONTAINER, on the host when
CONTAINER is nil; nil when it fails.  A short process, not TRAMP."
  (with-temp-buffer
    (when (zerop (condition-case nil
                     (if container
                         (apply #'call-process +container-program nil t nil
                                "enter" container "--" argv)
                       (apply #'call-process (car argv) nil t nil (cdr argv)))
                   (error 1)))
      (goto-char (point-min))
      (let ((line (string-trim (buffer-substring (point) (line-end-position)))))
        (and (not (string-empty-p line)) line)))))

;;;###autoload
(defun +container-has-p (container path)
  "Non-nil when PATH, a program or a file, is there inside CONTAINER.
A path is tested as a file, a bare name as a command."
  (condition-case nil
      (zerop (call-process +container-program nil nil nil "enter" container "--"
                           "sh" "-c"
                           (if (string-search "/" path)
                               (format "test -e %s" (shell-quote-argument path))
                             (format "command -v %s >/dev/null" (shell-quote-argument path)))))
    (error nil)))

;;;###autoload
(defvar +container-may-start t
  "Whether looking for a program may start a stopped container.
Starting one takes seconds, so it is bound to nil where the question is
incidental, as it is when a file is opened or a server started, and
left alone where the answer is what was asked for: a build, a run, a
deploy.")

(defvar +container--by-program (make-hash-table :test #'equal)
  "(RUNNING-CONTAINERS . PROGRAM) to the container that has it, or `host'.
Keyed by the running containers as well, so a container started later
is looked at, and a miss cached while it was down does not stick.")

;;;###autoload
(defun +container-for (program)
  "The container holding PROGRAM when the host does not, else nil.
The running ones are asked first; a stopped one is started to be
asked, which is what running the program there would do anyway, and
said so in the echo area. Unless `+container-may-start' says not to,
in which case only the running ones answer and nothing is cached, so
the stopped ones are asked the next time it is a fair question."
  (when (and program (not (file-exists-p program)))
    (let* ((running (+container-list))
           (key (cons running program))
           (known (gethash key +container--by-program)))
      (cond ((eq known 'host) nil)
            (known known)
            (t (let ((found (seq-find (lambda (name) (+container-has-p name program))
                                      running)))
                 (cond
                  (found (puthash key found +container--by-program) found)
                  ((not +container-may-start) nil)
                  (t (setq found
                           (seq-find (lambda (name)
                                       (message "Starting %s to look for %s there"
                                                name program)
                                       (+container-has-p name program))
                                     (seq-difference (+container-list 'all) running)))
                     (puthash key (or found 'host) +container--by-program)
                     found))))))))

(defvar +container--homes (make-hash-table :test #'equal)
  "Container name to the home directory it was given, as the host sees it.")

;;;###autoload
(defun +container-home (name)
  "The home directory of container NAME, a path the host can read, or
nil.  distrobox gives a container a home of its own under the host's,
and the container's environment says where."
  (let ((hit (gethash name +container--homes 'unknown)))
    (if (not (eq hit 'unknown))
        hit
      (puthash name
               (with-temp-buffer
                 (when (and (executable-find +container-runtime)
                            (zerop (condition-case nil
                                       (call-process +container-runtime nil t nil "inspect" "-f"
                                                     "{{range .Config.Env}}{{println .}}{{end}}" name)
                                     (error 1))))
                   (goto-char (point-min))
                   (when (re-search-forward "^HOME=\\(.+\\)$" nil t)
                     (let ((home (match-string 1)))
                       ;; A container that shares the host's home has none
                       ;; of its own, and there is nothing there to find.
                       (and (file-directory-p home)
                            (not (file-equal-p home (expand-file-name "~")))
                            home)))))
               +container--homes))))

;;;###autoload
(defun +container-path (container path)
  "PATH inside CONTAINER, as a path this Emacs can open: TRAMP reaches
it through the runtime."
  (format "/%s:%s:%s" +container-runtime container path))

;;;###autoload
(defun +container-forget ()
  "Drop what was found about containers, for one started or a program
installed since.  The library half: `+container/forget\=' is the command."
  (clrhash +container--by-program)
  (clrhash +container--homes))

;;;###autoload
(defun +container/forget ()
  "Forget what was found about the containers and look again."
  (interactive)
  (+container-forget)
  (message "What was known about the containers is forgotten"))

;;
;;; Running something in one

;;;###autoload
(defun +container-exported-functions ()
  "Shell functions exported into this Emacs (BASH_FUNC_x%%), which a bash
of another version, the container's, refuses with a line of noise."
  (seq-uniq
   (cl-loop for entry in process-environment
            when (string-match "\\`\\(BASH_FUNC_[^=]*\\)=" entry)
            collect (match-string 1 entry))))

;;;###autoload
(defun +container-enter (container)
  "Argv that starts a command inside CONTAINER: env -u for each exported
shell function, then the enter itself."
  (append (when-let* ((funcs (+container-exported-functions)))
            (cons "env" (mapcan (lambda (f) (list "-u" f)) funcs)))
          (list +container-program "enter" container "--")))

;;;###autoload
(defun +container-single-quoted (string)
  "STRING inside single quotes, for a shell, readable in a compilation buffer."
  (concat "'" (replace-regexp-in-string "'" "'\\''" string t t) "'"))

;;;###autoload
(defun +container-double-quoted (value)
  "VALUE inside a double-quoted bash string: quotes and backslashes
escaped, a ${NAME} left for the shell to fill in."
  (replace-regexp-in-string "[\"\\\\`]" "\\\\\\&" value t nil))
