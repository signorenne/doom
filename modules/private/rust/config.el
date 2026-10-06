;;; private/rust/config.el -*- lexical-binding: t; -*-
;;
;; Rust, on the keys the rest of the config uses. Doom's :lang rust
;; brings the mode, rustic and rust-analyzer; this module adds what a
;; build here depends on, which is the profile, the features, the
;; workspace member and the target, and puts building, running,
;; debugging and starting a project on SPC k, where C++ has them.

(defvar +rust-docs
  '(:groups (("rust" "Rust" (rust rustic) rustic-mode-map))
    :sections ((rustic-mode . "Rust")))
  "How the cheat sheet documents this module; see `+docs--module-docs'.")

(defvar +rust-templates-dir
  (file-name-concat doom-user-dir "templates/rust/")
  "Project templates, one directory per kind: bin, lib, workspace.")

(defvar +rust-modes '(rust-mode rust-ts-mode rustic-mode)
  "The modes a Rust file opens in, whichever of them is in charge.")

(declare-function +core-register-builder "build")
(declare-function projection-type "projection-types")


;;
;;; The build

;; projection ships a cargo type whose commands are the bare
;; `cargo build' and `cargo test'. This one asks the project what it is
;; set to first, so SPC k b, SPC k t and SPC k i carry the profile, the
;; features, the member and the target, and the panel's header shows the
;; line they will run.
(after! projection-types
  (defvar projection-project-type-cargo-kit
    (projection-type
     :name 'rust-cargo
     :predicate "Cargo.toml"
     :build   #'+rust-build-command
     :test    #'+rust-test-command
     :install #'+rust-install-command
     :run     #'+rust/run
     :src-dir "src"
     :test-prefix "test_")
    "projection type for cargo projects, built with what the project is set to.")

  ;; Replaced by name, so a rename upstream still leaves one cargo type.
  (setq projection-project-types
        (cons projection-project-type-cargo-kit
              (seq-remove (lambda (type) (eq (oref type name) 'rust-cargo))
                          projection-project-types))))

;; SPC k r, SPC k d, SPC k m and SPC k n in a cargo project are this
;; module's; everywhere else they stay cpp's.
(+core-register-builder 'rust #'+rust-project-p
                        :run #'+rust/run
                        :debug #'+rust/debug
                        :panel #'+rust/menu
                        :new #'+rust/new-project
                        :label "Rust")


;;
;;; The server

;; rust-analyzer does the work clippy would, on every save, and answers
;; with the same diagnostics: one process instead of two, and no wait
;; after a save. The rest is what makes a large crate bearable.
(after! eglot
  (setq-default eglot-workspace-configuration
                (append
                 (bound-and-true-p eglot-workspace-configuration)
                 '((:rust-analyzer
                    . (:check (:command "clippy"
                               :extraArgs ["--all-targets"])
                       :cargo (:buildScripts (:enable t)
                               :features "all")
                       :procMacro (:enable t)
                       :inlayHints (:closingBraceHints (:enable :json-false))
                       :completion (:callable (:snippets "fill_arguments"))))))))


;;
;;; Formatting

;; rustfmt is not a choice anyone makes per project, the way a
;; .clang-format is: every crate is formatted the same way, so this
;; formats on save without asking whether the project has a file.
(after! apheleia
  (dolist (mode +rust-modes)
    (setf (alist-get mode apheleia-mode-alist) 'rustfmt)))

(dolist (mode +rust-modes)
  (add-hook (intern (format "%s-hook" mode))
            (defun +rust--format-on-save-h ()
              "Format a Rust buffer when it is saved."
              (when (fboundp 'apheleia-mode) (apheleia-mode +1)))))


;;
;;; Debugging

;; codelldb rather than gdb: it knows Rust's enums, its strings and its
;; slices, and prints them as the language writes them. SPC k l i in the
;; cpp module downloads it.
(after! dape
  (add-to-list 'dape-configs
               `(codelldb-rust
                 modes ,+rust-modes
                 ensure ,(lambda (config)
                           (unless (dape-config-get config 'command)
                             (user-error "codelldb is not installed: M-x +cpp/install-codelldb")))
                 command ,(expand-file-name
                           "debug-adapters/codelldb/extension/adapter/codelldb"
                           doom-user-dir)
                 command-args ("--port" :autoport)
                 port :autoport
                 :type "lldb"
                 :request "launch"
                 :cwd "."
                 :program +rust--debug-program
                 :sourceLanguages ["rust"])))


;;
;;; Keybindings

;; The build keys are SPC k, shared: b, t, i, r, d, m and n all work
;; here through the dispatcher and projection. These are the ones only
;; Rust has.
(map! :after rustic
      :map rustic-mode-map
      :localleader
      (:prefix ("k" . "cargo")
       :desc "Check, the fast one"  "c" #'+rust/check
       :desc "Clippy"               "l" #'+rust/clippy
       :desc "Clippy, fixing"       "L" #'+rust/clippy-fix
       :desc "Test at point"        "u" #'+rust/test-at-point
       :desc "Expand the macros"    "e" #'+rust/expand
       :desc "Documentation"        "d" #'+rust/doc
       :desc "Cargo.toml"           "v" #'+rust/open-cargo-toml))
