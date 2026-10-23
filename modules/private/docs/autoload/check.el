;;; private/docs/autoload/check.el -*- lexical-binding: t; -*-
;;
;; Does every function the config refers to exist when the reference is
;; used? A name defined in an autoload file is void until that file
;; loads, and the file loads through a cookie, so a reference from any
;; other file needs the definition cookied. doom doctor runs the scan on
;; the files, and `+docs/check-autoloads' also asks the running session.

(defconst +docs--definition-regexp
  (concat "^(\\(?:defun\\|cl-defun\\|defmacro\\|defsubst\\|defalias"
          "\\|transient-define-prefix\\|define-minor-mode\\|define-derived-mode\\)"
          " '?\\(\\+[a-z]+[/-][^ \t\n()]+\\)")
  "A definition of one of this config's functions, the name in group 1.")

(defconst +docs--struct-regexp "^(cl-defstruct (?\\(\\+[a-z]+-[^ \t\n()]+\\)"
  "A struct definition, whose accessors are named after group 1.")

(defconst +docs--reference-regexp
  (concat "#'\\(\\+[a-z]+[/-][^ \t\n()\"]+\\)"
          "\\|'\\(\\+[a-z]+/[^ \t\n()\"]+\\)")
  "A reference to one of this config's functions: any name behind a
function quote, a command behind a plain quote.  Variables are quoted
plainly and never carry a slash, so they do not match.")

(defun +docs--cookied-p ()
  "Non-nil when a cookie sits above the definition at point, blank lines
and comments between them allowed."
  (save-excursion
    (forward-line -1)
    (while (and (not (bobp)) (looking-at-p "^[ \t]*$\\|^;; "))
      (forward-line -1))
    (looking-at-p "^;;;###autoload")))

(defun +docs--scan-autoloads ()
  "Read the private modules and return (DEFINED STRUCTS REFERENCES):
DEFINED maps a name to (FILE . COOKIED), STRUCTS is a list of struct
names, REFERENCES a list of (NAME . FILE) for every quoted reference,
files relative to modules/private.  A definition in a file that is not
an autoload file counts as cookied, since it is loaded at startup."
  (let* ((root (file-name-concat doom-user-dir "modules/private"))
         (files (directory-files-recursively root "\\.el\\'"))
         (defined (make-hash-table :test #'equal))
         structs references)
    (dolist (file files)
      (let ((name (file-relative-name file root))
            (autoload-file (string-match-p "/autoload/" file)))
        (with-temp-buffer
          (insert-file-contents file)
          (goto-char (point-min))
          (while (re-search-forward +docs--definition-regexp nil t)
            (puthash (match-string 1)
                     (cons name (or (not autoload-file)
                                    (save-excursion (goto-char (match-beginning 0))
                                                    (+docs--cookied-p))))
                     defined))
          (goto-char (point-min))
          (while (re-search-forward +docs--struct-regexp nil t)
            (push (match-string 1) structs))
          (unless (string-suffix-p "doctor.el" name)
            (goto-char (point-min))
            (while (re-search-forward +docs--reference-regexp nil t)
              (push (cons (or (match-string 1) (match-string 2)) name)
                    references))))))
    (list defined structs (seq-uniq references))))

(defun +docs--struct-function-p (name structs)
  "Non-nil when NAME is an accessor, copier or constructor of one of
STRUCTS, which a cookie on the struct itself covers."
  (seq-some (lambda (struct)
              (or (string-prefix-p (concat struct "-") name)
                  (equal name (concat "copy-" struct))))
            structs))

(defun +docs--prefix (name)
  "The module prefix of NAME: cpp for +cpp/run and +cpp--kit."
  (and (string-match "\\`\\+\\([a-z]+\\)[/-]" name) (match-string 1 name)))

(defun +docs--own-prefixes (defined structs)
  "The prefixes this config defines names under, from DEFINED and
STRUCTS.  A reference under any other prefix is Doom's or a package's,
+lookup/definition or +popup/close, and not judged here."
  (let (prefixes)
    (maphash (lambda (name _) (cl-pushnew (+docs--prefix name) prefixes :test #'equal))
             defined)
    (dolist (struct structs) (cl-pushnew (+docs--prefix struct) prefixes :test #'equal))
    (delq nil prefixes)))

;; Autoloaded: docs/doctor.el loads this file and calls it.
;;;###autoload
(defun +docs-autoload-problems ()
  "Every reference the files cannot honour, as a list of sentences:
a name defined nowhere, or defined in an autoload file without a
cookie and referred to from another file.  Nil when all is well."
  (pcase-let ((`(,defined ,structs ,references) (+docs--scan-autoloads)))
    (let ((prefixes (+docs--own-prefixes defined structs))
          problems)
      (pcase-dolist (`(,name . ,file) references)
        (let ((def (gethash name defined)))
          (cond
           ((not (member (+docs--prefix name) prefixes)))
           ((+docs--struct-function-p name structs))
           ((null def)
            (push (format "%s is referenced in %s but defined nowhere" name file)
                  problems))
           ((and (not (cdr def)) (not (equal (car def) file)))
            (push (format "%s is defined in %s without a ;;;###autoload cookie, so the reference in %s is void in a fresh session"
                          name (car def) file)
                  problems)))))
      (nreverse problems))))

;;;###autoload
(defun +docs/check-autoloads ()
  "Check that every function the config refers to is callable now.
The files first: a name defined nowhere, or defined in an autoload
file without its cookie and used from another file, passes doom sync
and fails on the first press.  Then the running session: every
referenced name must be callable, which catches a definition the
scanner misread.  Run it after a sync in a fresh Emacs, or after
editing an autoload file; doom doctor runs the file half."
  (interactive)
  (pcase-let* ((`(,defined ,structs ,references) (+docs--scan-autoloads))
               (prefixes (+docs--own-prefixes defined structs))
               (problems (+docs-autoload-problems))
               (missing (seq-remove
                         (lambda (pair)
                           (or (not (member (+docs--prefix (car pair)) prefixes))
                               (fboundp (intern (car pair)))
                               (+docs--struct-function-p (car pair) structs)
                               ;; Used only where it is defined: loaded
                               ;; together with its caller.
                               (equal (car (gethash (car pair) defined))
                                      (cdr pair))))
                         references)))
    (if (and (null problems) (null missing))
        (message "Every function the config refers to is callable: %d checked"
                 (length references))
      (with-current-buffer (get-buffer-create "*config check*")
        (let ((inhibit-read-only t))
          (erase-buffer)
          (when problems
            (insert "From the files:\n\n")
            (dolist (problem problems) (insert "  " problem "\n"))
            (insert "\n"))
          (when missing
            (insert "Referenced, not callable in this session:\n\n")
            (pcase-dolist (`(,name . ,file) missing)
              (insert (format "  %-40s %s\n" name file))))
          (special-mode))
        (pop-to-buffer (current-buffer)))
      (message "%d problem(s), see *config check*"
               (+ (length problems) (length missing))))))
