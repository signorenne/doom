;;; private/cpp/autoload/cmake.el -*- lexical-binding: t; -*-
;;
;; A CMake project as Qt Creator's Projects mode shows it: the cache in
;; the build directory, the presets, the overrides this module keeps per
;; project, configure and build, and the status report.

(declare-function +cpp--qt-prefixes "build-type")
(declare-function +cpp--lsp-status "lsp")
(declare-function +cpp--restart-servers "lsp")
(defvar +cpp-container)
(declare-function +cpp-kit-container "kit")
(declare-function +cpp-kit-dir "kit")
(declare-function +cpp-kit-env-script "kit")
(declare-function +cpp-kit-name "kit")
(declare-function +cpp--cmake-cache "kit")
(declare-function +qtcreator-active "qtcreator")
(declare-function +cpp-kit-preset "kit")
(declare-function +cpp-kit-build-type "kit")
(declare-function +cpp-kit-generator "kit")
(declare-function +cpp-kit-compiler "kit")
(declare-function +cpp-kit-toolchain "kit")
(declare-function +cpp-kit-sysroot "kit")
(declare-function +cpp-kit-qt "kit")
(declare-function +cpp-kit-args "kit")
(declare-function +cpp-kit-env "kit")
(declare-function +cpp--kit-environment "container")
(declare-function +cpp-kit-targets "kit")
(declare-function +cpp-kit-run "kit")
(declare-function +cpp-kit-configs "kit")
(declare-function +cpp--kits "kit")
(declare-function +cpp--kit-config "kit")
(declare-function +cpp--with-config "kit")
(declare-function +cpp--kit-locate "kit")
(declare-function +cpp--kit "kit")
(declare-function +cpp--target-names "run")
(declare-function +cpp-kit-qtc "kit")
(declare-function +cpp/forget-kits "kit")
(declare-function +cpp--carried-args "build-type")
(declare-function +cpp--arg-cell "kit")
(declare-function +cpp--sdk-root "container")
(defvar +cpp-lsp-server)
(defvar +pio-env)
(declare-function gdb "gdb-mi")
(declare-function project-root "project")
(defvar projection-build-jobs)
(defvar projection-cmake-configure-options)
(declare-function projection-multi-cmake-targets "projection-multi-cmake")
(declare-function projection-project-types "projection-core-type")


;;
;;; Reading the state

(defun +cpp--cmake-cache-file ()
  "Path of the project's CMakeCache.txt, whether or not it exists."
  (when-let* ((dir (+cpp--build-directory)))
    (expand-file-name "CMakeCache.txt" dir)))

(defun +cpp--cmake-cache-entries (&optional all)
  "Entries of the kit's CMakeCache.txt as a list of (NAME TYPE VALUE).
Internal and static entries are CMake's own bookkeeping rather than
settings, so they are dropped unless ALL."
  (when-let* ((file (+cpp--cmake-cache-file))
              (entries (+cpp--cmake-cache file)))
    (if all
        entries
      (seq-remove (lambda (entry) (member (nth 1 entry) '("INTERNAL" "STATIC")))
                  entries))))

;; Autoloaded: called from the panel header in menu.el.
;;;###autoload
(defun +cpp--cmake-cache-value (name)
  "Value of cache variable NAME, or nil.
Reads the internal entries too, since the generator lives there."
  (let ((value (nth 2 (assoc name (+cpp--cmake-cache-entries 'all)))))
    (unless (equal value "") value)))

;; Autoloaded: called from the panel header in menu.el.
;;;###autoload
(defun +cpp--configured-p ()
  "Whether the build directory holds a configured CMake project."
  (when-let* ((file (+cpp--cmake-cache-file)))
    (file-exists-p file)))


;;
;;; Which directory a preset builds in

(defun +cpp--preset-named (name presets)
  "The preset called NAME in PRESETS."
  (seq-find (lambda (p) (equal (alist-get 'name p) name)) presets))

(defun +cpp--preset-property (config presets key &optional depth)
  "Value of KEY in preset CONFIG, following inherits through PRESETS.
DEPTH guards against preset loops."
  (or (alist-get key config)
      (and (< (or depth 0) 16)
           (cl-loop for parent in (ensure-list (alist-get 'inherits config))
                    for pconfig = (+cpp--preset-named parent presets)
                    thereis (and pconfig
                                 (+cpp--preset-property
                                  pconfig presets key (1+ (or depth 0))))))))

;; Autoloaded: kit.el reads a preset's build type with it.
;;;###autoload
(defun +cpp--preset-cache-variable (config presets name)
  "The cache variable NAME preset CONFIG sets, through its inherits in
PRESETS, or nil."
  (or (alist-get (intern name) (alist-get 'cacheVariables config))
      (cl-loop for parent in (ensure-list (alist-get 'inherits config))
               for pconfig = (+cpp--preset-named parent presets)
               thereis (and pconfig (+cpp--preset-cache-variable pconfig presets name)))))

;;;###autoload
(defun +cpp--preset-binary-dir (name)
  "Build directory of the configure preset NAME, relative to the root.
Nil when there is no such preset or it has no binaryDir."
  (when-let* ((project (+cpp--projection-project 'no-error))
              (root (project-root project))
              (presets (+cpp--projection-presets root))
              (config (+cpp--preset-named name presets))
              (dir (+cpp--preset-property config presets 'binaryDir)))
    (let* ((expanded
            (replace-regexp-in-string
             "\\${\\([A-Za-z]+\\)}\\|\\$env{\\([^}]+\\)}"
             (lambda (m)
               (pcase (match-string 1 m)
                 ("sourceDir" (directory-file-name root))
                 ("presetName" name)
                 ;; CMake's names for the system it runs on.
                 ("hostSystemName" (pcase system-type
                                     ('darwin "Darwin")
                                     ('windows-nt "Windows")
                                     (_ "Linux")))
                 ("sourceDirName"
                  (file-name-nondirectory (directory-file-name root)))
                 ("sourceParentDir"
                  (directory-file-name
                   (file-name-directory (directory-file-name root))))
                 ((pred null) (or (getenv (match-string 2 m)) ""))
                 (_ m)))
             dir t t))
           (abs (expand-file-name expanded root)))
      (if (string-prefix-p (file-name-as-directory (expand-file-name root)) abs)
          (file-relative-name abs root)
        abs))))


;;
;;; Settings this module keeps per project

;;;###autoload
(defun +cpp--cache-overrides ()
  "The cache variables this project overrides, as an alist."
  (+cpp--setting '+cpp-cache-overrides))

;;;###autoload
(defun +cpp--cache-override-args ()
  "The overridden cache variables as -DNAME=VALUE arguments."
  (mapcar (lambda (cell) (format "-D%s=%s" (car cell) (cdr cell)))
          (+cpp--cache-overrides)))

;;;###autoload
(defun +cpp/cmake-set-variable (name value)
  "Set cache variable NAME to VALUE for the next configure.
Completion offers what CMakeCache.txt holds, so the list is the
project's own options with their current values, any other name can be
typed, and CMAKE_PREFIX_PATH is always there: it is where a Qt is
chosen, and the Qt installations found on this machine, the system one
and ~/Qt/*/gcc_64, are offered as its value.  The override is
remembered per project and passed to every configure until you clear
it."
  (interactive
   (let* ((entries (+cpp--cmake-cache-entries))
          (entries (if (assoc "CMAKE_PREFIX_PATH" entries)
                       entries
                     (append entries (list (list "CMAKE_PREFIX_PATH" "PATH" "")))))
          (overrides (+cpp--cache-overrides))
          (candidates
           (mapcar (lambda (entry)
                     (cl-destructuring-bind (name type value) entry
                       (cons (format "%-42s %-8s %s" name type
                                     (or (cdr (assoc name overrides)) value))
                             name)))
                   entries))
          (input (completing-read "Cache variable: " candidates))
          (choice (or (cdr (assoc input candidates)) (string-trim input)))
          (entry (assoc choice entries))
          (type (or (nth 1 entry) "STRING"))
          (current (or (cdr (assoc choice overrides)) (nth 2 entry) ""))
          (qts (and (equal choice "CMAKE_PREFIX_PATH") (+cpp--qt-prefixes))))
     (list choice
           (cond ((equal type "BOOL")
                  (completing-read (format "%s: " choice) '("ON" "OFF") nil t))
                 (qts (completing-read (format "%s (a Qt, or any prefix): " choice)
                                       qts nil nil current))
                 (t (read-string (format "%s = " choice) current))))))
  (let ((overrides (+cpp--cache-overrides)))
    (setf (alist-get name overrides nil nil #'equal) value)
    (+cpp--set-setting '+cpp-cache-overrides overrides))
  (message "%s = %s, saved to .dir-locals.el. SPC k c applies it" name value))

;;;###autoload
(defun +cpp/cmake-clear-variable (name)
  "Drop the override on cache variable NAME.
With no overrides left the next configure is back to the preset's values."
  (interactive
   (let ((overrides (+cpp--cache-overrides)))
     (unless overrides
       (user-error "No cache variables are overridden"))
     (list (completing-read "Clear override: "
                            (mapcar #'car overrides) nil t))))
  (+cpp--set-setting '+cpp-cache-overrides
                     (assoc-delete-all name (+cpp--cache-overrides)))
  (message "%s back to the project default" name))

;;;###autoload
(defun +cpp/cmake-list-variables ()
  "Show the cache variables this project overrides."
  (interactive)
  (let ((overrides (+cpp--cache-overrides)))
    (if (null overrides)
        (message "No overrides. SPC k m -D adds one")
      (message "%s" (string-join (+cpp--cache-override-args) " ")))))

;;;###autoload
(defun +cpp/set-build-target (target)
  "Build TARGET by default from now on."
  (interactive
   (progn
     (require 'projection-multi-cmake)
     ;; The kit's directory, not projection's build/, and the targets
     ;; Qt Creator's or the generator's list gives when projection's own
     ;; query has no reply there, as the target menu does.
     (let* ((root (+core-project-root))
            (kit (+cpp--kit root))
            (targets (or (+cpp--with-kit kit
                           (mapcar (lambda (cell)
                                     (string-remove-prefix "cmake:" (car cell)))
                                   (ignore-errors (projection-multi-cmake-targets))))
                         (+cpp--target-names kit root))))
       (unless targets
         (user-error "No targets yet, configure first with SPC k c"))
       (list (completing-read "Default build target: " targets nil t)))))
  ;; Kept with the other project settings; the kit macro hands it to
  ;; projection, which only exposes it through embark.
  (+cpp--set-setting '+cpp-build-target (unless (equal target "all") target))
  (+cpp--projection-cache-put (+cpp--projection-project)
                              'projection-cmake-build-target
                              (unless (equal target "all") target))
  (message "Default CMake build target: %s, saved to .dir-locals.el" target))

;;;###autoload
(defun +cpp/set-jobs (jobs)
  "Build with JOBS parallel jobs."
  (interactive
   (list (read-number "Parallel jobs: "
                      (if (numberp projection-build-jobs)
                          projection-build-jobs
                        (doom-system-cpus)))))
  (setq projection-build-jobs (max 1 (truncate jobs)))
  (message "Building with %d job(s)" projection-build-jobs))

(defun +cpp--kit-spec (kit root)
  "KIT written down, a plist for `+cpp-kits': its name and directory,
then everything it knows that a fresh checkout would not, the type,
the generator, the tool set as -D arguments (Qt Creator's when it has
them, else read off its cache), the environment, the build targets,
the run configuration, the configurations of a multi-config
generator, the container and the environment script."
  (let ((args (or (+cpp-kit-args kit) (+cpp--carried-args kit root))))
    (append
     (list :name (+cpp-kit-name kit) :dir (+cpp-kit-dir kit))
     (cl-loop for (key . value)
              in (list (cons :type (+cpp-kit-build-type kit))
                       (cons :generator (+cpp-kit-generator kit))
                       (cons :args args)
                       (cons :env (+cpp--kit-environment kit))
                       (cons :targets (+cpp-kit-targets kit))
                       (cons :run (+cpp-kit-run kit))
                       (cons :configs (+cpp-kit-configs kit))
                       (cons :container (+cpp-kit-container kit))
                       (cons :env-script (and (null (+cpp-kit-env kit)) (+cpp-kit-env-script kit))))
              when value append (list key value)))))

;;;###autoload
(defun +cpp/write-dir-locals ()
  "Write the project's setup as it stands into .dir-locals.el and open
the file: every kit, written down whole (`+cpp-kits'), then the kit in
use, where it runs, the language server, the build target and
configuration, the run target and its arguments, the cache overrides,
the package target and where packages go, the PlatformIO environment.
What is detected today, Qt Creator's kits and configurations, the
container the compiler was found in, the run configuration, becomes
explicit, and the project carries it without Qt Creator, its caches
or its settings; run it again whenever the setup changed, and
everything not written stays detected.  Each setting has its own
command too, which writes only itself."
  (interactive)
  (let* ((root (+core-project-root))
         (kit (+cpp--kit root))
         (kits (seq-remove #'+cpp-kit-preset (+cpp--kits root)))
         (active (+qtcreator-active root))
         (written nil))
    (cl-flet ((keep (key value)
                (+core-dir-locals-set root key value)
                (when value (push (format "%s %s" key (if (eq key '+cpp-kits) (format "(%d kits)" (length value)) (format "%S" value))) written))))
      (keep '+cpp-kits (mapcar (lambda (k) (+cpp--kit-spec (+cpp--kit-locate k) root)) kits))
      (keep '+cpp-kit (+cpp-kit-name kit))
      (keep '+cpp-build-config (+cpp--kit-config kit))
      (keep '+cpp-container (+cpp-kit-container kit))
      (keep '+cpp-lsp-server (bound-and-true-p +cpp-lsp-server))
      (keep '+cpp-build-target (+cpp--setting '+cpp-build-target))
      (keep '+cpp-run-target (or (+cpp--setting '+cpp-run-target)
                                 (plist-get active :run-target)))
      (keep '+cpp-run-args (let ((args (or (+cpp--setting '+cpp-run-args)
                                           (plist-get active :run-args))))
                             (and args (not (string-empty-p args)) args)))
      (keep '+cpp-cache-overrides (+cpp--cache-overrides))
      (keep '+cpp-package-target (+cpp--setting '+cpp-package-target))
      (keep '+cpp-package-dir (+cpp--setting '+cpp-package-dir))
      (when (bound-and-true-p +pio-env)
        (keep '+pio-env +pio-env)))
    (find-file (expand-file-name ".dir-locals.el" root))
    (message "Written: %s" (string-join (nreverse written) ", "))))


;;
;;; Configure and build

;;;###autoload
(defun +cpp/cmake-configure-fresh ()
  "Configure from scratch, dropping the existing CMake cache.
Use it after changing compiler, generator or preset, when a plain
configure keeps the stale value."
  (interactive)
  (let ((projection-cmake-configure-options
         (cons "--fresh" projection-cmake-configure-options)))
    (+cpp--compile "cmake configure" (+cpp--configure-command))))

(defun +cpp--cmake-clean-command ()
  "Command that builds the clean target, where the kit runs."
  (require 'projection)
  (let ((kit (+cpp--kit)))
    (+cpp--kit-shell kit (+cpp--with-config
                          (mapconcat #'shell-quote-argument
                                     (list "cmake" "--build" (+cpp-kit-dir kit)
                                           "--target" "clean")
                                     " ")
                          (+cpp--kit-config kit))
                     (+core-project-root))))

;;;###autoload
(defun +cpp/cmake-rebuild ()
  "Clean the build directory, then build it again."
  (interactive)
  (+cpp--compile "cmake rebuild"
                 (concat (+cpp--cmake-clean-command) " && " (+cpp--build-command))))

;;;###autoload
(defun +cpp/cmake-clean ()
  "Build the clean target."
  (interactive)
  (+cpp--compile "cmake clean" (+cpp--cmake-clean-command)))

;;;###autoload
(defun +cpp/reconfigure-and-reindex ()
  "Configure, then point the language server at the fresh index.
The one command for \"it builds but clangd is lost\": it reconfigures
and restarts the server, which is pointed at the kit's database."
  (interactive)
  (add-hook 'compilation-finish-functions #'+cpp--reindex-after-configure-h)
  (+cpp--compile "cmake configure" (+cpp--configure-command)))

(defun +cpp--reindex-after-configure-h (buffer status)
  "Relink the compilation database once BUFFER finishes with STATUS."
  (when (equal (buffer-local-value '+core-compile-name buffer) "cmake configure")
    (remove-hook 'compilation-finish-functions
                 #'+cpp--reindex-after-configure-h)
    (when (string-prefix-p "finished" status)
      (+cpp--restart-servers)
      (message "Configured and reindexed. %s" (or (+cpp--build-directory) "")))))


;;
;;; Inspecting

(defun +cpp--tool-version (kit program &rest args)
  "The version PROGRAM reports for ARGS where KIT runs, or a note that it
is missing there.  A kit in a container has its tools there, not on the
host's PATH."
  (let ((container (+cpp-kit-container kit)))
    (with-temp-buffer
      (let ((code (condition-case nil
                      (if container
                          (call-process "distrobox" nil t nil "enter" container "--"
                                        "sh" "-c" (format "command -v %s >/dev/null && %s %s"
                                                          (shell-quote-argument program)
                                                          (shell-quote-argument program)
                                                          (mapconcat #'shell-quote-argument args " ")))
                        (if-let* ((binary (executable-find program)))
                            (apply #'call-process binary nil t nil args)
                          127))
                    (error 127))))
        (if (= code 127)
            (format "not installed %s" (+cpp-kit-where kit))
          (let ((lines (split-string (buffer-string) "\n" t)))
            ;; Some tools print their name first and the version underneath.
            (concat (or (seq-find (lambda (line) (string-match-p "[0-9]+\\.[0-9]+" line))
                                  lines)
                        (car lines)
                        "unknown")
                    (if container (format "  (in %s)" container) ""))))))))

;;;###autoload
(defun +cpp/project-status ()
  "Report how this project is set up and what is missing.
The first place to look when a build, an index or a debugger misbehaves."
  (interactive)
  (require 'projection)
  (let* ((root (+core-project-root))
         (build (+cpp--build-directory))
         (configured (+cpp--configured-p))
         (db (+cpp--compile-commands-file))
         (root-db (expand-file-name "compile_commands.json" root))
         (buffer (get-buffer-create "*cpp project status*")))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (propertize (format "%s\n" (abbreviate-file-name root))
                            'face 'bold))
        (insert (format "types       %s\n"
                        (or (mapconcat (lambda (ty) (symbol-name (oref ty name)))
                                       (projection-project-types root) ", ")
                            "none detected")))
        (let ((kit (+cpp--kit root)))
          (insert (format "kit         %s\n" (+cpp--kit-describe kit)))
          (insert (format "build dir   %s%s\n"
                          (abbreviate-file-name build)
                          (if configured "" "  (not configured, SPC k c)")))
          (insert (format "runs        %s%s\n" (+cpp-kit-where kit)
                          (if-let* ((script (+cpp-kit-env-script kit)))
                              (format ", after %s" script)
                            "")))
          (when-let* ((others (seq-remove (lambda (k) (equal (+cpp-kit-name k) (+cpp-kit-name kit)))
                                          (+cpp--kits root))))
            (insert (format "other kits  %s  (SPC k K picks one)\n"
                            (mapconcat #'+cpp-kit-name others ", "))))
          (when-let* ((note (+cpp--stale-note root)))
            (insert (format "stale       %s\n" note))))
        (when configured
          (insert (format "build type  %s\n"
                          (or (+cpp--cmake-cache-value "CMAKE_BUILD_TYPE")
                              (+cpp--projection-build-type)
                              "unset")))
          (insert (format "generator   %s\n"
                          (or (+cpp--cmake-cache-value "CMAKE_GENERATOR")
                              "unknown")))
          (insert (format "compiler    %s\n"
                          (or (+cpp--cmake-cache-value "CMAKE_CXX_COMPILER")
                              "unknown")))
          (when-let* ((qt (+cpp--cmake-cache-value "Qt6_DIR")))
            (insert (format "qt          %s\n" qt))))
        (insert (format "overrides   %s\n"
                        (if-let* ((args (+cpp--cache-override-args)))
                            (string-join args " ")
                          "none")))
        (insert (format "run args    %s\n"
                        (let ((args (+cpp--setting '+cpp-run-args "")))
                          (if (string-empty-p args) "none" args))))
        (insert "\n")
        (insert (format "index       %s\n"
                        (cond (db
                               (format "%s  (%s%s)"
                                       (abbreviate-file-name db)
                                       (if (file-in-directory-p db build)
                                           "the kit's"
                                         "another kit's; SPC k K to switch")
                                       (if (file-exists-p root-db)
                                           ", linked into the root"
                                         "")))
                              (t "no compile_commands.json, SPC k c"))))
        (insert (format "server      %s\n" (+cpp--lsp-status)))
        (let ((kit (+cpp--kit root)))
          (insert (format "clangd      %s\n" (+cpp--tool-version kit "clangd" "--version")))
          (insert (format "cmake       %s\n" (+cpp--tool-version kit "cmake" "--version")))
          (insert (format "gdb         %s\n" (+cpp--tool-version kit "gdb" "--version")))
          (insert (format "clang-tidy  %s\n"
                          (+cpp--tool-version kit "clang-tidy" "--version"))))
        (insert "\n")
        (insert (format "style       %s, %s\n"
                        (if (file-exists-p (expand-file-name ".clang-format" root))
                            ".clang-format"
                          "no .clang-format (formatting on save is off)")
                        (if (file-exists-p (expand-file-name ".clang-tidy" root))
                            ".clang-tidy"
                          "no .clang-tidy")))
        (goto-char (point-min)))
      (special-mode))
    (pop-to-buffer buffer)))

;;
;;; The setup as presets

(defun +cpp--preset-environment (env)
  "ENV, Qt Creator's NAME=VALUE and NAME+=VALUE lines, as the
environment of a preset: an alist of NAME to VALUE, ${NAME} references
turned into $env{NAME}, a += appended behind a colon, and a PATH cut
down to the SDK's part with $penv{PATH} behind it, since the rest was
the machine's PATH of the day the kit was made."
  (let (result)
    (dolist (entry env)
      (when (string-match "\\`\\([A-Za-z_][A-Za-z0-9_]*\\)\\(\\+?\\)=\\(.*\\)\\'" entry)
        (let* ((name (match-string 1 entry))
               (append-p (equal (match-string 2 entry) "+"))
               (value (replace-regexp-in-string "\\${\\([A-Za-z_][A-Za-z0-9_]*\\)}" "$env{\\1}"
                                                (match-string 3 entry) t))
               (value (if (equal name "PATH")
                          (concat (mapconcat #'identity
                                             (seq-filter (lambda (d) (string-prefix-p "/opt/" d))
                                                         (split-string value ":" t))
                                             ":")
                                  ":$penv{PATH}")
                        value))
               (old (assoc name result)))
          (cond ((and append-p old) (setcdr old (concat (cdr old) ":" value)))
                (append-p (push (cons name (concat "$penv{" name "}:" value)) result))
                (old (setcdr old value))
                (t (push (cons name value) result))))))
    (nreverse result)))

(defun +cpp--preset-cache-variables (kit args)
  "The cacheVariables of a preset for KIT from its -D ARGS: the type
first, then each argument, typed when it says its type."
  (append
   (when-let* ((type (and (not (+cpp-kit-configs kit)) (+cpp-kit-build-type kit))))
     (list (cons "CMAKE_BUILD_TYPE" type)))
   (cl-loop for arg in args
            for cell = (+cpp--arg-cell arg)
            when (and cell (not (equal (car cell) "CMAKE_BUILD_TYPE")))
            collect (if (string-match "\\`-D[^:=]+:\\([^=]+\\)=" arg)
                        (cons (car cell) (list (cons "type" (match-string 1 arg))
                                               (cons "value" (cdr cell))))
                      cell))))

(defun +cpp--presets-json (kits root)
  "The presets file for KITS under ROOT as a JSON string: a configure
preset per kit with its directory, generator, cache variables and
environment, a build preset with its targets, a test preset."
  (require 'json)
  (let ((json-encoding-pretty-print t)
        (json-encoding-default-indentation "  ")
        configure build test)
    (dolist (kit kits)
      (let* ((name (+cpp-kit-name kit))
             (args (or (+cpp-kit-args kit) (+cpp--carried-args kit root)))
             (env (+cpp--preset-environment (+cpp--kit-environment kit))))
        (push `((name . ,name)
                (displayName . ,(if-let* ((qtc (+cpp-kit-qtc kit)))
                                    (format "%s, %s" (plist-get qtc :name) (or (+cpp-kit-build-type kit) name))
                                  name))
                ,@(when (+cpp-kit-generator kit) `((generator . ,(+cpp-kit-generator kit))))
                (binaryDir . ,(concat "${sourceDir}/" (directory-file-name (+cpp-kit-dir kit))))
                ,@(when-let* ((variables (+cpp--preset-cache-variables kit args)))
                    `((cacheVariables . ,variables)))
                ,@(when env `((environment . ,env))))
              configure)
        (push `((name . ,name)
                (configurePreset . ,name)
                ,@(when-let* ((targets (+cpp-kit-targets kit)))
                    `((targets . ,(vconcat targets))))
                ,@(when-let* ((config (+cpp--kit-config kit)))
                    `((configuration . ,config))))
              build)
        (push `((name . ,name)
                (configurePreset . ,name)
                (output . ((outputOnFailure . t))))
              test)))
    (json-encode `((version . 6)
                   (configurePresets . ,(vconcat (nreverse configure)))
                   (buildPresets . ,(vconcat (nreverse build)))
                   (testPresets . ,(vconcat (nreverse test)))))))

;;;###autoload
(defun +cpp/write-presets (file)
  "Write the project's kits as CMake presets into FILE, by default
CMakeUserPresets.json, since the tool sets are this machine's, and
open it: a configure preset per kit, its directory, generator, cache
variables (the tool set as -D arguments, Qt Creator's when it has
them, else read off the cache) and environment, a build preset with
the targets the kit builds, a test preset.  Then cmake --preset NAME
and cmake --build --preset NAME do what Qt Creator does, from any
shell, with no Qt Creator and no Emacs.  With a prefix argument, the
file is asked for, CMakePresets.json to make it the project's own."
  (interactive
   (let ((root (+core-project-root)))
     (list (if current-prefix-arg
               (read-file-name "Presets file: " root nil nil "CMakePresets.json")
             (expand-file-name "CMakeUserPresets.json" root)))))
  (let* ((root (+core-project-root))
         (kits (seq-remove #'+cpp-kit-preset (+cpp--kits root))))
    (when (null kits)
      (user-error "No kit to write: nothing configured, planned or declared"))
    (when (and (file-exists-p file)
               (not (y-or-n-p (format "%s exists; write it anew? " (file-relative-name file root)))))
      (user-error "Left as it was"))
    (with-temp-file file
      (insert (+cpp--presets-json (mapcar #'+cpp--kit-locate kits) root) "\n"))
    (+cpp/forget-kits)
    (find-file file)
    (message "%d preset(s) written; cmake --list-presets shows them, SPC k K offers them as kits"
             (length kits))))

;;;###autoload
(defun +cpp/open-cmake-cache ()
  "Open the project's CMakeCache.txt."
  (interactive)
  (let ((file (+cpp--cmake-cache-file)))
    (unless (and file (file-exists-p file))
      (user-error "Not configured yet, run SPC k c"))
    (find-file file)))

;;;###autoload
(defun +cpp/open-dir-locals ()
  "Open the project's .dir-locals.el, the setup as it was written."
  (interactive)
  (let ((file (expand-file-name ".dir-locals.el" (+core-project-root))))
    (unless (file-exists-p file)
      (user-error "Nothing written yet; SPC k w writes the setup as it stands"))
    (find-file file)))

;;;###autoload
(defun +cpp/open-presets ()
  "Open CMakePresets.json, or CMakeUserPresets.json with a prefix argument."
  (interactive)
  (let* ((root (+core-project-root))
         (name (if current-prefix-arg
                   "CMakeUserPresets.json"
                 "CMakePresets.json"))
         (file (expand-file-name name root)))
    (when (and (not (file-exists-p file))
               (not (y-or-n-p (format "%s does not exist.  Create it? " name))))
      (user-error "Aborted"))
    (find-file file)))

;;;###autoload
(defun +cpp/open-compile-commands ()
  "Open the compilation database the language server reads."
  (interactive)
  (let ((file (or (+cpp--compile-commands-file)
                  (let ((in-root (expand-file-name "compile_commands.json"
                                                   (+core-project-root))))
                    (and (file-exists-p in-root) in-root)))))
    (unless file
      (user-error "No compile_commands.json yet, run SPC k c"))
    (find-file file)))
