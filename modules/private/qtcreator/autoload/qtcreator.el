;;; private/qtcreator/autoload/qtcreator.el -*- lexical-binding: t; -*-
;;
;; Qt Creator, read whole. The project file, CMakeLists.txt.user, says
;; which kits a project builds with, in what directories, with what
;; arguments, what a build makes and what a run starts. The kits
;; themselves live in the settings, profiles.xml and its neighbours:
;; on the host, or in a container whose home the host can see, which
;; also says where that kit runs. Read together, a kit has its tool
;; set and its environment before anything was built, so a
;; configuration Qt Creator never built configures the way it would,
;; and a project's whole setup can be written down elsewhere.

(require 'xml)

(defvar +qtcreator-settings-dirs)
(declare-function +container-list "container")
(declare-function +container-home "container")
(declare-function +container-forget "container")

;;
;;; The file format

(defun +qtcreator--value (node)
  "A <value>, <valuemap> or <valuelist> NODE as a string, an alist or a list."
  (pcase (xml-node-name node)
    ('value (string-trim (or (car (xml-node-children node)) "")))
    ('valuemap (+qtcreator--valuemap node))
    ('valuelist (mapcar #'+qtcreator--value (seq-filter #'consp (xml-node-children node))))))

(defun +qtcreator--valuemap (node)
  "A Qt Creator <valuemap> NODE as an alist of KEY to value, sub-alist
or list."
  (let (result)
    (dolist (child (xml-node-children node))
      (when (consp child)
        (push (cons (xml-get-attribute-or-nil child 'key) (+qtcreator--value child)) result)))
    (nreverse result)))

(defvar +qtcreator--cache (make-hash-table :test #'equal)
  "File to (MTIME . PARSED): a settings file is parsed once per change.")

(defun +qtcreator--file (file)
  "A Qt Creator file, FILE, parsed to (VARIABLE . VALUE), or nil when
it is not there.  The project file and the settings share the shape."
  (when (file-readable-p file)
    (let ((mtime (file-attribute-modification-time (file-attributes file)))
          (hit (gethash file +qtcreator--cache)))
      (if (and hit (equal (car hit) mtime))
          (cdr hit)
        (let ((tree (car (xml-parse-file file))) result)
          (dolist (data (xml-get-children tree 'data))
            (let ((variable (car (xml-node-children (car (xml-get-children data 'variable)))))
                  (node (seq-find (lambda (n) (and (consp n) (memq (xml-node-name n) '(value valuemap valuelist))))
                                  (xml-node-children data))))
              (push (cons variable (and node (+qtcreator--value node))) result)))
          (setq result (nreverse result))
          (puthash file (cons mtime result) +qtcreator--cache)
          result)))))

(defun +qtcreator--get (map &rest keys)
  "The value under KEYS, one after the other, in the alist MAP."
  (dolist (key keys map)
    (setq map (and (listp map) (alist-get key map nil nil #'equal)))))

(defun +qtcreator--entries (file prefix)
  "The (VARIABLE . VALUE) entries of FILE whose variable is PREFIX.N,
in order: the tool chains, the Qt versions, the kits."
  (cl-loop for (variable . value) in (+qtcreator--file file)
           when (string-prefix-p (concat prefix ".") variable)
           collect value))


;;
;;; Where the settings are

(defvar +qtcreator--settings nil
  "Every Qt Creator settings directory found, as (DIR . CONTAINER).")

;; Autoloaded: `+cpp/forget-kits' drops it with the rest.
;;;###autoload
(defvar +qtcreator--kits-cache)

(defun +qtcreator-forget ()
  "Read the settings directories, the kits and the container homes again."
  (setq +qtcreator--settings nil
        ;; Every other cache here is keyed by the file's mtime; this one
        ;; is read once and was never dropped, so a kit whose sysroot or
        ;; compiler changed kept the old answer until Emacs restarted.
        +qtcreator--kits-cache nil)
  (when (fboundp '+container-forget) (+container-forget))
  (clrhash +qtcreator--cache))

(defun +qtcreator--settings-dirs ()
  "Every Qt Creator settings directory this machine can see, as
(DIR . CONTAINER): the host's, then one per distrobox whose home holds
one, stopped containers included, since a kit defined there runs there."
  (or +qtcreator--settings
      (setq +qtcreator--settings
            (let (out)
              (dolist (dir +qtcreator-settings-dirs)
                (let ((host (expand-file-name dir)))
                  (when (file-directory-p host)
                    (push (cons host nil) out))))
              (when (fboundp '+container-list)
                (dolist (name (+container-list 'all))
                  (when-let* ((home (+container-home name)))
                    (dolist (dir +qtcreator-settings-dirs)
                      (let ((there (expand-file-name
                                    (string-remove-prefix "~/" dir) home)))
                        (when (file-directory-p there)
                          (push (cons there name) out)))))))
              (nreverse out)))))


;;
;;; The kits

(defun +qtcreator--table (file prefix id-key value-key)
  "A hash of ID-KEY to VALUE-KEY over the PREFIX.N entries of FILE."
  (let ((table (make-hash-table :test #'equal)))
    (dolist (entry (+qtcreator--entries file prefix))
      (when-let* ((id (+qtcreator--get entry id-key)))
        (puthash id (+qtcreator--get entry value-key) table)))
    table))

(defun +qtcreator--braced (id)
  "The {uuid} part of ID, which a tool chain id carries behind a prefix."
  (and (stringp id) (string-match "{[^}]+}" id) (match-string 0 id)))

(defun +qtcreator--devices (dir)
  "The devices of the settings in DIR, id to plist :name :host :user
:port :key, the desktop left out."
  (let ((table (make-hash-table :test #'equal)))
    (dolist (device (+qtcreator--get (+qtcreator--file (expand-file-name "devices.xml" dir))
                                   "DeviceManager" "DeviceList"))
      (let ((host (+qtcreator--get device "Host")))
        (when (and host (not (string-empty-p host)))
          (puthash (+qtcreator--get device "InternalId")
                   (list :name (+qtcreator--get device "Name")
                         :host host
                         :user (+qtcreator--get device "Uname")
                         :port (+qtcreator--get device "SshPort")
                         :key (+qtcreator--get device "KeyFile"))
                   table))))
    table))

(defun +qtcreator--kits-in (dir container)
  "The kits defined by the Qt Creator settings in DIR, which run in
CONTAINER (nil for the host), as plists."
  (let* ((profiles (+qtcreator--entries (expand-file-name "profiles.xml" dir) "Profile"))
         (toolchains (let ((table (make-hash-table :test #'equal)))
                       (dolist (tc (+qtcreator--entries (expand-file-name "toolchains.xml" dir) "ToolChain"))
                         (when-let* ((id (+qtcreator--braced (+qtcreator--get tc "ProjectExplorer.ToolChain.Id"))))
                           (puthash id (+qtcreator--get tc "ProjectExplorer.GccToolChain.Path") table)))
                       table))
         (qts (+qtcreator--table (expand-file-name "qtversion.xml" dir) "QtVersion" "Id" "QMakePath"))
         (cmakes (+qtcreator--table (expand-file-name "cmaketools.xml" dir) "CMakeTools" "Id" "Binary"))
         (debuggers (+qtcreator--table (expand-file-name "debuggers.xml" dir) "DebuggerItem" "Id" "Binary"))
         (devices (+qtcreator--devices dir)))
    (cl-loop for kit in profiles
             for data = (+qtcreator--get kit "PE.Profile.Data")
             for name = (+qtcreator--get kit "PE.Profile.Name")
             ;; Qt Creator's own placeholders, %{Python:Name}, are not kits of ours.
             unless (or (null name) (string-match-p "%{" name))
             collect (list :id (+qtcreator--get kit "PE.Profile.Id")
                           :name name
                           :short (let ((s (+qtcreator--get kit "PE.Profile.FileSystemFriendlyName")))
                                    (and s (not (string-empty-p s)) s))
                           :sysroot (let ((s (+qtcreator--get data "PE.Profile.SysRoot")))
                                      (and s (not (string-empty-p s)) s))
                           :env (+qtcreator--get data "PE.Profile.Environment")
                           :cmake-args (+qtcreator--get data "CMake.ConfigurationKitInformation")
                           :generator (+qtcreator--get data "CMake.GeneratorKitInformation" "Generator")
                           :cc (gethash (+qtcreator--braced (+qtcreator--get data "PE.Profile.ToolChainsV3" "C")) toolchains)
                           :cxx (gethash (+qtcreator--braced (+qtcreator--get data "PE.Profile.ToolChainsV3" "Cxx")) toolchains)
                           :qmake (gethash (+qtcreator--get data "QtSupport.QtInformation") qts)
                           :cmake (gethash (+qtcreator--get data "CMakeProjectManager.CMakeKitInformation") cmakes)
                           :gdb (gethash (+qtcreator--get data "Debugger.Information") debuggers)
                           :device (gethash (+qtcreator--get data "PE.Profile.Device") devices)
                           :settings dir
                           :container container))))

(defvar +qtcreator--kits-cache nil
  "The kits of every settings directory, read once; `+cpp/forget-kits'
drops it.")

;;;###autoload
(defun +qtcreator-kits ()
  "Every kit Qt Creator defines on this machine, host and containers."
  (or +qtcreator--kits-cache
      (setq +qtcreator--kits-cache
            (cl-loop for (dir . container) in (+qtcreator--settings-dirs)
                     append (+qtcreator--kits-in dir container)))))

(defun +qtcreator-kit (id)
  "The kit with ID, as `+qtcreator-kits' lists it, or nil."
  (seq-find (lambda (kit) (equal (plist-get kit :id) id)) (+qtcreator-kits)))


;;
;;; Qt Creator's macros in the initial parameters

(defvar +qtcreator--qt-prefixes (make-hash-table :test #'equal)
  "qmake path to the QT_INSTALL_PREFIX it reports.")

(declare-function +container-run "container")

(defun +qtcreator--qt-prefix (qmake container)
  "What QMAKE, run in CONTAINER or on the host, says its install prefix
is; nil when it cannot be run."
  (when qmake
    (let ((hit (gethash (cons container qmake) +qtcreator--qt-prefixes 'unknown)))
      (if (not (eq hit 'unknown))
          hit
        (puthash (cons container qmake)
                 (let ((line (+container-run container (list qmake "-query" "QT_INSTALL_PREFIX"))))
                   (and line (string-prefix-p "/" line) line))
                 +qtcreator--qt-prefixes)))))

(defun +qtcreator--expand (parameter kit type)
  "PARAMETER, a -D line of a build configuration of TYPE, with Qt
Creator's macros filled in from KIT, or nil when it cannot be: the
package manager hook, whose file only Qt Creator writes, and any macro
this does not know."
  (cond
   ((string-match-p "\\`-D\\(?:CMAKE_GENERATOR\\|CMAKE_BUILD_TYPE\\|CMAKE_PROJECT_INCLUDE_BEFORE\\):" parameter) nil)
   ((not (string-match-p "%{" parameter)) parameter)
   (t (let ((expanded
             (replace-regexp-in-string
              "%{\\([^}]+\\)}"
              (lambda (macro)
                (let ((name (match-string 1 macro)))
                  (pcase name
                    ("Qt:qmakeExecutable" (or (plist-get kit :qmake) "%{}"))
                    ("Qt:QT_INSTALL_PREFIX" (or (+qtcreator--qt-prefix (plist-get kit :qmake) (plist-get kit :container)) "%{}"))
                    ("Compiler:Executable:C" (or (plist-get kit :cc) "%{}"))
                    ("Compiler:Executable:Cxx" (or (plist-get kit :cxx) "%{}"))
                    ;; QML debugging: on for a Debug or Profile build.
                    ("Qt:QML_DEBUG_FLAG" (if (or (equal type "Debug") (equal type "Profile")) "-DQT_QML_DEBUG" ""))
                    (_ "%{}"))))
              parameter t t)))
        (and (not (string-match-p "%{}" expanded)) expanded)))))


;;
;;; The project file

(defun +qtcreator--user-file (root)
  "Qt Creator's CMakeLists.txt.user of ROOT, parsed to (VARIABLE . VALUE)."
  (+qtcreator--file (expand-file-name "CMakeLists.txt.user" root)))

(defun +qtcreator--steps (list-map)
  "The targets of the CMake steps in LIST-MAP, a build step list."
  (cl-loop for i from 0
           for step = (+qtcreator--get list-map (format "ProjectExplorer.BuildStepList.Step.%d" i))
           while step
           when (equal (+qtcreator--get step "ProjectExplorer.ProjectConfiguration.Id") "CMakeProjectManager.MakeStep")
           append (+qtcreator--get step "CMakeProjectManager.MakeStep.BuildTargets")))

(defun +qtcreator--run-configuration (rc)
  "The run configuration RC as a plist :target :args :dir :remote."
  (when rc
    (let* ((id (+qtcreator--get rc "ProjectExplorer.ProjectConfiguration.Id"))
           ;; Recent Qt Creator names the target in BuildKey and leaves
           ;; the Id suffix empty; older versions put it in the suffix.
           (key (+qtcreator--get rc "ProjectExplorer.RunConfiguration.BuildKey")))
      (list :target (or (and key (not (string-empty-p key)) key)
                        (and id (string-match "RunConfiguration:?\\.?\\(.+\\)\\'" id) (match-string 1 id)))
            :args (+qtcreator--get rc "RunConfiguration.Arguments")
            :dir (or (+qtcreator--get rc "RunConfiguration.WorkingDirectory")
                     (+qtcreator--get rc "RunConfiguration.WorkingDirectory.default"))
            :remote (and id (string-prefix-p "RemoteLinuxRunConfiguration" id))))))

(defun +qtcreator--targets (root)
  "Every target of ROOT's project file, as plists: :name and :id the
kit's, :kit the kit as the settings define it or nil, :active which
build configuration is active, :configurations a list of plists (:name
:dir :type :args :targets :clean :qml-debug), :run the active run
configuration, :deploy the deploy steps' ids."
  (when-let* ((user (+qtcreator--user-file root)))
    (cl-loop for ti from 0
             for target = (+qtcreator--get user (format "ProjectExplorer.Project.Target.%d" ti))
             while target
             collect
             (let* ((id (+qtcreator--get target "ProjectExplorer.ProjectConfiguration.Id"))
                    (kit (+qtcreator-kit id))
                    (configurations
                     (cl-loop for i from 0
                              for bc = (+qtcreator--get target (format "ProjectExplorer.Target.BuildConfiguration.%d" i))
                              while bc
                              for dir = (+qtcreator--get bc "ProjectExplorer.BuildConfiguration.BuildDirectory")
                              when (and dir (not (string-empty-p dir)))
                              collect (let* ((type (+qtcreator--get bc "CMake.Build.Type"))
                                             (name (file-name-nondirectory (directory-file-name dir)))
                                             (qml (+qtcreator--get bc "EnableQmlDebugging"))
                                             (type-for-qml (if (or (equal qml "0")
                                                                   (and (not (equal qml "1")) (string-suffix-p "Profile" name t)))
                                                               "Profile"
                                                             type)))
                                        (list :name name
                                              :dir (expand-file-name dir)
                                              :type type
                                              :label (+qtcreator--get bc "ProjectExplorer.ProjectConfiguration.DisplayName")
                                              :args (delq nil (mapcar (lambda (p) (+qtcreator--expand p kit type-for-qml))
                                                                      (split-string (or (+qtcreator--get bc "CMake.Initial.Parameters") "") "\n" t)))
                                              :generator (let ((initial (or (+qtcreator--get bc "CMake.Initial.Parameters") "")))
                                                           (and (string-match "-DCMAKE_GENERATOR:STRING=\\([^\n]+\\)" initial)
                                                                (match-string 1 initial)))
                                              :targets (+qtcreator--steps (+qtcreator--get bc "ProjectExplorer.BuildConfiguration.BuildStepList.0"))
                                              :clean (+qtcreator--steps (+qtcreator--get bc "ProjectExplorer.BuildConfiguration.BuildStepList.1"))))))
                    (active (string-to-number (or (+qtcreator--get target "ProjectExplorer.Target.ActiveBuildConfiguration") "0")))
                    (rc (+qtcreator--get target (format "ProjectExplorer.Target.RunConfiguration.%s"
                                                      (or (+qtcreator--get target "ProjectExplorer.Target.ActiveRunConfiguration") "0"))))
                    (deploy (let ((dc (+qtcreator--get target (format "ProjectExplorer.Target.DeployConfiguration.%s"
                                                                    (or (+qtcreator--get target "ProjectExplorer.Target.ActiveDeployConfiguration") "0")))))
                              (cl-loop for i from 0
                                       for step = (+qtcreator--get dc "ProjectExplorer.BuildConfiguration.BuildStepList.0"
                                                                 (format "ProjectExplorer.BuildStepList.Step.%d" i))
                                       while step
                                       collect (+qtcreator--get step "ProjectExplorer.ProjectConfiguration.Id")))))
               (list :name (+qtcreator--get target "ProjectExplorer.ProjectConfiguration.DisplayName")
                     :id id
                     :kit kit
                     :active active
                     :configurations configurations
                     :run (+qtcreator--run-configuration rc)
                     :deploy deploy)))))

;;;###autoload
(defun +qtcreator-configurations (root)
  "Every build configuration of every Qt Creator target for ROOT, as
plists: :name, the directory's last component (Desktop-Release), :dir
absolute, :type its CMake build type, :configured whether its cache
exists, :generator, :args the -D arguments of its initial parameters
with Qt Creator's macros filled in from the kit, :targets what its
build step makes, :target the kit's name, :kit the kit as the settings
define it (tool set, environment, container, device) or nil when the
settings are not here, :run the target's run configuration.  What
its Projects mode lists, built or not, with two targets when the
project builds for two kits."
  (cl-loop for target in (+qtcreator--targets root)
           append (mapcar (lambda (conf)
                            (append conf
                                    (list :configured (file-exists-p (expand-file-name "CMakeCache.txt" (plist-get conf :dir)))
                                          :target (plist-get target :name)
                                          :kit (plist-get target :kit)
                                          :run (plist-get target :run))))
                          (plist-get target :configurations))))

;;;###autoload
(defun +qtcreator-active (root)
  "What Qt Creator has active for ROOT: a plist with :kit, :config, :dir,
:run-target, :run-args, :run-dir, :run-remote, or nil when there is no
user file."
  (when-let* ((user (+qtcreator--user-file root))
              (index (string-to-number (or (+qtcreator--get user "ProjectExplorer.Project.ActiveTarget") "0")))
              (target (nth index (+qtcreator--targets root))))
    (let ((conf (nth (plist-get target :active) (plist-get target :configurations)))
          (run (plist-get target :run)))
      (list :kit (plist-get target :name)
            :config (plist-get conf :label)
            :dir (plist-get conf :dir)
            :run-target (plist-get run :target)
            :run-args (plist-get run :args)
            :run-dir (plist-get run :dir)
            :run-remote (plist-get run :remote)))))
