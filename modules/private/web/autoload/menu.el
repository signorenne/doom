;;; private/web/autoload/menu.el -*- lexical-binding: t; -*-
;;
;; Two menus, as in C++. SPC k SPC is what you do: every key SPC k has
;; in a node project, with the same label. SPC k m is the panel, like the
;; others: what this project is built with, and the command the build
;; keys would run.

(require 'transient)

(declare-function +web-summary "web")
(declare-function +web-dev-command "web")
(declare-function +web-electron-p "web")
(declare-function +web-project-p "web")

(defun +web--menu-description ()
  "The header: what the project is, and what SPC k r would run."
  (concat (propertize "node" 'face 'transient-heading)
          "  "
          (propertize (+web-summary) 'face 'font-lock-doc-face)
          "\n"
          (propertize (condition-case err (+web-dev-command)
                        (error (error-message-string err)))
                      'face 'font-lock-comment-face)))

;;;###autoload (autoload '+web/kit-menu "private/web/autoload/menu" nil t)
(transient-define-prefix +web/kit-menu ()
  "What a node project can do: run, build, test, and its dependencies."
  [:description +web--menu-description
   ["Run"
    ("r" "Dev server"         +web/dev)
    ("R" "Run with arguments" +web/run-with-args)
    ("x" "Build, then run"    +core/build-and-run)
    ("v" "Preview the build"  +web/preview)
    ("s" "Any script"         +web/run-script)
    ("d" "Debug"              +web/debug)
    ("<f9>" "Breakpoint here" dape-breakpoint-toggle)]
   ["Build and check"
    ("b" "Build"              +web/build)
    ("t" "Test"               +web/test)
    ("T" "Test, and keep watching" +web/test-watch)
    ("l" "Lint"               +web/lint)
    ("c" "Types, without building" +web/check)]
   ["Dependencies"
    ("i" "Install"            +web/install)
    ("o" "What has moved on"  +web/outdated)
    ("M" "Package manager"    +web/set-manager)
    ("p" "package.json"       +web/open-manifest)
    ("P" "Package the Electron app" +web/package :if +web-electron-p)]
   ["Files and status"
    ("m" "The panel: what is set" +web/menu)
    ("I" "Project status"     +web/project-status)
    ("n" "New project"        +core/new-project)]])

;;;###autoload (autoload '+web/menu "private/web/autoload/menu" nil t)
(transient-define-prefix +web/menu ()
  "What this node project is built with, and what it can be told to do."
  [:description +web--menu-description
   ["Run"
    ("r" "Dev server"         +web/dev)
    ("b" "Build"              +web/build)
    ("v" "Preview the build"  +web/preview)
    ("t" "Test"               +web/test)
    ("T" "Test, and keep watching" +web/test-watch)
    ("s" "Any script"         +web/run-script)]
   ["Check"
    ("l" "Lint"               +web/lint)
    ("c" "Types, without building" +web/check)
    ("I" "Project status"     +web/project-status)]
   ["Dependencies"
    ("i" "Install"            +web/install)
    ("o" "What has moved on"  +web/outdated)
    ("m" "Package manager"    +web/set-manager :transient t)
    ("p" "package.json"       +web/open-manifest)]
   ["Application"
    :if +web-electron-p
    ("P" "Package the Electron app" +web/package)
    ("d" "Debug"              +web/debug)]
   ["Start"
    ("n" "New project"        +web/new-project)]])
