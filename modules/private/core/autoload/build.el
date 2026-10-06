;;; private/core/autoload/build.el -*- lexical-binding: t; -*-
;;
;; One set of keys for every language. SPC k b, SPC k t and SPC k i go
;; through projection, which already knows one project type from
;; another; SPC k r, SPC k d, SPC k m and SPC k n cannot, because
;; running, debugging, the panel and starting a project are this
;; config's own. A module says what it can do with
;; `+core-register-builder' and the first whose test answers takes it,
;; so the keys mean the same thing in a Rust buffer as in a C++ one.

(declare-function +core-project-root "lib")

(defvar +core-builders nil
  "What each module can do with a project.
Each entry is (NAME TEST . PLIST).  TEST is called with no arguments,
in the project root, and answers non-nil when that module owns the
project.  PLIST holds a command under any of :run, :debug, :panel and
:new, :label, what SPC k n calls its projects, and :fallback when the
module answers for whatever nothing else claimed. cpp does, since a directory with a Makefile and a binary in
it is its business as much as a CMake tree is.")

;;;###autoload
(defun +core-register-builder (name test &rest plist)
  "Say that module NAME runs, debugs, shows or starts a project TEST claims.
PLIST takes :run, :debug, :panel, :new, :label and :fallback; see
`+core-builders'.  Registering again under the same NAME replaces the
entry, so a reload does not stack them."
  (setq +core-builders
        (cons (cons name (cons test plist))
              (assq-delete-all name +core-builders))))

(defun +core--builder-claims-p (entry)
  "Non-nil when ENTRY's test claims the project we are in."
  (let ((root (+core-project-root 'noerror)))
    (condition-case nil
        (let ((default-directory (or root default-directory)))
          (funcall (cadr entry)))
      (error nil))))

(defun +core--builder (what)
  "The command registered for WHAT, for the project we are in.
The modules that claim a project are asked first, in the order they
registered; the fallback answers only when none of them does."
  (let ((entries (seq-remove (lambda (e) (plist-get (cddr e) :fallback))
                             +core-builders))
        (fallback (seq-find (lambda (e) (plist-get (cddr e) :fallback))
                            +core-builders)))
    (or (seq-some (lambda (entry)
                    (and (+core--builder-claims-p entry)
                         (plist-get (cddr entry) what)))
                  entries)
        (and fallback (plist-get (cddr fallback) what)))))

(defun +core--build-call (what missing)
  "Call the command registered for WHAT, or say MISSING."
  (if-let* ((command (+core--builder what)))
      (call-interactively command)
    (user-error "%s" missing)))

;;;###autoload
(defun +core/run ()
  "Run what this project builds, however this kind of project is run."
  (interactive)
  (+core--build-call :run "Nothing here knows how to run this project"))

;;;###autoload
(defun +core/debug ()
  "Debug what this project builds."
  (interactive)
  (+core--build-call :debug "Nothing here knows how to debug this project"))

;;;###autoload
(defun +core/build-panel ()
  "The panel of what this project's build depends on."
  (interactive)
  (+core--build-call :panel "This kind of project has no panel"))

;; A new project was asked of the module owning the project you were in,
;; so it offered that language alone: from the dashboard or a C++ tree
;; only C++ templates, and a Pascal, Rust or web project could not be
;; started at all. The language is asked first now, yours offered first.
;;;###autoload
(defun +core/new-project ()
  "Start a project, of any kind a module here can make: the language,
then its templates."
  (interactive)
  (let* ((makers (seq-filter (lambda (e) (plist-get (cddr e) :new)) +core-builders))
         (label (lambda (e) (or (plist-get (cddr e) :label)
                                (capitalize (symbol-name (car e))))))
         (here (or (seq-find #'+core--builder-claims-p
                             (seq-remove (lambda (e) (plist-get (cddr e) :fallback)) makers))
                   (seq-find (lambda (e) (plist-get (cddr e) :fallback)) makers)))
         (makers (if here (cons here (remq here makers)) makers))
         (entry (if (cdr makers)
                    (let ((choice (completing-read
                                   "New project in: " (mapcar label makers)
                                   nil t nil nil (funcall label (car makers)))))
                      (seq-find (lambda (e) (equal (funcall label e) choice)) makers))
                  (car makers))))
    (unless entry
      (user-error "Nothing here knows how to start a project"))
    (call-interactively (plist-get (cddr entry) :new))))
