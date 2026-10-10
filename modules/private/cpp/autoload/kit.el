;;; private/cpp/autoload/kit.el -*- lexical-binding: t; -*-
;;
;; The kit: which build directory a CMake project builds in, and where the
;; commands that touch it run. Read from what is on disk, the way Qt
;; Creator's Projects mode would show it:
;;
;;   build/*/CMakeCache.txt      compiler, toolchain, generator, build type
;;   CMakeLists.txt.user         Qt Creator's targets, configurations, runs
;;   Qt Creator's settings       the kits: tool set, environment, device
;;   CMakePresets.json           presets, with their binaryDir
;;   .dir-locals.el              kits written down by `+cpp/write-dir-locals'
;;
;; A compiler that is not on the host lives in a distrobox, and the SDK it
;; belongs to has an environment script next to its sysroots; where a
;; kit runs, and how a command runs there, is container.el; Qt Creator
;; is read in qtc.el. The choice is remembered in .dir-locals.el as
;; `+cpp-kit'.

(require 'cl-lib)

(defvar +cpp-kit)
(defvar +cpp-container)
(declare-function +cpp--setting "project")
(declare-function +cpp--kind-p "project")
(defvar projection-cmake-build-directory)
(defvar projection-cmake-configure-options)
(defvar projection-cmake-preset)
(declare-function projection-cache-clear-all "projection-core-cache")
(declare-function +core-dir-locals-read "lib")
(declare-function +core-dir-locals-set "lib")
(declare-function +cpp--cache-override-args "cmake")
(declare-function +cpp--preset-binary-dir "cmake")
(declare-function +cpp--preset-cache-variable "cmake")
(declare-function +cpp--target-names "run")
(declare-function +container-for "container")
(defvar +container-may-start)
(declare-function +cpp--env-script-for "container")
(declare-function +cpp--kit-shell "container")
(declare-function +cpp--forget-containers "container")
(declare-function +qtcreator-configurations "qtcreator")
(declare-function +qtcreator-active "qtcreator")
(declare-function +qtcreator-forget "qtcreator")
(declare-function +cpp--sdk-root "container")
(declare-function +cpp--new-configuration-command "build-type")
(declare-function +cpp--kit-type "build-type")
(defvar +cpp-kits)


;;
;;; What a kit is

;;;###autoload
(cl-defstruct (+cpp-kit (:constructor +cpp-kit-make))
  name                                  ; "horizon-pc-Debug", or a preset name
  dir                                   ; build directory, relative to the root
  source                                ; how it was chosen: `chosen', `qtcreator', `preset', `directory', `default'
  preset                                ; the configure preset it is, or nil
  build-type generator compiler toolchain sysroot qt
  configured                            ; CMakeCache.txt exists
  args                                  ; -D arguments its configure takes, from Qt Creator
  container                             ; distrobox holding the compiler, or nil
  env-script                            ; SDK environment script to source, or nil
  env                                   ; Qt Creator's environment, NAME=VALUE lines, or nil
  targets                               ; what its build step makes, ("all" "fdc.hpkg"), or nil
  run                                   ; its run configuration, (:target :args :dir :remote), or nil
  configs                               ; the configurations of a multi-config generator, or nil
  qtc)                                  ; the Qt Creator kit behind it, a plist, or nil

;;;###autoload
(defun +cpp-kit-abs-dir (kit &optional root)
  "The build directory of KIT as an absolute path under ROOT."
  (expand-file-name (+cpp-kit-dir kit) (or root (+core-project-root))))

;;;###autoload
(defun +cpp-kit-where (kit)
  "Where KIT's commands run, in words."
  (if-let* ((container (+cpp-kit-container kit)))
      (format "in %s" container)
    "on the host"))


;;
;;; Reading the disk

(defvar +cpp--cmake-caches (make-hash-table :test #'equal)
  "CMakeCache.txt path to (MTIME . ENTRIES): a cache is parsed once per
change, not once per question, and the menus ask many times a redraw.")

;; Autoloaded: called from cmake.el.
;;;###autoload
(defun +cpp--cmake-cache (file)
  "Every entry of CMakeCache.txt FILE as (NAME TYPE VALUE), or nil when
there is no such file.  Read again only when the file changed."
  (when-let* ((mtime (file-attribute-modification-time (file-attributes file))))
    (let ((hit (gethash file +cpp--cmake-caches)))
      (if (and hit (equal (car hit) mtime))
          (cdr hit)
        (let ((entries
               (with-temp-buffer
                 (insert-file-contents file)
                 (goto-char (point-min))
                 (let (entries)
                   (while (re-search-forward
                           "^\\([A-Za-z_][A-Za-z0-9_-]*\\):\\([A-Z]+\\)=\\(.*\\)$" nil t)
                     (push (list (match-string 1) (match-string 2) (match-string 3))
                           entries))
                   (nreverse entries)))))
          (puthash file (cons mtime entries) +cpp--cmake-caches)
          entries)))))

(defun +cpp--cache-values (file names)
  "The values of cache variables NAMES in CMakeCache.txt FILE, as an
alist; an empty or NOTFOUND value counts as unset."
  (cl-loop for (name _type value) in (+cpp--cmake-cache file)
           when (and (member name names)
                     (not (string-empty-p value))
                     (not (string-suffix-p "-NOTFOUND" value)))
           collect (cons name value)))

;; Autoloaded: build-type.el weighs a kit's cache against a planned
;; kit's arguments with these.
;;;###autoload
(defun +cpp--arg-cell (arg)
  "What -D argument ARG sets, as (NAME . VALUE): -DCMAKE_SYSROOT:PATH=/x
gives (\"CMAKE_SYSROOT\" . \"/x\").  Nil for anything else."
  (and (string-match "\\`-D\\([^:=]+\\)\\(?::[^=]*\\)?=\\(.*\\)\\'" arg)
       (cons (match-string 1 arg) (match-string 2 arg))))

;;;###autoload
(defun +cpp--arg-value (args name)
  "What the -D arguments ARGS set variable NAME to, or nil."
  (seq-some (lambda (arg)
              (let ((cell (+cpp--arg-cell arg)))
                (and (equal (car cell) name) (cdr cell))))
            args))

(defun +cpp--kit-from-directory (root dir &optional configurations)
  "A kit for build directory DIR (absolute) of ROOT, from its cache, and
from the Qt Creator configuration among CONFIGURATIONS that builds
there, when one does: its environment, build targets, run
configuration, container and kit come along.  Two targets building in
the same directory, the SDK kit and the PC kit both, are told apart by
the SDK the cache names."
  (let* ((cache (expand-file-name "CMakeCache.txt" dir))
         (values (+cpp--cache-values
                  cache '("CMAKE_BUILD_TYPE" "CMAKE_GENERATOR" "CMAKE_CXX_COMPILER"
                          "CMAKE_C_COMPILER" "CMAKE_TOOLCHAIN_FILE" "CMAKE_SYSROOT"
                          "CMAKE_CONFIGURATION_TYPES" "Qt6_DIR" "Qt5_DIR")))
         (get (lambda (name) (alist-get name values nil nil #'equal)))
         (sdk (+cpp--sdk-root (or (funcall get "CMAKE_TOOLCHAIN_FILE") (funcall get "CMAKE_CXX_COMPILER"))))
         (here (seq-filter (lambda (conf) (file-equal-p (plist-get conf :dir) dir)) configurations))
         (conf (or (seq-find (lambda (conf)
                               (let ((kit (plist-get conf :kit)))
                                 (and kit sdk (equal (+cpp--sdk-root (or (plist-get kit :sysroot) (plist-get kit :cxx))) sdk))))
                             here)
                   (car here)))
         (kit (plist-get conf :kit)))
    (+cpp-kit-make
     :name (file-name-nondirectory (directory-file-name dir))
     :dir (file-relative-name dir root)
     :source 'directory
     :build-type (funcall get "CMAKE_BUILD_TYPE")
     :generator (funcall get "CMAKE_GENERATOR")
     :compiler (or (funcall get "CMAKE_CXX_COMPILER") (funcall get "CMAKE_C_COMPILER"))
     :toolchain (funcall get "CMAKE_TOOLCHAIN_FILE")
     :sysroot (funcall get "CMAKE_SYSROOT")
     :qt (or (funcall get "Qt6_DIR") (funcall get "Qt5_DIR"))
     :configs (let ((types (funcall get "CMAKE_CONFIGURATION_TYPES")))
                (and types (split-string types ";" t)))
     :args (plist-get conf :args)
     :env (plist-get kit :env)
     :targets (plist-get conf :targets)
     :run (plist-get conf :run)
     :container (plist-get kit :container)
     :qtc kit
     :configured t)))

(defun +cpp--kit-from-configuration (root conf)
  "A kit for CONF, a Qt Creator configuration of ROOT that was never
built: what its kit's settings say, when they are here, the arguments
say the rest."
  (let ((kit (plist-get conf :kit))
        (args (plist-get conf :args)))
    (+cpp-kit-make
     :name (plist-get conf :name)
     :dir (file-relative-name (plist-get conf :dir) root)
     :source 'qtcreator
     :build-type (plist-get conf :type)
     :generator (or (plist-get conf :generator) (plist-get kit :generator))
     :compiler (or (plist-get kit :cxx) (+cpp--arg-value args "CMAKE_CXX_COMPILER"))
     :toolchain (+cpp--arg-value args "CMAKE_TOOLCHAIN_FILE")
     :sysroot (or (+cpp--arg-value args "CMAKE_SYSROOT") (plist-get kit :sysroot))
     :qt (plist-get kit :qmake)
     :configs (and (plist-get conf :generator)
                   (string-match-p "Multi-Config" (plist-get conf :generator))
                   '("Debug" "Release" "RelWithDebInfo" "MinSizeRel"))
     :args args
     :env (plist-get kit :env)
     :targets (plist-get conf :targets)
     :run (plist-get conf :run)
     :container (plist-get kit :container)
     :qtc kit
     :configured nil)))

(defconst +cpp--declared-slots
  '((:type . build-type) (:generator . generator) (:compiler . compiler)
    (:toolchain . toolchain) (:sysroot . sysroot) (:qt . qt) (:args . args)
    (:env . env) (:targets . targets) (:run . run) (:configs . configs)
    (:container . container) (:env-script . env-script))
  "What a kit written in .dir-locals.el may say, keyword to slot.")

(defun +cpp--declared-kits (root kits)
  "KITS with the project's `+cpp-kits' folded in: a declared kit that is
among KITS by name or directory fills the slots the disk left empty,
one that is not becomes a kit of its own, configured when its cache
is there.  The declaration is what `+cpp/write-dir-locals' wrote, or
what was typed in its place."
  (let ((declared (+cpp--setting '+cpp-kits)))
    (if (not (listp declared))
        kits
      (let ((kits (copy-sequence kits)))
        (dolist (spec declared)
          (when (and (listp spec) (stringp (plist-get spec :name)))
            (let* ((name (plist-get spec :name))
                   (dir (or (plist-get spec :dir) name))
                   (kit (or (seq-find (lambda (k) (equal (+cpp-kit-name k) name)) kits)
                            (seq-find (lambda (k) (file-equal-p (+cpp-kit-abs-dir k root)
                                                                (expand-file-name dir root)))
                                      kits))))
              (unless kit
                (setq kit (+cpp-kit-make :name name :dir dir :source 'declared
                                         :configured (file-exists-p
                                                      (expand-file-name "CMakeCache.txt"
                                                                        (expand-file-name dir root)))))
                (setq kits (append kits (list kit))))
              (pcase-dolist (`(,key . ,slot) +cpp--declared-slots)
                (when (and (plist-member spec key)
                           (null (cl-struct-slot-value '+cpp-kit slot kit)))
                  (setf (cl-struct-slot-value '+cpp-kit slot kit) (plist-get spec key)))))))
        kits))))

(defun +cpp--cache-home (dir)
  "The source directory the CMakeCache.txt in DIR was written for, or nil."
  (let ((cache (expand-file-name "CMakeCache.txt" dir)))
    (when (file-exists-p cache)
      (alist-get "CMAKE_HOME_DIRECTORY"
                 (+cpp--cache-values cache '("CMAKE_HOME_DIRECTORY"))
                 nil nil #'equal))))

(defun +cpp--candidate-directories (root)
  "Where a build directory of ROOT may be, absolute, from the listing
alone: build and anything under it, build-* and cmake-build-* in the
root, build-* beside the project.  Qt Creator configures into
build/<kit>-<type>, CLion into cmake-build-<type>, other tools into
build, a build type each, or beside the project."
  (cl-flet ((listing (dir match) (and (file-directory-p dir)
                                      (directory-files dir t match))))
    (append (list (expand-file-name "build" root))
            (listing (expand-file-name "build" root) "\\`[^.]")
            (listing root "\\`\\(?:cmake-\\)?build-")
            (listing (file-name-directory (directory-file-name root))
                     "\\`build-"))))

(defun +cpp--configured-directories (root)
  "Configured build directories of ROOT, absolute, newest cache first.
A cache written for another source tree is not this project's: a
sibling project's build-* beside this one, or a build made before the
project was moved (see `+cpp--stale-directories')."
  (thread-last (+cpp--candidate-directories root)
               (seq-filter (lambda (d)
                             (when-let* ((home (+cpp--cache-home d)))
                               (file-equal-p home root))))
               (seq-sort-by (lambda (d)
                              (float-time (file-attribute-modification-time
                                           (file-attributes
                                            (expand-file-name "CMakeCache.txt" d)))))
                            #'>)))

;;;###autoload
(defun +cpp--stale-directories (root)
  "Build directories under ROOT whose cache names another source tree:
the project was moved since they were configured.  CMake refuses to
build them; a configure from scratch (SPC k m F) puts them right."
  (let ((build (expand-file-name "build" root)))
    (seq-filter (lambda (d)
                  (when-let* ((home (+cpp--cache-home d)))
                    (not (file-equal-p home root))))
                (append (list build)
                        (and (file-directory-p build)
                             (directory-files build t "\\`[^.]"))))))

;;;###autoload
(defun +cpp--configured-build-dirs ()
  "Configured build directories of this project, relative to the root."
  (when-let* ((root (+core-project-root 'noerror)))
    (mapcar (lambda (d) (file-relative-name d root))
            (+cpp--configured-directories root))))


;;
;;; Presets as kits

(defun +cpp--preset-kits (root)
  "One kit per configure preset of ROOT that has a binaryDir."
  (when-let* ((presets (+cpp--projection-presets root)))
    (let ((default-directory root))
      (cl-loop for preset in presets
               for name = (alist-get 'name preset)
               for hidden = (alist-get 'hidden preset)
               for dir = (and name (not (eq hidden t))
                              (ignore-errors (+cpp--preset-binary-dir name)))
               when dir
               collect (let* ((abs (expand-file-name dir root))
                              (cache (expand-file-name "CMakeCache.txt" abs)))
                         (if (file-exists-p cache)
                             (let ((kit (+cpp--kit-from-directory root abs)))
                               (setf (+cpp-kit-name kit) name
                                     (+cpp-kit-source kit) 'preset
                                     (+cpp-kit-preset kit) name)
                               kit)
                           (+cpp-kit-make :name name :dir dir :source 'preset
                                          :preset name
                                          :build-type (let ((value (+cpp--preset-cache-variable
                                                                    preset presets "CMAKE_BUILD_TYPE")))
                                                        (if (consp value) (alist-get 'value value) value))
                                          :generator (alist-get 'generator preset))))))))


;;;###autoload
(defun +cpp-preset-names (&optional root)
  "The configure presets of the project at ROOT that can be chosen, by
name and in file order, hidden ones left out; nil without presets.  For
other modules: the ai module names the first one in a new CLAUDE.md."
  (when-let* ((root (or root (+core-project-root 'noerror)))
              (presets (+cpp--projection-presets root)))
    (cl-loop for preset in presets
             for name = (alist-get 'name preset)
             unless (or (null name) (eq (alist-get 'hidden preset) t))
             collect name)))


;;
;;; Where a kit runs, asked of container.el

;; Autoloaded: build-type.el locates a planned kit before configuring it.
;;;###autoload
(defun +cpp--kit-locate (kit)
  "Fill in where KIT runs: the container, and the environment script.
The project's `+cpp-container' wins over detection when it is set.  A
kit with no compiler yet, one planned by Qt Creator, is placed by its
toolchain file."
  (unless (+cpp-kit-container kit)
    (setf (+cpp-kit-container kit)
          (or (+cpp--setting '+cpp-container)
              (plist-get (+cpp-kit-qtc kit) :container)
              (+container-for (or (+cpp-kit-compiler kit) (+cpp-kit-toolchain kit))))))
  ;; Qt Creator's environment, when the kit has it, replaces the script.
  (unless (or (+cpp-kit-env kit) (+cpp-kit-env-script kit))
    (setf (+cpp-kit-env-script kit)
          (+cpp--env-script-for (+cpp-kit-container kit)
                                (or (+cpp-kit-toolchain kit) (+cpp-kit-compiler kit)))))
  kit)


;;
;;; All the kits of a project, and the one in use

(defvar +cpp--kits-cache (make-hash-table :test #'equal)
  "Project root to (STAMP . KITS); STAMP is what the answer depends on.")

(defvar +cpp--kit-cache (make-hash-table :test #'equal)
  "Project root to (STAMP . KIT), the kit in use, located.  Every header,
menu predicate and finish hook asks for it, so it is computed once per
change of the disk rather than once per keypress.")

;;;###autoload
(defun +cpp/forget-kits ()
  "Read the kits again from the disk on the next command, and drop what
projection cached for the project.  The caches follow the files by
themselves; this is for what they cannot see, a container started or
an SDK installed since."
  (interactive)
  (clrhash +cpp--kits-cache)
  (clrhash +cpp--kit-cache)
  (clrhash +cpp--warned-roots)
  (+cpp--forget-containers)
  (when (fboundp '+qtcreator-forget) (+qtcreator-forget))
  (when-let* ((project (and (featurep 'projection)
                            (+cpp--projection-project 'no-error))))
    (projection-cache-clear-all project))
  (message "Kits forgotten; the next command reads the disk again"))

(defun +cpp--kits-stamp (root)
  "Modification times of everything the kit list is read from: the
cache of every directory that may hold one, and the four files.  Stats
only, no file is read, since this runs on every question."
  (mapcar (lambda (file)
            (cons file (file-attribute-modification-time (file-attributes file))))
          (append (mapcar (lambda (d) (expand-file-name "CMakeCache.txt" d))
                          (+cpp--candidate-directories root))
                  (list (expand-file-name "CMakeLists.txt.user" root)
                        (expand-file-name "CMakePresets.json" root)
                        (expand-file-name "CMakeUserPresets.json" root)
                        (expand-file-name ".dir-locals.el" root)))))

;;;###autoload
(defun +cpp--kits (&optional root)
  "Every kit of the project at ROOT, presets first, then configured
directories newest first.  Read again only when the disk changed."
  (when-let* ((root (or root (+core-project-root 'noerror))))
    (let* ((root (file-name-as-directory (expand-file-name root)))
           (stamp (+cpp--kits-stamp root))
           (cached (gethash root +cpp--kits-cache)))
      (if (and cached (equal (car cached) stamp))
          (cdr cached)
        (let* ((presets (+cpp--preset-kits root))
               (taken (mapcar (lambda (k) (+cpp-kit-abs-dir k root)) presets))
               (configurations (+qtcreator-configurations root))
               (dirs (cl-loop for d in (+cpp--configured-directories root)
                              unless (member (file-name-as-directory d)
                                             (mapcar #'file-name-as-directory taken))
                              collect (+cpp--kit-from-directory root d configurations)))
               ;; Qt Creator's configurations that were never built: no
               ;; cache yet, but a directory, a type, and the kit's tool
               ;; set when the settings are here, so they can be chosen
               ;; and configured from here.
               (planned (cl-loop for conf in configurations
                                 unless (or (plist-get conf :configured)
                                            (seq-some (lambda (k) (file-equal-p (+cpp-kit-abs-dir k root)
                                                                                (plist-get conf :dir)))
                                                      (append presets dirs)))
                                 collect (+cpp--kit-from-configuration root conf)))
               ;; Kits written down in .dir-locals.el, `+cpp-kits': the
               ;; project's own word, which fills in what the disk lacks.
               (kits (+cpp--declared-kits
                      root
                      (append presets dirs
                              (seq-uniq planned (lambda (a b) (equal (+cpp-kit-dir a) (+cpp-kit-dir b))))))))
          (puthash root (cons stamp kits) +cpp--kits-cache)
          kits)))))

(defun +cpp--kit-named (name kits)
  "The kit called NAME, or whose directory is NAME, among KITS."
  (or (seq-find (lambda (k) (equal (+cpp-kit-name k) name)) kits)
      (seq-find (lambda (k) (equal (directory-file-name (+cpp-kit-dir k))
                                   (directory-file-name name)))
                kits)))

(defun +cpp--chosen-kit-name (root)
  "The kit this project chose, from .dir-locals.el, or nil."
  (when-let* ((locals (+core-dir-locals-read root))
              (entry (assq nil locals)))
    (or (alist-get '+cpp-kit (cdr entry))
        (alist-get 'projection-cmake-build-directory (cdr entry)))))

;;;###autoload
(defun +cpp--kit (&optional root)
  "The kit in use for the project at ROOT, never nil for a CMake project.
In order: the one chosen for the project, Qt Creator's active
configuration when it is configured, the newest configured directory,
Qt Creator's active configuration all the same, the first kit, and last
a plain build directory on the host."
  (when-let* ((root (or root (+core-project-root 'noerror))))
    (let* ((root (file-name-as-directory (expand-file-name root)))
           (stamp (+cpp--kits-stamp root))
           (cached (gethash root +cpp--kit-cache)))
      (if (and cached (equal (car cached) stamp))
          (cdr cached)
        (let ((kit (+cpp--kit-locate (+cpp--choose-kit root))))
          ;; Found while no container may be started, as a file opens,
          ;; a compiler in a stopped one is not found: kept, that answer
          ;; sent the next build to the host, where it is not.
          (unless (and (boundp '+container-may-start)
                       (not +container-may-start)
                       (not (+cpp-kit-container kit)))
            (puthash root (cons stamp kit) +cpp--kit-cache))
          kit)))))

(defun +cpp--kit-cache-time (kit root)
  "When KIT's CMakeCache.txt under ROOT was last written, or 0."
  (if-let* ((attributes (file-attributes
                         (expand-file-name "CMakeCache.txt" (+cpp-kit-abs-dir kit root)))))
      (float-time (file-attribute-modification-time attributes))
    0))

(defvar +cpp--warned-roots (make-hash-table :test #'equal)
  "Roots told once that their chosen kit names nothing on disk.")

(defun +cpp--qtcreator-active-kit (root kits)
  "The kit among KITS that is Qt Creator's active configuration of ROOT,
or nil."
  (when-let* ((active (+qtcreator-active root))
              (dir (plist-get active :dir))
              (k (+cpp--kit-named (file-relative-name dir root) kits)))
    (let ((active (copy-+cpp-kit k)))
      (setf (+cpp-kit-source active) 'qtcreator)
      active)))

(defun +cpp--choose-kit (root)
  "The kit for ROOT, chosen as `+cpp--kit' describes, not yet located.
The kit owns the preset: a preset configured through Qt Creator, CMake
or Emacs is a kit like any directory, so the newest configured one
wins whatever wrote it, and projection is told which preset that is."
  (let* ((kits (+cpp--kits root))
         (kit (or (when-let* ((name (+cpp--chosen-kit-name root)))
                    (if-let* ((k (+cpp--kit-named name kits)))
                        (let ((chosen (copy-+cpp-kit k)))
                          (setf (+cpp-kit-source chosen) 'chosen)
                          chosen)
                      ;; Chosen but nothing on disk by that name: a fresh
                      ;; directory called so, and a word about it once.
                      ;; A stale directory is a cache for another path.
                      (unless (gethash root +cpp--warned-roots)
                        (puthash root t +cpp--warned-roots)
                        (if (seq-some (lambda (d) (file-equal-p d (expand-file-name name root)))
                                      (+cpp--stale-directories root))
                            (message "+cpp-kit %S was configured before the project moved; SPC k m F configures it fresh"
                                     name)
                          (message "+cpp-kit %S in .dir-locals.el is no preset or build directory here; SPC k K picks one, SPC k c configures it as named"
                                   name)))
                      (+cpp-kit-make :name name :dir name :source 'chosen)))
                  (when-let* ((k (+cpp--qtcreator-active-kit root kits))
                              ((+cpp-kit-configured k)))
                    k)
                  (when-let* ((configured (seq-filter #'+cpp-kit-configured kits)))
                    (car (seq-sort-by (lambda (k) (+cpp--kit-cache-time k root))
                                      #'> configured)))
                  ;; Nothing configured yet, a fresh checkout: the one
                  ;; Qt Creator would build.
                  (+cpp--qtcreator-active-kit root kits)
                  (car kits)
                  (+cpp-kit-make :name "build" :dir "build" :source 'default))))
    kit))

;;;###autoload
(defun +cpp--compile-commands-file (&optional kit root)
  "The compilation database of KIT (default the kit in use) at ROOT,
absolute, else the one another configured kit wrote, else nil.
The one answer to \"where is compile_commands.json\": the server is
pointed at it when it starts, the root link and the .clangd writer copy
it, clang-tidy and the assembly view read it."
  (when-let* ((root (or root (+core-project-root 'noerror)))
              (kit (or kit (+cpp--kit root))))
    (seq-find #'file-exists-p
              (mapcar (lambda (k)
                        (expand-file-name "compile_commands.json"
                                          (+cpp-kit-abs-dir k root)))
                      (cons kit
                            (seq-remove (lambda (k)
                                          (equal (+cpp-kit-dir k) (+cpp-kit-dir kit)))
                                        (+cpp--kits root)))))))

;;;###autoload
(defun +cpp--build-directory ()
  "Absolute build directory of this project, the kit's, or nil."
  (when-let* ((root (+core-project-root 'noerror)))
    (+cpp-kit-abs-dir (+cpp--kit root) root)))

;;;###autoload
(defun +cpp--kit-describe (kit)
  "KIT in one line: name, build type or configuration, the Qt Creator
kit behind it, where it runs, how it was chosen."
  (format "%s%s%s, %s%s"
          (+cpp-kit-name kit)
          (if-let* ((type (or (+cpp--kit-config kit) (+cpp-kit-build-type kit))))
              (format " (%s%s)" type (if (+cpp-kit-configs kit) ", of several" ""))
            "")
          (if-let* ((qtc (+cpp-kit-qtc kit))) (format " [%s]" (plist-get qtc :name)) "")
          (+cpp-kit-where kit)
          (pcase (+cpp-kit-source kit)
            ('qtcreator (if (+cpp-kit-configured kit)
                            ", Qt Creator's active configuration"
                          ", Qt Creator's configuration, not built yet"))
            ('chosen (if (+cpp-kit-configured kit)
                         ", chosen for this project"
                       ", chosen for this project, not configured yet"))
            ('directory (if (+cpp-kit-preset kit)
                            ", the newest configured preset"
                          ", the newest configured"))
            ('preset (if (+cpp-kit-configured kit)
                         ", the newest configured preset"
                       ", the first preset, not configured yet"))
            ('declared (if (+cpp-kit-configured kit)
                           ", written in .dir-locals.el"
                         ", written in .dir-locals.el, not configured yet"))
            ('default ", not configured yet")
            (_ ""))))


;;
;;; Running a command with a kit

;; Autoloaded: the expansion of +cpp--with-kit calls it from other files.
;;;###autoload
(defun +cpp--sync-projection (kit)
  "Make what projection remembers agree with KIT and the project settings:
the configure preset, and the default build target.  projection reads
its cache before its options, so a preset chosen in an earlier session
would otherwise be passed beside the kit's directory, and the target
would be the session's rather than the project's."
  (when-let* ((project (+cpp--projection-project 'no-error)))
    (dolist (pair (list (cons (+cpp--projection-preset-cache-var 'configure)
                              (+cpp-kit-preset kit))
                        (cons 'projection-cmake-build-target
                              (+cpp--setting '+cpp-build-target))))
      (unless (equal (+cpp--projection-cache-get project (car pair)) (cdr pair))
        (+cpp--projection-cache-put project (car pair) (cdr pair))))))

;;;###autoload
(defmacro +cpp--with-kit (kit &rest body)
  "Run BODY with projection pointed at KIT's build directory.
Everything projection derives, the compile and ctest commands, the file
API reply, the artifacts and the targets, then concerns that directory.
A configure passes the kit's preset, when it is one, and the cache
overrides of the project; build and test take the directory only."
  (declare (indent 1))
  (let ((k (make-symbol "kit")))
    ;; The defvars make the bindings dynamic in whichever file expands
    ;; this, loaded before projection or not.
    `(progn
       (defvar projection-cmake-build-directory)
       (defvar projection-cmake-preset)
       (defvar projection-cmake-configure-options)
       (defvar projection-cmake-ctest-options)
       (let* ((,k ,kit)
              ;; projection reads the presets from `default-directory'.
              (default-directory (+core-project-root 'noerror))
              (projection-cmake-build-directory
               (if ,k (+cpp-kit-dir ,k) projection-cmake-build-directory))
              (projection-cmake-preset
               (if (and ,k (+cpp-kit-preset ,k))
                   (list (cons 'configure (+cpp-kit-preset ,k)) (cons t nil))
                 'disable))
              (projection-cmake-configure-options
               (append projection-cmake-configure-options
                       (+cpp--cache-override-args)))
              ;; A multi-config generator: ctest needs the configuration.
              (projection-cmake-ctest-options
               (append projection-cmake-ctest-options
                       (when-let* ((config (and ,k (+cpp--kit-config ,k))))
                         (list "-C" config)))))
         (when ,k (+cpp--sync-projection ,k))
         ,@body))))

;;
;;; Choosing

;;;###autoload
(defun +cpp/set-kit (name)
  "Build this project with the kit called NAME, from now on.
Offers what the project has: presets, every configured build
directory and every configuration Qt Creator planned, with its build
type and where it runs; a stale directory, one configured before the
project moved, is offered as such, for SPC k m F to configure fresh.
Written to .dir-locals.el, so it holds across sessions; a name that is
not there yet becomes a fresh build directory on the host."
  (interactive
   (let* ((root (+core-project-root))
          (kits (+cpp--kits root))
          (current (+cpp-kit-name (+cpp--kit root)))
          (rows (append
                 (mapcar (lambda (k)
                           (+cpp--kit-locate k)
                           (cons (format "%-28s %-16s %s" (+cpp-kit-name k)
                                         (or (+cpp-kit-build-type k) "")
                                         (+cpp-kit-where k))
                                 (+cpp-kit-name k)))
                         kits)
                 (mapcar (lambda (d)
                           (let ((name (file-relative-name d root)))
                             (cons (format "%-28s %-16s %s" name ""
                                           "stale: configured before the project moved")
                                   name)))
                         (+cpp--stale-directories root))))
          (choice (completing-read "Kit: " rows nil nil nil nil current)))
     (list (or (cdr (assoc choice rows)) (string-trim choice)))))
  (let ((root (+core-project-root)))
    (+core-dir-locals-set root '+cpp-kit name)
    (let ((kit (+cpp--kit root)))
      (message "Kit: %s. Saved to .dir-locals.el; SPC k l r restarts the server on it"
               (+cpp--kit-describe kit)))))

;;;###autoload
(defun +cpp--stale-note (root)
  "One clause naming ROOT's stale build directories, or nil."
  (when-let* ((stale (+cpp--stale-directories root)))
    (format "%s configured before the project moved (SPC k K picks one, SPC k m F configures it fresh)"
            (mapconcat (lambda (d) (file-relative-name d root)) stale ", "))))

;;;###autoload
(defun +cpp/show-kit ()
  "Say which kit is in use and why."
  (interactive)
  (let* ((root (+core-project-root))
         (kit (+cpp--kit root)))
    (message "%s, in %s%s" (+cpp--kit-describe kit) (+cpp-kit-dir kit)
             (if-let* ((note (+cpp--stale-note root))) (concat "; " note) ""))))


;;
;;; The commands a kit builds with

(declare-function projection-cmake-run-configure "projection-type-cmake")
(declare-function projection-cmake-run-build "projection-type-cmake")
(declare-function projection-cmake-run-test "projection-type-cmake")
(declare-function projection-cmake-run-install "projection-type-cmake")
(declare-function projection-cmake-list-artifacts "projection-type-cmake")
(declare-function projection-ctest-list-artifacts "projection-type-cmake")
(declare-function projection-multi-cmake-targets "projection-multi-cmake")
(declare-function projection-multi-ctest-targets "projection-multi-ctest")

;;;###autoload
(defun +cpp--kit-config (kit)
  "The configuration a multi-config KIT builds: the project's
`+cpp-build-config' when the kit lists it, else the first it lists;
nil for a kit with one configuration, the usual case."
  (when-let* ((configs (+cpp-kit-configs kit)))
    (let ((wanted (+cpp--setting '+cpp-build-config)))
      (if (member wanted configs) wanted (car configs)))))

(defun +cpp--with-config (command config)
  "COMMAND with --config CONFIG behind it when it builds or installs,
which a multi-config generator needs to know the configuration."
  (if (and config (string-match-p "\\_<cmake --\\(?:build\\|install\\) " command))
      (concat command " --config " (shell-quote-argument config))
    command))

(defun +cpp--kit-command (generator &rest args)
  "The shell command GENERATOR makes, called with ARGS, for the kit in use.
Run from the project root, whatever buffer asked."
  (require 'projection)
  (let ((kit (+cpp--kit))
        (root (+core-project-root)))
    (+cpp--kit-shell kit
                     (+cpp--with-config (+cpp--with-kit kit (apply generator args))
                                        (+cpp--kit-config kit))
                     root)))

;;;###autoload
(defun +cpp--configure-command ()
  "Configure the kit's build directory.  Writes the file API query first,
so the reply that lists targets and executables is there afterwards.
A kit never configured that carries arguments of its own, a Qt Creator
configuration or one written down in `+cpp-kits', is configured with
them and its build type, as Qt Creator would: projection passes
neither, and a toolchain file among them is what picks the SDK."
  (require 'projection)
  (let ((kit (+cpp--kit))
        (root (+core-project-root)))
    (+cpp--with-kit kit
      (+cpp--projection-write-file-api-query))
    (if (and (not (+cpp-kit-configured kit))
             (not (+cpp-kit-preset kit))
             (+cpp-kit-args kit))
        (+cpp--new-configuration-command kit (+cpp-kit-dir kit)
                                         (or (+cpp--kit-type kit) "Debug")
                                         root kit)
      (+cpp--kit-command #'projection-cmake-run-configure))))

;;;###autoload
(defun +cpp--build-command ()
  "Build the kit's default target."
  (+cpp--kit-command #'projection-cmake-run-build))

(defun +cpp--build-target-command (target)
  "Build TARGET in the kit's build directory."
  (+cpp--kit-command #'+cpp--projection-cmake-command 'build target))

;;;###autoload
(defun +cpp--test-command ()
  "Run ctest in the kit's build directory."
  (+cpp--kit-command #'projection-cmake-run-test))

;;;###autoload
(defun +cpp--install-command ()
  "Install from the kit's build directory."
  (+cpp--kit-command #'projection-cmake-run-install))

;;;###autoload
(defun +cpp--compile-multi-targets ()
  "Every CMake and CTest target of the kit, each running where the kit
runs, for `compile-multi'.  projection reads the targets from its own
File API query; a directory Qt Creator or the command line configured
has none, so its shared code model or the generator's help is read
instead, custom targets included, the packaging ones among them."
  (require 'projection)
  (require 'projection-multi-cmake)
  (require 'projection-multi-ctest)
  (let ((kit (+cpp--kit))
        (root (+core-project-root)))
    (+cpp--with-kit kit
      (let* ((cmake (or (ignore-errors (projection-multi-cmake-targets "cmake"))
                        (mapcar (lambda (name)
                                  (cons (format "cmake:%s" name)
                                        (list :command (+cpp--projection-cmake-command 'build name))))
                                (+cpp--target-names kit root))))
             (ctest (ignore-errors (projection-multi-ctest-targets "ctest"))))
        (mapcar (lambda (entry)
                  (let ((command (plist-get (cdr entry) :command)))
                    (if (stringp command)
                        (cons (car entry)
                              (plist-put (copy-sequence (cdr entry))
                                         :command (+cpp--kit-shell kit command root)))
                      entry)))
                (append cmake ctest))))))

;;;###autoload
(defun +cpp--compilation-search-paths ()
  "Where compilation errors of the kit's build resolve relative paths."
  (+cpp--with-kit (+cpp--kit) (+cpp--projection-build-directory 'expand)))

;;;###autoload
(defun +cpp-build-command (&optional target)
  "The shell command that builds the project of `default-directory', or
its TARGET, where the kit runs.  A CMake project builds through the kit;
any other type projection knows, through projection; nil otherwise."
  (let ((root (+core-project-root)))
    (if (+cpp--kind-p 'cmake)
        (if (and target (not (member target '("" "all"))))
            (+cpp--build-target-command target)
          (+cpp--build-command))
      (+cpp--projection-generic-command root 'build))))

;;;###autoload
(defun +cpp--artifacts ()
  "The executables and tests the kit's build directory knows."
  (require 'projection)
  (+cpp--with-kit (+cpp--kit)
    (append (ignore-errors (projection-cmake-list-artifacts))
            (ignore-errors (projection-ctest-list-artifacts)))))
