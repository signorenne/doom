;;; private/notes/autoload/agenda.el -*- lexical-binding: t; -*-

(declare-function org-agenda "org-agenda")
(declare-function org-agenda-files "org")
(declare-function org-ql-find "org-ql-find")
(declare-function +notes--agenda-files-refresh-h "roam")

(defun +notes--agenda (key)
  "Open the custom agenda view KEY."
  (require 'org-agenda)
  (org-agenda nil key))

;;;###autoload
(defun +notes/dashboard ()
  "Today, habits and every open task grouped by state."
  (interactive)
  (+notes--agenda "x"))

;;;###autoload
(defun +notes/weekly-review ()
  "The week, plus waiting, projects and unscheduled tasks."
  (interactive)
  (+notes--agenda "w"))

;;;###autoload
(defun +notes/next-actions ()
  "Every NEXT task."
  (interactive)
  (+notes--agenda "n"))

;;;###autoload
(defun +notes/projects ()
  "Open actions of the active projects."
  (interactive)
  (+notes--agenda "p"))

;;;###autoload
(defun +notes/inbox ()
  "Tasks still sitting in the inbox."
  (interactive)
  (+notes--agenda "i"))

;;;###autoload
(defun +notes/query ()
  "Find a heading by an org-ql query: in this note, or from any other
buffer in the agenda files, the roam notes that hold a task among them.
org-ql-find alone refused every buffer that is not Org's."
  (interactive)
  (if (derived-mode-p 'org-mode 'org-agenda-mode)
      (call-interactively #'org-ql-find)
    ;; Org first: loading it sets the base list the refresh builds on.
    (require 'org-ql-find)
    (+notes--agenda-files-refresh-h)
    (org-ql-find (org-agenda-files))))
