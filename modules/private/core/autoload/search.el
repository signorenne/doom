;;; private/core/autoload/search.el -*- lexical-binding: t; -*-
;;
;; Finding text and changing it, with the options in front of you
;; rather than remembered. ripgrep takes flags for a literal string,
;; whole words, a kind of file; consult hands it whatever follows a
;; lone -- in the prompt, which works and has to be known by heart.
;; The menu sets the flags by name, searches where you say, and the
;; prompt is the plain one again. The same options narrow a replace:
;; ripgrep says which files hold the text, and the replace visits those
;; and no others.

(require 'transient)

;; `fileloop-initialize-replace' is autoloaded and loads the library, so
;; this exists by the time it is called; the compiler cannot know that.
(declare-function fileloop-continue "fileloop")

(declare-function +default/search-buffer "search")
(declare-function +vertico-file-search "vertico")
(declare-function projectile-relevant-known-projects "projectile")
(declare-function consult-line-multi "consult")
(declare-function consult--convert-regexp "consult")
(declare-function dired-do-find-regexp-and-replace "dired-aux")
(declare-function +core-project-root "lib")

(defun +core--rg-types ()
  "Every kind of file ripgrep knows by name, for the menu to complete."
  (when-let* ((rg (executable-find "rg")))
    (ignore-errors
      (mapcar (lambda (line) (car (split-string line ":")))
              (process-lines rg "--type-list")))))

(defvar transient-current-command)

(defvar +core--kept-flags nil
  "The flags the search menu was set to when the replace menu opened.
A transient only answers for itself, and the replace menu is its own;
the options are set once and meant for both.")

(defun +core--search-flags ()
  "The ripgrep flags the menus are set to.
Only the two menus have flags. `transient-args\=' answers nil outside a
transient rather than refusing, so without the second test a search
started from a key would have quietly carried whatever the last replace
was set to, and un-setting a flag in the menu would not have un-set it."
  (or (ignore-errors (transient-args '+core/search-menu))
      (and (eq transient-current-command '+core/replace-menu)
           +core--kept-flags)))

(defun +core--search-flag-p (flag)
  "Non-nil when the menu is set to FLAG."
  (and (member flag (+core--search-flags)) t))

(defun +core--search-in (directory &optional query)
  "Search DIRECTORY with the menu's flags, QUERY typed in already.
Doom builds ripgrep's command line itself, from scratch, every time it
searches; binding `consult-ripgrep-args' round it would be thrown away.
It takes extra flags as :args, so they go there."
  (unless (fboundp '+vertico-file-search)
    (user-error "The vertico module is not here to search with"))
  (+vertico-file-search :in directory :query query :args (+core--search-flags)))

;;
;;; Searching

(transient-define-suffix +core/search-project-with-flags ()
  "Search the whole project."
  (interactive)
  (+core--search-in (ignore-errors (+core-project-root))))

(transient-define-suffix +core/search-cwd-with-flags ()
  "Search this directory and below."
  (interactive)
  (+core--search-in default-directory))

(transient-define-suffix +core/search-other-cwd-with-flags ()
  "Search a directory you pick."
  (interactive)
  (+core--search-in (read-directory-name "Search under: ")))

(transient-define-suffix +core/search-other-project-with-flags ()
  "Search another project."
  (interactive)
  (require 'projectile nil t)
  (let ((projects (if (fboundp 'projectile-relevant-known-projects)
                      (projectile-relevant-known-projects)
                    (user-error "Projectile is not here to list the projects"))))
    (+core--search-in (completing-read "Search project: " projects nil t))))

(transient-define-suffix +core/search-symbol-with-flags ()
  "Search the project for the word under the cursor."
  (interactive)
  (+core--search-in (ignore-errors (+core-project-root))
                    (when-let* ((word (thing-at-point 'symbol t)))
                      ;; With F the text goes to ripgrep as it is.
                      (if (+core--search-flag-p "-F") word (regexp-quote word)))))

;;
;;; Replacing

(defun +core--rg-files (pattern &optional directory)
  "The files under DIRECTORY ripgrep finds PATTERN in, with the menu's
options; the project when DIRECTORY is nil.  A replace then visits
those files and no others.  Nil when ripgrep finds nothing, which is
how it reports no match."
  (let* ((default-directory (or directory
                                (ignore-errors (+core-project-root))
                                default-directory))
         ;; Lines of context mean nothing when only the names are wanted.
         (flags (seq-remove (lambda (flag) (string-prefix-p "--context=" flag))
                            (+core--search-flags))))
    ;; The replace reads PATTERN as an Emacs regexp, so ripgrep is given
    ;; it in its own syntax, as consult does for a search; otherwise \(
    ;; and \| would be literal to ripgrep, and | a choice the replace
    ;; never makes.
    (unless (or (member "-F" flags) (not (require 'consult nil t)))
      (setq pattern (consult--convert-regexp pattern 'extended)))
    (mapcar #'expand-file-name
            (ignore-errors
              (apply #'process-lines
                     (or (executable-find "rg") "rg")
                     (append '("--files-with-matches" "--no-messages" "--color=never")
                             flags (list "-e" pattern ".")))))))

(defun +core--replace-read (where)
  "Read what to replace in WHERE and what to put there, as (FROM . TO).
The word under the cursor is offered, since it is usually the one."
  (let* ((literal (+core--search-flag-p "-F"))
         (here (thing-at-point 'symbol t))
         (from (read-string (format "Replace %s in %s%s: "
                                    (if literal "text" "regexp") where
                                    (if here (format " (%s)" here) ""))
                            nil nil here))
         (to (read-string (format "Replace %s with: " from))))
    (when (string-empty-p from) (user-error "Nothing to replace"))
    (cons from to)))

;;;###autoload
(defun +core/replace-in-buffer ()
  "Replace through this buffer, with the menu's options: a literal
string with F, whole words with w, either case with i."
  (interactive)
  (pcase-let* ((`(,from . ,to) (+core--replace-read "this buffer"))
               (literal (+core--search-flag-p "-F"))
               (case-fold-search (if (+core--search-flag-p "-i") t case-fold-search)))
    (save-excursion
      (goto-char (point-min))
      ;; Literal both ways: a backslash in TO is text, not \\1 or \\&.
      (perform-replace (if literal (regexp-quote from) from)
                       (if literal (replace-quote to) to)
                       t t (+core--search-flag-p "-w")))))

(defun +core--replace-through (directory where)
  "Replace through the files under DIRECTORY that hold the text, asking
at every match.  WHERE names the place in the prompt.  Only the files
ripgrep finds it in are opened, and the menu's options say which those
are: one kind of file, one set of names, whole words, either case."
  (pcase-let* ((`(,from . ,to) (+core--replace-read where))
               (files (+core--rg-files from directory)))
    (unless files
      (user-error "No file under %s holds %s"
                  (abbreviate-file-name (or directory default-directory)) from))
    (fileloop-initialize-replace
     (if (+core--search-flag-p "-F") (regexp-quote from) from)
     (if (+core--search-flag-p "-F") (replace-quote to) to)
     files
     (if (+core--search-flag-p "-i") t 'default)
     (+core--search-flag-p "-w"))
    (message "%d file(s) hold it; y and n as usual, ! for the rest of a file"
             (length files))
    ;; fileloop says it is finished by signalling, which would read as
    ;; something having gone wrong; say it plainly instead.
    (condition-case nil
        (fileloop-continue)
      (user-error (message "Replaced through %d file(s)" (length files))))))

;;;###autoload
(defun +core/replace-in-project ()
  "Replace through the project, in the files that hold the text."
  (interactive)
  (+core--replace-through (ignore-errors (+core-project-root)) "the project"))

;;;###autoload
(defun +core/replace-in-cwd ()
  "Replace through this directory and below."
  (interactive)
  (+core--replace-through default-directory "this directory"))

;;;###autoload
(defun +core/replace-in-other-cwd ()
  "Replace through a directory you pick."
  (interactive)
  (let ((directory (read-directory-name "Replace under: ")))
    (+core--replace-through directory (abbreviate-file-name directory))))

;;;###autoload
(defun +core/replace-in-other-project ()
  "Replace through another project."
  (interactive)
  (require 'projectile nil t)
  (let* ((projects (if (fboundp 'projectile-relevant-known-projects)
                       (projectile-relevant-known-projects)
                     (user-error "Projectile is not here to list the projects")))
         (directory (completing-read "Replace in project: " projects nil t)))
    (+core--replace-through directory (abbreviate-file-name directory))))

(transient-define-suffix +core/replace-in-buffer-suffix ()
  "Replace in this buffer."
  (interactive)
  (call-interactively #'+core/replace-in-buffer))

(transient-define-suffix +core/replace-in-project-suffix ()
  "Replace in the project."
  (interactive)
  (call-interactively #'+core/replace-in-project))

(transient-define-suffix +core/replace-in-cwd-suffix ()
  "Replace in this directory."
  (interactive)
  (call-interactively #'+core/replace-in-cwd))

(transient-define-suffix +core/replace-in-other-cwd-suffix ()
  "Replace in a directory you pick."
  (interactive)
  (call-interactively #'+core/replace-in-other-cwd))

(transient-define-suffix +core/replace-in-other-project-suffix ()
  "Replace in another project."
  (interactive)
  (call-interactively #'+core/replace-in-other-project))

(defun +core--replace-menu-description ()
  "The line over the replace menu: what is set, so it is not a surprise."
  (let ((flags (+core--search-flags)))
    (concat "Replace"
            (if flags (format ", with %s" (string-join flags " ")) "")
            ": y n ! q at each match")))

;;;###autoload (autoload '+core/replace-menu "private/core/autoload/search" nil t)
(transient-define-prefix +core/replace-menu ()
  "Replace, in the same places the search menu looks."
  [:description +core--replace-menu-description
   ["Replace in"
    ("l" "This buffer"          +core/replace-in-buffer-suffix)
    ("p" "The project"          +core/replace-in-project-suffix)
    ("d" "This directory"       +core/replace-in-cwd-suffix)
    ("D" "A directory..."       +core/replace-in-other-cwd-suffix)
    ("P" "Another project"      +core/replace-in-other-project-suffix)
    ("f" "The files marked in dired" dired-do-find-regexp-and-replace
     :if (lambda () (derived-mode-p 'dired-mode)))]])

(transient-define-suffix +core/replace-menu-suffix ()
  "Open the replace menu, keeping what is set here."
  (interactive)
  (setq +core--kept-flags (+core--search-flags))
  (transient-setup '+core/replace-menu))

;;
;;; The menu

(defun +core--search-menu-description ()
  "The line over the menu: what it does, and the project a project
search or replace would reach."
  (format "Find and replace%s"
          (if-let* ((root (ignore-errors (+core-project-root))))
              (format ", project: %s"
                      (file-name-nondirectory (directory-file-name root)))
            "")))

;;;###autoload (autoload '+core/search-menu "private/core/autoload/search" nil t)
(transient-define-prefix +core/search-menu ()
  "Find text, and change it, with what to look for set before you look."
  [:description +core--search-menu-description
   ["What to look for"
    ("F" "Literal text, no regexp" "-F")
    ("w" "Whole words only"       "-w")
    ("i" "Ignore case"            "-i")
    ("v" "Lines that do not match" "-v")
    ("m" "Across line ends"       "--multiline")]
   ["Which files"
    ("g" "Only names matching" "--glob=")
    ("G" "Every name but"      "--glob=!")
    ("t" "Only this kind"      "--type=" :choices +core--rg-types)
    ("T" "Every kind but"      "--type-not=" :choices +core--rg-types)
    ("u" "Ignored and hidden too" "-uu")
    ("c" "Lines of context"    "--context=")]]
  [["Search"
    ("p" "The project"          +core/search-project-with-flags)
    ("d" "This directory"       +core/search-cwd-with-flags)
    ("D" "A directory..."       +core/search-other-cwd-with-flags)
    ("P" "Another project"      +core/search-other-project-with-flags)
    ("*" "The word at point"    +core/search-symbol-with-flags)
    ("b" "Every open buffer"    consult-line-multi)
    ("l" "This buffer"          +default/search-buffer)]
   ["Replace"
    ("r" "Where to replace..."  +core/replace-menu-suffix)
    ("R" "The project, at once" +core/replace-in-project-suffix)]])
