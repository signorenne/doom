;;; private/cpp/autoload/tasks.el -*- lexical-binding: t; -*-
;;
;; What a project does besides compiling: package it, put the package
;; where it goes, run one of its scripts. All of it where the kit runs,
;; so an SDK's environment is there for the packaging script and the
;; deploy script alike.

(declare-function +cpp-kit-name "kit")
(declare-function +cpp-kit-abs-dir "kit")
(declare-function +cpp--kit "kit")
(declare-function +cpp--build-target-command "kit")
(declare-function +cpp--target-names "run")
(declare-function +cpp--kit-shell "container")
(declare-function +cpp--compile "project")
(declare-function +cpp--setting "project")
(declare-function +cpp--set-setting "project")
(declare-function +cpp--kind-p "project")
(declare-function +cpp--save-project-buffers "project")
(defvar +core-compile-name)

(defvar +cpp-package-target)              ; config.el, with the other settings
(defvar +cpp-package-dir)

(defconst +cpp-package-target-regexp
  "\\.hpkg\\(?:lite\\)?\\'\\|\\`package\\(?:_source\\)?\\'\\|\\.deb\\'\\|\\.rpm\\'\\|\\`dist\\'\\|\\`bundle\\'"
  "A target name that packages: the Horizon hpkg targets, CMake's own
package and package_source, and the usual names.")

(defconst +cpp-package-file-regexp
  "\\.\\(?:hpkg\\|hpkglite\\|deb\\|rpm\\|zip\\|tar\\.[a-z0-9]+\\|tgz\\|AppImage\\|ipk\\|apk\\)\\'"
  "A file a packaging target leaves in the build directory.")


;;
;;; Packaging

(defun +cpp--package-targets (kit root)
  "The packaging targets the kit's build directory knows, by name."
  (seq-filter (lambda (name) (string-match-p +cpp-package-target-regexp name))
              (+cpp--target-names kit root)))

(defun +cpp--packages (dir &optional since)
  "The packages in DIR, newest first, those written after SINCE when
given (a `float-time')."
  (thread-last (directory-files dir t +cpp-package-file-regexp)
               (seq-filter (lambda (file)
                             (let ((time (float-time (file-attribute-modification-time
                                                      (file-attributes file)))))
                               (or (null since) (> time since)))))
               (seq-sort-by (lambda (file)
                              (float-time (file-attribute-modification-time (file-attributes file))))
                            #'>)))

(defvar +cpp--package-started nil
  "(ROOT DIR . TIME) of the packaging build running, for its finish hook.")

(defun +cpp--packaged-h (buffer status)
  "Name the packages the build in BUFFER wrote once it ends with STATUS."
  (when (equal (buffer-local-value '+core-compile-name buffer) "package")
    (remove-hook 'compilation-finish-functions #'+cpp--packaged-h)
    (pcase-let ((`(,_root ,dir . ,time) +cpp--package-started))
      (setq +cpp--package-started nil)
      (if (not (string-prefix-p "finished" status))
          (message "Packaging failed; see the buffer")
        (let ((made (+cpp--packages dir time)))
          (message "%s; SPC k o copies it where the packages go"
                   (if made
                       (format "Packaged: %s" (mapconcat #'file-name-nondirectory made ", "))
                     "The target finished; nothing new in the build directory")))))))

;;;###autoload
(defun +cpp/package (target)
  "Build TARGET, the one that packages this project, where the kit runs:
an hpkg target of the Horizon SDK, CMake's own package, or whatever
the project calls it.  Offered from the targets the build directory
knows; the choice is kept in .dir-locals.el.  When it ends, the
packages it wrote are named."
  (interactive
   (let* ((root (+core-project-root))
          (kit (+cpp--kit root))
          (candidates (+cpp--package-targets kit root))
          (kept (+cpp--setting '+cpp-package-target)))
     (list (cond ((and kept (not current-prefix-arg)) kept)
                 ((null candidates)
                  (user-error "No packaging target in %s; SPC k B lists every target"
                              (+cpp-kit-name kit)))
                 ((and (null (cdr candidates)) (not current-prefix-arg)) (car candidates))
                 (t (completing-read "Package with: " candidates nil t nil nil kept))))))
  (+cpp--save-project-buffers)
  (let* ((root (+core-project-root))
         (kit (+cpp--kit root)))
    (unless (equal target (+cpp--setting '+cpp-package-target))
      (+cpp--set-setting '+cpp-package-target target))
    (setq +cpp--package-started (cons root (cons (+cpp-kit-abs-dir kit root) (float-time))))
    (add-hook 'compilation-finish-functions #'+cpp--packaged-h)
    (+cpp--compile "package" (+cpp--build-target-command target))))

;;;###autoload
(defun +cpp/package-copy (file dir)
  "Copy FILE, the newest package the kit's build directory holds unless
another is chosen, into DIR, where this project's packages go, asked
the first time and kept in .dir-locals.el."
  (interactive
   (let* ((root (+core-project-root))
          (kit (+cpp--kit root))
          (packages (or (+cpp--packages (+cpp-kit-abs-dir kit root))
                        (user-error "No package in %s yet; SPC k P makes one" (+cpp-kit-name kit))))
          (file (if current-prefix-arg
                    (completing-read "Package: " packages nil t)
                  (car packages)))
          (dir (or (+cpp--setting '+cpp-package-dir)
                   (read-directory-name "Packages go to: " nil nil nil))))
     (list file dir)))
  (unless (equal dir (+cpp--setting '+cpp-package-dir))
    (+cpp--set-setting '+cpp-package-dir (abbreviate-file-name dir)))
  (make-directory dir t)
  (let ((to (expand-file-name (file-name-nondirectory file) dir)))
    (copy-file file to t)
    (message "%s is in %s" (file-name-nondirectory file) (abbreviate-file-name dir))))


;;
;;; The project's scripts

(defun +cpp--scripts (root)
  "The scripts of the project at ROOT: executables under scripts/,
tools/ and bin/, and shell scripts at the top, relative to ROOT."
  (let (scripts)
    (dolist (dir '("scripts" "tools" "bin"))
      (let ((full (expand-file-name dir root)))
        (when (file-directory-p full)
          (dolist (file (directory-files full t "\\`[^.]"))
            (when (and (file-regular-p file) (file-executable-p file))
              (push (file-relative-name file root) scripts))))))
    (dolist (file (directory-files root t "\\.\\(?:sh\\|py\\)\\'"))
      (when (file-regular-p file)
        (push (file-relative-name file root) scripts)))
    (sort scripts #'string<)))

(defvar +cpp--script-args (make-hash-table :test #'equal)
  "Script to the arguments it was last run with, this session.")

;;;###autoload
(defun +cpp/run-script (script args)
  "Run SCRIPT, one of the project's own, with ARGS, where the kit runs
and with its SDK environment: a deploy script, a build_arm.sh, a
tester.  The arguments last given are offered again."
  (interactive
   (let* ((root (+core-project-root))
          (scripts (or (+cpp--scripts root)
                       (user-error "No scripts in %s: nothing executable under scripts/, tools/, bin/ or a .sh at the top"
                                   (abbreviate-file-name root))))
          (script (completing-read "Run: " scripts nil t)))
     (list script (read-string (format "%s arguments: " script)
                               (gethash script +cpp--script-args)))))
  (+cpp--save-project-buffers)
  (puthash script args +cpp--script-args)
  (let* ((root (+core-project-root))
         (kit (and (+cpp--kind-p 'cmake) (+cpp--kit root)))
         (line (string-trim (concat (shell-quote-argument (concat "./" script)) " " args))))
    (+cpp--compile (format "script: %s" (file-name-nondirectory script))
                   (if kit (+cpp--kit-shell kit line root) line)
                   t)))
