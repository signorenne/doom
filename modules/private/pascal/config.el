;;; private/pascal/config.el -*- lexical-binding: t; -*-
;;
;; Object Pascal. Free Pascal and Lazarus build, run and debug here;
;; Delphi sources are read and edited here and built in the IDE, which
;; is the honest limit of a Linux machine. Emacs ships the mode, so this
;; module is the project side: what a build depends on, the keys, the
;; server and the templates.

(defvar +pascal-docs
  '(:groups (("pascal" "Pascal" (opascal) opascal-mode-map))
    :sections ((opascal-mode . "Pascal")))
  "How the cheat sheet documents this module; see `+docs--module-docs'.")

(defvar +pascal-templates-dir
  (file-name-concat doom-user-dir "templates/pascal/")
  "Project templates, one directory per kind: console, lcl.")

(defvar +pascal-modes '(opascal-mode)
  "The modes an Object Pascal file opens in.")

(defvar +pascal-lazarus-dir
  (seq-find #'file-directory-p
            '("/usr/lib64/lazarus" "/usr/lib/lazarus" "/usr/share/lazarus"))
  "Where Lazarus keeps its sources, which CodeTools reads.
openSUSE puts them under lib64; another distribution will not.")

(defvar +pascal-fpc-src-dir
  (seq-find #'file-directory-p
            '("/usr/share/fpcsrc" "/usr/lib64/fpc/src" "/usr/share/fpc/src"))
  "Where Free Pascal keeps its own sources, so the RTL resolves.")

(declare-function +core-register-builder "build")
(declare-function projection-type "projection-types")


;;
;;; The files

;; opascal-mode is Emacs's own, and it is Delphi's dialect: the same one
;; Free Pascal writes in {$MODE OBJFPC}. .pp is Free Pascal's unit
;; suffix, .lpr and .dpr the program files, .inc an included fragment.
(add-to-list 'auto-mode-alist
             '("\\.\\(pas\\|pp\\|lpr\\|dpr\\|dpk\\|inc\\)\\'" . opascal-mode))

;; A form is not code: .lfm and .dfm are a property list Lazarus and
;; Delphi write, and reading them as Pascal colours the wrong words.
;; conf-mode knows the shape and leaves the rest alone.
(add-to-list 'auto-mode-alist '("\\.\\(lfm\\|dfm\\)\\'" . conf-mode))

(after! opascal
  ;; Two spaces, which is what Lazarus and Delphi both write. The tab
  ;; key is Emacs's own `tab-always-indent' now; opascal's setting for
  ;; it has been obsolete since 24.4.
  (setq opascal-indent-level 2
        opascal-compound-block-indent 2
        opascal-case-label-indent 2))


;;
;;; The build

;; projection has no Pascal type, so here are two: a Lazarus project is
;; the .lpi and lazbuild, a Free Pascal one the program file and fpc.
;; SPC k b and SPC k r then work here as they do in a CMake tree.
(after! projection-types
  (defvar projection-project-type-lazarus
    (projection-type
     :name 'lazarus
     :predicate (lambda () (eq (+pascal-project-kind default-directory) 'lazarus))
     :build #'+pascal-build-command
     :run   #'+pascal/run
     :src-dir "src")
    "projection type for Lazarus projects, built with lazbuild.")

  (defvar projection-project-type-fpc
    (projection-type
     :name 'fpc
     :predicate (lambda () (eq (+pascal-project-kind default-directory) 'fpc))
     :build #'+pascal-build-command
     :run   #'+pascal/run
     :test  #'+pascal/test
     :src-dir "src")
    "projection type for Free Pascal projects, built with fpc.")

  (setq projection-project-types
        (append (list projection-project-type-lazarus
                      projection-project-type-fpc)
                (seq-remove (lambda (type) (memq (oref type name) '(lazarus fpc)))
                            projection-project-types))))

;; SPC k r, SPC k d, SPC k m and SPC k n in a Pascal project are this
;; module's. A Delphi project is claimed too: the panel and the status
;; then say what can and cannot be done with it here, which is better
;; than the keys quietly meaning the C++ module.
(+core-register-builder 'pascal #'+pascal-project-p
                        :run #'+pascal/run
                        :debug #'+pascal/debug
                        :panel #'+pascal/menu
                        :new #'+pascal/new-project
                        :label "Pascal: Free Pascal and Lazarus")


;;
;;; The server

;; pasls is Lazarus's CodeTools behind an LSP server. It is not
;; packaged: the README says how to build it, and until it is there a
;; Pascal buffer has the mode's own navigation and nothing more.
(declare-function +pascal-project-kind "pascal")

;; pasls reads a Lazarus project's unit paths from its .lpi, but not the
;; include path the LCL's own package sets: every LCL unit it opened then
;; failed on lcl_defines.inc, and nothing of the LCL, TForm among it,
;; could be looked up. A Lazarus project hands it that directory.
(defun +pascal--pasls-contact (&rest _)
  "How to start pasls for this buffer's project, or nil without pasls."
  (when-let* ((pasls (executable-find "pasls")))
    (let ((include (and +pascal-lazarus-dir
                        (eq (ignore-errors (+pascal-project-kind)) 'lazarus)
                        (expand-file-name "lcl/include" +pascal-lazarus-dir))))
      (if (and include (file-directory-p include))
          (list pasls :initializationOptions
                (list :fpcOptions (vector (concat "-Fi" include))))
        (list pasls)))))

(when (modulep! :tools lsp)
  (after! eglot
    (add-to-list 'eglot-server-programs '(opascal-mode . +pascal--pasls-contact))
    ;; CodeTools needs to know where the compiler and its sources are,
    ;; the way the Lazarus IDE tells it. pasls reads the environment for
    ;; this, so the variables are set rather than only sent.
    (when +pascal-fpc-src-dir (setenv "FPCDIR" +pascal-fpc-src-dir))
    (when +pascal-lazarus-dir (setenv "LAZARUSDIR" +pascal-lazarus-dir))
    (when-let* ((fpc (executable-find "fpc"))) (setenv "PP" fpc))
    (setq-default
     eglot-workspace-configuration
     (append
      (bound-and-true-p eglot-workspace-configuration)
      `((:pasls . (:fpcDir ,(or +pascal-fpc-src-dir "")
                   :pp ,(or (executable-find "fpc") "")
                   :lazarusDir ,(or +pascal-lazarus-dir "")))))))

  ;; Started the way Doom starts every other server: on the local
  ;; variables hook, so a .dir-locals.el that names another pasls is
  ;; read before the server is chosen. Nothing happens when pasls is
  ;; not installed, rather than an error on every Pascal file.
  (add-hook! 'opascal-mode-local-vars-hook
    (defun +pascal--lsp-h ()
      "Start the Pascal server when there is one to start."
      (when (executable-find "pasls") (lsp!)))))


;;
;;; Debugging

;; FPC writes DWARF when asked (-gw3, which the build carries), so gdb
;; reads a Pascal binary as it reads a C++ one.
(after! dape
  (add-to-list 'dape-configs
               `(gdb-pascal
                 modes ,+pascal-modes
                 ensure dape-ensure-command
                 command "gdb"
                 command-args ("--interpreter=dap")
                 :type "gdb"
                 :request "launch"
                 :program +pascal-program
                 :cwd +pascal-root
                 :stopAtBeginningOfMainSubprogram t)))


;;
;;; Keybindings

;; The build keys are SPC k, shared. These are the ones only Pascal has.
(map! :after opascal
      :map opascal-mode-map
      :localleader
      (:prefix ("k" . "pascal")
       :desc "Build, then run"      "x" #'+pascal/build-and-run
       :desc "Clean"                "C" #'+pascal/clean
       :desc "Build mode"           "y" #'+pascal/set-build-mode
       :desc "Widget set"           "w" #'+pascal/set-widgetset
       :desc "Which program"        "s" #'+pascal/set-main
       :desc "Project status"       "I" #'+pascal/project-status
       :desc "The project file"     "v" #'+pascal/open-project-file))
