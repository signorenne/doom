;;; private/pascal/autoload/scaffold.el -*- lexical-binding: t; -*-
;;
;; A new Pascal project. There is no `cargo new' here, so the templates
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
