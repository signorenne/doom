;;; private/cpp/autoload/compdb.el -*- lexical-binding: t; -*-
;;
;; Any C or C++ project's compilation database read by clangd, with
;; nothing set up: found where build systems write it, made readable to
;; clang by bin/clangd-db when it names a cross compiler or flags clang
;; refuses, and the server pointed at it and allowed to ask those
;; compilers for their headers. A CMake project never configured here is
;; configured once, in the background. A PlatformIO project has its own
;; way, in pio.el, which this leaves to it.

(declare-function +pio--root "pio")
(declare-function +cpp--restart-servers "lsp")
(declare-function +cpp--compile-commands-file "kit")
(declare-function +cpp--kit "kit")
(declare-function +cpp--configure-command "kit")
(declare-function +cpp-kit-configured "kit")
(declare-function +cpp-kit-container "kit")
(declare-function +cpp-kit-env-script "kit")
(declare-function +cpp-kit-env "kit")
(declare-function +cpp-kit-dir "kit")
(declare-function +core-project-root-or-nil "lib")
(defvar +cpp-modes)
(defvar projection-cmake-kit)

(defvar +cpp-compdb-places
  '("compile_commands.json" "build/compile_commands.json"
    "build*/compile_commands.json" "build/*/compile_commands.json"
    "cmake-build-*/compile_commands.json" "out/build/*/compile_commands.json")
  "Where a project's compile_commands.json is looked for, from its root:
the root, where bear and a link put it; build/, where CMake, ESP-IDF's
idf.py and Zephyr's west write it; a kit's or a preset's build directory.
The kits' own directories are asked as well.")

;;;###autoload
(defun +cpp--compdb-source (root)
  "ROOT's newest compilation database, absolute, or nil."
  (let ((found (append (mapcan (lambda (glob)
                                 (file-expand-wildcards (expand-file-name glob root) t))
                               +cpp-compdb-places)
                       (when-let* ((db (ignore-errors (+cpp--compile-commands-file nil root))))
                         (list db)))))
    (car (sort (delete-dups (mapcar #'file-truename (seq-filter #'file-regular-p found)))
               #'file-newer-than-file-p))))

(defun +cpp--compdb-dir (root)
  "Where ROOT's database for clangd is kept: in Doom's cache, so no
project's tree gets a file it did not ask for. clangd keeps its index
beside it."
  (expand-file-name (concat "clangd-db/" (md5 (directory-file-name (expand-file-name root))) "/")
                    doom-cache-dir))

(defun +cpp--compdb-note (root)
  "What was decided for ROOT's database, (SOURCE . HOW), HOW being `copy'
or `as-is', or nil.  Read from the note written beside the copy."
  (let ((note (expand-file-name "source" (+cpp--compdb-dir root))))
    (when (file-readable-p note)
      (with-temp-buffer
        (insert-file-contents note)
        (pcase (split-string (buffer-string) "\n" t)
          (`(,how ,source) (cons source (intern how))))))))

(defun +cpp--compdb-current-p (root source)
  "Non-nil when the note for ROOT is about SOURCE and younger than it."
  (when-let* ((note (+cpp--compdb-note root))
              ((equal (car note) source)))
    (let ((what (if (eq (cdr note) 'copy)
                    (expand-file-name "compile_commands.json" (+cpp--compdb-dir root))
                  (expand-file-name "source" (+cpp--compdb-dir root)))))
      (and (file-exists-p what) (not (file-newer-than-file-p source what))))))

;;;###autoload
(defun +cpp--compdb-drivers (dir)
  "The cross compilers listed in DIR's query-drivers, which bin/clangd-db
writes beside its copy."
  (let ((file (expand-file-name "query-drivers" dir)))
    (when (file-readable-p file)
      (with-temp-buffer
        (insert-file-contents file)
        (split-string (buffer-string) "\n" t)))))

;;;###autoload
(defun +cpp--compdb-for-clangd (root)
  "(DIR . DRIVERS) for clangd in ROOT, not a PlatformIO project: the
directory of the database it is to read and the compilers it may ask.
The copy once it is there and current, else the database as it is."
  (when-let* ((root root)
              (source (+cpp--compdb-source root)))
    (if (and (+cpp--compdb-current-p root source)
             (eq (cdr (+cpp--compdb-note root)) 'copy))
        (let ((dir (+cpp--compdb-dir root)))
          (cons dir (+cpp--compdb-drivers dir)))
      (cons (file-name-directory source) nil))))

(defvar +cpp--compdb-tried (make-hash-table :test #'equal)
  "ROOT to (SOURCE . TIME) last worked from, so a database that cannot be
made readable is not tried again at every file.")

(defun +cpp--compdb-write-note (root source how)
  (let ((dir (+cpp--compdb-dir root)))
    (make-directory dir t)
    (with-temp-file (expand-file-name "source" dir)
      (insert (symbol-name how) "\n" source "\n"))))

(defun +cpp--compdb-update (root &optional restart)
  "Make ROOT's database readable to clangd in the background, then start
its servers again when what they read changed, or always with RESTART."
  (when-let* ((source (+cpp--compdb-source root))
              (python (executable-find "python3"))
              (stamp (cons source (file-attribute-modification-time (file-attributes source))))
              ((or restart (not (equal (gethash root +cpp--compdb-tried) stamp)))))
    (puthash root stamp +cpp--compdb-tried)
    (let ((dir (+cpp--compdb-dir root)))
      (make-process
       :name "clangd-db"
       :buffer (generate-new-buffer " *clangd db*")
       :noquery t
       :command (list python (expand-file-name "bin/clangd-db" doom-user-dir)
                      source (expand-file-name "compile_commands.json" dir))
       :sentinel
       (lambda (process _event)
         (unless (process-live-p process)
           (let ((status (process-exit-status process))
                 (said (with-current-buffer (process-buffer process)
                         (string-trim (buffer-string)))))
             (kill-buffer (process-buffer process))
             (pcase status
               (0 (+cpp--compdb-write-note root source 'copy)
                  (+cpp--restart-servers root)
                  (message "clangd: %s, %s" (file-name-nondirectory (directory-file-name root)) said))
               (3 (+cpp--compdb-write-note root source 'as-is)
                  (when restart (+cpp--restart-servers root)))
               (_ (message "clangd: the database of %s could not be made readable: %s"
                           (file-name-nondirectory (directory-file-name root)) said))))))))))


;;
;;; A CMake project never configured here

(defvar +cpp--configure-tried nil
  "Roots this session has configured in the background, or tried to.")

(defun +cpp--configure-for-clangd (root)
  "Configure ROOT, a CMake project with no build directory, in the
background, then give clangd its database.  Not for a kit that runs in
a container or with an SDK's environment, which would start the one or
source the other behind your back; nor twice a session, so a configure
that fails is not tried at every file."
  (when-let* (((not (member root +cpp--configure-tried)))
              ((file-exists-p (expand-file-name "CMakeLists.txt" root)))
              ((executable-find "cmake"))
              (kit (ignore-errors (let ((default-directory root)) (+cpp--kit root))))
              ((not (+cpp-kit-configured kit)))
              ((not (or (+cpp-kit-container kit) (+cpp-kit-env-script kit) (+cpp-kit-env kit)))))
    (push root +cpp--configure-tried)
    (let* ((default-directory root)
           (name (file-name-nondirectory (directory-file-name root)))
           ;; Asked nothing: projection would have a compiler kit picked
           ;; from VS Code's list. Any other question stops the configure
           ;; with a message, since opening a file should not prompt.
           (command (condition-case err
                        (let ((projection-cmake-kit 'silent)
                              (inhibit-interaction t))
                          (+cpp--configure-command))
                      (error (message "cmake: %s not configured in the background: %s; SPC k c configures it"
                                      name (error-message-string err))
                             nil))))
      (when command
        (message "cmake: configuring %s into %s in the background, for clangd..."
                 name (+cpp-kit-dir kit))
        (make-process
         :name "cmake-configure"
         :buffer (generate-new-buffer (format " *cmake configure %s*" name))
         :noquery t
         :command (list shell-file-name shell-command-switch command)
         :sentinel
         (lambda (process _event)
           (unless (process-live-p process)
             (if (eq (process-exit-status process) 0)
                 (progn (kill-buffer (process-buffer process))
                        (message "cmake: %s configured" name)
                        (+cpp--compdb-update root 'restart))
               (message "cmake: the background configure of %s failed; SPC k c runs it where you can see why"
                        name)))))))))

;; Autoloaded: called from `find-file-hook' in config.el.
;;;###autoload
(defun +cpp--compdb-h ()
  "Give clangd this file's project database, with nothing set up: made
readable when it is missing or older than the project's, the project
configured when it has none.  A PlatformIO project is pio.el's."
  (when-let* (((apply #'derived-mode-p +cpp-modes))
              ((not (file-remote-p default-directory)))
              ((not (ignore-errors (+pio--root 'noerror))))
              (root (+core-project-root-or-nil))
              (root (expand-file-name root)))
    (if-let* ((source (+cpp--compdb-source root)))
        (unless (+cpp--compdb-current-p root source)
          (+cpp--compdb-update root))
      (+cpp--configure-for-clangd root))))
