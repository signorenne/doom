;;; private/cpp/autoload/shim.el -*- lexical-binding: t; -*-
;;
;; Every call into a private function of projection, dape or jsonrpc, in
;; one place, with the version it was read from. An upgrade that renames
;; one breaks here and nowhere else.
;;
;;   projection  898c6fc, 2026-06-14
;;   dape        0.25.0
;;   jsonrpc     the one in Emacs 31.1

(defvar dape-configs)
(declare-function projection--current-project "projection-core-misc")
(declare-function projection--cache-get "projection-core-cache")
(declare-function projection--cache-put "projection-core-cache")
(declare-function projection-cmake--list-presets2 "projection-type-cmake")
(declare-function projection-cmake--available-preset-files "projection-type-cmake")
(declare-function projection-cmake--preset-cache-var "projection-type-cmake")
(declare-function projection-cmake--build-directory "projection-type-cmake")
(declare-function projection-cmake--active-build-type "projection-type-cmake")
(declare-function projection-cmake--command "projection-type-cmake")
(declare-function projection-cmake--file-api-create-query-file "projection-type-cmake")
(declare-function projection-artifacts--all-artifacts "projection-artifacts")
(declare-function projection-commands--get-command "projection-commands")
(declare-function projection-project-types "projection-core-type")
(declare-function dape--config-eval "dape")
(declare-function dape--live-connection "dape")
(declare-function jsonrpc--process "jsonrpc")


;;
;;; projection

;;;###autoload
(defun +cpp--projection-project (&optional no-error)
  "The projection project of `default-directory'; nil with NO-ERROR."
  (require 'projection)
  (projection--current-project no-error))

;;;###autoload
(defun +cpp--projection-cache-get (project key)
  "What projection remembers under KEY for PROJECT."
  (require 'projection)
  (projection--cache-get project key))

;;;###autoload
(defun +cpp--projection-cache-put (project key value)
  "Remember VALUE under KEY for PROJECT in projection's cache."
  (require 'projection)
  (projection--cache-put project key value))

;;;###autoload
(defun +cpp--projection-presets (root)
  "The configure presets of ROOT as projection reads them, raw: hidden
presets included, which `inherits' needs.  Nil without preset files."
  (require 'projection)
  (require 'projection-type-cmake)
  (let ((default-directory root))
    (when (or (file-exists-p (expand-file-name "CMakePresets.json" root))
              (file-exists-p (expand-file-name "CMakeUserPresets.json" root)))
      (ignore-errors
        (alist-get 'configure
                   (projection-cmake--list-presets2
                    (projection-cmake--available-preset-files)))))))

;;;###autoload
(defun +cpp--projection-preset-cache-var (build-type)
  "The cache key under which projection keeps the BUILD-TYPE preset."
  (require 'projection-type-cmake)
  (projection-cmake--preset-cache-var build-type))

;;;###autoload
(defun +cpp--projection-build-directory (&optional expand)
  "projection's build directory for the project, absolute with EXPAND."
  (require 'projection-type-cmake)
  (projection-cmake--build-directory expand))

;;;###autoload
(defun +cpp--projection-build-type ()
  "The build type projection would configure with, or nil."
  (require 'projection-type-cmake)
  (ignore-errors (projection-cmake--active-build-type)))

;;;###autoload
(defun +cpp--projection-cmake-command (build-type &optional target)
  "projection's cmake command for BUILD-TYPE, building TARGET when given."
  (require 'projection-type-cmake)
  (projection-cmake--command build-type target))

;;;###autoload
(defun +cpp--projection-write-file-api-query ()
  "Write the file API query into projection's build directory, quietly."
  (require 'projection-type-cmake)
  (ignore-errors (projection-cmake--file-api-create-query-file)))

;;;###autoload
(defun +cpp--projection-generic-command (root build-type)
  "The BUILD-TYPE command projection derives for ROOT from its first
project type, uncached, or nil when it knows no type there."
  (require 'projection)
  (require 'projection-commands)
  (let ((default-directory root))
    (when-let* ((type (car (projection-project-types root))))
      (projection-commands--get-command
       (projection--current-project) type build-type nil :use-cache nil))))

;;;###autoload
(defun +cpp--projection-artifacts (project)
  "Every artifact projection knows for PROJECT, or nil."
  (require 'projection)
  (require 'projection-artifacts)
  (condition-case nil
      (projection-artifacts--all-artifacts project)
    (error nil)))


;;
;;; dape and jsonrpc

;;;###autoload
(defun +cpp--dape-config (name)
  "The dape configuration called NAME, evaluated for this buffer."
  (require 'dape)
  (dape--config-eval name (alist-get name dape-configs)))

;;;###autoload
(defun +cpp--dape-stopped-p ()
  "Non-nil when a debug session is stopped at a breakpoint."
  (require 'dape)
  (dape--live-connection 'stopped t))

;;;###autoload
(defun +cpp--server-process (server)
  "The process behind the eglot SERVER."
  (jsonrpc--process server))
