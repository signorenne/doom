;;; private/notes/autoload/agenda.el -*- lexical-binding: t; -*-

(declare-function org-agenda "org-agenda")

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
  "Every PROJ task."
  (interactive)
  (+notes--agenda "p"))

;;;###autoload
(defun +notes/inbox ()
  "Tasks still sitting in the inbox."
  (interactive)
  (+notes--agenda "i"))
