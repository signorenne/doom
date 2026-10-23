;;; check-config.el -*- lexical-binding: t; -*-
;; Loaded into a throwaway daemon by bin/check-config: byte-compile every
;; private file into a temporary directory, then report the compile
;; warnings, the load warnings, the errors in *Messages*, the repeating
;; timers, whether every function the config refers to is callable,
;; whether every private menu sets up and every documented key is
;; bound, and what grows when the config is reloaded twice.

(require 'bytecomp)

(defvar check-config--lists
  '(org-capture-templates dirvish-yank-keys projection-project-types
    dape-configs find-sibling-rules exec-path org-latex-packages-alist
    org-modules gptel-directives savehist-additional-variables
    evil-buffer-regexps auto-mode-alist)
  "Lists the config appends to, watched across a reload with every hook.")

(defun check-config--snapshot ()
  "Every hook, the lists in `check-config--lists', and the repeating
timers, each with a copy of its value, as an alist.  Global values: what
a config file appends to is global, and a buffer's own hooks are its own."
  (let (snapshot)
    (mapatoms (lambda (symbol)
                (when (and (boundp symbol)
                           (string-match-p "-\\(?:hook\\|functions\\)\\'"
                                           (symbol-name symbol))
                           (listp (default-value symbol)))
                  (push (cons symbol (copy-sequence (default-value symbol)))
                        snapshot))))
    (dolist (symbol check-config--lists)
      (when (and (boundp symbol) (listp (default-value symbol)))
        (push (cons symbol (copy-sequence (default-value symbol))) snapshot)))
    (push (cons 'repeating-timers
                (copy-sequence (seq-filter #'timer--repeat-delay timer-list)))
          snapshot)
    snapshot))

(defun check-config--own-regexp ()
  "A regexp matching a name this config defines, by its module prefixes:
the directories under modules/private, and pio for the cpp module."
  (concat "\\+"
          (regexp-opt
           (cons "pio"
                 (mapcar #'file-name-nondirectory
                         (seq-filter #'file-directory-p
                                     (directory-files
                                      (expand-file-name "modules/private" doom-user-dir)
                                      t "\\`[^.]")))))
          "[/-]"))

(defun check-config--ours-p (entry regexp)
  "Non-nil when hook ENTRY comes from this config: a symbol under one of
its prefixes, or a closure whose text names one.  Doom's own modules add
entries on every reload as well, its after-call hooks and general's
deferred bindings, and those are not this config's to keep still."
  (string-match-p regexp (format "%S" entry)))

(defun check-config--reload ()
  "Load the config again, as `doom/reload' does once its doom sync has
run: that command runs the sync in a subprocess first, which a daemon
without a terminal cannot answer, so its in-session half is done here."
  (let ((inhibit-message t))
    (with-doom-context 'reload
      (doom-run-hooks 'doom-before-reload-hook)
      (general-auto-unbind-keys)
      (unwind-protect
          (startup--load-user-init-file nil)
        (general-auto-unbind-keys t))
      (doom-run-hooks 'doom-after-reload-hook))))

(defun check-config--reload-growth ()
  "Reload the config twice and return what the second reload grew, as
lines.  A form that appends to a list, adds a hook or starts a timer
without removing its own entry first shows here.  The first reload is
not compared: Doom's own modules add hooks lazily while it runs, evil's
and solaire's, which the second reload must leave alone.  The packages
whose lists the config touches are loaded first, so their lists exist."
  (dolist (feature '(org-capture dirvish-yank projection org-roam dape gptel))
    (require feature nil t))
  (check-config--reload)
  (let ((before (check-config--snapshot))
        (ours (check-config--own-regexp)))
    (check-config--reload)
    (let ((after (check-config--snapshot)) grown)
      (pcase-dolist (`(,symbol . ,was) before)
        (let* ((now (alist-get symbol after))
               (added (and now (> (length now) (length was))
                           (seq-difference now was))))
          ;; A watched list or a timer is this config's whatever was added;
          ;; a hook counts only for entries of this config.
          (when (and added
                     (or (memq symbol check-config--lists)
                         (eq symbol 'repeating-timers)
                         (seq-some (lambda (entry) (check-config--ours-p entry ours))
                                   added)))
            (push (format "%s grew: %d -> %d, %s" symbol (length was) (length now)
                          (mapconcat (lambda (entry)
                                       (let ((text (format "%S" entry)))
                                         (if (> (length text) 60)
                                             (concat (substring text 0 60) "...")
                                           text)))
                                     (seq-take added 3) "; "))
                  grown))))
      (nreverse grown))))

(defun check-config--arity-fits (got need)
  "Non-nil when a function taking GOT, a `func-arity', can be called
with NEED arguments, another."
  (and (<= (car got) (car need))
       (or (eq (cdr got) 'many)
           (and (numberp (cdr need)) (>= (cdr got) (cdr need))))))

(defun check-config--advice-problems ()
  "This config's advice that cannot take what it will be given.
An advice called with more arguments than it accepts signals, but only
when that path runs: SPC q q stopped on one for ten days.  A function
whose library is not loaded yet keeps its advice waiting on the
symbol; the library is loaded so the advice is in place to look at."
  (let ((ours (check-config--own-regexp)) problems)
    (mapatoms (lambda (symbol)
                (when (and (get symbol 'advice--pending)
                           (autoloadp (symbol-function symbol)))
                  (ignore-errors (autoload-do-load (symbol-function symbol) symbol)))))
    (mapatoms
     (lambda (symbol)
       (let ((def (and (fboundp symbol) (advice--symbol-function symbol))))
         (when (advice--p def)
           (let* ((original (advice--cd*r def))
                  (arity (and (not (autoloadp original)) (not (macrop original))
                              (ignore-errors (func-arity original)))))
             (when (consp arity)
               (while (advice--p def)
                 (let* ((advice (advice--car def))
                        (how (if (fboundp 'advice--how) (advice--how def) (advice--where def)))
                        (got (ignore-errors (func-arity advice)))
                        (need (pcase how
                                ((or :filter-args :filter-return) '(1 . 1))
                                (:around (cons (1+ (car arity))
                                               (if (numberp (cdr arity)) (1+ (cdr arity)) (cdr arity))))
                                (_ arity))))
                   (when (and (symbolp advice) (consp got)
                              (string-match-p ours (symbol-name advice))
                              (not (check-config--arity-fits got need)))
                     (push (format "%s on %s %s takes %S, is given %S" advice symbol how got need)
                           problems)))
                 (setq def (advice--cdr def)))))))))
    problems))

;; A question asked in the daemon waits for an answer no one can give,
;; so the check would hang (vterm, for one, offers to compile its
;; module). Each question signals an error instead, naming itself.
(defconst check-config--questions
  '(read-from-minibuffer read-key y-or-n-p yes-or-no-p)
  "What asks the user something, behind every prompt there is.")

(defun check-config--refuse-question (&optional prompt &rest _)
  "Signal that PROMPT was asked, rather than wait for an answer."
  (error "check-config: the daemon was asked %S" prompt))

(defun check-config--run (out log)
  "Compile into OUT and write the report to LOG."
  (dolist (fn check-config--questions)
    (advice-add fn :before #'check-config--refuse-question))
  (let* (;; Asked before compiling: compiling defines every command, and
         ;; one missing from the session the sheet was generated from
         ;; would read as drift. An error, a refused question among
         ;; them, is reported rather than read as an up to date sheet.
         (stale (and (fboundp '+docs-sheet-stale-p)
                     (condition-case err (+docs-sheet-stale-p)
                       (error (list 'error err)))))
         (root doom-user-dir)
         (files (append (list (expand-file-name "init.el" root)
                              (expand-file-name "config.el" root))
                        (directory-files-recursively
                         (expand-file-name "modules/private" root) "\\.el\\'")))
         (byte-compile-dest-file-function
          (lambda (file)
            (concat out (replace-regexp-in-string
                         "/" "__" (file-relative-name file root))
                    "c")))
         (byte-compile-warnings t)
         (byte-compile-verbose nil)
         failed)
    (make-directory out t)
    (when (get-buffer "*Compile-Log*")
      (with-current-buffer "*Compile-Log*"
        (let ((inhibit-read-only t)) (erase-buffer))))
    (dolist (file (sort files #'string<))
      (condition-case err
          (byte-compile-file file)
        (error (push (format "%s: %S" (file-relative-name file root) err) failed))))
    (with-temp-file log
      (insert (format "%d files, %d failed to compile\n" (length files) (length failed)))
      (dolist (f failed) (insert "  " f "\n"))
      ;; A package that loads later is not a finding ("might not be
      ;; defined", wrapped by the compiler), nor is Doom's own init
      ;; macro, nor the function `custom-set-faces!' names after a
      ;; gensym and defines in the same breath.
      (insert "\ncompile log, errors and warnings:\n")
      (when (get-buffer "*Compile-Log*")
        (dolist (line (split-string (with-current-buffer "*Compile-Log*" (buffer-string))
                                    "\n" t))
          (when (and (string-match-p "Error\\|Warning" line)
                     (not (string-match-p "might not\\|doom-module--put\\|the function$\\|doom--customize-themes-h-" line)))
            (insert "  " line "\n"))))
      (insert "\n*Warnings* at startup, this config's:\n")
      (when (get-buffer "*Warnings*")
        (dolist (line (split-string (with-current-buffer "*Warnings*" (buffer-string)) "\n" t))
          (when (and (string-match-p "Warning" line)
                     (not (string-match-p "site-lisp" line)))
            (insert "  " line "\n"))))
      (insert "\n*Messages* lines with error, void or failed:\n")
      (dolist (line (split-string (with-current-buffer "*Messages*" (buffer-string)) "\n" t))
        (when (string-match-p "rror\\|void\\|failed" line) (insert "  " line "\n")))
      (insert "\nrepeating timers on a frameless daemon:\n")
      (dolist (tm timer-list)
        (when (timer--repeat-delay tm)
          (insert (format "  %S every %S s\n" (timer--function tm) (timer--repeat-delay tm)))))
      (insert "\nthe sheet's generated tables: ")
      (insert (if (fboundp '+docs-sheet-stale-p)
                  (pcase stale
                    (`(error ,err) (format "1 problem(s): the check stopped, %S" err))
                    ('nil "say what the config binds today")
                    (_ "out of date, press gr in the sheet"))
                "no +docs-sheet-stale-p, the docs module is off")
              "\n")

      (insert "\nfunctions the config refers to: ")
      (insert (cl-letf (((symbol-function 'message) #'format))
                (if (fboundp '+docs/check-autoloads)
                    (+docs/check-autoloads)
                  "no +docs/check-autoloads, the docs module is off"))
              "\n")
      (insert "\nthe menus, the leader and the documented keys: ")
      (insert (if (fboundp '+docs/check-keys)
                  (let ((problems (append (+docs-menu-problems) (+docs-leader-problems)
                                          (+docs-key-problems) (+docs-binding-problems)
                                          (when (fboundp '+docs-module-problems)
                                            (+docs-module-problems)))))
                    (if problems
                        (format "%d problem(s)\n%s" (length problems)
                                (mapconcat (lambda (p) (concat "  " p "\n")) problems ""))
                      "every menu sets up clean, the leader holds up, every documented key is bound"))
                "no +docs/check-keys, the docs module is off")
              "\n")
      (insert "\nadvice against what it advises: ")
      (let ((problems (check-config--advice-problems)))
        (insert (if problems
                    (format "%d problem(s)\n%s" (length problems)
                            (mapconcat (lambda (p) (concat "  " p "\n")) problems ""))
                  "every advice of this config takes the arguments it is given")
                "\n"))
      (insert "\nafter two reloads:\n")
      (let ((grown (check-config--reload-growth)))
        (if grown
            (dolist (line grown) (insert "  " line "\n"))
          (insert "  nothing grew\n"))))
    t))
