;;; private/web/autoload/web.el -*- lexical-binding: t; -*-
;;
;; A node project: what it is built with, what it can be told to do, and
;; the commands built from both. The shape follows cpp, rust and pascal:
;; the settings live in .dir-locals.el, every command is built from them,
;; so SPC k b and the panel and F7 run the same line.

(defvar dape-adapter-dir)
(declare-function dape "dape")
(declare-function dape--config-eval "dape")
(declare-function +core-project-root "lib")
(declare-function +core-dir-locals-set "lib")
(declare-function +core-compile "lib")


;;
;;; The settings

;;;###autoload
(defvar-local +web-package-manager nil
  "The package manager to use here: \"yarn\", \"npm\", \"pnpm\" or \"bun\".
Nil means the one the lock file names, which is what a project cloned
from elsewhere wants.")
;;;###autoload
(put '+web-package-manager 'safe-local-variable #'stringp)

;;;###autoload
(defvar-local +web-dev-script nil
  "The script `SPC k r' runs, when it is not the usual dev or start.")
;;;###autoload
(put '+web-dev-script 'safe-local-variable #'stringp)

;;;###autoload
(defvar-local +web-build-script nil
  "The script `SPC k b' runs, when it is not the usual build.")
;;;###autoload
(put '+web-build-script 'safe-local-variable #'stringp)


;;
;;; The project

;;;###autoload
(defun +web-project-p (&optional dir)
  "Non-nil when DIR, or the current project, is a node project."
  (let ((root (or dir (+core-project-root 'noerror))))
    (and root (file-exists-p (expand-file-name "package.json" root)))))

;;;###autoload
(defun +web-root ()
  "The node project's root, or an error."
  (let ((root (+core-project-root 'noerror)))
    (unless (+web-project-p root)
      (user-error "No package.json here: this is not a node project"))
    (file-name-as-directory (expand-file-name root))))

(defvar +web--manifest-cache (make-hash-table :test #'equal)
  "Project root to (MTIME . PARSED) of its package.json.
Read once per change: the panel asks for the scripts on every redraw.")

;;;###autoload
(defun +web-manifest (&optional root)
  "The project's package.json, parsed, or nil.
Nil rather than an error when there is no project: this is asked from
the panel's predicates and from the server list, where being somewhere
else is an ordinary answer."
  (let* ((root (or root (and (+web-project-p) (+core-project-root 'noerror))))
         (root (and root (file-name-as-directory (expand-file-name root))))
         (file (and root (expand-file-name "package.json" root)))
         (mtime (and file (file-attribute-modification-time
                           (file-attributes file))))
         (hit (and root (gethash root +web--manifest-cache))))
    (cond ((null mtime) nil)
          ((and hit (equal (car hit) mtime)) (cdr hit))
          (t (let ((parsed (with-temp-buffer
                             (insert-file-contents file)
                             (goto-char (point-min))
                             (ignore-errors
                               (json-parse-buffer :object-type 'alist
                                                  :array-type 'list)))))
               (puthash root (cons mtime parsed) +web--manifest-cache)
               parsed)))))


;;;###autoload
(defun +web-tailwind-p (&optional root)
  "Non-nil when the project uses Tailwind.
Asked from the eglot server list, where there may be no project at all,
so it answers nil rather than raising."
  (ignore-errors
    (when (+web-project-p root)
      (let ((manifest (+web-manifest (or root (+core-project-root 'noerror)))))
        (and (or (assq 'tailwindcss (alist-get 'dependencies manifest))
                 (assq 'tailwindcss (alist-get 'devDependencies manifest))
                 (assq '@tailwindcss/vite (alist-get 'devDependencies manifest)))
             t)))))


;;
;;; Which package manager

(defvar +web-package-managers
  '(("bun.lockb"         . "bun")
    ("pnpm-lock.yaml"    . "pnpm")
    ("yarn.lock"         . "yarn")
    ("package-lock.json" . "npm"))
  "Lock file to the manager that wrote it, most particular first.")

;;;###autoload
(defun +web-manager (&optional root)
  "The package manager this project is built with.
The dir-local setting when there is one, else whichever manager's lock
file is beside the manifest, else what `packageManager' in the manifest
says, else yarn."
  (let ((root (file-name-as-directory (or root (+web-root)))))
    (or +web-package-manager
        (cdr (seq-find (lambda (pair)
                         (file-exists-p (expand-file-name (car pair) root)))
                       +web-package-managers))
        (when-let* ((field (alist-get 'packageManager (+web-manifest root)))
                    ((stringp field)))
          (car (split-string field "@")))
        "yarn")))

;;;###autoload
(defun +web/set-manager (manager)
  "Build with MANAGER from now on, kept in .dir-locals.el."
  (interactive
   (list (completing-read "Package manager: "
                          (mapcar #'cdr +web-package-managers)
                          nil t nil nil (+web-manager))))
  (+core-dir-locals-set (+web-root) '+web-package-manager manager)
  (setq-local +web-package-manager manager)
  (message "Using %s here" manager))


;;
;;; What it can be told to do

;;;###autoload
(defun +web-scripts (&optional root)
  "The scripts the manifest defines, as an alist of (NAME . COMMAND)."
  (mapcar (lambda (pair) (cons (symbol-name (car pair)) (cdr pair)))
          (alist-get 'scripts (+web-manifest root))))

(defun +web--script (&rest names)
  "The first of NAMES the project defines, or nil."
  (let ((scripts (+web-scripts)))
    (seq-find (lambda (name) (assoc name scripts)) names)))

;;;###autoload
(defun +web-run-script-command (script)
  "The command line that runs SCRIPT with this project's manager.
npm wants `run' before a script that is not one of its own; yarn, pnpm
and bun take the name directly, and all of them take `run' as well, so
it is written the way each one's own documentation writes it."
  (let ((manager (+web-manager)))
    (if (equal manager "npm")
        (format "npm run %s" script)
      (format "%s %s" manager script))))

;;;###autoload
(defun +web-dev-command ()
  "What `SPC k r' runs: the project's dev server."
  (let ((script (or +web-dev-script (+web--script "dev" "start" "serve"))))
    (unless script
      (user-error "No dev, start or serve script in package.json"))
    (+web-run-script-command script)))

;;;###autoload
(defun +web-build-command ()
  "What `SPC k b' runs."
  (let ((script (or +web-build-script (+web--script "build" "compile"))))
    (unless script
      (user-error "No build script in package.json"))
    (+web-run-script-command script)))

;;;###autoload
(defun +web-test-command ()
  "What `SPC k t' runs."
  (let ((script (+web--script "test" "test:unit")))
    (unless script
      (user-error "No test script in package.json"))
    (+web-run-script-command script)))


;;
;;; The commands

(defun +web--compile (name command &optional interactive)
  "Run COMMAND in a compilation buffer called NAME, from the root.
With INTERACTIVE the buffer takes input, which a dev server wants: it
does not end, and it is asked questions."
  (+core-compile name command (+web-root) interactive))

;;;###autoload
(defun +web/dev ()
  "Start the project's dev server, and leave it running."
  (interactive)
  (+web--compile "run dev server" (+web-dev-command) t))

;;;###autoload
(defun +web/build ()
  "Build the project."
  (interactive)
  (+web--compile "build" (+web-build-command)))

;;;###autoload
(defun +web/preview ()
  "Serve what the build made, as it will be served for real."
  (interactive)
  (let ((script (+web--script "preview" "serve:build" "start")))
    (unless script (user-error "No preview script in package.json"))
    (+web--compile "run preview" (+web-run-script-command script) t)))

;;;###autoload
(defun +web/test ()
  "Run the project's tests."
  (interactive)
  (+web--compile "test" (+web-test-command)))

;;;###autoload
(defun +web/test-watch ()
  "Run the tests and keep running them as the files change."
  (interactive)
  (let ((script (+web--script "test:watch" "test:unit" "test")))
    (unless script (user-error "No test script in package.json"))
    (+web--compile "run tests" (+web-run-script-command script) t)))

;;;###autoload
(defun +web/lint ()
  "Run the project's linter."
  (interactive)
  (let ((script (+web--script "lint" "eslint")))
    (+web--compile "lint" (if script
                              (+web-run-script-command script)
                            "eslint ."))))

;;;###autoload
(defun +web/check ()
  "Check the types without building: svelte-check, or tsc."
  (interactive)
  (let ((script (+web--script "check" "typecheck" "check:types")))
    (+web--compile "check" (if script
                               (+web-run-script-command script)
                             "tsc --noEmit"))))

;;;###autoload
(defun +web/install ()
  "Install what the manifest asks for."
  (interactive)
  (+web--compile "install" (format "%s install" (+web-manager))))

;;;###autoload
(defun +web/outdated ()
  "Say which dependencies have moved on."
  (interactive)
  (+web--compile "outdated" (format "%s outdated" (+web-manager))))

;;;###autoload
(defun +web/run-script (script)
  "Run any SCRIPT the manifest defines."
  (interactive
   (list (completing-read "Script: "
                          (or (mapcar #'car (+web-scripts))
                              (user-error "No scripts in package.json"))
                          nil t)))
  (+web--compile (format "run %s" script)
                 (+web-run-script-command script)
                 t))

;;;###autoload
(defun +web/open-manifest ()
  "Open the project's package.json."
  (interactive)
  (find-file (expand-file-name "package.json" (+web-root))))


;;
;;; Electron

;;;###autoload
(defun +web-electron-p (&optional root)
  "Non-nil when the project is an Electron application.
Answers nil outside a project: the panel asks it to decide whether to
show a group."
  (let ((manifest (ignore-errors (+web-manifest root))))
    (and (or (assq 'electron (alist-get 'devDependencies manifest))
             (assq 'electron (alist-get 'dependencies manifest))
             (assq 'electron-builder (alist-get 'devDependencies manifest)))
         t)))

;;;###autoload
(defun +web/package (target)
  "Package the Electron application for TARGET.
Linux and Windows are built here, Windows through wine as
electron-builder arranges; macOS needs a Mac to sign for, so the
template's CI workflow builds that one."
  (interactive
   (list (completing-read "Package for: "
                          '("linux" "win" "mac" "current") nil t nil nil "linux")))
  (unless (+web-electron-p)
    (user-error "Not an Electron project: no electron in package.json"))
  (let ((script (+web--script "package" "dist" "build:app")))
    (+web--compile
     "package"
     (cond ((and script (equal target "current")) (+web-run-script-command script))
           ((equal target "current") "electron-builder")
           (t (format "electron-builder --%s" target))))))

;;;###autoload
(defun +web/debug ()
  "Debug the project: the Electron main process, or node."
  (interactive)
  (unless (fboundp 'dape)
    (user-error "dape is not here to debug with"))
  (require 'dape)
  ;; dape takes the configuration itself, not its name: handed
  ;; (node-project :cwd ...) it read every key as a value, found no
  ;; command, and no session started.
  (let ((root (+web-root)))
    (dape (if (+web-electron-p)
              (dape--config-eval 'electron-main
                                 (list :cwd root
                                       :runtimeExecutable
                                       (expand-file-name "node_modules/.bin/electron" root)))
            (dape--config-eval 'node-project (list :cwd root))))))

;;;###autoload
(defun +web/install-js-debug ()
  "Download js-debug, the debugger VS Code uses for node and Electron,
where dape keeps its adapters; SPC k d uses it afterwards."
  (interactive)
  (require 'dape)
  (let* ((version "1.140.0")
         (url (format "https://github.com/microsoft/vscode-js-debug/releases/download/v%s/js-debug-dap-v%s.tar.gz"
                      version version))
         (tarball (expand-file-name "js-debug.tar.gz" temporary-file-directory))
         (dir (file-name-as-directory dape-adapter-dir)))
    (unless (executable-find "tar") (user-error "tar is not installed"))
    (make-directory dir t)
    (message "Downloading js-debug %s..." version)
    (url-copy-file url tarball t)
    (unless (zerop (call-process "tar" nil nil nil "-xzf" tarball "-C" dir))
      (user-error "tar failed on %s" tarball))
    (delete-file tarball)
    (message "js-debug installed: %s"
             (file-name-concat dir "js-debug" "src" "dapDebugServer.js"))))


;;
;;; What it all adds up to

;;;###autoload
(defun +web-summary ()
  "One line saying what this project is built with, for the panel."
  (if (not (+web-project-p))
      "not a node project"
    (let* ((manifest (+web-manifest))
           (deps (append (alist-get 'dependencies manifest)
                         (alist-get 'devDependencies manifest))))
      (string-join
       (delq nil
             (list (+web-manager)
                   (when (assq 'svelte deps) "svelte")
                   (when (assq '@sveltejs/kit deps) "sveltekit")
                   (when (assq 'vite deps) "vite")
                   (when (assq 'tailwindcss deps) "tailwind")
                   (when (assq 'typescript deps) "typescript")
                   (when (+web-electron-p) "electron")
                   (format "%d scripts" (length (+web-scripts)))))
       ", "))))

;;;###autoload
(defun +web/project-status ()
  "Say what is installed and what this project is."
  (interactive)
  (message
   "%s"
   (string-join
    (delq nil
          (list (format "node:      %s" (or (executable-find "node") "MISSING"))
                (format "yarn:      %s" (or (executable-find "yarn") "MISSING"))
                (format "typescript-language-server: %s"
                        (or (executable-find "typescript-language-server") "MISSING"))
                (format "svelteserver: %s"
                        (or (executable-find "svelteserver") "MISSING"))
                (format "prettier:  %s" (or (executable-find "prettier") "MISSING"))
                (when (+web-project-p)
                  (format "this one:  %s" (+web-summary)))
                (when (+web-project-p)
                  (format "installed: %s"
                          (if (file-directory-p
                               (expand-file-name "node_modules" (+web-root)))
                              "yes" "no, SPC k m i")))))
    "\n")))
