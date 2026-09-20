;;; private/rust/autoload/menu.el -*- lexical-binding: t; -*-
;;
;; The panel: what a cargo build here depends on, and the files behind
;; it. The same shape as the CMake panel, so SPC k m means the same
;; thing in a Rust buffer as in a C++ one.

(require 'transient)

(declare-function +rust-summary "rust")
(declare-function +rust-root "rust")
(declare-function +rust-build-command "rust")

(defun +rust--menu-description ()
  "The header: what is set, and what SPC k b would run."
  (concat (propertize "cargo" 'face 'transient-heading)
          "  "
          (propertize (+rust-summary) 'face 'font-lock-doc-face)
          "\n"
          (propertize (condition-case nil (+rust-build-command)
                        (error "no project here"))
                      'face 'font-lock-comment-face)))

;;;###autoload (autoload '+rust/menu "private/rust/autoload/menu" nil t)
(transient-define-prefix +rust/menu ()
  "What a cargo build depends on, and the files behind it.
A setter keeps the panel open, so the header shows what it did."
  [:description +rust--menu-description
   ["Build with"
    ("y" "Profile"            +rust/set-profile :transient t)
    ("Y" "dev against release" +rust/toggle-profile :transient t)
    ("f" "Features"           +rust/set-features :transient t)
    ("F" "No default features" +rust/set-no-default-features :transient t)
    ("p" "Workspace member"   +rust/set-member :transient t)
    ("T" "Target triple"      +rust/set-target :transient t)
    ("a" "Run arguments"      +rust/set-run-args :transient t)]
   ["Do"
    ("b" "Build"              +rust/build)
    ("r" "Run"                +rust/run)
    ("R" "Run with arguments" +rust/run-with-args)
    ("c" "Check, the fast one" +rust/check)
    ("l" "Clippy"             +rust/clippy)
    ("L" "Clippy, fixing what it can" +rust/clippy-fix)
    ("t" "Test"               +rust/test)
    ("u" "Test at point"      +rust/test-at-point)]
   ["And"
    ("d" "Documentation"      +rust/doc)
    ("B" "Benchmarks"         +rust/bench)
    ("e" "Expand the macros"  +rust/expand)
    ("C" "Clean"              +rust/clean)
    ("U" "Update the lock file" +rust/update)]
   ["Files and status"
    ("I" "Project status"     +rust/project-status)
    ("v" "Cargo.toml"         +rust/open-cargo-toml)
    ("n" "New project"        +rust/new-project)]])
