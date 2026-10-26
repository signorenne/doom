;;; private/pascal/autoload/complete.el -*- lexical-binding: t; -*-
;;
;; What completion offers in a Pascal buffer. pasls knows a record's
;; fields and the library's routines, but not the names a program file
;; declares for itself, nor a routine's own locals at times, nor the
;; units a uses clause can name, nor the keywords. So the buffer's words
;; and the snippets are offered alongside pasls's, not only when it has
;; nothing.

(defvar +pascal-lazarus-dir)
(defvar +pascal-fpc-src-dir)
(defvar +pascal-host-os)
(declare-function +pascal-project-kind "pascal")
(declare-function +core-project-root-or-nil "lib")
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

;; Reading them greps Free Pascal's, the LCL's and the project's sources,
;; too slow for a key. The greps run in the background from the moment a
;; project's Pascal file opens, and completion offers what was read last.

(defvar +pascal--scans nil
  "The scans under way, (KEY . PROCESS), so one is not started twice.")

(defun +pascal--scan (key command done)
  "Run COMMAND in the background unless a scan for KEY is under way, and
call DONE in a buffer holding what it printed, point at its start, once
it has finished."
  (unless (assoc key +pascal--scans)
    (let ((out (generate-new-buffer " *pascal-units*")))
      (condition-case nil
          (push (cons key
                      (make-process
                       :name "pascal-units" :buffer out :command command
                       :noquery t :connection-type 'pipe
                       :sentinel
                       (lambda (proc _event)
                         (unless (process-live-p proc)
                           (setq +pascal--scans (assoc-delete-all key +pascal--scans))
                           (unwind-protect
                               (with-demoted-errors "Pascal units: %S"
                                 (with-current-buffer out
                                   (goto-char (point-min))
                                   (funcall done)))
                             (kill-buffer out))))))
                +pascal--scans)
        (error (kill-buffer out))))))

(defun +pascal--source-dirs ()
  "The source directories whose unit lines spell the installed units."
  (seq-filter (lambda (dir) (and dir (file-directory-p dir)))
              (list (and +pascal-fpc-src-dir
                         (file-name-concat +pascal-fpc-src-dir "rtl"))
                    (and +pascal-fpc-src-dir
                         (file-name-concat +pascal-fpc-src-dir "packages"))
                    (and +pascal-lazarus-dir
                         (file-name-concat +pascal-lazarus-dir "lcl")))))

(defun +pascal--unit-names-here ()
  "The unit names the unit lines from point on write, in order."
  (let ((case-fold-search t) names)
    (while (re-search-forward "unit[ \t]+\\([A-Za-z_][A-Za-z0-9_.]*\\)" nil t)
      (push (match-string 1) names))
    (nreverse names)))

(defun +pascal--spellings (names)
  "NAMES keyed by lower case: the one with capitals where they disagree,
SysUtils over sysutils."
  (let ((table (make-hash-table :test #'equal)))
    (dolist (name names table)
      (let* ((key (downcase name)) (had (gethash key table)))
        (when (or (null had) (and (equal had key) (not (equal name key))))
          (puthash key name table))))))

(defun +pascal--read-installed-units (dirs key cache)
  "Read the units compiled in DIRS in the background, as their sources
spell them, and keep them under KEY, in memory and in CACHE."
  (let ((finish
         (lambda (spellings)
           (let* ((units (delete-dups
                          (mapcar (lambda (file)
                                    (let ((name (file-name-base file)))
                                      (gethash name spellings name)))
                                  (mapcan (lambda (d)
                                            (directory-files-recursively d "\\.ppu\\'"))
                                          dirs))))
                  (saved (cons key (sort units #'string-lessp))))
             (setq +pascal--units saved)
             (ignore-errors
               (make-directory (file-name-directory cache) t)
               (with-temp-file cache (prin1 saved (current-buffer)))))))
        (sources (+pascal--source-dirs)))
    (if (and sources (executable-find "grep"))
        (+pascal--scan
         'installed
         ;; -s: its complaints would be read as unit names.
         `("grep" "-rshoiE"
           "^[[:space:]]*unit[[:space:]]+[A-Za-z_][A-Za-z0-9_.]*[[:space:]]*;"
           "--include=*.pp" "--include=*.pas" ,@sources)
         (lambda () (funcall finish (+pascal--spellings (+pascal--unit-names-here)))))
      (funcall finish (make-hash-table :test #'equal)))))

(defun +pascal--installed-units ()
  "Every installed unit's name, as its source spells it: kept in Doom's
cache until a unit directory changes, then read again in the background
while the last list is offered."
  (let* ((dirs (+pascal--unit-dirs))
         (key (mapcar (lambda (d) (cons d (file-attribute-modification-time
                                          (file-attributes d))))
                      dirs))
         (cache (file-name-concat doom-cache-dir "pascal-units.eld")))
    (unless (or (equal (car +pascal--units) key)
                (assq 'installed +pascal--scans))
      (let ((saved (ignore-errors
                     (with-temp-buffer
                       (insert-file-contents cache)
                       (read (current-buffer))))))
        (if (equal (car saved) key)
            (setq +pascal--units saved)
          (+pascal--read-installed-units dirs key cache))))
    (cdr +pascal--units)))

(defvar +pascal--project-units (make-hash-table :test #'equal)
  "Project root to (TIME . UNITS): its units and when they were read.
One a project, so a slow scan of one ending after another's keeps to
its own.")

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
  "The units this project has sources for, as their unit lines name them:
what was read last, read again in the background past ten seconds.
None outside a project: a stray file in ~ is not a reason to read ~."
  (when-let* ((root (+core-project-root-or-nil)))
    (let ((have (gethash root +pascal--project-units)))
      (unless (and have (< (- (float-time) (car have)) 10))
        (+pascal--read-project-units root))
      (cdr have))))

(defun +pascal--read-project-units (root)
  "Read the units ROOT has sources for in the background, each file's
first unit line, outside .git, lib, bin and backup."
  (when (executable-find "grep")
    (+pascal--scan
     (cons 'project root)
     ;; grep's globs are not case-blind.
     `("grep" "-rshoiE" "-m" "1"
       ,@(mapcar (lambda (ext) (concat "--include=*." ext))
                 '("pas" "pp" "PAS" "PP" "Pas" "Pp"))
       ,@(mapcar (lambda (dir) (concat "--exclude-dir=" dir))
                 '(".git" "lib" "Lib" "LIB" "bin" "Bin" "BIN" "backup" "Backup" "BACKUP"))
       "^[[:space:]]*unit[[:space:]]+[A-Za-z_][A-Za-z0-9_.]*"
       ,(file-name-as-directory (expand-file-name root)))
     (lambda ()
       (puthash root (cons (float-time) (+pascal--unit-names-here))
                +pascal--project-units)))))

(defvar +pascal--kinds nil
  "(ROOT TIME . KIND): the last project's kind and when it was asked.")

(defun +pascal--project-kind-soon ()
  "`+pascal-project-kind' for completion, asked again at most every ten
seconds: a project without an .lpi or .lpr is told by reading its
sources, and completion asks at every key."
  (when-let* ((root (+core-project-root-or-nil)))
    (unless (and (equal root (car +pascal--kinds))
                 (< (- (float-time) (cadr +pascal--kinds)) 10))
      (setq +pascal--kinds (cons root (cons (float-time) (+pascal-project-kind root)))))
    (cddr +pascal--kinds)))

;;;###autoload
(defun +pascal-prefetch-units ()
  "Start reading the names a uses clause offers, as a Pascal buffer of
a project opens, so they are there by the first one."
  (when (derived-mode-p 'opascal-mode)
    (ignore-errors (+pascal--project-units) (+pascal--installed-units))))

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
           (lazarus (eq (+pascal--project-kind-soon) 'lazarus))
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
    (add-hook 'completion-at-point-functions #'+pascal-units-capf -20 t)
    (+pascal-prefetch-units)))
