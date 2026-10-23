;;; private/core/+data.el -*- lexical-binding: t; -*-
;;
;; The data and configuration formats: JSON, YAML, TOML, XML and the
;; plainer ones. Doom's :lang json, :lang yaml and :lang data bring the
;; modes; this file adds the part that says whether a file is actually
;; valid, and the two shapes you usually want it in.
;;
;; Validation comes from a language server where one exists, so a bad
;; comma is underlined as you type. The servers also know SchemaStore,
;; so a file they recognise (package.json, a compose file, a GitHub
;; workflow) is checked against its schema and a misspelt key is an
;; error.


;;
;;; TOML

;; Doom has no :lang toml. Emacs has `toml-ts-mode' and
;; `conf-toml-mode' already; what is missing is the file association and
;; a server.
(add-to-list 'auto-mode-alist
             `("\\.toml\\'" . ,(if (fboundp 'toml-ts-mode)
                                  'toml-ts-mode
                                'conf-toml-mode)))
(add-to-list 'auto-mode-alist '("Cargo\\.lock\\'" . conf-toml-mode))


;;
;;; The servers

;; taplo for TOML, and the JSON and YAML servers Doom starts through
;; :lang json +lsp and :lang yaml +lsp. Each is asked for by name, so a
;; missing one leaves the mode working without validation rather than
;; erroring on every file.
(after! eglot
  (add-to-list 'eglot-server-programs
               '((conf-toml-mode toml-ts-mode) . ("taplo" "lsp" "stdio")))

  ;; The YAML server fetches SchemaStore's catalog itself once told it
  ;; may. The JSON server does not: `+data-schemas-setup-h' keeps a
  ;; cached copy fresh and `+data--json-schemas-h' hands it over, since
  ;; without it a JSON file is only checked for syntax and "name": 123 in
  ;; a package.json passes. Only small settings go in here: every server
  ;; is sent all of this when it starts.
  (setq-default eglot-workspace-configuration
                (append '((:yaml . (:schemaStore (:enable t)
                                    :validate t
                                    :hover t
                                    :completion t))
                          (:json . (:validate (:enable t))))
                        (assq-delete-all
                         :json (assq-delete-all
                                :yaml (copy-alist
                                       (bound-and-true-p eglot-workspace-configuration))))))
  (add-hook 'eglot-managed-mode-hook #'+data--json-schemas-h)
  (+data-schemas-setup-h))

(when (modulep! :tools lsp)
  (add-hook! '(conf-toml-mode-hook toml-ts-mode-hook)
    (defun +data--toml-lsp-h ()
      "Start taplo when there is one to start."
      (when (executable-find "taplo") (lsp!)))))


;;
;;; Keybindings

;; One set of keys across every format, so validating a YAML file is the
;; same gesture as validating a JSON one. Each waits for its own mode,
;; since none of these keymaps exists when this file is read.
(map! (:after json-mode
       :map json-mode-map
       :localleader
       :desc "Validate this file" "v" #'+data/validate
       :desc "Prettify"           "=" #'+data/prettify
       :desc "Compact"            "-" #'+data/compact
       :desc "What is this"       "?" #'+data/what-is-this)

      (:after json-ts-mode
       :map json-ts-mode-map
       :localleader
       :desc "Validate this file" "v" #'+data/validate
       :desc "Prettify"           "=" #'+data/prettify
       :desc "Compact"            "-" #'+data/compact
       :desc "What is this"       "?" #'+data/what-is-this)

      (:after yaml-mode
       :map yaml-mode-map
       :localleader
       :desc "Validate this file" "v" #'+data/validate
       :desc "Prettify"           "=" #'+data/prettify
       :desc "Compact"            "-" #'+data/compact
       :desc "What is this"       "?" #'+data/what-is-this)

      (:after yaml-ts-mode
       :map yaml-ts-mode-map
       :localleader
       :desc "Validate this file" "v" #'+data/validate
       :desc "Prettify"           "=" #'+data/prettify
       :desc "Compact"            "-" #'+data/compact
       :desc "What is this"       "?" #'+data/what-is-this)

      (:after toml-ts-mode
       :map toml-ts-mode-map
       :localleader
       :desc "Validate this file" "v" #'+data/validate
       :desc "Prettify"           "=" #'+data/prettify
       :desc "What is this"       "?" #'+data/what-is-this)

      (:after nxml-mode
       :map nxml-mode-map
       :localleader
       :desc "Validate this file" "v" #'+data/validate
       :desc "Prettify"           "=" #'+data/prettify
       :desc "Compact"            "-" #'+data/compact
       :desc "What is this"       "?" #'+data/what-is-this)

      (:after csv-mode
       :map csv-mode-map
       :localleader
       :desc "Validate this file" "v" #'+data/validate
       :desc "Align the columns"  "=" #'+data/prettify
       :desc "Unalign them"       "-" #'+data/compact
       :desc "What is this"       "?" #'+data/what-is-this)

      (:after conf-mode
       :map conf-mode-map
       :localleader
       :desc "Validate this file" "v" #'+data/validate
       :desc "What is this"       "?" #'+data/what-is-this))
