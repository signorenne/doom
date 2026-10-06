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


;;
;;; The servers

;; eglot already knows typescript-language-server for js and ts, the
;; css server for css, and the html server for html. Svelte is ours, and
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

  (add-to-list 'eglot-server-programs
               `((css-mode css-ts-mode scss-mode less-css-mode)
                 . ,(lambda (&rest _)
                      (if (and (+web-tailwind-p)
                               (executable-find "tailwindcss-language-server"))
                          '("tailwindcss-language-server" "--stdio")
                        '("vscode-css-language-server" "--stdio"))))))

;; Doom starts a server with `lsp!' on the local variables hook; svelte
;; is not one of its modes, so it is added here the same way.
(when (modulep! :tools lsp)
  (add-hook! 'svelte-mode-local-vars-hook
    (defun +web--lsp-h ()
      "Start the Svelte server when there is one to start."
      (when (executable-find "svelteserver") (lsp!)))))

;; :lang web starts one in XML buffers too, SVG among them, but eglot
;; knows no server for XML and none is installed: every SVG opened
;; printed eglot's failure, processp nil, in the echo area.
(remove-hook 'nxml-mode-local-vars-hook #'lsp!)


;;
;;; The project's own tools before the global ones

;; A project pins its typescript, its prettier and its eslint, and those
;; are the versions its code is written against: node_modules/.bin goes
;; on `exec-path' for the buffer, so a formatter run here is the one the
;; project would run in CI, not whatever is newest on this machine.
(use-package! add-node-modules-path
  :defer t
  :init
  (dolist (mode +web-modes)
    (add-hook (intern (format "%s-hook" mode)) #'add-node-modules-path)))


;;
;;; Formatting

;; apheleia knows prettier for css, html, js, json and typescript
;; already. Svelte needs the plugin the project installs, which is why
;; this goes through the project's own prettier and not a global one.
(after! apheleia
  (setf (alist-get 'prettier-svelte apheleia-formatters)
        '("prettier" "--stdin-filepath" filepath))
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
(after! emmet-mode
  (add-hook 'svelte-mode-hook #'emmet-mode)
  (add-hook 'tsx-ts-mode-hook #'emmet-mode))


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
                        :label "Web")


;;
;;; Debugging

;; node's own inspector, which dape speaks: the main process of an
;; Electron application is node, so the two differ only in what is
;; started.
(after! dape
  (add-to-list 'dape-configs
               `(node-project
                 modes ,+web-modes
                 ensure dape-ensure-command
                 command "node"
                 command-args ("--inspect-brk=:autoport" :program)
                 port :autoport
                 :type "node"
                 :request "launch"
                 :cwd "."
                 :program (lambda () (read-file-name "Run: " nil nil t))))
  (add-to-list 'dape-configs
               `(electron-main
                 modes ,+web-modes
                 ensure dape-ensure-command
                 command "node"
                 command-args ("--inspect-brk=:autoport"
                               "node_modules/electron/cli.js" ".")
                 port :autoport
                 :type "node"
                 :request "launch"
                 :cwd ".")))


;;
;;; Keybindings

;; The build keys are SPC k, shared: b, t, r, d, m and n all work here
;; through the dispatcher and projection. These are the ones only a node
;; project has.
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
