;;; private/core/autoload/build.el -*- lexical-binding: t; -*-
;;
;; One set of keys for every language. A module says what it can do
;; with `+core-register-builder' and the first whose test answers takes
;; the project: F6, F5 and the rest mean the same thing in a Rust buffer
;; as in a C++ one, and SPC k opens that module's own keys, the same
;; letters for the same things, b build, r run, t test, d debug, m the
;; panel, n a new project.

(declare-function +core-project-root "lib")
(declare-function +core-project-root-or-nil "lib")
(defvar +core-kit-map)                  ; config.el
(defvar +core-kit-project-map)          ; config.el
(defvar +core-projects-dir)             ; config.el

(defvar +core-builders nil
  "What each module can do with a project.
Each entry is (NAME TEST . PLIST).  TEST is called with no arguments,
in the project root, and answers non-nil when that module owns the
project.  PLIST holds a command under any of :run, :run-with-args,
:build-and-run, :debug, :panel and :new, :label, what SPC k n calls its
projects, :keys, the symbol of the keymap SPC k opens in its projects,
and :fallback when the module answers for whatever nothing else
claimed.  cpp does, since a directory with a Makefile and a binary in it
is its business as much as a CMake tree is; its own keys it shows only
where its TEST says the project is its kind.")

;;;###autoload
(defun +core-register-builder (name test &rest plist)
  "Say that module NAME runs, debugs, shows or starts a project TEST claims.
PLIST takes :run, :run-with-args, :build-and-run, :debug, :panel, :new,
:label, :keys and :fallback; see
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
The first module that claims the project, in the order they registered,
owns it and answers, nil when it has no such command; the fallback
answers only when none of them claims it."
  (let ((owner (seq-find #'+core--builder-claims-p
                         (seq-remove (lambda (e) (plist-get (cddr e) :fallback))
                                     +core-builders)))
        (fallback (seq-find (lambda (e) (plist-get (cddr e) :fallback))
                            +core-builders)))
    ;; A module without the command used to hand it to the fallback, so
    ;; a web project got the C++ run with arguments, which failed.
    (plist-get (cddr (or owner fallback)) what)))

(defun +core--build-call (what missing)
  "Call the command registered for WHAT, or say MISSING."
  (if-let* ((command (+core--builder what)))
      (call-interactively command)
    (user-error "%s" missing)))

;;
;;; SPC k

;;;###autoload
(defun +core-kit-keymap (bindings)
  "A keymap for SPC k of BINDINGS, (KEY DESCRIPTION DEFINITION) each.
The description is kept in the map itself, where which-key reads it, so
one key can say one thing in a C++ project and another in a Pascal one.
A DEFINITION that is a list of bindings is a prefix of its own; one
written #\='command is the command, and the config's check of what it
refers to then sees it."
  (let ((map (make-sparse-keymap)))
    (pcase-dolist (`(,key ,description ,definition) bindings)
      (define-key map (kbd key)
                  (cons description
                        (cond ((eq (car-safe definition) 'function) (cadr definition))
                              ((and (consp definition) (consp (car definition)))
                               (+core-kit-keymap definition))
                              (t definition)))))
    map))

(defvar +core--kit-owners (make-hash-table :test #'equal)
  "Directory to (MTIME . NAME): the module whose keys SPC k opens there.
which-key asks on every page it draws; a marker file appearing or going
changes the directory's mtime.")

(defun +core--kit-dir ()
  "Where SPC k looks: the project root, else the buffer's own directory,
so a project with no version control is still known by its files.  Not
the home directory or /, where every folder under them would be read."
  (or (+core-project-root-or-nil)
      (let ((dir (expand-file-name default-directory)))
        (unless (or (file-equal-p dir "~/") (file-equal-p dir "/"))
          dir))))

(defun +core--kit-owner ()
  "The `+core-builders' entry whose keys SPC k opens here, or nil.
The first module that claims the project, else the fallback when its own
test says the project is its kind."
  (when-let* ((dir (+core--kit-dir)))
    (let* ((dir (file-name-as-directory dir))
           (mtime (file-attribute-modification-time (file-attributes dir)))
           (hit (gethash dir +core--kit-owners))
           (claims (lambda (entry)
                     (condition-case nil
                         (let ((default-directory dir)) (funcall (cadr entry)))
                       (error nil))))
           (name (if (and hit (equal (car hit) mtime))
                     (cdr hit)
                   (let ((owner (or (seq-find claims
                                              (seq-remove (lambda (e) (plist-get (cddr e) :fallback))
                                                          +core-builders))
                                    (seq-find (lambda (e) (and (plist-get (cddr e) :fallback)
                                                               (funcall claims e)))
                                              +core-builders))))
                     (puthash dir (cons mtime (car owner)) +core--kit-owners)
                     (car owner)))))
      (and name (assq name +core-builders)))))

;;;###autoload
(defun +core--kit-map (&optional _)
  "The keymap SPC k opens here: the owning module's; else, in a project
no module knows, what projection can do with it; else starting a project
and going to one."
  (let ((keys (plist-get (cddr (+core--kit-owner)) :keys)))
    (cond ((and keys (boundp keys)) (symbol-value keys))
          ((+core-project-root-or-nil) +core-kit-project-map)
          (t +core-kit-map))))

;;;###autoload
(defun +core-kit-maps ()
  "Every keymap SPC k can open, as (WHERE . KEYMAP), for the docs."
  (append (list (cons "outside a project" +core-kit-map)
                (cons "a project no module knows" +core-kit-project-map))
          (cl-loop for entry in (reverse +core-builders)
                   for keys = (plist-get (cddr entry) :keys)
                   when (and keys (boundp keys))
                   collect (cons (or (plist-get (cddr entry) :label)
                                     (capitalize (symbol-name (car entry))))
                                 (symbol-value keys)))))

;;;###autoload
(defun +core/open-projects-dir ()
  "Open the folder new projects go in, to pick one by hand."
  (interactive)
  (dired (expand-file-name +core-projects-dir)))

;;;###autoload
(defun +core/run ()
  "Run what this project builds, however this kind of project is run."
  (interactive)
  (+core--build-call :run "Nothing here knows how to run this project"))

;;;###autoload
(defun +core/run-with-args ()
  "Run what this project builds once, with arguments asked for."
  (interactive)
  (+core--build-call :run-with-args
                     "Nothing here knows how to run this project with arguments"))

;;;###autoload
(defun +core/build-and-run ()
  "Build this project, then run it when the build worked."
  (interactive)
  (+core--build-call :build-and-run
                     "Nothing here knows how to build and run this project"))

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
