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
(declare-function +cpp--kit-compiler-missing-p "kit")
(declare-function +cpp--kit-shell "container")
(declare-function +core-need-program "lib")
(declare-function +core-read-arguments "lib")
(declare-function +core-read-or-empty "lib")
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
             (+cpp--help-target-names kit dir root)))))

(defvar +cpp--help-targets (make-hash-table :test #'equal)
  "Build directory to (STAMP . NAMES), the targets its generator listed.")

(defun +cpp--help-target-names (kit dir root)
  "The targets of KIT's build directory DIR, as its generator's help
target lists them, asked where the kit runs. Kept until the build file,
the cache or the top CMakeLists.txt changes."
  (let* ((build (seq-find #'file-exists-p
                          (mapcar (lambda (f) (expand-file-name f dir))
                                  '("build.ninja" "Makefile"))))
         (stamp (and build
                     (mapcar (lambda (file)
                               (cons file (file-attribute-modification-time
                                           (file-attributes file))))
                             (list build
                                   (expand-file-name "CMakeCache.txt" dir)
                                   (expand-file-name "CMakeLists.txt" root)))))
         (have (gethash dir +cpp--help-targets)))
    (if (and stamp (equal (car have) stamp))
        (cdr have)
      (let* ((code nil)
             (ask (lambda (args)
                    (with-temp-buffer
                      (setq code (process-file shell-file-name nil t nil
                                               shell-command-switch
                                               (+cpp--kit-shell kit
                                                                (format "cmake --build %s %s"
                                                                        (shell-quote-argument dir) args)
                                                                root)))
                      (buffer-string))))
             (output (funcall ask "--target help"))
             (names (cl-loop for line in (split-string output "\n" t)
                             ;; Makefiles: "... name"; Ninja: "name: phony".
                             when (string-match "\\`\\(?:\\.\\.\\. \\([^ ]+\\)\\|\\([^ :]+\\): \\)" line)
                             collect (or (match-string 1 line) (match-string 2 line)))))
        ;; Ninja's help leaves out the programs and libraries, which its
        ;; full list names by their link rule.
        (when (and (eql code 0) (string-suffix-p "build.ninja" build))
          (let ((linked (funcall ask "-- -t targets all")))
            (when (eql code 0)
              (setq names
                    (delete-dups
                     (append names
                             (cl-loop for line in (split-string linked "\n" t)
                                      when (string-match "_\\(?:EXECUTABLE\\|STATIC_LIBRARY\\|SHARED_LIBRARY\\|MODULE\\)_LINKER__\\(.+\\)_\\'" line)
                                      collect (match-string 1 line))))))))
        ;; Only an answer: a failure's lines would pass for targets.
        (when (and stamp names (eql code 0))
          (puthash dir (cons stamp names) +cpp--help-targets))
        names))))

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

(defvar +cpp--file-api-asked nil
  "Build directories asked for their codemodel in the background.")

;;;###autoload
(defun +cpp--file-api-prefetch ()
  "Ask CMake in the background for the codemodel of this project's build
directory when it has no file API reply, so running or debugging finds
it rather than waiting for CMake. Not for a remote file or a container
kit, which a run asks for itself, nor one whose compiler is not on the
host, which a stopped container may hold, nor during a build."
  (ignore-errors
    (let* ((kit (+cpp--kit))
           (dir (+cpp-kit-abs-dir kit)))
      (when (and (not (file-remote-p dir))
                 (not (+cpp-kit-container kit))
                 (not (+cpp--kit-compiler-missing-p kit))
                 ;; A build, not a program's run, which is named run-something.
                 (not (seq-some (lambda (process)
                                  (and (process-live-p process)
                                       (string-prefix-p "compilation" (process-name process))
                                       (buffer-live-p (process-buffer process))
                                       (not (string-prefix-p
                                             "run" (or (buffer-local-value '+core-compile-name
                                                                           (process-buffer process))
                                                       "")))))
                                (process-list)))
                 (file-exists-p (expand-file-name "CMakeCache.txt" dir))
                 (not (file-directory-p (expand-file-name ".cmake/api/v1/reply" dir)))
                 (not (member dir +cpp--file-api-asked)))
        (push dir +cpp--file-api-asked)
        (let ((query (expand-file-name ".cmake/api/v1/query/codemodel-v2" dir)))
          (make-directory (file-name-directory query) t)
          (unless (file-exists-p query) (write-region "" nil query nil 'silent)))
        (make-process
         :name "cmake-file-api" :noquery t :buffer nil
         :command (list shell-file-name shell-command-switch
                        (+cpp--kit-shell kit (format "cmake %s" (shell-quote-argument dir)))))))))

(defun +cpp--runnable-p (artifacts)
  "Non-nil when ARTIFACTS holds something to run and not only tests."
  (seq-some (lambda (a) (eq (alist-get 'type a) 'cmake-executable)) artifacts))

(defun +cpp--executable-artifacts (kit)
  "Executables CMake knows about in KIT's build directory, or nil.
Read from the file API reply: projection's client query, which a
configure through SPC k k writes, else the shared codemodel of a
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
Qt Creator's active run configuration, the only one there is, or asked.
One asked for is the project's run target from then on, kept in
.dir-locals.el, so F6, S-F6 and F5 ask once; SPC k m A picks another."
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
          (exes (let* ((rows (mapcar (lambda (a) (cons (alist-get 'name a) a)) exes))
                       (name (completing-read (format-prompt "Run executable" nil)
                                              rows nil t)))
                  (+cpp--set-setting '+cpp-run-target name)
                  (message "Run target: %s, saved to .dir-locals.el; SPC k m A picks another"
                           name)
                  (alist-get 'arg0 (cdr (assoc name rows)))))
          (t (user-error "No executable known for kit %s; configure and build first (SPC k k, SPC k b)"
                         (+cpp-kit-name kit))))))


;;
;;; Run

;;;###autoload
(defun +cpp/run (&optional args exe)
  "Run one of the project's executables, passing it ARGS.
ARGS defaults to what `+cpp/set-run-args' stored for this project, or to
Qt Creator's run configuration.  The program runs where the kit runs, in
the working directory Qt Creator uses, or beside the executable.  CMake
projects offer their targets, EXE when it is given; anything else uses
projection's run command, which for PlatformIO means upload."
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
            (let* ((exe (or exe (+cpp--pick-executable kit)))
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
      ;; It takes the project and the command, which only its
      ;; interactive form works out.
      (when (and args (not (string-empty-p args)))
        (user-error "This kind of project cannot be run with arguments"))
      (call-interactively #'projection-commands-run-project))))

;;;###autoload
(defun +cpp/run-with-args (args)
  "Run a project executable with ARGS."
  (interactive
   (progn
     ;; Said before the arguments are asked for.
     (+core-project-root)
     (unless (+cpp--kind-p 'cmake)
       (user-error "This kind of project cannot be run with arguments"))
     (list (+core-read-arguments
            (or (+cpp--setting '+cpp-run-args)
                (plist-get (+qtcreator-active (+core-project-root)) :run-args))))))
  (+cpp/run args))

;;;###autoload
(defun +cpp/set-run-target (name)
  "Run the executable target NAME with SPC k r, from now on.  Empty goes
back to Qt Creator's run configuration, the only one, or a choice."
  (interactive
   (let* ((exes (seq-filter (lambda (a) (eq (alist-get 'type a) 'cmake-executable))
                            (+cpp--executable-artifacts (+cpp--kit)))))
     (list (+core-read-or-empty "Run target" "to choose again"
                                (mapcar (lambda (a) (alist-get 'name a)) exes)
                                (+cpp--setting '+cpp-run-target)))))
  (let ((value (unless (string-empty-p name) name)))
    (+cpp--set-setting '+cpp-run-target value)
    (message "Run target: %s, saved to .dir-locals.el"
             (or value "chosen again at the next run"))))

;;;###autoload
(defun +cpp/set-run-args (args)
  "Set the ARGS every run of this project passes to the executable."
  (interactive (progn (+core-project-root)
                      (list (+core-read-arguments (+cpp--setting '+cpp-run-args) 'keep))))
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

(defun +cpp--debugger (kit)
  "How a program of KIT is debugged, or one outside a kit when KIT is
nil: the head of a dape config, its command and its type.  gdb's DAP
inside the kit's container or environment when it has one; else this
machine's debugger, `+core-os-debugger', lldb-dap on a Mac."
  (let ((gdb (and kit (+cpp--kit-process kit '("gdb" "--interpreter=dap")))))
    (if (and gdb (not (equal (car gdb) "gdb")))
        `(command ,(car gdb)
          command-args ,(cdr gdb)
          :type "gdb"
          :stopAtBeginningOfMainSubprogram t)
      (+core-os-debugger))))

(defun +cpp--need-debugger (adapter)
  "Say that gdb is not installed, and how to install it, when ADAPTER,
the head of a dape config, runs gdb on the host and it is not there."
  (when (equal (plist-get adapter 'command) "gdb")
    (+core-need-program "gdb" (if (featurep :system 'macos)
                                  "xcode-select --install, or brew install llvm"
                                "zypper in gdb"))))

;;;###autoload
(cl-defun +cpp/debug ()
  "Debug the project's executable where the kit runs.
CMake: the run target, with gdb, in the kit's container; on a Mac, with
no gdb, lldb-dap.  Rust: the crate binary with codelldb
\(`+cpp/install-codelldb' fetches it).  Anything else asks for the
program and uses the same debugger."
  (interactive)
  (require 'dape)
  (+cpp--save-project-buffers)
  (let* ((root (+core-project-root))
         (kit (and (+cpp--kind-p 'cmake) (+cpp--kit root)))
         (adapter (+cpp--debugger kit))
         ;; A missing gdb is said before the program is asked for.
         (exe (cond (kit (+cpp--need-debugger adapter)
                         (+cpp--pick-executable kit))
                    ((derived-mode-p 'rust-mode 'rust-ts-mode 'rustic-mode)
                     ;; dape's codelldb-rust config knows target/debug/<crate>.
                     (cl-return-from +cpp/debug
                       (dape (+cpp--dape-config 'codelldb-rust))))
                    (t (+cpp--need-debugger adapter)
                       (+cpp--read-program))))
         (active (and kit (+qtcreator-active root)))
         (args (or (+cpp--setting '+cpp-run-args) (plist-get active :run-args) ""))
         (cwd (let ((qtc (plist-get active :run-dir)))
                (if (and qtc (file-directory-p qtc)) qtc (file-name-directory exe))))
         (config `(modes ,+cpp-modes
                   ,@adapter
                   :request "launch"
                   :program ,exe
                   :cwd ,cwd
                   :args ,(vconcat (+cpp--run-argv args)))))
    (dape config)))

;;;###autoload
(defun +cpp/debug-or-continue ()
  "Continue the running debug session, or start one.
While the program runs it says so: starting another session then would
debug a second copy beside the first."
  (interactive)
  ;; Started as SPC k d is, so a Pascal, Rust or web project gets its
  ;; own debug rather than the C++ one, which asks for a program.
  (cond ((+cpp--dape-stopped-p) (call-interactively #'dape-continue))
        ((+cpp--dape-live-p)
         (message "The program is running: F5 continues it once it stops, S-F5 ends the session"))
        (t (call-interactively #'+core/debug))))

;;;###autoload
(defun +cpp/install-codelldb ()
  "Download codelldb, the debugger for Rust, into Doom's debug-adapters.
dape looks for it there; SPC k d in a Rust buffer uses it afterwards."
  (interactive)
  (let* ((dir (expand-file-name "debug-adapters/codelldb" doom-user-dir))
         (version "1.11.4")
         ;; A build per system and processor: darwin-arm64 on a Mac with
         ;; Apple silicon, linux-x64 on a PC.
         (platform (format "%s-%s"
                           (pcase system-type
                             ('darwin "darwin")
                             ('gnu/linux "linux")
                             (_ (user-error "codelldb has no build for %s here" system-type)))
                           (if (string-prefix-p "aarch64" system-configuration) "arm64" "x64")))
         (url (format "https://github.com/vadimcn/codelldb/releases/download/v%s/codelldb-%s.vsix"
                      version platform))
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
  "(ORIGIN BUILD . EXE): the buffer a build was started from, which should
be followed by a run, the build's compilation buffer, and the executable
picked before it, or nil.  The buffer and not a flag: a timer runs in
whatever buffer happens to be current when it fires, and `+cpp/run'
asks the current buffer which project it is in.  The build's own
buffer, since any compilation that finished first, the assembly view's,
ran the program before the build was done.")

;; Autoloaded: on `compilation-finish-functions', added in config.el.
;;;###autoload
(defun +cpp--run-after-build-h (buffer status)
  "Run what was built, when BUFFER finished with STATUS and was asked to.
A build that failed stops here, with its output where it is: the reason
is what you wanted to see, not a program that cannot have changed."
  (when (and +cpp--run-after-build
             (eq buffer (cadr +cpp--run-after-build))
             (buffer-live-p buffer))
    (pcase-let ((`(,origin ,_build . ,exe) +cpp--run-after-build))
      (setq +cpp--run-after-build nil)
      (if (equal status "finished\n")
          ;; What runs was settled before the build, so nothing is asked
          ;; from this timer, while you may be typing elsewhere.
          (run-at-time 0 nil
                       (lambda ()
                         (when (buffer-live-p origin)
                           (with-current-buffer origin
                             (+cpp/run nil exe)))))
        (message "Build failed, so nothing was run")))))

;;;###autoload
(defun +cpp/build-and-run ()
  "Build the project and run it when the build succeeded.
The two keys in one, since that is the pair you press all day.  Which
executable runs is asked, when it has to be, before the build starts."
  (interactive)
  (let* ((origin (current-buffer))
         (root (+core-project-root))
         (kit (and (+cpp--kind-p 'cmake) (+cpp--kit root)))
         (exe (and kit (not (+cpp--device-run-p kit))
                   (+cpp--pick-executable kit)))
         build)
    (setq +cpp--run-after-build nil)
    ;; The build's buffer, from the hook that sees it start; set once the
    ;; command is back, so a build it interrupted is not taken for it.
    (let ((compilation-start-hook
           (cons (lambda (process) (setq build (process-buffer process)))
                 compilation-start-hook)))
      (call-interactively #'projection-commands-build-project))
    (when build
      (setq +cpp--run-after-build (cons origin (cons build exe))))))
