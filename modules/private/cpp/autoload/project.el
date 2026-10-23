;;; private/cpp/autoload/project.el -*- lexical-binding: t; -*-
;;
;; What every command asks first: what kind of project this is, where it
;; is, what it keeps in .dir-locals.el, and how a command of it runs.

(defvar +core-compile-name)
(defvar +cpp-modes)

(defvar +cpp--kind-cache (make-hash-table :test #'equal)
  "Project root to (ROOT-MTIME . KIND).  The menu asks twenty times per
redraw; a marker file appearing or going changes the root's mtime.")


;;
;;; What kind of project

;; Autoloaded: called from the menus.
;;;###autoload
(defun +cpp--project-kind ()
  "What kind of project this is, by its marker files: `cmake',
`platformio', `cargo', `meson', `gradle', `maven', `npm', `make',
`python' or nil."
  (let* ((root (file-name-as-directory (+core-project-root 'noerror)))
         (mtime (file-attribute-modification-time (file-attributes root)))
         (hit (gethash root +cpp--kind-cache)))
    (if (and hit (equal (car hit) mtime))
        (cdr hit)
      (let* ((has (lambda (&rest files)
                    (seq-some (lambda (f) (file-exists-p (expand-file-name f root)))
                              files)))
             (kind (cond ((funcall has "platformio.ini") 'platformio)
                         ((funcall has "CMakeLists.txt") 'cmake)
                         ((funcall has "Cargo.toml") 'cargo)
                         ((funcall has "meson.build") 'meson)
                         ((funcall has "build.gradle" "build.gradle.kts"
                                   "settings.gradle" "settings.gradle.kts")
                          'gradle)
                         ((funcall has "pom.xml") 'maven)
                         ((funcall has "package.json") 'npm)
                         ((funcall has "Makefile" "GNUmakefile" "makefile") 'make)
                         ((funcall has "pyproject.toml" "setup.py" "requirements.txt")
                          'python)
                         (t nil))))
        (puthash root (cons mtime kind) +cpp--kind-cache)
        kind))))

;;;###autoload
(defun +cpp-project-p ()
  "Non-nil in a C or C++ project: CMake, PlatformIO, Meson or make."
  (+cpp--kind-p 'cmake 'platformio 'meson 'make))

;; Autoloaded: called from the menus.
;;;###autoload
(defun +cpp--kind-p (&rest kinds)
  "Non-nil when the project is one of KINDS."
  (memq (+cpp--project-kind) kinds))


;;
;;; Where the project is

;;;###autoload
(defun +cpp--project-try-build-root (dir)
  "Find the project DIR belongs to, for `project-find-functions'.
The nearest platformio.ini, else the topmost CMakeLists.txt."
  (when-let* ((root (or (locate-dominating-file dir "platformio.ini")
                        (let ((cur (locate-dominating-file
                                    dir "CMakeLists.txt"))
                              top)
                          (while cur
                            (setq top cur
                                  cur (locate-dominating-file
                                       (file-name-directory
                                        (directory-file-name cur))
                                       "CMakeLists.txt")))
                          top))))
    (cons 'transient (file-name-as-directory (expand-file-name root)))))

;;;###autoload
(defun +cpp--project-root-or-cwd ()
  "Project root, or `default-directory'.  Used as dape's :cwd."
  (+core-project-root 'noerror))

;; Autoloaded: called from run.el and style.el.
;;;###autoload
(defun +cpp--save-project-buffers ()
  "Save every modified file of the project, the way a build does."
  (let ((root (+core-project-root 'noerror)))
    (save-some-buffers t (lambda ()
                           (and buffer-file-name root
                                (file-in-directory-p buffer-file-name root))))))


;;
;;; Settings kept in .dir-locals.el

;;;###autoload
(defun +cpp--setting (key &optional default)
  "Value of project setting KEY, or DEFAULT.
The buffer-local value when this buffer has one (a .dir-locals.el entry
for its mode or subdirectory, a setq-local, the setter below), else the
entry for every mode in the project's .dir-locals.el, which is what a
transient or a compilation buffer sees."
  (or (and (local-variable-p key) (symbol-value key))
      (when-let* ((root (+core-project-root 'noerror))
                  (locals (+core-dir-locals-read root))
                  (entry (assq nil locals)))
        (alist-get key (cdr entry)))
      default))

;;;###autoload
(defun +cpp--set-setting (key value)
  "Store VALUE as project setting KEY in .dir-locals.el.
Settings survive a restart and can be read or edited by hand, which is
what a build configuration should do.  The C, C++, CMake and QML
buffers of the project pick the value up at once."
  (when-let* ((root (+core-project-root 'noerror)))
    (+core-dir-locals-set root key value)
    (dolist (buffer (buffer-list))
      (with-current-buffer buffer
        ;; The C and C++ buffers, and the CMake and QML ones a project
        ;; carries, which read the same settings.
        (when (and buffer-file-name
                   (apply #'derived-mode-p
                          (append +cpp-modes
                                  '(cmake-mode cmake-ts-mode qml-mode qml-ts-mode)))
                   (file-in-directory-p buffer-file-name root))
          (set (make-local-variable key) value)))))
  value)


;;
;;; Running a command

;;;###autoload
(defun +cpp--compile (name command &optional comint)
  "Run shell COMMAND in the compilation buffer *NAME* from the project root.
COMMAND is complete: whoever builds it wraps it for the kit.  With
COMINT the buffer takes input.  The buffer carries NAME in
`+core-compile-name', which is how the reindex hook finds its own."
  (+core-compile name command (+core-project-root) comint))
