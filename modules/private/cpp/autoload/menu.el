;;; private/cpp/autoload/menu.el -*- lexical-binding: t; -*-
;;
;; Two menus, one rule: a key means the same thing on the leader, in the
;; menu and in the panel. SPC k SPC is the menu, what you do: build, run,
;; fix, the tools; its columns follow the project, CMake gets the kit,
;; PlatformIO its environments, a Cargo, Meson, Make, Gradle or npm
;; project projection's commands. SPC k m is the CMake panel, what you
;; set: the kit, the cache, the targets, the arguments, and the files
;; behind them, what Qt Creator puts in its Projects mode. Both show
;; the state in their header, the kit and how it was chosen first, so
;; you see what you are about to act on. Two keys are the menu's own,
;; so no command sits on them: ? then a key explains the key, and q
;; closes the menu (core binds it so in every transient), which is why
;; the leader's SPC k ? has no seat here and the quickfix is on . in
;; both places.

(require 'transient)

(declare-function +cpp--cmake-cache-value "cmake")
(declare-function +cpp--configured-p "cmake")
(declare-function +cpp--types-summary "build-type")
(declare-function +cpp--kits "kit")
(declare-function +cpp--kind-p "project")
(declare-function +cpp--project-kind "project")
(defvar +cpp-lsp-server)
(declare-function +cpp/debug "run")
(defvar +pio-env)
(declare-function eglot-current-server "eglot")
(declare-function gdb "gdb-mi")
(defvar projection-build-jobs)

;; A transient refuses a suffix that is neither defined nor autoloaded,
;; and eglot's commands are neither until a server has started, nor
;; dape's breakpoint toggle until dape ran; the menu opens from any
;; buffer.
(autoload 'eglot-rename "eglot" nil t)
(autoload 'eglot-inlay-hints-mode "eglot" nil t)
(autoload 'eglot-events-buffer "eglot" nil t)
(autoload 'dape-breakpoint-toggle "dape" nil t)


;;
;;; The headers

(defun +cpp--state-lines (root)
  "Two lines on what the next build of ROOT uses: the kit and how it was
chosen; then the types of its family (the current one starred, an
unbuilt one marked with a plus), the default target and the server."
  (format "kit %s
types %s   target %s   server %s"
          (+cpp--kit-describe (+cpp--kit root))
          (+cpp--types-summary (+cpp--kit root) (+cpp--kits root))
          (or (+cpp--setting '+cpp-build-target) "all")
          (bound-and-true-p +cpp-lsp-server)))

(defun +cpp--menu-description ()
  "Header for `+cpp/menu': the project, its type, and what a build uses."
  (let* ((root (+core-project-root 'noerror))
         (kind (+cpp--project-kind)))
    (concat
     (format "%s  [%s]"
             (propertize (abbreviate-file-name (directory-file-name root)) 'face 'bold)
             (or kind "unknown"))
     (pcase kind
       ('cmake (concat "\n" (+cpp--state-lines root)))
       ('platformio (format "   env: %s" (or (bound-and-true-p +pio-env) "default")))
       (_ (if-let* ((server (and (fboundp 'eglot-current-server) (eglot-current-server))))
              (format "   server: %s" (car (process-command (+cpp--server-process server))))
            ""))))))

(defun +cpp--cmake-menu-description ()
  "Header for `+cpp/cmake-menu': what a build uses, and the settings
behind it: the generator, the jobs, the overrides, the run line."
  (require 'projection)
  (let* ((root (+core-project-root 'noerror))
         (configured (+cpp--configured-p))
         (overrides (length (+cpp--cache-overrides)))
         (run-target (+cpp--setting '+cpp-run-target))
         (run-args (+cpp--setting '+cpp-run-args)))
    (concat
     (format "%s   %s\n"
             (propertize (abbreviate-file-name (directory-file-name root)) 'face 'bold)
             (if configured
                 (format "%s, %s"
                         (or (+cpp--cmake-cache-value "CMAKE_GENERATOR") "?")
                         (or (+cpp--cmake-cache-value "CMAKE_BUILD_TYPE") "no build type"))
               (propertize "not configured" 'face 'warning)))
     (+cpp--state-lines root)
     (format "\njobs %s   overrides %d   run %s%s"
             (if (numberp projection-build-jobs) projection-build-jobs "auto")
             overrides
             (or run-target "the run configuration's")
             (if (and run-args (not (string-empty-p run-args))) (concat " " run-args) "")))))


;;
;;; SPC k SPC: what you do

;;;###autoload (autoload '+cpp/menu "private/cpp/autoload/menu" nil t)
(transient-define-prefix +cpp/menu ()
  "What the project can do: build, run, fix, and the tools."
  [:description +cpp--menu-description
   ["Build"
    ("c" "Configure"          projection-commands-configure-project)
    ("b" "Build"              projection-commands-build-project)
    ("B" "Build a target"     projection-multi-compile)
    ("x" "Build, then run"    +cpp/build-and-run)
    ("t" "Test"               projection-commands-test-project)
    ("T" "Test at point"      +cpp/test-at-point :if (lambda () (+cpp--kind-p 'cmake)))
    ("u" "A test executable"  +cpp/test-binary :if (lambda () (+cpp--kind-p 'cmake)))
    ("i" "Install"            projection-commands-install-project)
    ("P" "Package"            projection-commands-package-project
     :if (lambda () (+cpp--kind-p 'cargo 'gradle 'maven 'npm 'python)))
    ("P" "Package"            +cpp/package :if (lambda () (+cpp--kind-p 'cmake)))
    ("o" "Copy the package out" +cpp/package-copy :if (lambda () (+cpp--kind-p 'cmake)))]
   ["Run"
    ("r" "Run"                +cpp/run)
    ("R" "Run with arguments" +cpp/run-with-args :if (lambda () (+cpp--kind-p 'cmake)))
    ("S" "Run a project script" +cpp/run-script)
    ("U" "Deploy to the device" +cpp/deploy :if (lambda () (+cpp--kind-p 'cmake)))
    ("d" "Debug"              +cpp/debug)
    ("D" "Debug on the device" +cpp/debug-on-device
     :if (lambda () (+cpp--kind-p 'cmake)))
    ("j" "Attach to a gdb server" +cpp/debug-remote)
    ("<f9>" "Breakpoint here" dape-breakpoint-toggle)]
   ["Kit"
    :if (lambda () (+cpp--kind-p 'cmake))
    ("K" "Pick the kit"       +cpp/set-kit)
    ("y" "Build type"         +cpp/build-type)
    ("Y" "Kit family"         +cpp/kit-family)
    ("I" "Project status"     +cpp/project-status)
    ("m" "CMake panel: what you set" +cpp/cmake-menu)]
   ["Project"
    :if (lambda () (not (+cpp--kind-p 'cmake)))
    ("I" "Project info"       projection-show-project-info)
    ("O" "Set the project type" projection-set-primary-project-type)
    ("Z" "Reset the cache"    projection-cache-clear)]]
  [["Fix"
    ("e" "Next problem"       +cpp/next-problem :transient t)
    ("E" "Previous problem"   +cpp/previous-problem :transient t)
    ("L" "List the problems"  +default/diagnostics)
    ("." "Fix it: the quickfix at point" +cpp/quickfix)
    ("f" "clang-format this buffer" +cpp/format-buffer
     :if (lambda () (+cpp--kind-p 'cmake 'platformio 'make)))
    ("g F" "clang-format the project" +cpp/format-project :if (lambda () (+cpp--kind-p 'cmake)))
    ("g t" "clang-tidy this file" +cpp/tidy-file :if (lambda () (+cpp--kind-p 'cmake)))
    ("g T" "clang-tidy this file, apply the fixes" (lambda () (interactive) (+cpp/tidy-file t))
     :if (lambda () (+cpp--kind-p 'cmake)))
    ("g p" "clang-tidy the project" +cpp/tidy-project :if (lambda () (+cpp--kind-p 'cmake)))
    ("g r" "Rename the symbol" eglot-rename)]
   ["Server"
    ("l s" "Switch server: clangd, ccls" +cpp/set-lsp-server
     :if (lambda () (+cpp--kind-p 'cmake 'platformio 'make)))
    ("l r" "Restart it"       +cpp/restart-lsp)
    ("l i" "Inlay hints"      eglot-inlay-hints-mode)
    ("l c" "Write .clangd"    +cpp/write-clangd-config
     :if (lambda () (+cpp--kind-p 'cmake 'platformio 'make)))
    ("l l" "Link compile_commands.json into the root" +cpp/link-compile-commands
     :if (lambda () (+cpp--kind-p 'cmake)))
    ("l b" "Run the kit in a container" +cpp/set-container
     :if (lambda () (+cpp--kind-p 'cmake)))
    ("l e" "The server's log" eglot-events-buffer)]
   ["Files and tools"
    ("h" "Header and source"  find-sibling-file
     :if (lambda () (+cpp--kind-p 'cmake 'platformio 'make)))
    ("H" "Other file of the project" projection-find-other-file)
    ("a" "Assembly, live"     +cpp/assembly)
    ("A" "Disassemble at point" disaster
     :if (lambda () (+cpp--kind-p 'cmake 'platformio 'make)))
    ("w" "Write the setup to .dir-locals.el" +cpp/write-dir-locals
     :if (lambda () (+cpp--kind-p 'cmake 'platformio)))
    ("n" "New project"        +cpp/new-project)
    ("N" "New Qt MVVM app"    +cpp/new-qt-project)
    ("p n" "New PlatformIO project" +pio/new-project)]
   ["PlatformIO"
    :if (lambda () (+cpp--kind-p 'platformio))
    ("p e" "Environment"      +pio/set-env)
    ("p b" "Build"            +pio/build)
    ("p u" "Upload"           +pio/upload)
    ("p c" "Clean"            +pio/clean)
    ("p m" "Serial monitor"   +pio/monitor)
    ("p t" "Test"             +pio/test)
    ("p i" "compile_commands.json" +pio/compiledb)
    ("p d" "Debug (gdb)"      +pio/debug)
    ("p l" "Devices"          +pio/device-list)
    ("p B" "Boards"           +pio/boards)
    ("p L" "Install a library" +pio/lib-install)
    ("p U" "Update the packages" +pio/update)]])


;;
;;; SPC k m: what you set

;;;###autoload (autoload '+cpp/cmake-menu "private/cpp/autoload/menu" nil t)
(transient-define-prefix +cpp/cmake-menu ()
  "The settings a CMake build depends on, and the files behind them.
A setter keeps the panel open, so the header shows what it did; the
CMake flags are the keys: -D sets a cache variable, -U clears one,
-j the jobs, -v verbose, -L the log level. -l lists the ones set."
  [:description +cpp--cmake-menu-description
   ["Kit"
    ("K" "Pick the kit"       +cpp/set-kit :transient t)
    ("y" "Build type"         +cpp/build-type)
    ("Y" "Kit family"         +cpp/kit-family)
    ("Z" "Forget the kits, read the disk again" +cpp/forget-kits :transient t)]
   ["Settings"
    ("-D" "Set a cache variable" +cpp/cmake-set-variable :transient t)
    ("-U" "Clear a cache variable" +cpp/cmake-clear-variable :transient t)
    ("-l" "List the ones set" +cpp/cmake-list-variables :transient t)
    ("-L" "Log level"         projection-cmake-set-configure-log-level :transient t)
    ("-j" "Parallel jobs"     +cpp/set-jobs :transient t)
    ("-v" "Verbose build"     projection-cmake-set-build-verbosely :transient t)
    ("s" "Default target"     +cpp/set-build-target :transient t)
    ("A" "Run target"         +cpp/set-run-target :transient t)
    ("a" "Run arguments"      +cpp/set-run-args :transient t)]
   ["Configure and build"
    ("c" "Configure"          projection-commands-configure-project)
    ("F" "Configure fresh, the cache dropped" +cpp/cmake-configure-fresh)
    ("z" "Configure, reindex, restart the server" +cpp/reconfigure-and-reindex)
    ("b" "Build"              projection-commands-build-project)
    ("C" "Clean"              +cpp/cmake-clean)
    ("W" "Rebuild: clean, then build" +cpp/cmake-rebuild)]
   ["Files and status"
    ("I" "Project status"     +cpp/project-status)
    ("v c" "CMakeCache.txt"   +cpp/open-cmake-cache)
    ("v p" "CMakePresets.json" +cpp/open-presets)
    ("v j" "compile_commands.json" +cpp/open-compile-commands)
    ("v d" ".dir-locals.el"   +cpp/open-dir-locals)
    ("w" "Write the setup to .dir-locals.el" +cpp/write-dir-locals)
    ("G" "Generate the presets from the setup" +cpp/write-presets)]])
