;;; private/pascal/autoload/pascal.el -*- lexical-binding: t; -*-
;;
;; Object Pascal: Free Pascal and Lazarus locally, Delphi sources read
;; and edited. What a build depends on is kept in .dir-locals.el, the
;; way the cpp and rust modules keep theirs, and every command is built
;; from it.

(declare-function +core-project-root "lib")
(declare-function +core-dir-locals-set "lib")
(declare-function +core-compile "lib")
(declare-function dape "dape")
(declare-function dape--config-eval "dape")
(defvar +pascal-host-os)


;;
;;; The settings

;;;###autoload
(defvar-local +pascal-build-mode nil
  "The Lazarus build mode to build with, or nil for the project's default.")
;;;###autoload
(put '+pascal-build-mode 'safe-local-variable #'stringp)

;;;###autoload
(defvar-local +pascal-widgetset nil
  "The widget set an LCL program is built against: gtk2, gtk3, qt5, qt6,
cocoa on a Mac.
Nil leaves the choice to the project, which is what a project that only
ever runs here wants.")
;;;###autoload
(put '+pascal-widgetset 'safe-local-variable #'stringp)

;;;###autoload
(defvar-local +pascal-target nil
  "The target as CPU-OS, say \"x86_64-linux\" or \"arm-embedded\", or nil
for this machine.")
;;;###autoload
(put '+pascal-target 'safe-local-variable #'stringp)

;;;###autoload
(defvar-local +pascal-run-args nil
  "Arguments passed to the program, as one string.")
;;;###autoload
(put '+pascal-run-args 'safe-local-variable #'stringp)

;;;###autoload
(defvar-local +pascal-main nil
  "The program file to build when a project holds more than one, relative
to the root.  Nil means the one the project names, or the only one.")
;;;###autoload
(put '+pascal-main 'safe-local-variable #'stringp)


;;;###autoload
(defun +pascal-jcf-settings-file ()
  "The formatter's settings for this buffer: the project's jcfsettings.cfg
when it has one, else `+pascal-jcf-settings'."
  (if-let* ((dir (locate-dominating-file default-directory "jcfsettings.cfg")))
      (expand-file-name "jcfsettings.cfg" dir)
    (bound-and-true-p +pascal-jcf-settings)))


;;
;;; What kind of project this is

(defun +pascal--files (root pattern)
  "The files matching PATTERN directly under ROOT, and one level down."
  (when (and root (file-directory-p root))
    (append (directory-files root t pattern)
            (mapcan (lambda (dir)
                      (when (file-directory-p dir)
                        (directory-files dir t pattern)))
                    (seq-remove
                     (lambda (d) (string-match-p "/\\.\\{1,2\\}\\'" d))
                     (directory-files root t "\\`[^.]"))))))

;;;###autoload
(defun +pascal-project-kind (&optional dir)
  "What kind of Pascal project DIR is: `lazarus', `fpc', `delphi' or nil.
A Lazarus project has an .lpi beside its sources; a Delphi one a .dproj
or a .dpr; anything else with a .lpr or a .pas that says `program' is
Free Pascal's to build."
  (let ((root (or dir (+core-project-root 'noerror))))
    (when root
      (cond ((+pascal--files root "\\.lpi\\'") 'lazarus)
            ((+pascal--files root "\\.\\(dproj\\|dpr\\)\\'") 'delphi)
            ((+pascal--files root "\\.lpr\\'") 'fpc)
            ((seq-some (lambda (file)
                         (with-temp-buffer
                           (insert-file-contents file nil 0 2000)
                           (goto-char (point-min))
                           (re-search-forward "^[[:space:]]*program[[:space:]]" nil t)))
                       (+pascal--files root "\\.pp?\\(as\\)?\\'"))
             'fpc)))))

;;;###autoload
(defun +pascal-project-p (&optional dir)
  "Non-nil when DIR, or the current project, is a Pascal project."
  (and (+pascal-project-kind dir) t))

;;;###autoload
(defun +pascal-root ()
  "The Pascal project's root, or an error."
  (let ((root (+core-project-root 'noerror)))
    (unless (+pascal-project-p root)
      (user-error "No Pascal project here"))
    (file-name-as-directory (expand-file-name root))))

(defun +pascal--main-file ()
  "The file a build starts from: the .lpi, the .lpr, or the program unit."
  (let* ((root (+pascal-root))
         (named (when +pascal-main (expand-file-name +pascal-main root))))
    (or (and named (file-exists-p named) named)
        (car (+pascal--files root "\\.lpi\\'"))
        (car (+pascal--files root "\\.lpr\\'"))
        (car (+pascal--files root "\\.dpr\\'"))
        (seq-find (lambda (file)
                    (with-temp-buffer
                      (insert-file-contents file nil 0 2000)
                      (goto-char (point-min))
                      (re-search-forward "^[[:space:]]*program[[:space:]]" nil t)))
                  (+pascal--files root "\\.pp?\\(as\\)?\\'"))
        (user-error "Nothing here to build: no .lpi, .lpr or program unit"))))


;;
;;; The command a build is

(defun +pascal--lazbuild-args ()
  "The lazbuild flags this project is set to, quoted for the shell: a
build mode is a name, \"Release Linux\" made lazbuild read Linux as a
second project."
  (mapcar #'shell-quote-argument
          (append
           (when +pascal-build-mode (list (concat "--build-mode=" +pascal-build-mode)))
           (when +pascal-widgetset (list (concat "--widgetset=" +pascal-widgetset)))
           (when +pascal-target
             (let ((parts (split-string +pascal-target "-")))
               (list (concat "--cpu=" (car parts))
                     (concat "--os=" (or (cadr parts) +pascal-host-os))))))))

(defun +pascal--fpc-args ()
  "The fpc flags this project is set to, plus the ones every build wants.
-Mobjfpc is Object Pascal rather than Turbo Pascal, -Sh long strings,
-gw3 the DWARF a debugger can read, -vb full paths in the messages, -FE
and -FU put the binary and the units somewhere other than beside the
sources, and -Fu says where the project\='s own units are."
  (append
   ;; -Fu names where the units are: without src/ on it, fpc looks only
   ;; beside the program file and cannot find the project's own units.
   ;; -vb: an error in src/greeter.pas said greeter.pas, which the build
   ;; buffer looked for at the root and could not open.
   '("-Mobjfpc" "-Sh" "-gw3" "-vb" "-FEbin" "-FUlib" "-Fusrc" "-Fu." "-Fisrc")
   (when +pascal-target
     (let ((parts (split-string +pascal-target "-")))
       (list (concat "-P" (car parts))
             (concat "-T" (or (cadr parts) +pascal-host-os)))))))

;;;###autoload
(defun +pascal-build-command ()
  "What `SPC k b' runs in a Pascal project."
  (pcase (+pascal-project-kind)
    ('lazarus
     (string-join (append '("lazbuild") (+pascal--lazbuild-args)
                          (list (shell-quote-argument (+pascal--main-file))))
                  " "))
    ('fpc
     ;; fpc will not make -FE and -FU itself, and .gitignore keeps them
     ;; out of the repository, so a fresh clone has neither.
     (concat "mkdir -p bin lib && "
             (string-join (append '("fpc") (+pascal--fpc-args)
                                  (list (shell-quote-argument (+pascal--main-file))))
                          " ")))
    ('delphi
     (user-error "Delphi projects are read here, not built: build it in the IDE"))
    (_ (user-error "No Pascal project here"))))

;;;###autoload
(defun +pascal--program-candidates ()
  "Where the binary may be: in bin/, where this config's builds put it,
or beside the project file, where Lazarus does unless told otherwise."
  (let ((root (+pascal-root))
        (base (file-name-base (+pascal--main-file))))
    (list (expand-file-name (concat "bin/" base) root)
          (expand-file-name base root))))

(defun +pascal-program ()
  "The binary this project builds, the newer when both places hold one,
or nil when it has not been built."
  (car (sort (seq-filter (lambda (f) (and (file-exists-p f) (file-executable-p f)))
                         (+pascal--program-candidates))
             #'file-newer-than-file-p)))

;;;###autoload
(defun +pascal-run-command ()
  "What `SPC k r' runs in a Pascal project."
  (let ((program (or (+pascal-program)
                     (user-error "Nothing built yet: F7 first"))))
    (string-join (delq nil (list (shell-quote-argument program)
                                 (unless (or (null +pascal-run-args)
                                             (string-empty-p +pascal-run-args))
                                   +pascal-run-args)))
                 " ")))


;;
;;; The commands

(defun +pascal--compile (name command)
  "Run COMMAND in a compilation buffer called NAME, from the root."
  (+core-compile name command (+pascal-root)))

;;;###autoload
(defun +pascal/build ()
  "Build the project with what it is set to."
  (interactive)
  (let ((kind (+pascal-project-kind)))
    (when (eq kind 'lazarus)
      (unless (executable-find "lazbuild")
        (user-error "lazbuild is not installed: %s"
                    (if (featurep :system 'macos) "brew install --cask lazarus" "zypper in lazarus"))))
    (when (eq kind 'fpc)
      (unless (executable-find "fpc")
        (user-error "fpc is not installed: %s"
                    (if (featurep :system 'macos) "brew install fpc" "zypper in fpc fpc-src")))))
  (+pascal--compile "build" (+pascal-build-command)))

;;;###autoload
(defun +pascal/run ()
  "Run what the project builds, with the arguments it is set to."
  (interactive)
  (+pascal--compile "run pascal" (+pascal-run-command)))

;;;###autoload
(defun +pascal/run-with-args (args)
  "Run the program once with ARGS, without writing them down."
  (interactive (list (read-string "Arguments: " +pascal-run-args)))
  (let ((program (or (+pascal-program) (user-error "Nothing built yet: F7 first"))))
    (+pascal--compile "run pascal"
                      (string-join (delq nil (list (shell-quote-argument program)
                                                   (unless (string-empty-p args) args)))
                                   " "))))

;;;###autoload
(defun +pascal/build-and-run ()
  "Build, and run it when the build worked."
  (interactive)
  ;; Which binary is known once the build is done: the newer of the two
  ;; places, as `+pascal-program' picks; bin/ was assumed, and a Lazarus
  ;; project that builds beside its file found nothing there.
  (pcase-let ((`(,bin ,beside) (mapcar #'shell-quote-argument (+pascal--program-candidates))))
    (+pascal--compile "build"
                      (concat (+pascal-build-command)
                              (format " && p=%s && { [ %s -nt %s ] || p=%s; } && \"$p\""
                                      bin bin beside beside)
                              (if (or (null +pascal-run-args) (string-empty-p +pascal-run-args))
                                  ""
                                (concat " " +pascal-run-args))))))

;;;###autoload
(defun +pascal-tests-file ()
  "The tests' program, tests/tests.lpr, or nil when the project has none."
  (let ((file (expand-file-name "tests/tests.lpr" (+pascal-root))))
    (and (file-exists-p file) file)))

;;;###autoload
(defun +pascal-test-command ()
  "What `SPC k t' runs in a Free Pascal project: build the tests, run them.
They are built with the program's own flags, so the units the build
already compiled into lib/ are not compiled again."
  (unless (eq (+pascal-project-kind) 'fpc)
    (user-error "SPC k t builds a Free Pascal project's tests; build a Lazarus one's in the IDE"))
  (let ((tests (or (+pascal-tests-file)
                   (user-error "No tests here: SPC k t builds tests/tests.lpr"))))
    (concat "mkdir -p bin lib && "
            (string-join (append '("fpc") (+pascal--fpc-args) '("-Futests")
                                 (list (shell-quote-argument tests)))
                         " ")
            " && "
            (shell-quote-argument
             (expand-file-name (concat "bin/" (file-name-base tests)) (+pascal-root)))
            " --all --format=plain")))

;;;###autoload
(defun +pascal/test ()
  "Build the tests and run them all."
  (interactive)
  (+pascal--compile "test" (+pascal-test-command)))

;;;###autoload
(defun +pascal/clean ()
  "Remove what the build made."
  (interactive)
  (let ((root (+pascal-root)))
    (+pascal--compile
     "clean"
     ;; A Lazarus project too: lazbuild has no clean, and --build-all,
     ;; what ran here, builds everything again.
     (format "rm -rf %s %s"
             (shell-quote-argument (expand-file-name "lib" root))
             (shell-quote-argument (expand-file-name "bin" root))))))

;;;###autoload
(defun +pascal/debug ()
  "Debug what this project builds, given the run arguments: with gdb, or
lldb-dap on a Mac, `+core-os-debugger'."
  (interactive)
  (unless (fboundp 'dape)
    (user-error "dape is not here to debug with"))
  (require 'dape)
  (let ((program (or (+pascal-program) (user-error "Nothing built yet: F7 first"))))
    ;; dape takes the configuration itself, not its name: handed
    ;; (gdb-pascal :program ...) it read every key as a value, found no
    ;; command, and no session started.
    (dape (dape--config-eval
           'gdb-pascal
           (append (let ((debugger (+core-os-debugger)))
                     ;; The program's body is PASCALMAIN; main is the
                     ;; RTL's start, where lldb would stop instead. The
                     ;; first of a key in these options is the one kept.
                     (if (equal (plist-get debugger :type) "lldb-dap")
                         (append '(:preRunCommands ["breakpoint set --name PASCALMAIN --one-shot true"])
                                 debugger)
                       debugger))
                   (list :program program
                         :cwd (+pascal-root)
                         :args (vconcat (split-string-shell-command
                                         (or +pascal-run-args "")))))))))

;;;###autoload
(defun +pascal/open-project-file ()
  "Open the .lpi, .lpr or .dproj this project is built from."
  (interactive)
  (find-file (+pascal--main-file)))


;;
;;; Setting what a build depends on

(defun +pascal--build-modes ()
  "The build modes the .lpi names."
  (when-let* ((lpi (car (+pascal--files (+pascal-root) "\\.lpi\\'"))))
    (with-temp-buffer
      (insert-file-contents lpi)
      (let ((modes nil))
        (goto-char (point-min))
        ;; <Item1 Name="Debug" .../> inside <BuildModes>, the shape
        ;; Lazarus has written since 1.x.
        (while (re-search-forward "<Item[0-9]*[^>]*Name=\"\\([^\"]+\\)\"" nil t)
          (push (match-string 1) modes))
        (nreverse (delete-dups modes))))))

;;;###autoload
(defun +pascal/set-build-mode (mode)
  "Build with MODE from now on, kept in .dir-locals.el."
  (interactive
   (list (completing-read "Build mode (empty for the project's default): "
                          (+pascal--build-modes) nil nil nil nil
                          (or +pascal-build-mode ""))))
  (let ((value (unless (string-empty-p mode) mode)))
    (+core-dir-locals-set (+pascal-root) '+pascal-build-mode value)
    (setq-local +pascal-build-mode value)
    (message "%s" (if value (format "Build mode %s" value)
                    "The project's own build mode"))))

;;;###autoload
(defun +pascal/set-widgetset (widgetset)
  "Build the LCL against WIDGETSET.  Empty leaves it to the project."
  (interactive
   (list (completing-read "Widget set: " '("gtk2" "gtk3" "qt5" "qt6" "cocoa" "")
                          nil nil nil nil (or +pascal-widgetset ""))))
  (let ((value (unless (string-empty-p widgetset) widgetset)))
    (+core-dir-locals-set (+pascal-root) '+pascal-widgetset value)
    (setq-local +pascal-widgetset value)
    (message "%s" (if value (format "Against %s" value) "The project's widget set"))))

;;;###autoload
(defun +pascal/set-target (target)
  "Build for TARGET, written CPU-OS.  Empty means this machine."
  (interactive
   (list (completing-read "Target (empty for this machine): "
                          '("x86_64-linux" "i386-linux" "aarch64-linux"
                            "arm-linux" "arm-embedded" "x86_64-win64"
                            "aarch64-darwin" "x86_64-darwin")
                          nil nil nil nil (or +pascal-target ""))))
  (let ((value (unless (string-empty-p target) target)))
    (+core-dir-locals-set (+pascal-root) '+pascal-target value)
    (setq-local +pascal-target value)
    (message "%s" (if value (format "Building for %s" value)
                    "Building for this machine"))))

;;;###autoload
(defun +pascal/set-run-args (args)
  "Keep ARGS for the program, so SPC k r passes them every time."
  (interactive (list (read-string "Arguments: " +pascal-run-args)))
  (let ((value (unless (string-empty-p args) args)))
    (+core-dir-locals-set (+pascal-root) '+pascal-run-args value)
    (setq-local +pascal-run-args value)
    (message "%s" (if value (format "Arguments: %s" value) "No arguments"))))

;;;###autoload
(defun +pascal/set-main (file)
  "Build FILE from now on, for a project that holds more than one program."
  (interactive
   (list (completing-read "Build which: "
                          (mapcar (lambda (f) (file-relative-name f (+pascal-root)))
                                  (append (+pascal--files (+pascal-root) "\\.lpi\\'")
                                          (+pascal--files (+pascal-root) "\\.lpr\\'")
                                          (+pascal--files (+pascal-root) "\\.dpr\\'")))
                          nil nil nil nil (or +pascal-main ""))))
  (let ((value (unless (string-empty-p file) file)))
    (+core-dir-locals-set (+pascal-root) '+pascal-main value)
    (setq-local +pascal-main value)
    (message "%s" (if value (format "Building %s" value) "The only one there is"))))


;;
;;; What it all adds up to

;;;###autoload
(defun +pascal-summary ()
  "One line saying what a build here depends on, for the panel."
  (pcase (+pascal-project-kind)
    ('nil "not a Pascal project")
    ('delphi "Delphi project: read and edited here, built in the IDE")
    (kind
     (string-join
      (delq nil
            (list (format "%s" kind)
                  (when +pascal-build-mode (format "mode %s" +pascal-build-mode))
                  (when +pascal-widgetset (format "widgetset %s" +pascal-widgetset))
                  (when +pascal-target (format "target %s" +pascal-target))
                  (when +pascal-main (format "main %s" +pascal-main))
                  (when +pascal-run-args (format "args %s" +pascal-run-args))))
      ", "))))

;;;###autoload
(defun +pascal/project-status ()
  "Say what is set up here and what is missing."
  (interactive)
  (message
   "%s"
   (string-join
    (delq nil
          (list (format "fpc:       %s" (or (executable-find "fpc") "MISSING"))
                (format "lazbuild:  %s" (or (executable-find "lazbuild") "MISSING"))
                (format "pasls:     %s"
                        (or (executable-find "pasls")
                            "MISSING (see the module README)"))
                (format "gdb:       %s" (or (executable-find "gdb") "MISSING"))
                (when (+pascal-project-p)
                  (format "this one:  %s" (+pascal-summary)))
                (when (+pascal-project-p)
                  (format "built:     %s"
                          (or (+pascal-program) "nothing yet")))))
    "\n")))
