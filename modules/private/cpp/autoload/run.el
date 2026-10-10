;;; private/cpp/autoload/run.el -*- lexical-binding: t; -*-
;;
;; Run and debug one of the project's executables, where the kit runs,
;; with the arguments and working directory Qt Creator uses.

(defvar compilation-start-hook)
(declare-function +core/debug "build")
(declare-function +cpp--save-project-buffers "project")
(declare-function +cpp--kind-p "project")
(defvar +cpp-modes)
(declare-function +cpp-kit-name "kit")
(declare-function +cpp-kit-configs "kit")
(declare-function +cpp--device-run-p "device")
(declare-function +cpp/run-on-device "device")
(declare-function +cpp--kit-config "kit")
(declare-function +cpp-kit-abs-dir "kit")
(declare-function +cpp--kit-shell "container")
(declare-function dape-continue "dape")
(declare-function gdb "gdb-mi")
(declare-function projection-commands-run-project "projection-commands")


;;
;;; Which executable

(defun +cpp--file-api-executables (build-dir &optional config)
  "Executables in the newest file API reply of BUILD-DIR, in projection's
shape: an alist with name, type, category and arg0 per artifact, of
the configuration CONFIG when the generator has several, else of the
one there is.  Reads the shared codemodel, which Qt Creator's configure
writes and projection's own client query does not cover."
  (pcase-let ((`(,reply . ,codemodel) (+cpp--file-api-codemodel build-dir)))
    (when codemodel
      (let* ((configurations (alist-get 'configurations codemodel))
             (configuration (or (and config
                                     (seq-find (lambda (c) (equal (alist-get 'name c) config))
                                               configurations))
                                (car configurations))))
        (cl-loop for target in (alist-get 'targets configuration)
                 for info = (+cpp--file-api-read (expand-file-name (alist-get 'jsonFile target) reply))
                 when (equal (alist-get 'type info) "EXECUTABLE")
                 append (mapcar (lambda (artifact)
                                  (let ((path (alist-get 'path artifact)))
                                    `((name . ,path)
                                      (type . cmake-executable)
                                      (debuggable . t)
                                      (category . "CMake executable")
                                      (arg0 . ,(expand-file-name path build-dir)))))
                                (alist-get 'artifacts info)))))))

(defun +cpp--file-api-read (file)
  "FILE, a file API reply, parsed to alists and lists."
  (with-temp-buffer
    (insert-file-contents file)
    (json-parse-buffer :object-type 'alist :array-type 'list)))

(defun +cpp--file-api-codemodel (build-dir)
  "The codemodel of the newest file API reply of BUILD-DIR, as
(REPLY-DIR . CODEMODEL), or nil without one."
  (let* ((reply (expand-file-name ".cmake/api/v1/reply/" build-dir))
         (index (and (file-directory-p reply)
                     (car (last (sort (directory-files reply t "\\`index-.*\\.json\\'")
                                      #'string<))))))
    (when-let* ((index)
                (codemodel-file
                 (seq-some (lambda (object)
                             (and (equal (alist-get 'kind object) "codemodel")
                                  (alist-get 'jsonFile object)))
                           (alist-get 'objects (+cpp--file-api-read index)))))
      (cons reply (+cpp--file-api-read (expand-file-name codemodel-file reply))))))

;; Autoloaded: device.el reads a target's install destination with it.
;;;###autoload
(defun +cpp--file-api-target (build-dir name &optional config)
  "The target NAME of BUILD-DIR's file API reply, parsed, of the
configuration CONFIG when the generator has several; nil without."
  (pcase-let ((`(,reply . ,codemodel) (+cpp--file-api-codemodel build-dir)))
    (when codemodel
      (let* ((configurations (alist-get 'configurations codemodel))
             (configuration (or (and config (seq-find (lambda (c) (equal (alist-get 'name c) config)) configurations))
                                (car configurations)))
             (target (seq-find (lambda (tg) (equal (alist-get 'name tg) name))
                               (alist-get 'targets configuration))))
        (and target (+cpp--file-api-read (expand-file-name (alist-get 'jsonFile target) reply)))))))

;; Autoloaded: kit.el lists the targets with it.
;;;###autoload
(defun +cpp--file-api-target-names (build-dir)
  "The names of every target in the newest file API reply of BUILD-DIR,
custom targets included, from the shared codemodel; nil without one."
  (when-let* ((codemodel (cdr (+cpp--file-api-codemodel build-dir)))
              (config (car (alist-get 'configurations codemodel))))
    (mapcar (lambda (target) (alist-get 'name target))
            (alist-get 'targets config))))

;; Autoloaded: kit.el and tasks.el list the targets with it.
;;;###autoload
(defun +cpp--target-names (kit &optional root)
  "The names of KIT's targets under ROOT: from the file API reply when
the directory has one, else from the generator's help target, which
Makefiles and Ninja both provide, asked where the kit runs."
  (let* ((root (or root (+core-project-root)))
         (dir (+cpp-kit-abs-dir kit root)))
    (or (+cpp--file-api-target-names dir)
        (and (file-exists-p (expand-file-name "CMakeCache.txt" dir))
             (let ((output (shell-command-to-string
                            (+cpp--kit-shell kit
                                             (format "cmake --build %s --target help"
                                                     (shell-quote-argument dir))
                                             root))))
               (cl-loop for line in (split-string output "\n" t)
                        ;; Makefiles: "... name"; Ninja: "name: phony".
                        when (string-match "\\`\\(?:\\.\\.\\. \\([^ ]+\\)\\|\\([^ :]+\\): \\)" line)
                        collect (or (match-string 1 line) (match-string 2 line))))))))

(defun +cpp--file-api-ask (kit)
  "Have CMake write the shared codemodel for KIT's build directory: the
query file placed, then a plain regeneration where the kit runs, a few
seconds.  For a directory that was configured on the command line,
which has no reply until someone asks.  Non-nil when a reply is there
afterwards."
  (let* ((dir (+cpp-kit-abs-dir kit))
         (query (expand-file-name ".cmake/api/v1/query/codemodel-v2" dir)))
    (when (file-exists-p (expand-file-name "CMakeCache.txt" dir))
      (make-directory (file-name-directory query) t)
      (unless (file-exists-p query) (write-region "" nil query))
      (message "Asking CMake what %s builds..." (+cpp-kit-name kit))
      (shell-command-to-string
       (+cpp--kit-shell kit (format "cmake %s" (shell-quote-argument dir))))
      (+cpp--file-api-codemodel dir))))

(defun +cpp--runnable-p (artifacts)
  "Non-nil when ARTIFACTS holds something to run and not only tests."
  (seq-some (lambda (a) (eq (alist-get 'type a) 'cmake-executable)) artifacts))

(defun +cpp--executable-artifacts (kit)
  "Executables CMake knows about in KIT's build directory, or nil.
Read from the file API reply: projection's client query, which a
configure through SPC k c writes, else the shared codemodel of a
directory Qt Creator configured, else one asked for now, for a
directory configured on the command line.

Each answer is taken only if it holds an executable.  A directory
configured outside projection leaves it with the ctest targets and
nothing to run, which is an answer, and the shorter kind of `or' would
stop at it and never read the reply that has the program in it."
  (let ((projection (and (not (+cpp-kit-configs kit))
                         (+cpp--with-kit kit
                           (+cpp--projection-artifacts (+cpp--projection-project))))))
    (cond
     ((+cpp--runnable-p projection) projection)
     ((let ((reply (+cpp--file-api-executables (+cpp-kit-abs-dir kit)
                                               (+cpp--kit-config kit))))
        (and (+cpp--runnable-p reply) reply)))
     ((and (+cpp--file-api-ask kit)
           (let ((reply (+cpp--file-api-executables (+cpp-kit-abs-dir kit)
                                                    (+cpp--kit-config kit))))
             (and (+cpp--runnable-p reply) reply))))
     (t projection))))

(defun +cpp--run-argv (args)
  "The program arguments in ARGS as a list, split the way Qt Creator splits
its arguments field: on spaces, quotes grouping, no shell behind it, so
run and debug pass the same words."
  (if (and args (not (string-empty-p args)))
      (split-string-and-unquote args)
    nil))

;; Autoloaded: debug.el picks what to debug.
;;;###autoload
(defun +cpp--pick-executable (kit)
  "The executable to run for KIT: the run target chosen for the project,
Qt Creator's active run configuration, the only one there is, or asked."
  (let* ((exes (seq-filter (lambda (a) (eq (alist-get 'type a) 'cmake-executable))
                           (+cpp--executable-artifacts kit)))
         (root (+core-project-root))
         (wanted (or (+cpp--setting '+cpp-run-target)
                     (plist-get (+qtcreator-active root) :run-target)))
         (named (and wanted
                     (seq-find (lambda (a)
                                 (member wanted
                                         (list (alist-get 'name a)
                                               (file-name-nondirectory
                                                (or (alist-get 'arg0 a) "")))))
                               exes))))
    (cond (named (alist-get 'arg0 named))
          ((= (length exes) 1) (alist-get 'arg0 (car exes)))
          (exes (alist-get 'arg0
                           (let ((rows (mapcar (lambda (a) (cons (alist-get 'name a) a)) exes)))
                             (cdr (assoc (completing-read "Run executable: " rows nil t)
                                         rows)))))
          (t (user-error "No executable known for kit %s; configure and build first (SPC k c, SPC k b)"
                         (+cpp-kit-name kit))))))


;;
;;; Run

;;;###autoload
(defun +cpp/run (&optional args)
  "Run one of the project's executables, passing it ARGS.
ARGS defaults to what `+cpp/set-run-args' stored for this project, or to
Qt Creator's run configuration.  The program runs where the kit runs, in
the working directory Qt Creator uses, or beside the executable.  CMake
projects offer their targets; anything else uses projection's run command,
which for PlatformIO means upload."
  (interactive)
  (+cpp--save-project-buffers)
  (let ((root (+core-project-root)))
    (if (+cpp--kind-p 'cmake)
        (let* ((kit (+cpp--kit root))
               (active (+qtcreator-active root))
               (args (or args
                         (+cpp--setting '+cpp-run-args)
                         (plist-get active :run-args))))
          (if (+cpp--device-run-p kit)
              ;; Qt Creator's run configuration is on the device.
              (+cpp/run-on-device args)
            (let* ((exe (+cpp--pick-executable kit))
                   (dir (let ((qtc (plist-get active :run-dir)))
                          (if (and qtc (file-directory-p qtc)) qtc
                            (file-name-directory exe)))))
              (+cpp--compile (format "run: %s" (file-name-nondirectory exe))
                             (+cpp--kit-shell
                              kit
                              (format "cd %s && %s"
                                      (shell-quote-argument dir)
                                      (mapconcat #'shell-quote-argument
                                                 (cons exe (+cpp--run-argv args))
                                                 " ")))
                             t))))
      ;; It takes the project and the command, which its interactive
      ;; form works out: called bare it failed on the number of them.
      (when (and args (not (string-empty-p args)))
        (user-error "Only a CMake project's programs are given arguments here"))
      (call-interactively #'projection-commands-run-project))))

;;;###autoload
(defun +cpp/run-with-args (args)
  "Run a project executable with ARGS."
  (interactive (list (read-string "Program arguments: ")))
  (+cpp/run args))

;;;###autoload
(defun +cpp/set-run-target (name)
  "Run the executable target NAME with SPC k r, from now on."
  (interactive
   (let* ((exes (seq-filter (lambda (a) (eq (alist-get 'type a) 'cmake-executable))
                            (+cpp--executable-artifacts (+cpp--kit)))))
     (list (completing-read "Run target: " (mapcar (lambda (a) (alist-get 'name a)) exes)
                            nil nil nil nil (+cpp--setting '+cpp-run-target)))))
  (+cpp--set-setting '+cpp-run-target name)
  (message "Run target: %s, saved to .dir-locals.el" name))

;;;###autoload
(defun +cpp/set-run-args (args)
  "Set the ARGS every run of this project passes to the executable."
  (interactive (list (read-string "Program arguments: "
                                  (+cpp--setting '+cpp-run-args ""))))
  (+cpp--set-setting '+cpp-run-args args)
  (message "Run arguments: %s, saved to .dir-locals.el"
           (if (string-empty-p args) "none" args)))


;;
;;; Debug

;;;###autoload
(defun +cpp--read-program (&rest _)
  "Ask which executable to debug, starting in the build directory."
  (let* ((root (+core-project-root 'noerror))
         (build (+cpp-kit-abs-dir (+cpp--kit root) root))
         (start (if (file-directory-p build) build root)))
    (expand-file-name (read-file-name "Program to debug: " start nil t))))

;;;###autoload
(defun +cpp--read-pid (&rest _)
  "Ask which process to attach to."
  (read-number "Attach to PID: "))

;;;###autoload
(cl-defun +cpp/debug ()
  "Debug the project's executable where the kit runs.
CMake: the run target, with gdb, in the kit's container.  Rust: the crate
binary with codelldb (`+cpp/install-codelldb' fetches it).  Anything
else asks for the program and uses gdb."
  (interactive)
  (require 'dape)
  (+cpp--save-project-buffers)
  (let* ((root (+core-project-root))
         (kit (and (+cpp--kind-p 'cmake) (+cpp--kit root)))
         (exe (cond (kit (+cpp--pick-executable kit))
                    ((derived-mode-p 'rust-mode 'rust-ts-mode 'rustic-mode)
                     ;; dape's codelldb-rust config knows target/debug/<crate>.
                     (cl-return-from +cpp/debug
                       (dape (+cpp--dape-config 'codelldb-rust))))
                    (t (+cpp--read-program))))
         (active (and kit (+qtcreator-active root)))
         (args (or (+cpp--setting '+cpp-run-args) (plist-get active :run-args) ""))
         (cwd (let ((qtc (plist-get active :run-dir)))
                (if (and qtc (file-directory-p qtc)) qtc (file-name-directory exe))))
         (command (if kit
                      (+cpp--kit-process kit '("gdb" "--interpreter=dap"))
                    '("gdb" "--interpreter=dap")))
         (config `(modes ,+cpp-modes
                   command ,(car command)
                   command-args ,(cdr command)
                   :type "gdb"
                   :request "launch"
                   :program ,exe
                   :cwd ,cwd
                   :args ,(vconcat (+cpp--run-argv args))
                   :stopAtBeginningOfMainSubprogram t)))
    (dape config)))

;;;###autoload
(defun +cpp/debug-or-continue ()
  "Continue the running debug session, or start one."
  (interactive)
  ;; Started as SPC k d is: it was the C++ debug, which in a Pascal,
  ;; Rust or web project asked for a program instead of knowing it.
  (if (+cpp--dape-stopped-p)
      (call-interactively #'dape-continue)
    (call-interactively #'+core/debug)))

;;;###autoload
(defun +cpp/install-codelldb ()
  "Download codelldb, the debugger for Rust, into Doom's debug-adapters.
dape looks for it there; SPC k d in a Rust buffer uses it afterwards."
  (interactive)
  (let* ((dir (expand-file-name "debug-adapters/codelldb" doom-user-dir))
         (version "1.11.4")
         (url (format "https://github.com/vadimcn/codelldb/releases/download/v%s/codelldb-linux-x64.vsix"
                      version))
         (vsix (expand-file-name "codelldb.vsix" temporary-file-directory)))
    (unless (executable-find "unzip") (user-error "unzip is not installed"))
    (make-directory dir t)
    (message "Downloading codelldb %s..." version)
    (url-copy-file url vsix t)
    (unless (zerop (call-process "unzip" nil nil nil "-oq" vsix "-d" dir))
      (user-error "unzip failed on %s" vsix))
    (delete-file vsix)
    (let ((adapter (expand-file-name "extension/adapter/codelldb" dir)))
      (set-file-modes adapter #o755)
      (message "codelldb installed: %s" adapter))))

;;
;;; Build and run in one

(defvar +cpp--run-after-build nil
  "(ORIGIN . BUILD): the buffer a build was started from, which should be
followed by a run, and the build's compilation buffer.  The buffer and
not a flag: a timer runs in whatever buffer happens to be current when
it fires, and `+cpp/run' asks the current buffer which project it is
in.  The build's own buffer, since any compilation that finished first,
the assembly view's, ran the program before the build was done.")

;; Autoloaded: on `compilation-finish-functions', added in config.el.
;;;###autoload
(defun +cpp--run-after-build-h (buffer status)
  "Run what was built, when BUFFER finished with STATUS and was asked to.
A build that failed stops here, with its output where it is: the reason
is what you wanted to see, not a program that cannot have changed."
  (when (and +cpp--run-after-build
             (eq buffer (cdr +cpp--run-after-build))
             (buffer-live-p buffer))
    (let ((origin (car +cpp--run-after-build)))
      (setq +cpp--run-after-build nil)
      (if (equal status "finished\n")
          (run-at-time 0 nil
                       (lambda ()
                         (when (buffer-live-p origin)
                           (with-current-buffer origin
                             (call-interactively #'+cpp/run)))))
        (message "Build failed, so nothing was run")))))

;;;###autoload
(defun +cpp/build-and-run ()
  "Build the project and run it when the build succeeded.
The two keys in one, since that is the pair you press all day."
  (interactive)
  (let ((origin (current-buffer))
        build)
    (setq +cpp--run-after-build nil)
    ;; The build's buffer, from the hook that sees it start; set once the
    ;; command is back, so a build it interrupted is not taken for it.
    (let ((compilation-start-hook
           (cons (lambda (process) (setq build (process-buffer process)))
                 compilation-start-hook)))
      (call-interactively #'projection-commands-build-project))
    (when build
      (setq +cpp--run-after-build (cons origin build)))))
