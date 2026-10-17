;;; private/pascal/autoload/complete.el -*- lexical-binding: t; -*-
;;
;; What completion offers in a Pascal buffer. pasls knows a record's
;; fields and the library's routines, but not the names a program file
;; declares for itself, nor a routine's own locals at times, nor the
;; units a uses clause can name, nor the keywords. And the buffer's
;; words and the snippets were only asked when pasls had nothing at
;; all: Par offered ParamStr and never Parsed, the variable on the line
;; above.

(defvar +pascal-lazarus-dir)
(defvar +pascal-fpc-src-dir)
(defvar +pascal-host-os)
(declare-function +pascal-project-kind "pascal")
(declare-function +core-project-root "lib")
(declare-function eglot-completion-at-point "eglot")
(declare-function cape-dabbrev "cape")
(declare-function cape-wrap-super "cape")
(declare-function yasnippet-capf "yasnippet-capf")


;;
;;; The units a uses clause can name

(defvar +pascal--units nil
  "(KEY . UNITS): the installed units as `+pascal--installed-units' found
them, KEY saying from which directories and when.")

(defun +pascal--unit-dirs ()
  "The directories whose compiled units a program here can use."
  (let ((fpc (seq-some (lambda (root)
                         (car (file-expand-wildcards
                               (format "%s/fpc/*/units/*-%s" root +pascal-host-os))))
                       ;; The distribution's, the macOS installer's, Homebrew's.
                       '("/usr/lib*" "/usr/local/lib" "/opt/homebrew/lib")))
        (lcl (and +pascal-lazarus-dir
                  (car (file-expand-wildcards
                        (file-name-concat +pascal-lazarus-dir
                                          (concat "lcl/units/*-" +pascal-host-os)))))))
    (delq nil (list fpc lcl))))

(defun +pascal--spellings ()
  "Unit names as their sources write them, keyed by lower case: the one
with capitals where the sources disagree, SysUtils over sysutils."
  (let ((table (make-hash-table :test #'equal))
        (dirs (seq-filter #'file-directory-p
                          (list (and +pascal-fpc-src-dir
                                     (file-name-concat +pascal-fpc-src-dir "rtl"))
                                (and +pascal-fpc-src-dir
                                     (file-name-concat +pascal-fpc-src-dir "packages"))
                                (and +pascal-lazarus-dir
                                     (file-name-concat +pascal-lazarus-dir "lcl"))))))
    (when (and dirs (executable-find "grep"))
      (with-temp-buffer
        (apply #'call-process "grep" nil t nil "-rhoiE"
               "^[[:space:]]*unit[[:space:]]+[A-Za-z_][A-Za-z0-9_.]*[[:space:]]*;"
               "--include=*.pp" "--include=*.pas" dirs)
        (goto-char (point-min))
        (while (re-search-forward "unit[ \t]+\\([A-Za-z_][A-Za-z0-9_.]*\\)" nil t)
          (let* ((name (match-string 1)) (key (downcase name)) (had (gethash key table)))
            (when (or (null had) (and (equal had key) (not (equal name key))))
              (puthash key name table))))))
    table))

(defun +pascal--installed-units ()
  "Every installed unit's name, as its source spells it.  Read once and
kept in Doom's cache, until a unit directory changes."
  (let* ((dirs (+pascal--unit-dirs))
         (key (mapcar (lambda (d) (cons d (file-attribute-modification-time
                                          (file-attributes d))))
                      dirs))
         (cache (file-name-concat doom-cache-dir "pascal-units.eld")))
    (unless (equal (car +pascal--units) key)
      (setq +pascal--units
            (or (ignore-errors
                  (let ((saved (with-temp-buffer
                                 (insert-file-contents cache)
                                 (read (current-buffer)))))
                    (and (equal (car saved) key) saved)))
                (let* ((spellings (+pascal--spellings))
                       (units (delete-dups
                               (mapcar (lambda (file)
                                         (let ((name (file-name-base file)))
                                           (gethash name spellings name)))
                                       (mapcan (lambda (d)
                                                 (directory-files-recursively d "\\.ppu\\'"))
                                               dirs))))
                       (saved (cons key (sort units #'string-lessp))))
                  (ignore-errors
                    (make-directory (file-name-directory cache) t)
                    (with-temp-file cache (prin1 saved (current-buffer))))
                  saved))))
    (cdr +pascal--units)))

(defvar +pascal--project-units nil
  "(ROOT TIME . UNITS): the last project's units and when they were read.")

(defvar +pascal--fpc-units nil
  "(INSTALLED . FPC-UNITS): the installed units without the LCL's.")

(defun +pascal--fpc-units ()
  "The installed units a program without the LCL can use."
  (let ((installed (+pascal--installed-units)))
    (unless (eq (car +pascal--fpc-units) installed)
      (let ((lcl (car (last (+pascal--unit-dirs)))))
        (setq +pascal--fpc-units
              (cons installed
                    (if (and lcl (string-match-p "/lcl/" lcl))
                        (let ((names (mapcar #'file-name-base
                                             (directory-files-recursively lcl "\\.ppu\\'"))))
                          (seq-remove (lambda (unit) (member (downcase unit) names)) installed))
                      installed)))))
    (cdr +pascal--fpc-units)))

(defun +pascal--project-units ()
  "The units this project has sources for, as their unit lines name them.
Read again at most every ten seconds: completion asks at every key."
  (let ((root (+core-project-root 'noerror)))
    (if (and root (equal root (car +pascal--project-units))
             (< (- (float-time) (cadr +pascal--project-units)) 10))
        (cddr +pascal--project-units)
      (let ((units (+pascal--read-project-units root)))
        (setq +pascal--project-units (cons root (cons (float-time) units)))
        units))))

(defun +pascal--read-project-units (root)
  "The units ROOT has sources for, as their unit lines name them."
  (when root
    (let ((case-fold-search t) units)
      (dolist (file (directory-files-recursively
                     root "\\.\\(pas\\|pp\\)\\'" nil
                     (lambda (dir) (not (string-match-p "/\\(\\.git\\|lib\\|bin\\|backup\\)\\'" dir)))))
        (with-temp-buffer
          (insert-file-contents file nil 0 4000)
          (when (re-search-forward "^[ \t]*unit[ \t]+\\([A-Za-z_][A-Za-z0-9_.]*\\)" nil t)
            (push (match-string 1) units))))
      units)))

(defun +pascal--in-uses-clause ()
  "The start of the uses clause point is in, or nil."
  (save-excursion
    (let ((case-fold-search t) found)
      (while (and (not found)
                  (re-search-backward "\\_<uses\\_>\\|;" nil t))
        (unless (nth 8 (syntax-ppss))
          (setq found (if (eq (char-after) ?\;) 'no (point)))))
      (and (integerp found) found))))

;;;###autoload
(defun +pascal-units-capf ()
  "Complete a unit's name in a uses clause: the installed ones, the
LCL's in a Lazarus project, and the project's own."
  (when-let* (((derived-mode-p 'opascal-mode))
              ((not (nth 8 (syntax-ppss))))
              ((+pascal--in-uses-clause)))
    (let* ((bounds (or (bounds-of-thing-at-point 'symbol) (cons (point) (point))))
           (lazarus (eq (+pascal-project-kind) 'lazarus))
           (units (append (+pascal--project-units)
                          (if lazarus
                              (+pascal--installed-units)
                            (+pascal--fpc-units)))))
      (list (car bounds) (cdr bounds)
            (completion-table-case-fold (delete-dups units))
            :exclusive 'no
            :annotation-function (lambda (_) " unit")
            :company-kind (lambda (_) 'module)))))


;;
;;; pasls, the buffer's words and the snippets, in one list

(defun +pascal--without (result taken)
  "RESULT, a completion result, without the candidates the function TAKEN
already gives for the same input."
  (pcase-let ((`(,beg ,end ,table . ,plist) result))
    `(,beg ,end
           ,(lambda (string pred action)
              (if (eq action t)
                  (let ((have (funcall taken string)))
                    (seq-remove (lambda (c) (member c have))
                                (all-completions string table pred)))
                (complete-with-action action table string pred)))
           ,@plist)))

;;;###autoload
(defun +pascal-completion-at-point ()
  "pasls's completions, then the words of the buffers it did not offer,
then the snippets whose key fits, in one list.  Nil where pasls has
nothing to say, a comment or a string, so the others answer alone."
  (when-let* ((main (and (fboundp 'eglot-completion-at-point)
                         (eglot-completion-at-point))))
    (let* ((table (nth 2 main))
           (from-pasls (lambda (string) (all-completions string table)))
           (words (and (fboundp 'cape-dabbrev) (cape-dabbrev)))
           (words (and words (= (car words) (car main))
                       (+pascal--without words from-pasls)))
           (snippets (and (fboundp 'yasnippet-capf) (yasnippet-capf)))
           (snippets (and snippets (= (car snippets) (car main))
                          (+pascal--without
                           snippets
                           (lambda (string)
                             (append (funcall from-pasls string)
                                     (and words (all-completions string (nth 2 words)))))))))
      (apply #'cape-wrap-super
             ;; All three are main sources: a snippet is offered when
             ;; neither pasls nor the buffer has a word for its key.
             (delq nil (list (lambda () main)
                             (and words (lambda () words))
                             (and snippets (lambda () snippets))))))))

;;;###autoload
(defun +pascal-completion-h ()
  "Give a Pascal buffer eglot manages its unit names and the one list."
  (when (derived-mode-p 'opascal-mode)
    (if (bound-and-true-p eglot--managed-mode)
        (progn
          (remove-hook 'completion-at-point-functions #'eglot-completion-at-point t)
          (add-hook 'completion-at-point-functions #'+pascal-completion-at-point -10 t))
      (remove-hook 'completion-at-point-functions #'+pascal-completion-at-point t))
    (add-hook 'completion-at-point-functions #'+pascal-units-capf -20 t)))
