;;; private/web/autoload/menu.el -*- lexical-binding: t; -*-
;;
;; The panel, on SPC k m like the others: what this project is built
;; with, and the command the build keys would run.

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
    ("P" "Package it"         +web/package)
    ("d" "Debug the main process" +web/debug)]
   ["Start"
    ("n" "New project"        +web/new-project)]])
