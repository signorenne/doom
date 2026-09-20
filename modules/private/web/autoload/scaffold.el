;;; private/web/autoload/scaffold.el -*- lexical-binding: t; -*-
;;
;; A new node project. Where an official generator exists it does the
;; skeleton, because it is the one that knows what the framework looks
;; like this month; the house files go on top. Where there is none, the
;; whole thing is a template here.

(declare-function +core-copy-template "scaffold")
(declare-function +core-read-new-project "scaffold")
(declare-function +core-leave-dirvish "dired")
(declare-function +web-root "web")
(defvar +web-templates-dir)

(defvar +web-scaffold-timeout 900
  "Seconds a generator or an install may take before it is given up on.
A first install fetches a few hundred packages, which on a slow line is
minutes rather than seconds.")

;;;###autoload
(defun +web-project-kinds ()
  "The kinds of node project this module can start."
  '("sveltekit" "electron" "library" "static" "node"))

(defun +web--run (dir command &rest args)
  "Run COMMAND with ARGS in DIR, or raise what it said.
The output is the useful part when a generator refuses, so it is
carried out rather than left in a buffer nobody opens."
  (let ((default-directory (file-name-as-directory dir)))
    (with-temp-buffer
      (unless (zerop (or (apply #'call-process command nil t nil args) 1))
        (user-error "%s: %s" command
                    (string-trim
                     (replace-regexp-in-string
                      "[ \t\n]+" " "
                      (buffer-substring-no-properties
                       (max (point-min) (- (point-max) 600)) (point-max))))))
      t)))

(defun +web--sv-create (parent name &rest add)
  "Run the Svelte generator in PARENT for NAME with the ADD add-ons.
The name goes first, before the options: `--add\=' takes a list, and a
name after it is read as one more add-on and the project is never made.
Every add-on option is given too, since the generator prompts for any
it was not told, and a prompt in a batch call is a hang."
  (apply #'+web--run parent "npx" "--yes" "sv@latest" "create" name
         "--template" "minimal" "--types" "ts"
         "--no-dir-check" "--no-download-check"
         "--install" "yarn"
         (when add (cons "--add" add))))

(defun +web--yarn-add-dev (dir &rest packages)
  "Add PACKAGES to DIR as development dependencies."
  (apply #'+web--run dir "yarn" "add" "--dev" packages))

(defun +web--overlay (kind dir name)
  "Put the house files for KIND over the project in DIR, called NAME."
  (dolist (part (list "_base" kind))
    (let ((src (file-name-concat +web-templates-dir part)))
      (when (file-directory-p src)
        (+core-copy-template src dir name)))))

(defun +web--merge-scripts (dir scripts)
  "Add SCRIPTS, an alist of (NAME . COMMAND), to DIR's package.json.
Written through the parser rather than by hand: a manifest is JSON and
a generator may have changed its shape since this was written."
  (let ((file (expand-file-name "package.json" dir)))
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      (let* ((manifest (json-parse-buffer :object-type 'alist :array-type 'list))
             (existing (alist-get 'scripts manifest)))
        (pcase-dolist (`(,name . ,command) scripts)
          (setf (alist-get (intern name) existing nil nil #'eq) command))
        (setf (alist-get 'scripts manifest) existing)
        (erase-buffer)
        (insert (json-serialize manifest))
        ;; json-serialize writes one line; a manifest is read by people.
        (json-pretty-print-buffer)
        (goto-char (point-max))
        (unless (bolp) (insert "\n"))
        (write-region (point-min) (point-max) file nil 'quiet)))))

(defun +web--set-manifest-field (dir key value)
  "Set KEY to VALUE at the top of DIR's package.json.
Electron reads `main\=' there to find its own process; without it the app
cannot start at all, whatever the scripts say."
  (let ((file (expand-file-name "package.json" dir)))
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      (let ((manifest (json-parse-buffer :object-type 'alist :array-type 'list)))
        (setf (alist-get key manifest nil nil #'eq) value)
        (erase-buffer)
        (insert (json-serialize manifest))
        (json-pretty-print-buffer)
        (goto-char (point-max))
        (unless (bolp) (insert "\n"))
        (write-region (point-min) (point-max) file nil 'quiet)))))

(defun +web--spa-fallback (dir)
  "Tell the static adapter in DIR to write a fallback page.
Without one it refuses a route it cannot know ahead of time, and an
application gains those as soon as it has a URL with an id in it. The
generator writes the adapter call into vite.config.ts."
  (let ((file (expand-file-name "vite.config.ts" dir)))
    (when (file-exists-p file)
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (when (re-search-forward "adapter:[[:space:]]*adapter()" nil t)
          (replace-match "adapter: adapter({ fallback: 'index.html' })" t t)
          (write-region (point-min) (point-max) file nil 'quiet))))))

(defun +web--electron (dir name)
  "Turn the SvelteKit project in DIR into an Electron application."
  ;; The static adapter, so the build is files Electron can load from
  ;; disk: adapter-auto guesses a hosting platform, and there is none.
  (+web--yarn-add-dev dir "electron" "electron-builder" "concurrently"
                      "wait-on" "@sveltejs/adapter-static")
  (+web--overlay "electron" dir name)
  (+web--spa-fallback dir)
  (+web--set-manifest-field dir 'main "electron/main.cjs")
  (+web--merge-scripts
   dir
   '(("dev:app" . "concurrently -k \"vite dev --port 5173\" \"wait-on tcp:5173 && electron .\"")
     ("package" . "yarn build && electron-builder")
     ("package:linux" . "yarn build && electron-builder --linux")
     ("package:win" . "yarn build && electron-builder --win"))))

;;;###autoload
(defun +web/new-project (kind dir name)
  "Start node project NAME of KIND in DIR, and open it.
KIND is one of `+web-project-kinds': a SvelteKit application, the same
wrapped as an Electron desktop application, a library, a static page,
or a TypeScript program for node."
  (interactive
   (cons (completing-read "Kind: " (+web-project-kinds) nil t nil nil "sveltekit")
         (+core-read-new-project)))
  (unless (executable-find "node")
    (user-error "node is not installed"))
  (when (and (file-exists-p dir) (directory-files dir nil "^[^.]"))
    (unless (y-or-n-p (format "%s is not empty.  Continue? " dir))
      (user-error "Aborted")))
  (let ((parent (file-name-directory (directory-file-name dir)))
        (base (file-name-nondirectory (directory-file-name dir))))
    (message "Starting %s: the generator fetches as it goes, so this takes a minute" name)
    (pcase kind
      ("sveltekit"
       (+web--sv-create parent base
                        "prettier" "eslint" "vitest=usages:unit"
                        "tailwindcss=plugins:forms,typography"
                        "sveltekit-adapter=adapter:auto")
       (+web--overlay kind dir name))
      ("electron"
       (+web--sv-create parent base
                        "prettier" "eslint" "vitest=usages:unit"
                        "tailwindcss=plugins:forms,typography"
                        "sveltekit-adapter=adapter:static")
       (+web--electron dir name))
      ("library"
       (+web--run parent "npx" "--yes" "sv@latest" "create" base
                  "--template" "library" "--types" "ts"
                  "--no-dir-check" "--no-download-check" "--install" "yarn"
                  "--add" "prettier" "eslint" "vitest=usages:unit")
       (+web--overlay kind dir name))
      ((or "static" "node")
       (make-directory dir t)
       (+web--overlay kind dir name)
       (+web--run dir "yarn" "install"))
      (_ (user-error "No such kind: %s" kind))))
  (when (and (executable-find "git")
             (not (file-directory-p (expand-file-name ".git" dir)))
             (y-or-n-p "Initialise a git repository? "))
    (let ((default-directory dir))
      (call-process "git" nil nil nil "init" "-q")))
  ;; Made from a listing, the dirvish panes would stay standing round it.
  (+core-leave-dirvish)
  (find-file (or (seq-find #'file-exists-p
                           (list (expand-file-name "src/routes/+page.svelte" dir)
                                 (expand-file-name "src/index.ts" dir)
                                 (expand-file-name "src/lib/index.ts" dir)
                                 (expand-file-name "index.html" dir)
                                 (expand-file-name "package.json" dir)))
                 dir))
  (message "%s created: SPC k r starts the dev server, SPC k m is the panel" name))
