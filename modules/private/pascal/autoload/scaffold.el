;;; private/pascal/autoload/scaffold.el -*- lexical-binding: t; -*-
;;
;; A new Pascal project. Pascal has no `cargo new', so the templates
;; carry the whole thing: the program file, a unit, and for an LCL
;; application the .lpi Lazarus reads.

(declare-function +core-copy-template "scaffold")
(declare-function +core-read-new-project "scaffold")
(declare-function +core-leave-dirvish "dired")
(defvar +pascal-templates-dir)

;;;###autoload
(defun +pascal-project-kinds ()
  "The kinds of Pascal project this module can start.
A directory starting with _ is the overlay every kind is built on."
  (when (file-directory-p +pascal-templates-dir)
    (mapcar #'file-name-nondirectory
            (seq-filter #'file-directory-p
                        (directory-files +pascal-templates-dir t "^[^._]")))))

(defconst +pascal--reserved-words
  '("and" "array" "as" "asm" "begin" "case" "class" "const" "constructor"
    "destructor" "dispinterface" "div" "do" "downto" "else" "end" "except"
    "exports" "file" "finalization" "finally" "for" "function" "goto" "if"
    "implementation" "in" "inherited" "initialization" "interface" "is"
    "label" "library" "mod" "nil" "not" "object" "of" "operator" "or"
    "packed" "procedure" "program" "property" "raise" "record" "repeat"
    "resourcestring" "set" "shl" "shr" "string" "then" "threadvar" "to"
    "try" "type" "unit" "until" "uses" "var" "while" "with" "xor")
  "The words fpc -Mobjfpc will not take as a program's name.")

(defun +pascal--names-taken (kind)
  "The names a KIND project cannot have: the units its template's files
are and use.  A program called like one of them is a duplicate identifier."
  (let ((names nil)
        (case-fold-search t))
    (dolist (part (list "_base" kind))
      (let ((dir (file-name-concat +pascal-templates-dir part)))
        (when (file-directory-p dir)
          (dolist (file (directory-files-recursively dir "\\.\\(pas\\|pp\\|lpr\\)\\'"))
            (push (downcase (file-name-base file)) names)
            (with-temp-buffer
              (insert-file-contents file)
              ;; Comments out first: {$IFDEF UNIX}cthreads,{$ENDIF}.
              (while (re-search-forward "{[^}]*}\\|//.*" nil t)
                (replace-match " "))
              (goto-char (point-min))
              (while (re-search-forward "\\_<uses\\_>\\([^;]*\\);" nil t)
                (dolist (unit (split-string (match-string 1) "," t "[ \t\n]+"))
                  ;; Options in 'src/options.pas' is the unit Options.
                  (push (downcase (car (split-string unit "[ \t\n]+" t))) names))))))))
    (delete "{{project}}" (delete-dups names))))

;;;###autoload
(defun +pascal/new-project (kind dir name)
  "Start Pascal project NAME of KIND in DIR, and open it.
KIND is \"console\" for a Free Pascal program or \"lcl\" for a Lazarus
application with a window."
  (interactive
   (let ((kinds (or (+pascal-project-kinds)
                    (user-error "No templates in %s" +pascal-templates-dir))))
     (cons (completing-read "Kind: " kinds nil t nil nil (car kinds))
           (+core-read-new-project))))
  (cond ((member name +pascal--reserved-words)
         (user-error "%s is a Pascal keyword: a program cannot be called that" name))
        ((member name (+pascal--names-taken kind))
         (user-error "The %s template has a unit called %s already: pick another name"
                     kind name)))
  (when (and (file-exists-p dir) (directory-files dir nil "^[^.]"))
    (unless (y-or-n-p (format "%s is not empty.  Continue? " dir))
      (user-error "Aborted")))
  (make-directory dir t)
  (dolist (part (list "_base" kind))
    (let ((src (file-name-concat +pascal-templates-dir part)))
      (when (file-directory-p src)
        (+core-copy-template src dir name))))
  (when (and (executable-find "git")
             (not (file-directory-p (expand-file-name ".git" dir)))
             (y-or-n-p "Initialise a git repository? "))
    (let ((default-directory dir))
      (call-process "git" nil nil nil "init" "-q")))
  ;; Made from a listing, the dirvish panes would stay standing round it.
  (+core-leave-dirvish)
  (find-file (or (seq-find #'file-exists-p
                           (list (expand-file-name (concat name ".lpr") dir)
                                 (expand-file-name "mainform.pas" dir)
                                 (expand-file-name (concat name ".lpi") dir)))
                 dir))
  (message "%s created from the %s template: F7 builds it, F6 runs it"
           name kind))
