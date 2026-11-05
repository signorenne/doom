;;; private/rust/autoload/menu.el -*- lexical-binding: t; -*-
;;
;; Two menus, as in C++. SPC k SPC is what you do: every key SPC k has
;; in a cargo project, with the same label. SPC k m is the panel: what a
;; cargo build depends on and the files behind it, the same shape as the
;; CMake panel, so SPC k m means the same thing in a Rust buffer as in a
;; C++ one.

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
          (propertize (condition-case err (+rust-build-command)
                        (error (error-message-string err)))
                      'face 'font-lock-comment-face)))

;;;###autoload (autoload '+rust/kit-menu "private/rust/autoload/menu" nil t)
(transient-define-prefix +rust/kit-menu ()
  "What a cargo project can do: build, run, check, and the tools."
  [:description +rust--menu-description
   ["Build"
    ("b" "Build"              +rust/build)
    ("x" "Build, then run"    +core/build-and-run)
    ("c" "Check, the fast one" +rust/check)
    ("t" "Test"               +rust/test)
    ("u" "Test at point"      +rust/test-at-point)
    ("B" "Benchmarks"         +rust/bench)
    ("i" "Install"            projection-commands-install-project)
    ("C" "Clean"              +rust/clean)]
   ["Run"
    ("r" "Run"                +rust/run)
    ("R" "Run with arguments" +rust/run-with-args)
    ("d" "Debug"              +rust/debug)
    ("<f9>" "Breakpoint here" dape-breakpoint-toggle)]
   ["Fix"
    ("l" "Clippy"             +rust/clippy)
    ("L" "Clippy, fixing"     +rust/clippy-fix)
    ("e" "Expand the macros"  +rust/expand)
    ("U" "Update the lock file" +rust/update)]
   ["Build with"
    ("y" "Profile"            +rust/set-profile)
    ("Y" "Dev against release" +rust/toggle-profile)
    ("f" "Features"           +rust/set-features)
    ("F" "No default features" +rust/set-no-default-features)
    ("p" "Workspace member"   +rust/set-member)
    ("T" "Target triple"      +rust/set-target)
    ("a" "Run arguments, kept" +rust/set-run-args)]
   ["Files and status"
    ("m" "The panel: what is set" +rust/menu)
    ("I" "Project status"     +rust/project-status)
    ("v" "Cargo.toml"         +rust/open-cargo-toml)
    ("D" "Documentation"      +rust/doc)
    ("n" "New project"        +core/new-project)]])

;;;###autoload (autoload '+rust/menu "private/rust/autoload/menu" nil t)
(transient-define-prefix +rust/menu ()
  "What a cargo build depends on, and the files behind it.
A setter keeps the panel open, so the header shows what it did."
  [:description +rust--menu-description
   ["Build with"
    ("y" "Profile"            +rust/set-profile :transient t)
    ("Y" "Dev against release" +rust/toggle-profile :transient t)
    ("f" "Features"           +rust/set-features :transient t)
    ("F" "No default features" +rust/set-no-default-features :transient t)
    ("p" "Workspace member"   +rust/set-member :transient t)
    ("T" "Target triple"      +rust/set-target :transient t)
    ("a" "Run arguments, kept" +rust/set-run-args :transient t)]
   ["Do"
    ("b" "Build"              +rust/build)
    ("r" "Run"                +rust/run)
    ("R" "Run with arguments" +rust/run-with-args)
    ("c" "Check, the fast one" +rust/check)
    ("l" "Clippy"             +rust/clippy)
    ("L" "Clippy, fixing"     +rust/clippy-fix)
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
