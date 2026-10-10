;;; private/cpp/autoload/build-type.el -*- lexical-binding: t; -*-
;;
;; Build types: Debug, Release and the rest, across the kits a project
;; has. A type is a sibling kit, the same tool set in another directory
;; or another preset; switching to one that was never configured makes
;; it from the current kit's own settings, read off its cache, so a
;; plain CMake tree gets what a Qt Creator project has. Nothing here
;; invents a configuration where one exists.

(declare-function +cpp-kit-name "kit")
(declare-function +cpp-kit-dir "kit")
(declare-function +cpp-kit-abs-dir "kit")
(declare-function +cpp-kit-source "kit")
(declare-function +cpp-kit-preset "kit")
(declare-function +cpp-kit-build-type "kit")
(declare-function +cpp-kit-generator "kit")
(declare-function +cpp-kit-configured "kit")
(declare-function +cpp-kit-container "kit")
(declare-function +cpp-kit-args "kit")
(declare-function +cpp-kit-qtc "kit")
(declare-function +cpp-kit-configs "kit")
(declare-function +cpp--kit-config "kit")
(declare-function +cpp-kit-make "kit")
(declare-function +cpp--kit "kit")
(declare-function +cpp--kits "kit")
(declare-function +cpp--kit-describe "kit")
(declare-function +cpp--kit-locate "kit")
(declare-function +cpp--cache-values "kit")
(declare-function +cpp--kit-shell "container")
(declare-function +cpp--sdk-root "container")
(declare-function +cpp--arg-cell "kit")
(declare-function +cpp--arg-value "kit")
(declare-function +cpp-kit-toolchain "kit")
(declare-function +cpp-kit-env-script "kit")
(declare-function +core-dir-locals-set "lib")
(declare-function +cpp--compile "project")
(declare-function +cpp--cache-override-args "cmake")
(declare-function +cpp--cache-overrides "cmake")
(declare-function +cpp--set-setting "project")
(declare-function +cpp--configure-command "kit")
(defvar +core-compile-name)

(defconst +cpp-build-types '("Debug" "Release" "RelWithDebInfo" "MinSizeRel")
  "CMake's build types, in the order they are offered.")

(defconst +cpp--type-suffix-regexp
  "\\`\\(.*?\\)[-_/]?\\(debug\\|release\\|relwithdebinfo\\|minsizerel\\|profile\\)\\'"
  "A kit name that ends in a build type: Desktop-Debug, build-release,
cmake-build-debug.  Group 1 is the family, group 2 the type.")


;;
;;; What type a kit is, and its siblings

(defun +cpp--canonical-type (type)
  "TYPE as CMake spells it; Qt Creator's Profile is RelWithDebInfo."
  (pcase (downcase (or type ""))
    ("debug" "Debug")
    ("release" "Release")
    ((or "relwithdebinfo" "profile") "RelWithDebInfo")
    ("minsizerel" "MinSizeRel")
    ("" nil)
    (_ type)))

;; Autoloaded: kit.el configures a planned kit with these two.
;;;###autoload
(defun +cpp--kit-type (kit)
  "The build type of KIT: the configuration it builds when its generator
has several, else what its cache or preset says, else what its name
ends in, else nil."
  (or (+cpp--kit-config kit)
      (+cpp--canonical-type (+cpp-kit-build-type kit))
      (let ((case-fold-search t))
        (and (string-match +cpp--type-suffix-regexp (+cpp-kit-name kit))
             (+cpp--canonical-type (match-string 2 (+cpp-kit-name kit)))))))

(defun +cpp--named-type (kit)
  "What KIT's name calls its type when CMake spells it otherwise, Qt
Creator's Profile; nil for a kit named after a CMake type or after
nothing."
  (let ((case-fold-search t)
        (name (+cpp-kit-name kit)))
    (and (string-match +cpp--type-suffix-regexp name)
         (let ((spelled (match-string 2 name)))
           (and (not (string-equal-ignore-case (+cpp--canonical-type spelled) spelled))
                (capitalize spelled))))))

(defun +cpp--kit-family (kit)
  "The family KIT belongs to: the Qt Creator kit behind it when the
settings say, by its name, since two kits may share a short name and
even a directory, else its name without the type suffix (Desktop-Debug
and Desktop-Release are Desktop; build is build), or `preset' for a
preset, since presets are one family."
  (cond ((+cpp-kit-preset kit) 'preset)
        ((plist-get (+cpp-kit-qtc kit) :name))
        (t (let ((case-fold-search t)
                 (name (+cpp-kit-name kit)))
             (if (string-match +cpp--type-suffix-regexp name)
                 (let ((base (match-string 1 name)))
                   (if (string-empty-p base) "build" base))
               name)))))

(defun +cpp--siblings (kit kits)
  "The kits of KIT's family among KITS, KIT included."
  (let ((family (+cpp--kit-family kit)))
    (seq-filter (lambda (k) (equal (+cpp--kit-family k) family)) kits)))

(defun +cpp--sibling-of-type (kit type kits)
  "KIT's sibling of build TYPE among KITS, or nil.  In the family, a
configured one first, then one whose name spells the type, then any;
outside it, a preset of that type, the project's own word on how to
build it, before anything would be made up."
  (cl-flet ((pick (candidates)
              (or (seq-find #'+cpp-kit-configured candidates)
                  (seq-find (lambda (k) (string-suffix-p type (+cpp-kit-name k) t)) candidates)
                  (car candidates))))
    (let ((typed (seq-filter (lambda (k) (equal (+cpp--kit-type k) type)) kits)))
      (or (pick (seq-intersection typed (+cpp--siblings kit kits)))
          (pick (seq-filter #'+cpp-kit-preset typed))))))

(defun +cpp--taken-p (dir kits root)
  "Non-nil when DIR, relative to ROOT, is a kit's directory in KITS,
letter case aside."
  (seq-some (lambda (k)
              (string-equal-ignore-case (directory-file-name (+cpp-kit-dir k))
                                        (directory-file-name dir)))
            (cons (+cpp--kit root) kits)))

(defun +cpp--sibling-name (kit type kits root)
  "The name and directory a new sibling of KIT of build TYPE would get,
as (NAME . DIR), DIR relative to ROOT: the type replaces KIT's own
suffix in its spelling (Desktop-Debug gives Desktop-Release,
cmake-build-debug gives cmake-build-release); a kit called build gets
build/Release under it; a preset project gets build/Release beside its
presets.  Never the directory of a kit in KITS: -manual is added when
one is in the way, a preset called release with Release wanted."
  (let* ((case-fold-search t)
         (name (+cpp-kit-name kit))
         (dir (directory-file-name (+cpp-kit-dir kit)))
         (candidate
          (cond ((+cpp-kit-preset kit)
                 (cons type (file-name-concat "build" type)))
                ((string-match +cpp--type-suffix-regexp name)
                 (let* ((base (match-string 1 name))
                        (old (match-string 2 name))
                        (spelled (cond ((string= old (downcase old)) (downcase type))
                                       ((string= old (upcase old)) (upcase type))
                                       (t type)))
                        (sep (substring name (length base) (- (length name) (length old))))
                        (new (concat base sep spelled)))
                   (cons new (concat (file-name-directory dir) new))))
                (t (cons type (file-name-concat dir type))))))
    (if (+cpp--taken-p (cdr candidate) kits root)
        (cons (concat (car candidate) "-manual") (concat (cdr candidate) "-manual"))
      candidate)))

;; Autoloaded: the CMake panel's header in menu.el.
;;;###autoload
(defun +cpp--types-summary (kit kits)
  "One line on the build types of KIT's family: the current one starred,
an unconfigured one marked with a plus.  For a kit whose generator
has several configurations, those, the one it builds starred."
  (if-let* ((configs (+cpp-kit-configs kit)))
      (let ((active (+cpp--kit-config kit)))
        (mapconcat (lambda (c) (concat c (if (equal c active) "*" ""))) configs " "))
   (let ((siblings (seq-sort-by (lambda (k) (or (seq-position +cpp-build-types (+cpp--kit-type k)) 99))
                                #'< (+cpp--siblings kit kits))))
    (mapconcat (lambda (k)
                 (concat (cond ((+cpp-kit-preset k)
                                (format "%s:%s" (+cpp-kit-name k) (or (+cpp--kit-type k) "?")))
                               ;; Profile is shown as it is named.
                               ((+cpp--named-type k))
                               (t (or (+cpp--kit-type k) (+cpp-kit-name k))))
                         (cond ((equal (+cpp-kit-name k) (+cpp-kit-name kit)) "*")
                               ((not (+cpp-kit-configured k)) "+")
                               (t ""))))
               siblings " "))))


;;
;;; Configuring a sibling from what a kit already has

(defconst +cpp--carried-cache-variables
  '("CMAKE_C_COMPILER" "CMAKE_CXX_COMPILER" "CMAKE_TOOLCHAIN_FILE"
    "CMAKE_SYSROOT" "CMAKE_PREFIX_PATH" "QT_QMAKE_EXECUTABLE"
    "CMAKE_MAKE_PROGRAM")
  "The cache variables a new configuration takes over from the kit it
is made from: the tool set.  Not the build type, and not the flags,
which Qt Creator sets per type.")

;; Autoloaded: cmake.el writes a kit's tool set down with it.
;;;###autoload
(defun +cpp--carried-args (kit root)
  "-D arguments carrying KIT's tool set, from its cache under ROOT; nil
when it has no cache."
  (let ((cache (expand-file-name "CMakeCache.txt" (+cpp-kit-abs-dir kit root))))
    (when (file-exists-p cache)
      (mapcar (lambda (cell) (format "-D%s=%s" (car cell) (cdr cell)))
              (+cpp--cache-values cache +cpp--carried-cache-variables)))))

;; Autoloaded: cmake.el offers them as the value of CMAKE_PREFIX_PATH.
;;;###autoload
(defun +cpp--qt-prefixes ()
  "Where a Qt lives on this machine: the system one, and every
~/Qt/<version>/gcc_64, newest first."
  (append
   (seq-filter (lambda (prefix)
                 (seq-some (lambda (sub) (file-directory-p (expand-file-name sub prefix)))
                           '("lib64/cmake/Qt6" "lib/cmake/Qt6"
                             "lib/x86_64-linux-gnu/cmake/Qt6" "lib64/cmake/Qt5")))
               '("/usr" "/usr/local"))
   (sort (file-expand-wildcards "~/Qt/[0-9]*/gcc_64")
         (lambda (a b) (string> a b)))))

(defun +cpp--uses-qt-p (root)
  "Non-nil when ROOT's CMakeLists.txt asks for Qt."
  (let ((file (expand-file-name "CMakeLists.txt" root)))
    (and (file-readable-p file)
         (with-temp-buffer
           (insert-file-contents file)
           (re-search-forward "find_package *( *Qt[56]" nil t)))))

(defun +cpp--qt-args (root args)
  "A -DCMAKE_PREFIX_PATH for a Qt project under ROOT when neither the
ARGS nor the overrides name a prefix or a toolchain file, which brings
its own Qt: the one Qt on this machine, or a choice."
  (when (and (+cpp--uses-qt-p root)
             (let ((all (append args (+cpp--cache-override-args))))
               (not (or (+cpp--arg-value all "CMAKE_PREFIX_PATH")
                        (+cpp--arg-value all "CMAKE_TOOLCHAIN_FILE")))))
    (when-let* ((prefixes (+cpp--qt-prefixes))
                (prefix (if (cdr prefixes)
                            (completing-read "Qt to build with: " prefixes nil t)
                          (car prefixes))))
      (list (concat "-DCMAKE_PREFIX_PATH=" prefix)))))

;;;###autoload
(defun +cpp--new-configuration-command (from dir type root &optional planned)
  "The cmake line that configures DIR under ROOT as TYPE with the tool
set of kit FROM, and the arguments PLANNED, the Qt Creator configuration
the directory is, carries of its own.  Those win over FROM's cache, and
a toolchain file among them stands for a whole tool set: nothing of
another SDK is carried beside it, and the line runs where that SDK is,
where FROM runs otherwise."
  (let* ((own (and planned (+cpp-kit-args planned)))
         (toolchain (+cpp--arg-value own "CMAKE_TOOLCHAIN_FILE"))
         (sdk (+cpp--sdk-root toolchain))
         (carried (seq-remove
                   (lambda (arg)
                     (pcase-let ((`(,name . ,value) (+cpp--arg-cell arg)))
                       (or (+cpp--arg-value own name)
                           (and toolchain
                                (not (equal (+cpp--sdk-root value) sdk))))))
                   (+cpp--carried-args from root)))
         (runner (or (and toolchain (+cpp-kit-toolchain planned)
                          (let ((kit (+cpp--kit-locate planned)))
                            (and (or (+cpp-kit-container kit) (+cpp-kit-env-script kit))
                                 kit)))
                     from))
         (generator (or (and planned (+cpp-kit-generator planned))
                        (+cpp-kit-generator from)))
         (args (append (list "cmake" "-S" root "-B" (expand-file-name dir root))
                       (when generator (list "-G" generator))
                       (list (concat "-DCMAKE_BUILD_TYPE=" type)
                             "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON")
                       carried
                       own
                       (+cpp--qt-args root (append carried own))
                       (+cpp--cache-override-args))))
    (+cpp--kit-shell runner (mapconcat #'shell-quote-argument args " ") root)))

(defun +cpp--switch-to (root sibling)
  "Choose SIBLING as ROOT's kit; a preset that was never configured is
configured through projection on the way."
  (+core-dir-locals-set root '+cpp-kit (+cpp-kit-name sibling))
  (if (and (+cpp-kit-preset sibling) (not (+cpp-kit-configured sibling)))
      (progn (+cpp--compile "cmake configure" (+cpp--configure-command))
             (message "Kit: %s, configuring through its preset" (+cpp-kit-name sibling)))
    (message "Kit: %s; SPC k b builds it, SPC k l r restarts the server on it"
             (+cpp--kit-describe (+cpp--kit root)))))

(defvar +cpp--pending-kit nil
  "(ROOT . NAME) of the kit to switch to once its configure finishes.")

(defun +cpp--configure-new (root from name dir type &optional planned)
  "Configure DIR under ROOT as kit NAME of build TYPE with FROM's tool
set, and the arguments of PLANNED, the Qt Creator configuration DIR
is, when it is one; then switch to it.  Asks first."
  (when (y-or-n-p (if (eq from planned)
                      (format "Configure %s (%s) in %s with its Qt Creator settings? "
                              name type dir)
                    (format "Configure %s (%s) in %s from %s's settings? "
                            name type dir (+cpp-kit-name from))))
    (setq +cpp--pending-kit (cons root name))
    (add-hook 'compilation-finish-functions #'+cpp--configured-new-kit-h)
    (+cpp--compile "cmake configure"
                   (+cpp--new-configuration-command from dir type root planned))))

(defun +cpp--configured-new-kit-h (buffer status)
  "Switch to the kit `+cpp--configure-type' made once BUFFER finishes with STATUS."
  (when (equal (buffer-local-value '+core-compile-name buffer) "cmake configure")
    (remove-hook 'compilation-finish-functions #'+cpp--configured-new-kit-h)
    (pcase-let ((`(,root . ,name) +cpp--pending-kit))
      (setq +cpp--pending-kit nil)
      (if (string-prefix-p "finished" status)
          (progn
            (+core-dir-locals-set root '+cpp-kit name)
            (message "Kit: %s, configured and chosen; SPC k b builds it, SPC k l r restarts the server on it"
                     name))
        (message "The configure of %s failed; see the buffer, SPC k K keeps the kit as it was" name)))))

(defun +cpp--configure-type (type &optional planned)
  "Configure a new kit of build TYPE from the current kit and switch to
it, what `+cpp/build-type' does for a type the family lacks.  The new
directory takes the current kit's tool set, compilers, toolchain,
sysroot, Qt prefix, generator, from its cache, the type and the
project's overrides on top; a Qt project with no prefix anywhere is
asked which Qt.  Runs where the current kit runs.  PLANNED names the
unconfigured kit to make, else the family's own of that type is made,
else a new directory."
  (let* ((root (+core-project-root))
         (kit (+cpp--kit root))
         (kits (+cpp--kits root))
         (planned (or planned (+cpp--sibling-of-type kit type kits)))
         (target (if planned
                     (cons (+cpp-kit-name planned) (+cpp-kit-dir planned))
                   (+cpp--sibling-name kit type kits root))))
    (cond
     ((and planned (+cpp-kit-configured planned))
      (user-error "%s is configured already; SPC k y switches to it" (car target)))
     ((and planned (+cpp-kit-preset planned))
      (+cpp--switch-to root planned))
     ((and (not planned) (+cpp--taken-p (cdr target) kits root))
      (user-error "%s is another kit's directory; it is not reconfigured in place" (cdr target)))
     (t (+cpp--configure-new root kit (car target) (cdr target) type planned)))))

;;;###autoload
(defun +cpp/build-type (type)
  "Build as TYPE from now on: Debug, Release, RelWithDebInfo or
MinSizeRel.  Switches to the kit of that type in the current kit's
family, the other Qt Creator configuration, the other preset, the
other directory; one that exists but was never configured is
configured first, from the current kit's settings; one that does not
exist is made.  Written to .dir-locals.el like any kit choice."
  (interactive
   (let* ((root (+core-project-root))
          (kit (+cpp--kit root))
          (kits (+cpp--kits root))
          (current (+cpp--kit-type kit))
          ;; Qt Creator's Profile is offered by its own name.
          (named (delq nil (mapcar #'+cpp--named-type (+cpp--siblings kit kits)))))
     (list (completing-read
            (format "Build type (now %s, family %s: %s): "
                    (or current "unknown") (+cpp--kit-family kit)
                    (+cpp--types-summary kit kits))
            (or (+cpp-kit-configs kit) (append +cpp-build-types (seq-uniq named))) nil t nil nil
            (car (seq-remove (lambda (ty) (equal ty current))
                             (or (+cpp-kit-configs kit) +cpp-build-types)))))))
  (let* ((root (+core-project-root))
         (kit (+cpp--kit root))
         (kits (+cpp--kits root))
         (configs (+cpp-kit-configs kit))
         ;; Profile: the sibling spelled so, made as itself when new.
         (named (and (not (member type +cpp-build-types))
                     (seq-find (lambda (k) (equal (+cpp--named-type k) type))
                               (+cpp--siblings kit kits))))
         (type (if named (+cpp--kit-type named) (+cpp--canonical-type type)))
         (sibling (or named (+cpp--sibling-of-type kit type kits))))
    (cond
     ;; A multi-config generator: the type is chosen at build time.
     (configs
      (unless (member type configs)
        (user-error "%s builds %s; %s is not among them" (+cpp-kit-name kit)
                    (mapconcat #'identity configs ", ") type))
      (+cpp--set-setting '+cpp-build-config type)
      (message "%s builds %s from now on, --config at build time; SPC k b builds it"
               (+cpp-kit-name kit) type))
     ((and (or (+cpp-kit-configured kit) (+cpp-kit-preset kit))
           (if named
               (equal (+cpp-kit-name named) (+cpp-kit-name kit))
             (equal (+cpp--kit-type kit) type)))
      (message "Already building %s: %s" type (+cpp--kit-describe kit)))
     ((and sibling (or (+cpp-kit-configured sibling) (+cpp-kit-preset sibling)))
      (+cpp--switch-to root sibling))
     (t (+cpp--configure-type type named)))))

;;;###autoload
(defun +cpp/kit-family (family)
  "Build with FAMILY from now on, keeping the build type: the other Qt
Creator kit of the project, the SDK one against the PC one, or a plain
directory against the presets.  Switches to the kit of the current
type in FAMILY; one never built is configured first, from a configured
kit of that family, since a tool set cannot be borrowed across
families, or from its own Qt Creator settings when they name a
toolchain file, which is a tool set by itself."
  (interactive
   (let* ((root (+core-project-root))
          (kit (+cpp--kit root))
          (kits (+cpp--kits root))
          (families (seq-uniq (mapcar (lambda (k) (format "%s" (+cpp--kit-family k))) kits))))
     (list (completing-read
            (format "Family (now %s): " (+cpp--kit-family kit))
            (mapcar (lambda (f)
                      (let ((member (seq-find (lambda (k) (equal (format "%s" (+cpp--kit-family k)) f)) kits)))
                        (format "%s  %s" f (+cpp--types-summary member kits))))
                    families)
            nil t))))
  (let* ((family (car (split-string family "  ")))
         (root (+core-project-root))
         (kit (+cpp--kit root))
         (kits (+cpp--kits root))
         (type (+cpp--kit-type kit))
         (members (seq-filter (lambda (k) (equal (format "%s" (+cpp--kit-family k)) family)) kits))
         (wanted (or (seq-find (lambda (k) (and (equal (+cpp--kit-type k) type) (+cpp-kit-configured k))) members)
                     (seq-find (lambda (k) (equal (+cpp--kit-type k) type)) members)
                     (seq-find #'+cpp-kit-configured members)
                     (car members)))
         (source (or (seq-find #'+cpp-kit-configured members)
                     (and wanted (+cpp-kit-toolchain wanted) wanted))))
    (cond
     ((null wanted) (user-error "No kit of family %s" family))
     ((or (+cpp-kit-configured wanted) (+cpp-kit-preset wanted))
      (+cpp--switch-to root wanted)
      (unless (equal (+cpp--kit-type wanted) type)
        (message "Kit: %s; the family has no %s yet, SPC k y makes one" (+cpp-kit-name wanted) type)))
     ((null source)
      (user-error "%s has no configured kit to take a tool set from; build one there once, in Qt Creator or with SPC k c on it"
                  family))
     (t (+cpp--configure-new root source (+cpp-kit-name wanted) (+cpp-kit-dir wanted)
                             (or (+cpp--kit-type wanted) "Debug") wanted)))))
