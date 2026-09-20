;;; private/pascal/autoload/menu.el -*- lexical-binding: t; -*-
;;
;; The panel, on SPC k m like the others: what a build here depends on
;; and the line it would run.

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
    ("a" "Run arguments"      +pascal/set-run-args :transient t
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
