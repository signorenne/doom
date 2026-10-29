;;; private/web/config.el -*- lexical-binding: t; -*-
;;
;; The web side: HTML, CSS, TypeScript, Svelte and SvelteKit, and the
;; node project around them. Doom's :lang web and :lang javascript bring
;; the modes and eglot brings the servers for most of them; this module
;; adds Svelte, Tailwind, the project's own tools in place of the global
;; ones, and puts the dev server, the build and the tests on SPC k,
;; where C++, Rust and Pascal have them.

(defvar +web-docs
  '(:groups (("web" "Web" (svelte-mode web-mode typescript-ts-mode)
              svelte-mode-map)))
  "How the cheat sheet documents this module; see `+docs--module-docs'.")

(defvar +web-templates-dir
  (file-name-concat doom-user-dir "templates/web/")
  "Project templates, one directory per kind; see `+web-project-kinds'.")

(defvar +web-modes
  '(svelte-mode web-mode html-mode html-ts-mode mhtml-mode
    css-mode css-ts-mode scss-mode
    js-mode js-ts-mode typescript-mode typescript-ts-mode tsx-ts-mode
    json-mode json-ts-mode)
  "Every mode this module answers for.")

(declare-function +core-register-builder "build")
(declare-function projection-type "projection-types")


;;
;;; Svelte

;; Doom has no Svelte module and Emacs no mode: a .svelte file is a
;; template with a <script> and a <style> in it, which svelte-mode
;; handles as one thing rather than three.
(use-package! svelte-mode
  :mode "\\.svelte\\'"
  :config
  (setq svelte-basic-offset 2
        ;; The tag names Svelte adds to HTML's, so they indent and close
        ;; like any other rather than being unknown.
        svelte-display-submode-name t))


;; In front of web-mode, which Doom's :lang web gives .svelte too: the
;; :mode above finds svelte-mode's own entry already in the list and
;; moves nothing, so web-mode would win.
(setq auto-mode-alist
      (cons '("\\.svelte\\'" . svelte-mode)
            (seq-remove (lambda (entry) (equal (car entry) "\\.svelte\\'"))
                        auto-mode-alist)))


;;
;;; The servers

;; eglot already knows the css server for css and the html server for
;; html. JavaScript and TypeScript are ours, for TypeScript 7, Svelte, and
;; so is Tailwind: in a project that uses it the plain css server reads
;; `@tailwind base' as an error, and the Tailwind server is a superset
;; that understands it and completes classes besides.
;;
;; One server manages a buffer under eglot, so Tailwind takes the CSS
;; family in a Tailwind project and nothing else: in markup the file's
;; own server stays, and there is no Tailwind class completion there.
;; That is eglot's limit, not a setting.
(after! eglot
  (add-to-list 'eglot-server-programs
               '(svelte-mode . ("svelteserver" "--stdio")))

  ;; See `+web-typescript-server'; the language ids are eglot's.
  (add-to-list 'eglot-server-programs
               '(((js-mode :language-id "javascript")
                  (js-ts-mode :language-id "javascript")
                  (tsx-ts-mode :language-id "typescriptreact")
                  (typescript-ts-mode :language-id "typescript")
                  (typescript-mode :language-id "typescript"))
                 . +web-typescript-server))
  ;; json-mode descends from js-mode, so the entry above would take JSON
  ;; too; eglot's own JSON entry goes back in front of it.
  (when-let* ((json (seq-find (lambda (entry)
                                (and (listp (car entry)) (memq 'json-mode (car entry))))
                              eglot-server-programs)))
    (setq eglot-server-programs (cons json (delq json eglot-server-programs))))

  (add-to-list 'eglot-server-programs
               `((css-mode css-ts-mode scss-mode less-css-mode)
                 . ,(lambda (&rest _)
                      (if (and (+web-tailwind-p)
                               (executable-find "tailwindcss-language-server"))
                          '("tailwindcss-language-server" "--stdio")
                        '("vscode-css-language-server" "--stdio"))))))

;; Doom starts a server with `lsp!' on the local variables hook; svelte
;; is not one of its modes, so it is added the same way.
(when (modulep! :tools lsp)
  (add-hook! 'svelte-mode-local-vars-hook
    (defun +web--lsp-h ()
      "Start the Svelte server when there is one to start."
      (when (executable-find "svelteserver") (lsp!)))))

;; :lang web starts one in XML buffers too, SVG among them, but eglot
;; knows no server for XML, so each would only print a failure.
(remove-hook 'nxml-mode-local-vars-hook #'lsp!)


;;
;;; The project's own tools before the global ones

;; A project pins its typescript, its prettier and its eslint, and those
;; are the versions its code is written against: node_modules/.bin goes
;; on `exec-path' for the buffer, so a formatter run is the one the
;; project would run in CI, not whatever is installed globally. Found on
;; disk, not through `npm bin', which npm no longer has.
(dolist (mode +web-modes)
  (add-hook (intern (format "%s-hook" mode))
            (defun +web--node-modules-path-h ()
              "Put the project's node_modules/.bin in front of this
buffer's `exec-path'."
              (when-let* ((dir (locate-dominating-file default-directory "node_modules/.bin")))
                (setq-local exec-path
                            (cons (expand-file-name "node_modules/.bin" dir)
                                  exec-path))))))


;;
;;; Formatting

;; apheleia knows prettier for css, html, js, json and typescript
;; already. Svelte needs the plugin the project installs, which is why
;; this goes through the project's own prettier and not a global one.
(after! apheleia
  ;; apheleia-npx, as apheleia's own prettiers: the project's, from its
  ;; node_modules, which `exec-path' alone does not hand the process.
  (setf (alist-get 'prettier-svelte apheleia-formatters)
        '("apheleia-npx" "prettier" "--stdin-filepath" filepath))
  (setf (alist-get 'svelte-mode apheleia-mode-alist) 'prettier-svelte))

(dolist (mode +web-modes)
  (add-hook (intern (format "%s-hook" mode))
            (defun +web--format-on-save-h ()
              "Format with prettier on save, where a prettier is to be had."
              (when (and (fboundp 'apheleia-mode)
                         (or (executable-find "prettier")
                             (+web-project-p)))
                (apheleia-mode +1)))))


;;
;;; Emmet

;; An abbreviation expands into the tags it stands for: div.card>p*3
;; becomes the markup. Doom turns it on for html and css; Svelte and TSX
;; are markup too.
;; At the top level, since emmet-mode is autoloaded: inside `after!' the
;; hooks would wait for something else to load it first.
(add-hook 'svelte-mode-hook #'emmet-mode)
(add-hook 'tsx-ts-mode-hook #'emmet-mode)


;;
;;; The build

;; projection has a npm type whose commands are the bare `npm run'.
;; This one asks the project which manager wrote its lock file and what
;; its scripts are called, so SPC k b and SPC k t run what the project
;; would run.
(after! projection-types
  (defvar projection-project-type-node
    (projection-type
     :name 'node
     :predicate "package.json"
     :build #'+web-build-command
     :test  #'+web-test-command
     :run   #'+web/dev
     :src-dir "src")
    "projection type for node projects, built with the project's own manager.")

  (setq projection-project-types
        (cons projection-project-type-node
              (seq-remove (lambda (type) (memq (oref type name) '(node npm)))
                          projection-project-types))))

;; SPC k r, SPC k d, SPC k m and SPC k n in a node project are this
;; module's.
(+core-register-builder 'web #'+web-project-p
                        :run #'+web/dev
                        :debug #'+web/debug
                        :panel #'+web/menu
                        :new #'+web/new-project
                        :label "Web"
                        :keys '+web-kit-map)


;;
;;; Debugging

;; js-debug, the adapter VS Code debugs node and Electron with; node's
;; own --inspect speaks Chrome's protocol, which dape does not. M-x
;; +web/install-js-debug puts it where dape keeps adapters. Electron's
;; main process is node, run by the electron binary of the project.
(after! dape
  (let ((adapter
         `(modes ,+web-modes
           ensure ,(lambda (config)
                     (dape-ensure-command config)
                     (unless (file-exists-p (car (plist-get config 'command-args)))
                       (user-error "js-debug is not installed: M-x +web/install-js-debug")))
           command "node"
           command-args (,(file-name-concat dape-adapter-dir "js-debug" "src" "dapDebugServer.js")
                         :autoport)
           port :autoport
           :type "pwa-node"
           :request "launch"
           :console "internalConsole")))
    (add-to-list 'dape-configs
                 `(node-project
                   ,@adapter
                   :cwd "."
                   :program (lambda () (read-file-name "Run: " nil nil t))))
    (add-to-list 'dape-configs
                 `(electron-main
                   ,@adapter
                   :cwd "."
                   :runtimeExecutable "node_modules/.bin/electron"
                   :args ["."]
                   :outputCapture "std"))))


;;
;;; Keybindings

;; SPC k in a node project: the panel's keys, on the letters SPC k has
;; in every project, b build, r run, t test, d debug, m the panel. The
;; panel's m, the package manager, is M here.
(declare-function +core-kit-keymap "build")
(defvar +web-kit-map
  (+core-kit-keymap
   '(("m" "The panel: what is set"   #'+web/menu)
     ("r" "Dev server"               #'+web/dev)
     ("b" "Build"                    #'+web/build)
     ("v" "Preview the build"        #'+web/preview)
     ("t" "Test"                     #'+web/test)
     ("T" "Test, and keep watching"  #'+web/test-watch)
     ("s" "Any script"               #'+web/run-script)
     ("l" "Lint"                     #'+web/lint)
     ("c" "Types, without building"  #'+web/check)
     ("i" "Install"                  #'+web/install)
     ("o" "What has moved on"        #'+web/outdated)
     ("M" "Package manager"          #'+web/set-manager)
     ("p" "package.json"             #'+web/open-manifest)
     ("P" "Package the Electron app" #'+web/package)
     ("d" "Debug"                    #'+web/debug)
     ("I" "Project status"           #'+web/project-status)
     ("n" "New project"              #'+core/new-project)))
  "SPC k in a node project.")

;; The most used of them, also on the localleader.
(map! :after svelte-mode
      :map svelte-mode-map
      :localleader
      (:prefix ("k" . "node")
       :desc "Dev server"          "r" #'+web/dev
       :desc "Preview the build"   "v" #'+web/preview
       :desc "Any script"          "s" #'+web/run-script
       :desc "Lint"                "l" #'+web/lint
       :desc "Types, without building" "c" #'+web/check
       :desc "Install"             "i" #'+web/install
       :desc "package.json"        "p" #'+web/open-manifest))
