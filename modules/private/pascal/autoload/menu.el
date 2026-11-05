;;; private/pascal/autoload/menu.el -*- lexical-binding: t; -*-
;;
;; Two menus, as in C++. SPC k SPC is what you do: every key SPC k has
;; in a Pascal project, with the same label. SPC k m is the panel, like
;; the others: what a build depends on and the line it would run.

(require 'transient)

(declare-function +pascal-summary "pascal")
(declare-function +pascal-build-command "pascal")
(declare-function +pascal-project-kind "pascal")

(defun +pascal--menu-description ()
  "The header: what kind of project this is, what is set, what would run."
  (concat (propertize "pascal" 'face 'transient-heading)
          "  "
          (propertize (+pascal-summary) 'face 'font-lock-doc-face)
          "\n"
          (propertize (condition-case err (+pascal-build-command)
                        (error (error-message-string err)))
                      'face 'font-lock-comment-face)))

(defun +pascal--buildable-p ()
  "Non-nil when this project is one that builds here."
  (memq (+pascal-project-kind) '(lazarus fpc)))

;;;###autoload (autoload '+pascal/kit-menu "private/pascal/autoload/menu" nil t)
(transient-define-prefix +pascal/kit-menu ()
  "What a Pascal project can do: build, run, debug, and what it is set to."
  [:description +pascal--menu-description
   ["Build"
    :if +pascal--buildable-p
    ("b" "Build"              +pascal/build)
    ("x" "Build, then run"    +pascal/build-and-run)
    ("t" "Test"               +pascal/test)
    ("C" "Clean"              +pascal/clean)]
   ["Run"
    :if +pascal--buildable-p
    ("r" "Run"                +pascal/run)
    ("R" "Run with arguments" +pascal/run-with-args)
    ("d" "Debug"              +pascal/debug)
    ("<f9>" "Breakpoint here" dape-breakpoint-toggle)]
   ["Build with"
    :if +pascal--buildable-p
    ("y" "Build mode"         +pascal/set-build-mode)
    ("w" "Widget set"         +pascal/set-widgetset)
    ("T" "Target"             +pascal/set-target)
    ("s" "Which program"      +pascal/set-main)
    ("a" "Run arguments, kept" +pascal/set-run-args)]
   ["Files and status"
    ("m" "The panel: what is set" +pascal/menu)
    ("I" "Project status"     +pascal/project-status)
    ("v" "The project file"   +pascal/open-project-file)
    ("n" "New project"        +core/new-project)]])

;;;###autoload (autoload '+pascal/menu "private/pascal/autoload/menu" nil t)
(transient-define-prefix +pascal/menu ()
  "What a Pascal build depends on, and the files behind it."
  [:description +pascal--menu-description
   ["Build with"
    ("y" "Build mode"         +pascal/set-build-mode :transient t
     :if +pascal--buildable-p)
    ("w" "Widget set"         +pascal/set-widgetset :transient t
     :if +pascal--buildable-p)
    ("T" "Target"             +pascal/set-target :transient t
     :if +pascal--buildable-p)
    ("s" "Which program"      +pascal/set-main :transient t
     :if +pascal--buildable-p)
    ("a" "Run arguments, kept" +pascal/set-run-args :transient t
     :if +pascal--buildable-p)]
   ["Do"
    ("b" "Build"              +pascal/build :if +pascal--buildable-p)
    ("x" "Build, then run"    +pascal/build-and-run :if +pascal--buildable-p)
    ("r" "Run"                +pascal/run :if +pascal--buildable-p)
    ("R" "Run with arguments" +pascal/run-with-args :if +pascal--buildable-p)
    ("d" "Debug"              +pascal/debug :if +pascal--buildable-p)
    ("C" "Clean"              +pascal/clean :if +pascal--buildable-p)]
   ["Files and status"
    ("I" "Project status"     +pascal/project-status)
    ("v" "The project file"   +pascal/open-project-file)
    ("n" "New project"        +pascal/new-project)]])
