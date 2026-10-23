;;; private/cpp/config.el -*- lexical-binding: t; -*-
;;
;; A Qt Creator style workflow for C and C++, under SPC k:
;;   projection  configure, build, run, test, with CMake presets and targets
;;               or PlatformIO environments
;;   clangd      the default server, ccls on request, per project if needed
;;   dape        debugging through gdb
;; Doom's :lang cc still provides cc-mode, the grammars, the lsp! hooks,
;; disaster, find-sibling-rules and cmake-mode.

;;
;;; Settings

(defconst +cpp-modes '(c-mode c-ts-mode c++-mode c++-ts-mode objc-mode)
  "The major modes of C and C++ buffers, the ones the kit, the server
and the formatter act on.")

(defvar +cpp-docs
  `(:groups (("cpp" "C and C++" (cc-mode c-ts-mode)
              c++-mode-map c++-ts-mode-map c-mode-map c-ts-mode-map)
             ("pio" "PlatformIO" ()))
    :sections ,(mapcar (lambda (mode) (cons mode "C and C++"))
                       (append +cpp-modes
                               '(cmake-mode cmake-ts-mode qml-mode qml-ts-mode
                                 compilation-mode))))
  "How the cheat sheet documents this module; see `+docs--module-docs'.")

(defvar +cpp-lsp-server 'clangd
  "Language server for C and C++: `clangd' or `ccls'.
Change it with `+cpp/set-lsp-server', or per project in .dir-locals.el.")
(put '+cpp-lsp-server 'safe-local-variable #'symbolp)

(defvar +cpp-container nil
  "The distrobox this project's kit runs in, or nil to read the disk.
Builds, tests, the debugger and the language server all run there, so
the server sees the sysroot the compiler does.  Nil means detect it: a
compiler the build directory names that is not on the host is looked
for in the running containers.  Set with `+cpp/set-container', kept per
project in .dir-locals.el, for the case detection cannot decide, a
compiler that exists on the host and in a container both.")
(put '+cpp-container 'safe-local-variable #'stringp)

(defvar +cpp-kit nil
  "The kit this project builds with: a preset name, or the name of a
configured build directory (build/horizon-Debug is \"horizon-Debug\").
Nil means read the disk: Qt Creator's active configuration when it is
configured, else the newest configured directory.  `+cpp/set-kit' writes
the choice to .dir-locals.el.")
(put '+cpp-kit 'safe-local-variable #'stringp)

(defvar +cpp-kits nil
  "The kits of this project written down, a list of plists, one per kit:
:name and :dir, then what a kit knows, :type :generator :compiler
:toolchain :sysroot :qt :args :env :targets :run :configs :container
:env-script, any of them.  `+cpp/write-dir-locals' writes what Qt
Creator, the caches and the presets say, so the project carries its
setup without them; a kit declared here that the disk does not know
is offered like any other, and one it knows is completed from here.
Kept in .dir-locals.el.")
(put '+cpp-kits 'safe-local-variable #'listp)

(defvar +cpp-package-target nil
  "The target SPC k P builds to package this project, by name; nil asks
among the packaging targets.  Set with `+cpp/package', kept in
.dir-locals.el.")
(put '+cpp-package-target 'safe-local-variable #'stringp)

(defvar +cpp-package-dir nil
  "Where `+cpp/package-copy' puts the packages this project makes.
Asked the first time, kept in .dir-locals.el.")
(put '+cpp-package-dir 'safe-local-variable #'stringp)

(defvar +cpp-build-config nil
  "The configuration a multi-config generator, Ninja Multi-Config,
builds: Debug, Release, RelWithDebInfo or MinSizeRel, passed as
--config to the build and -C to ctest.  Nil means the first the cache
lists.  `+cpp/build-type' sets it for such a kit; kept in
.dir-locals.el.")
(put '+cpp-build-config 'safe-local-variable #'stringp)

;; Written into a project's .dir-locals.el by the panel and by
;; `+cpp/write-dir-locals'; marking them safe keeps Emacs from asking.
(put 'projection-cmake-build-directory 'safe-local-variable #'stringp)
(put '+cpp-cache-overrides 'safe-local-variable #'listp)
(put '+cpp-run-args 'safe-local-variable #'stringp)
(put '+cpp-run-target 'safe-local-variable #'stringp)
(put '+cpp-build-target 'safe-local-variable #'stringp)

(defvar +pio-env nil
  "PlatformIO environment to build for, or nil for the project default.")
(put '+pio-env 'safe-local-variable #'string-or-null-p)

(defvar +cpp-debug-port 2345
  "The port gdbserver listens on when debugging on a device.")
(put '+cpp-debug-port 'safe-local-variable #'integerp)

(defvar +cpp-gdb nil
  "The gdb to debug with, when the one beside the kit's compiler is not
the one wanted.  Nil and it is worked out from the kit.")
(put '+cpp-gdb 'safe-local-variable #'string-or-null-p)

(defvar +cpp-clangd-args
  (list "--background-index"
        ;; Index at low priority: a fresh project is indexed in the
        ;; background without the editor or the build feeling it.
        "--background-index-priority=low"
        "--clang-tidy"
        "--header-insertion=iwyu"
        "--completion-style=detailed"
        "--function-arg-placeholders=0"
        "--pch-storage=memory"
        "--log=error"
        (format "-j=%d" (doom-system-cpus))
        ;; Compilers clangd may run to learn their include paths: PlatformIO's
        ;; cross compilers, and any SDK under /opt laid out the Yocto way,
        ;; sysroots/<host>/usr/bin/<triple>/<compiler>, which is what Qt
        ;; Creator kits for embedded targets use.
        (concat "--query-driver="
                (expand-file-name "~/.platformio/packages/toolchain-*/bin/*")
                ",/opt/*/sysroots/*/usr/bin/*/*"))
  "Arguments passed to clangd.")

(defvar +cpp-ccls-init-options
  `(:index (:threads ,(doom-system-cpus) :trackDependency 1)
    :cache (:directory ".ccls-cache"))
  "Options sent to ccls when it starts.")

(defvar +cpp-templates-dir (file-name-concat doom-user-dir "templates/cpp/")
  "Project templates, one directory per kind: lib, app, qt.")

(defvar +cpp-cache-overrides nil
  "CMake cache variables this project overrides, as (NAME . VALUE).
Set from the panel with SPC k m -D; kept in the project's .dir-locals.el.")

(defvar +cpp-run-args nil
  "Arguments every run of this project passes to the executable.
Split on spaces with quotes grouping, as Qt Creator splits its field,
no shell behind it.  Set from the panel with SPC k m a; kept in the
project's .dir-locals.el.  Nil means Qt Creator's run configuration,
when the project has one.")

(defvar +cpp-run-target nil
  "The executable target SPC k r runs, by name.
Nil means Qt Creator's run configuration, else the only executable, else
a choice.  Set with `+cpp/set-run-target', kept in .dir-locals.el.")

(defvar +cpp-build-target nil
  "The target SPC k b builds, by name; nil for all.
Set with `+cpp/set-build-target', kept in .dir-locals.el.")


;; The offline docs SPC s k searches, and core installs on first use.
;; Doom names them when cc-mode and cmake-mode load, which a tree-sitter
;; buffer never does, so the tree-sitter modes are named too.
(when (modulep! :tools lookup +docsets)
  (set-docsets! '(c-mode c-ts-mode) "C")
  (set-docsets! '(c++-mode c++-ts-mode) "C++" "Boost")
  (set-docsets! '(cmake-mode cmake-ts-mode) "CMake"))


;;
;;; Language server (eglot)

;; :lang cc starts eglot for us. This entry picks the server when it
;; connects, so a dir-local `+cpp-lsp-server' can override the default.
(set-eglot-client! +cpp-modes #'+cpp--eglot-server-program)

;; The first C or C++ file of a session loads the files of this module
;; that find the kit and the container, Qt Creator's and projection's.
;; When the file opened last was one, they are loaded ahead while Emacs
;; waits after starting (`+core-warm-up-functions').
(defun +cpp--warm-up-h (mode)
  "Load what the first C or C++ file of a session loads, if MODE is one."
  (when (memq mode +cpp-modes)
    (+core-load-autoloads '+pio--configure-command '+cpp-kit-abs-dir
                          '+cpp--eglot-server-program '+cpp--projection-project
                          '+cpp--sdk-root '+cpp--project-kind '+qtcreator-kits
                          '+container-list 'doom-store-get)
    (require 'xml)
    (require 'projection-type-cmake nil t)))

(add-hook '+core-warm-up-functions #'+cpp--warm-up-h 50)

;; F4 and SPC p o: header and source. Doom sets these rules when cc-mode
;; loads, but a tree-sitter buffer never loads cc-mode, so they are set
;; here, with one more pair for names with a platform in them, so
;; foo.arm.cpp finds foo.h and back.
(dolist (rule '(("/\\([^/]+\\)\\.c\\(c\\|pp\\)?\\'" "\\1.h\\(h\\|pp\\)?\\'")
                ("/\\([^/]+\\)\\.h\\(h\\|pp\\)?\\'" "\\1.c\\(c\\|pp\\)?\\'")
                ("/\\([^/]+\\)\\.[^./]+\\.c\\(c\\|pp\\)?\\'" "\\1.h\\(h\\|pp\\)?\\'")
                ;; No slash in this class: the expansion is split on them.
                ("/\\([^/]+\\)\\.h\\(h\\|pp\\)?\\'" "\\1\\.[^.]+\\.c\\(c\\|pp\\)?\\'")))
  (add-to-list 'find-sibling-rules rule))

(after! eglot
  ;; Let xref follow definitions into system headers.
  (setq eglot-extend-to-xref t)
  ;; Who calls this, and what a class derives from: eglot has both and
  ;; binds neither. They are the questions an IDE is asked about a large
  ;; C++ tree, and they work wherever a server answers them.
  (map! :leader
        :desc "Call hierarchy" "c h" #'eglot-show-call-hierarchy
        :desc "Type hierarchy" "c T" #'eglot-show-type-hierarchy)
  ;; A path inside the container opens through TRAMP.
  (advice-add #'eglot-uri-to-path :filter-return #'+cpp--container-path-a))

;; The server's semantic tokens, on by default in this eglot, stay on:
;; they colour by meaning, what tree-sitter cannot know, a member, a
;; parameter, a macro, at a request per change and per range scrolled to,
;; which a fast machine does not feel. M-x eglot-semantic-tokens-mode
;; turns them off in a buffer; SPC k l i the inlay hints.

;; QML: openSUSE installs Qt 6 tools with a version suffix, so the plain
;; name Doom looks for is not there; Homebrew keeps them in its Qt. Doom
;; registers `qmlls' for `qml-ts-mode' on its own and eglot takes the
;; first entry that matches, so that entry goes and ours is used. And
;; qmlls resolves only what Qt ships unless it is given a build
;; directory, so a type of the project's own, or a Label from a module
;; the project builds, is unknown; the kit knows where that directory is.
(when (modulep! :lang qt +lsp)
  ;; Doom registers its entry from the mode's own `:config', which is
  ;; later than any `after! eglot' here, so it would land in front of
  ;; ours whatever we did at load time. This runs as the mode starts,
  ;; before `eglot-ensure' on the same hook, and leaves one entry.
  (add-hook 'qml-ts-mode-hook #'+cpp--qml-server-h -100)
  (add-hook 'qml-mode-hook #'+cpp--qml-server-h -100))

;; A PlatformIO project keeps its flags in platformio.ini, and the server
;; cannot read that: it reads compile_commands.json, which pio writes on
;; being asked. The first C or C++ file opened in such a project asks.
;; Any other project's database is found where its build wrote it and
;; made readable to clang, and a CMake project never configured is
;; configured in the background. The mode is tested first, so any other
;; file leaves pio.el and compdb.el unloaded.
(add-hook! 'find-file-hook
  (defun +pio--compiledb-maybe-h ()
    "Ask for the compilation database when the file is C or C++."
    (when (derived-mode-p 'c-mode 'c++-mode 'c-ts-mode 'c++-ts-mode)
      (+pio--compiledb-h)
      (+cpp--compdb-h))))

;; CMakeLists.txt: completion and documentation for commands and variables.
(set-eglot-client! '(cmake-mode cmake-ts-mode)
                   '("cmake-language-server") '("neocmakelsp" "--stdio"))

(after! projectile
  ;; Recognise CMake/PlatformIO trees that are not (yet) git repositories.
  ;; "top-down-recurring" keeps climbing while the marker is present, so a
  ;; nested src/CMakeLists.txt still resolves to the top-level directory.
  (dolist (marker '("CMakeLists.txt" "platformio.ini"))
    (add-to-list 'projectile-project-root-files-top-down-recurring marker)))

(after! project
  ;; The same for project.el (used by projection and eglot). Runs after
  ;; `project-try-vc', so a git root always wins over the marker.
  (add-hook 'project-find-functions #'+cpp--project-try-build-root 'append))


;;
;;; Build system (projection)

;; Declared special here so the `let' in `+cpp--with-kit' binds dynamically
;; even if a file is ever byte-compiled before projection is loaded.
(defvar projection-cmake-build-directory)
(defvar projection-cmake-build-directory-remote)
(defvar projection-cmake-configure-options)

;; projection's commands autoload from files that load its core but not
;; its project types, so an early build would find no type and fall back
;; to "make". The whole package, and with it the types below, loads as
;; soon as the core does.
(after! projection-core
  (require 'projection))

(use-package! projection
  :defer t
  :commands (projection-commands-configure-project
             projection-commands-build-project
             projection-commands-test-project
             projection-commands-run-project
             projection-commands-package-project
             projection-commands-install-project
             projection-set-primary-project-type
             projection-show-project-info
             projection-cache-clear
             projection-find-other-file
             projection-artifacts-list)
  :config
  (setq projection-cmake-build-directory "build"
        ;; Always write compile_commands.json, for clangd and ccls.
        projection-cmake-configure-options
        '("-DCMAKE_EXPORT_COMPILE_COMMANDS=ON")
        projection-cmake-ctest-options '("--output-on-failure")
        projection-build-jobs (doom-system-cpus))

  ;; PlatformIO projects build, upload and test through pio.
  (defvar projection-project-type-platformio
    (projection-type
     :name 'platformio
     :predicate "platformio.ini"
     :configure #'+pio--configure-command
     :build     #'+pio--build-command
     :test      #'+pio--test-command
     :run       #'+pio--upload-command
     :install   #'+pio--upload-command
     :compile-multi-targets #'+pio-targets)
    "projection type for PlatformIO projects (platformio.ini).")

  ;; CMake projects build through the kit: the build directory the kit
  ;; names, inside the container the kit's compiler lives in, with the
  ;; SDK environment sourced. projection's own CMake type is replaced by
  ;; this one, which asks projection for every command with the kit's
  ;; directory in place and wraps what comes back.
  (defvar projection-project-type-cmake-kit
    (projection-type
     :name 'cmake
     :predicate "CMakeLists.txt"
     :configure #'+cpp--configure-command
     :build     #'+cpp--build-command
     :test      #'+cpp--test-command
     :install   #'+cpp--install-command
     :run       #'+cpp/run
     :artifacts-list #'+cpp--artifacts
     :test-suffix '(".t" ".g")
     :compilation-error-regexp-alist
     `((projection-gnu+ctest . ,projection-types--gnu-ctest-compilation-error-regexp))
     :compilation-search-paths #'+cpp--compilation-search-paths
     :compile-multi-targets #'+cpp--compile-multi-targets)
    "projection type for CMake projects, built through the kit.")

  ;; Replaced by name, so a rename upstream of the object still drops
  ;; projection's own cmake type rather than leaving two.
  (setq projection-project-types
        (cons projection-project-type-platformio
              (cons projection-project-type-cmake-kit
                    (seq-remove (lambda (type)
                                  (memq (oref type name) '(cmake platformio)))
                                projection-project-types))))

  ;; projection writes its file API query into `projection-cmake-build-directory'
  ;; before a configure, which without the kit in place creates an empty
  ;; build/. `+cpp--configure-command' writes it into the kit's directory
  ;; itself, so that hook does nothing here. Its autoload adds it back
  ;; every time projection-type-cmake loads, hence the advice rather
  ;; than a remove-hook. The one projection internal outside shim.el.
  (advice-add #'projection-cmake--file-api-create-query-hook :override #'ignore))

(use-package! projection-multi
  :defer t
  :commands (projection-multi-compile projection-multi-projection))

(use-package! projection-multi-embark
  :after (embark projection-multi)
  :config (projection-multi-embark-setup-command-map))

(use-package! compile-multi-embark
  :after (embark compile-multi)
  :config (compile-multi-embark-mode +1))

(use-package! compile-multi-nerd-icons
  :after compile-multi)

(use-package! projection-dape
  :defer t
  :commands projection-dape)

;; Compilation buffer UX: keep the point on the first error, honour colours.
(after! compile
  (setq compilation-scroll-output 'first-error
        compilation-max-output-line-length nil))

(set-popup-rule! "^\\*pio monitor"
  :side 'bottom :size 0.35 :quit nil :ttl nil :select t)
;; The keys that cannot go through projection, which are run, debug,
;; the panel and a new project, are dispatched by kind, so they mean the
;; same thing in a Rust or a Pascal buffer. cpp is the fallback for
;; those: a directory with a Makefile and a binary in it is its business
;; as much as a CMake tree is. Its SPC k keys it shows only in a C or
;; C++ project, which is what its test says.
(+core-register-builder 'cpp #'+cpp-project-p
                        :run #'+cpp/run
                        :run-with-args #'+cpp/run-with-args
                        :build-and-run #'+cpp/build-and-run
                        :debug #'+cpp/debug
                        :panel #'+cpp/cmake-menu
                        :new #'+cpp/new-project
                        :label "C and C++, PlatformIO"
                        :keys '+cpp-kit-map
                        :fallback t)


;; SPC k R and S-F6: the build is asked to run what it made when it ends.
(add-hook 'compilation-finish-functions #'+cpp--run-after-build-h)



;;
;;; Debugging (dape + gdb DAP)

(after! dape
  ;; Doom already sets dape's layout and inlay hints, and dape ships a gdb
  ;; config. SPC k d builds its own config from the kit; these two are
  ;; for M-x dape by hand: a program asked for, or a process.
  (add-to-list 'dape-configs
               `(gdb-project
                 modes ,+cpp-modes
                 ensure dape-ensure-command
                 command "gdb"
                 command-args ("--interpreter=dap")
                 :type "gdb"
                 :request "launch"
                 :program +cpp--read-program
                 :cwd +cpp--project-root-or-cwd
                 :args []
                 :stopAtBeginningOfMainSubprogram t))
  (add-to-list 'dape-configs
               `(gdb-attach
                 modes ,+cpp-modes
                 ensure dape-ensure-command
                 command "gdb"
                 command-args ("--interpreter=dap")
                 :type "gdb"
                 :request "attach"
                 :pid +cpp--read-pid)))


;;
;;; Assembly

(use-package! rmsbolt
  :defer t
  :config
  (setq rmsbolt-asm-format "intel"
        rmsbolt-filter-directives t
        rmsbolt-filter-labels t
        rmsbolt-filter-comment-only t
        rmsbolt-automatic-recompile t
        rmsbolt-compile-delay 0.6
        ;; The compiler is quiet enough; the compilation buffer is noise.
        rmsbolt-hide-compile t)
  (set-popup-rule! "^\\*rmsbolt-compilation\\*" :ignore t))


;;
;;; Indentation, from the project's .clang-format

;; The tree-sitter modes indent GNU style by two, and their C++ rules
;; leave holes: the brace of a namespace, a class or an enum body is
;; pushed in, and case labels sit on the switch.  A buffer takes its indentation from the .clang-format that
;; governs it: the width, tabs or spaces, where braces go (Allman when
;; a function's brace opens its own line, K&R otherwise, Linux and GNU
;; by name), whether namespace bodies and case labels indent; a project
;; without one gets K&R by four.  clang-format on save settles the rest.
(defun +cpp--clang-format-values (file)
  "The top-level KEY: VALUE lines of FILE, a .clang-format, as an alist,
with the AfterFunction line of BraceWrapping, the one that says where
a function's brace goes."
  (with-temp-buffer
    (insert-file-contents file)
    (goto-char (point-min))
    (let (values)
      (while (re-search-forward "^\\(  \\)?\\([A-Za-z]+\\):[ \t]*\\([^#\n]*?\\)[ \t]*\\(?:#.*\\)?$" nil t)
        (let ((nested (match-beginning 1)) (key (match-string 2)) (value (match-string 3)))
          (when (and (not (string-empty-p value))
                     (or (not nested) (equal key "AfterFunction")))
            (push (cons key value) values))))
      values)))

(defvar-local +cpp--indent-plan nil
  "(STYLE OFFSET NAMESPACES CASES) for this buffer: the base style, the
width, whether namespace bodies indent, whether case labels do.")

(defun +cpp--indent-plan (file)
  "The indent plan FILE, a .clang-format, asks for; the default without one."
  (if (not file)
      (list 'k&r 4 nil nil)
    (let* ((values (+cpp--clang-format-values file))
           (get (lambda (key) (cdr (assoc key values))))
           (based (funcall get "BasedOnStyle"))
           (braces (funcall get "BreakBeforeBraces"))
           (width (or (funcall get "IndentWidth")
                      (pcase based
                        ((or "Google" "LLVM" "Chromium" "Mozilla" "GNU") "2")
                        (_ "4"))))
           (style (pcase braces
                    ("Allman" 'bsd)
                    ("Linux" 'linux)
                    ("GNU" 'gnu)
                    ("Custom" (if (equal (funcall get "AfterFunction") "true") 'bsd 'k&r))
                    ((pred stringp) 'k&r)
                    (_ (pcase based ("GNU" 'gnu) ("Microsoft" 'bsd) (_ 'k&r))))))
      (list style (string-to-number width)
            (member (funcall get "NamespaceIndentation") '("All" "Inner"))
            (equal (funcall get "IndentCaseLabels") "true")))))

(declare-function +core-register-builder "build")
(declare-function c-ts-mode-set-style "c-ts-mode")
(declare-function c-ts-mode--simple-indent-rules "c-ts-mode")

(defun +cpp--indent-rules ()
  "The indent rules for this buffer: Emacs's own for the base style,
with the C++ holes filled.  `c-ts-mode-indent-style' when it is a
function, so `c-ts-mode-set-style' installs them."
  (pcase-let ((`(,style ,_offset ,namespaces ,cases) +cpp--indent-plan))
    (append
     ;; The brace that opens a namespace, class, struct, union or enum
     ;; body sits under the line that names it, in every style but GNU.
     (unless (eq style 'gnu)
       `(((node-is ,(rx bos (or "declaration_list" "field_declaration_list" "enumerator_list") eos))
          standalone-parent 0)))
     ;; A namespace body stays put unless the project indents it.
     (unless namespaces
       '(((n-p-gp nil "declaration_list" "namespace_definition") standalone-parent 0)
         ((n-p-gp "}" "declaration_list" "namespace_definition") standalone-parent 0)))
     ;; Case labels step in from the switch when the project says so.
     (when cases
       '(((node-is "case_statement") standalone-parent c-ts-indent-offset)))
     (alist-get 'cpp (c-ts-mode--simple-indent-rules 'cpp style)))))

(declare-function c-set-offset "cc-styles")

(defun +cpp--indent-from-project-h ()
  "Indent this buffer the way its project's .clang-format says."
  (when (or (derived-mode-p 'c++-mode)
            (and (derived-mode-p 'c++-ts-mode) (fboundp 'c-ts-mode--simple-indent-rules)))
    (let* ((dir (locate-dominating-file default-directory ".clang-format"))
           (file (and dir (expand-file-name ".clang-format" dir)))
           (values (and file (+cpp--clang-format-values file))))
      (setq +cpp--indent-plan (+cpp--indent-plan file))
      (when-let* ((tabs (cdr (assoc "UseTab" values))))
        (setq-local indent-tabs-mode (not (equal tabs "Never"))))
      (when-let* ((tab (cdr (assoc "TabWidth" values))))
        (setq-local tab-width (string-to-number tab)))
      (pcase-let ((`(,_style ,offset ,namespaces ,cases) +cpp--indent-plan))
        (if (derived-mode-p 'c++-ts-mode)
            (progn
              ;; Renamed in Emacs 31; the old name still works and warns.
              (setq-local c-ts-indent-offset offset)
              (c-ts-mode-set-style #'+cpp--indent-rules))
          ;; A test file, in cc-mode: the same width, namespaces, labels.
          (setq-local c-basic-offset offset)
          (c-set-offset 'innamespace (if namespaces '+ 0))
          (c-set-offset 'case-label (if cases '+ 0)))))))

(add-hook 'c-ts-base-mode-hook #'+cpp--indent-from-project-h)
(add-hook 'c++-mode-hook #'+cpp--indent-from-project-h)

;; Doom's style lines a closing paren up with this function, whose
;; argument is spelt `langlem' while its body reads `langelem', so TAB on
;; a line that closes an argument list signals a void variable in a
;; cc-mode buffer. This is the same function with the name it reads.
(declare-function c-langelem-pos "cc-defs")
(declare-function c-lineup-arglist "cc-align")
(defadvice! +cpp--lineup-arglist-close-a (langelem)
  :override #'+cc-lineup-arglist-close
  (when (save-excursion
          (save-match-data
            (skip-chars-backward " \t\n" (c-langelem-pos langelem))
            (memq (char-before) (list ?, ?\( ?\;))))
    (c-lineup-arglist langelem)))

;; QML indents by `qml-ts-mode-indent-offset', which the mode reads once
;; when the package loads and writes into every one of its indent rules,
;; so setting it afterwards, or from .editorconfig, changes nothing and
;; the file is indented by four whatever it says. The rules are built
;; again per buffer from whatever the offset is by then.
(after! editorconfig
  (add-to-list 'editorconfig-indentation-alist
               '(qml-ts-mode qml-ts-mode-indent-offset)))

(add-hook 'qml-ts-mode-hook #'+cpp--qml-indent-h)
(add-hook 'editorconfig-after-apply-functions
          (defun +cpp--qml-editorconfig-h (&rest _)
            (when (derived-mode-p 'qml-ts-mode) (+cpp--qml-indent-h))))


;;
;;; Formatting

;; QML has a formatter of its own that Doom does not know, so it is
;; added here. qmlformat prints to stdout and takes the indent width,
;; which is the one this file is written in.
(after! apheleia
  (setf (alist-get 'qmlformat apheleia-formatters)
        ;; The plain name is Qt 5 on openSUSE and does not know
        ;; -w; the suffixed one is Qt 6, as with qmlls.
        '((or (executable-find "qmlformat6")
              (executable-find "/usr/lib64/qt6/bin/qmlformat")
              (executable-find "qmlformat")
              (executable-find "/opt/homebrew/opt/qt/bin/qmlformat"))
          "-w" (number-to-string (or (bound-and-true-p qml-ts-mode-indent-offset) 4))
          input))
  (setf (alist-get 'qml-ts-mode apheleia-mode-alist) 'qmlformat)
  (setf (alist-get 'qml-mode apheleia-mode-alist) 'qmlformat))

;; :editor format runs clang-format on save. Without a .clang-format that
;; means LLVM style everywhere, so only format projects that ship one. The
;; scaffolds do, so a new project is formatted from the first save.
(add-hook! 'apheleia-inhibit-functions
  (defun +cpp--inhibit-format-without-clang-format-h ()
    (and (apply #'derived-mode-p +cpp-modes)
         (not (locate-dominating-file default-directory ".clang-format")))))


;;
;;; File templates

;; New files start from the templates in $DOOMDIR/snippets. Doom already
;; points .hpp and .cpp at __hpp and __cpp but ships no such snippet; ours
;; follow the house style.
(set-file-template! "/CMakeLists\\.txt\\'"
                    :trigger "__CMakeLists.txt" :mode 'cmake-mode)
(set-file-template! "/te?st_[^/]+\\.cpp\\'"
                    :trigger "__test.cpp" :mode 'c++-mode)


;;
;;; Keybindings

(declare-function +core-kit-keymap "build")
(defvar +core-kit-project-map)

(defvar +cpp-kit-map
  (+core-kit-keymap
   `(("SPC" "Kit menu: what you do" #'+cpp/menu)
     ("m" "The project's panel" #'+core/build-panel)
     ;; Build. Doom's SPC c C recompiles, so the kit prefix does not.
     ("c" "Configure" #'projection-commands-configure-project)
     ("b" "Build" #'projection-commands-build-project)
     ("x" "Build, then run" #'+core/build-and-run)
     ("B" "Build a target" #'projection-multi-compile)
     ("t" "Test" #'projection-commands-test-project)
     ("T" "Test at point" #'+cpp/test-at-point)
     ("u" "A test executable" #'+cpp/test-binary)
     ("i" "Install" #'projection-commands-install-project)
     ("P" "Package" #'+cpp/package)
     ("o" "Copy the package out" #'+cpp/package-copy)
     ;; Run
     ("r" "Run" #'+core/run)
     ("R" "Run with arguments" #'+core/run-with-args)
     ("S" "Run a project script" #'+cpp/run-script)
     ("U" "Deploy to the device" #'+cpp/deploy)
     ("d" "Debug" #'+core/debug)
     ("D" "Debug on the device" #'+cpp/debug-on-device)
     ("j" "Attach to a gdb server" #'+cpp/debug-remote)
     ;; Kit
     ("K" "Pick the kit" #'+cpp/set-kit)
     ("y" "Build type" #'+cpp/build-type)
     ("Y" "Kit family" #'+cpp/kit-family)
     ("?" "Which kit, and why" #'+cpp/show-kit)
     ("s" "Default target" #'+cpp/set-build-target)
     ("I" "Project status" #'+cpp/project-status)
     ("w" "Write the setup to .dir-locals.el" #'+cpp/write-dir-locals)
     ("G" "Generate the presets" #'+cpp/write-presets)
     ;; Fix
     ("e" "Next problem" #'+cpp/next-problem)
     ("E" "Previous problem" #'+cpp/previous-problem)
     ("." "Fix it: the quickfix at point" #'+cpp/quickfix)
     ("f" "clang-format this buffer" #'+cpp/format-buffer)
     ("g" "gates: format, tidy"
      (("F" "clang-format the project" #'+cpp/format-project)
       ("t" "clang-tidy this file" #'+cpp/tidy-file)
       ("T" "clang-tidy this file, apply the fixes" ,(cmd! (+cpp/tidy-file t)))
       ("p" "clang-tidy the project" #'+cpp/tidy-project)))
     ;; Files and tools. Header and source is Doom's SPC p o, and F4.
     ("H" "Other file of the project" #'projection-find-other-file)
     ("a" "Assembly, live" #'+cpp/assembly)
     ("A" "Disassemble at point" #'disaster)
     ("n" "New project" #'+core/new-project)
     ("N" "New Qt MVVM app" #'+cpp/new-qt-project)
     ("l" "language server"
      (("s" "Switch server: clangd, ccls" #'+cpp/set-lsp-server)
       ("r" "Restart it" #'+cpp/restart-lsp)
       ("i" "Inlay hints" #'eglot-inlay-hints-mode)
       ("c" "Write .clangd" #'+cpp/write-clangd-config)
       ("l" "Link compile_commands.json into the root" #'+cpp/link-compile-commands)
       ("b" "Run the kit in a container" #'+cpp/set-container)
       ("e" "The server's log" #'+cpp/server-log)))
     ("p" "PlatformIO"
      (("e" "Environment" #'+pio/set-env)
       ("b" "Build" #'+pio/build)
       ("u" "Upload" #'+pio/upload)
       ("c" "Clean" #'+pio/clean)
       ("m" "Serial monitor" #'+pio/monitor)
       ("t" "Test" #'+pio/test)
       ("i" "compile_commands.json" #'+pio/compiledb)
       ("d" "Debug (gdb)" #'+pio/debug)
       ("l" "Devices" #'+pio/device-list)
       ("B" "Boards" #'+pio/boards)
       ("L" "Install a library" #'+pio/lib-install)
       ("U" "Update the packages" #'+pio/update)
       ("H" "PlatformIO Home" #'+pio/home)
       ("n" "New project" #'+pio/new-project)))))
  "SPC k in a C or C++ project: CMake, PlatformIO, Meson or make.")

;; And its menu of what a project can do, which reads Cargo, Gradle,
;; Maven, npm and Python projects as well, in a project no module knows.
(define-key +core-kit-project-map (kbd "SPC") (cons "What the project can do" #'+cpp/menu))

;; Qt Creator's function keys. F2 and F4 only in C and C++ buffers; map!
;; defers each map until its mode loads, so the four maps share one block.
;; F6, S-F6 and SPC k R go by the project's language, as SPC k r does,
;; so a Pascal or Rust project runs its own way rather than as C++.
(map! :g "<f5>"  #'+cpp/debug-or-continue
      :g "<f6>"  #'+core/run
      :g "<S-f6>" #'+core/build-and-run
      :g "<f7>"  #'projection-commands-build-project
      :g "<f8>"  #'projection-commands-configure-project
      :g "<f9>"  #'dape-breakpoint-toggle
      (:map (c-mode-map c++-mode-map c-ts-mode-map c++-ts-mode-map)
       "<f2>"   #'+lookup/definition
       "<S-f2>" #'+cpp/find-declaration
       "<f4>"   #'find-sibling-file))

;; The stepping keys, while a session runs. dape's mode for that has no
;; keymap of its own, and a map bound to `dape-active-mode-map' would
;; wait for a variable that never comes; this one hangs from the mode's
;; variable instead.
(defvar +cpp-dape-active-map
  (define-keymap
    "<f10>"   #'dape-next
    "<f11>"   #'dape-step-in
    "S-<f11>" #'dape-step-out
    "S-<f5>"  #'dape-quit)
  "Keys that step through a running debug session.")
(add-to-list 'minor-mode-map-alist (cons 'dape-active-mode +cpp-dape-active-map))

;; The most used ones, also on the localleader.
(map! :map (c-mode-map c++-mode-map c-ts-mode-map c++-ts-mode-map)
      :localleader
      :desc "Kit menu: what you do" "k" #'+cpp/menu
      :desc "Build"             "b" #'projection-commands-build-project
      :desc "Run"               "r" #'+cpp/run
      :desc "Debug"             "d" #'+cpp/debug
      :desc "Header and source" "h" #'find-sibling-file
      :desc "Declaration"       "D" #'+cpp/find-declaration
      :desc "Where is it used"  "u" #'+lookup/references
      :desc "clang-format"      "f" #'+cpp/format-buffer
      :desc "Disassemble"       "a" #'disaster)
