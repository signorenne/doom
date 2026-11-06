;;; private/cpp/autoload/check.el -*- lexical-binding: t; -*-
;;
;; SPC k c: this file checked, errors only. Its own compile command, the
;; one the kit's compile_commands.json holds, run with -fsyntax-only, -w
;; and no output file, where the kit's builds run: what the compiler
;; says of the file, in a second, with nothing built. A header has no
;; command of its own, so it is checked with the one of a source that
;; includes it, as clangd reads it.

(require 'cl-lib)

(declare-function +cpp--kit "kit")
(declare-function +cpp--compile-commands-file "kit")
(declare-function +cpp--compdb-source "compdb")
(declare-function +cpp--kit-shell "container")
(declare-function +cpp--kind-p "project")
(declare-function +cpp-project-p "project")
(declare-function +cpp--compile "project")
(declare-function +cpp--save-project-buffers "project")
(declare-function +core-project-root "lib")
(defvar +cpp-modes)
(defvar compilation-search-path)

(defconst +cpp--header-extensions
  '("h" "hh" "hpp" "hxx" "h++" "inl" "ipp" "tpp" "tcc")
  "What a header's name ends in.")

(defvar +cpp--compdb-cache (make-hash-table :test #'equal)
  "compile_commands.json to (MTIME . ENTRIES), read once per change.")

(defun +cpp--compdb-entries (db)
  "The entries of compilation database DB as (FILE DIRECTORY . ARGV),
FILE and DIRECTORY absolute.  Read again only when DB changed."
  (let ((mtime (file-attribute-modification-time (file-attributes db)))
        (hit (gethash db +cpp--compdb-cache)))
    (if (and hit (equal (car hit) mtime))
        (cdr hit)
      (let ((entries
             (mapcar (lambda (entry)
                       (let ((dir (file-name-as-directory
                                   (expand-file-name (alist-get 'directory entry)
                                                     (file-name-directory db)))))
                         (cons (expand-file-name (alist-get 'file entry) dir)
                               (cons dir (or (alist-get 'arguments entry)
                                             (split-string-shell-command
                                              (alist-get 'command entry)))))))
                     (condition-case err
                         (with-temp-buffer
                           (insert-file-contents db)
                           (json-parse-buffer :object-type 'alist :array-type 'list))
                       (json-error
                        (user-error "%s cannot be read: %s" db (error-message-string err)))))))
        (puthash db (cons mtime entries) +cpp--compdb-cache)
        entries))))

(defun +cpp--compdb-entry (entries file)
  "The entry of ENTRIES for FILE, absolute, or nil."
  (or (assoc file entries)
      (let ((true (file-truename file)))
        (seq-find (lambda (entry) (equal (file-truename (car entry)) true)) entries))))

(defun +cpp--compdb-includer (entries header)
  "The entry of a source in ENTRIES that includes HEADER by its name, or
nil: a source of the same name first, then one beside it, then any."
  (let* ((name (file-name-nondirectory header))
         (base (file-name-sans-extension name))
         (dir (file-name-directory header))
         (case-fold-search nil)
         (include (format "^[ \t]*#[ \t]*include[ \t]*[<\"]\\(?:[^\">\n]*/\\)?%s[\">]"
                          (regexp-quote name))))
    (seq-find (lambda (entry)
                (and (file-readable-p (car entry))
                     (with-temp-buffer
                       (insert-file-contents (car entry))
                       (re-search-forward include nil t))))
              (seq-sort-by (lambda (entry)
                             (cond ((equal (file-name-base (car entry)) base) 0)
                                   ((equal (file-name-directory (car entry)) dir) 1)
                                   (t 2)))
                           #'< entries))))

(defun +cpp--check-argv (entry &optional header)
  "ENTRY's compile command, (FILE DIRECTORY . ARGV), as a check of its
file alone, errors only: no output file, no dependency file, and
-fsyntax-only -w in front of the file.  With HEADER, that header is
checked in the file's place, in the file's language."
  (pcase-let* ((`(,file ,dir . ,argv) entry)
               (kept nil))
    (while argv
      (let ((arg (pop argv)))
        (cond ((member arg '("-o" "-MF" "-MT" "-MQ")) (pop argv))
              ((member arg '("-MD" "-MMD" "-MP")))
              ((and (string-prefix-p "-o" arg) (> (length arg) 2)
                    (not (string-prefix-p "-objc" arg))))
              ((string-match-p "\\`-M[FTQ]." arg))
              (t (push arg kept)))))
    (setq kept (nreverse kept))
    (let ((at (or (cl-position-if (lambda (arg) (equal (expand-file-name arg dir) file)) kept)
                  (user-error "The compile command of %s does not name it" file))))
      ;; In front of a -- that ends the options, if the file is behind one.
      (let ((front (if (and (> at 0) (equal (nth (1- at) kept) "--")) (1- at) at)))
        (append (seq-take kept front)
                '("-fsyntax-only" "-w")
                (when header
                  (list "-x" (pcase (file-name-extension file)
                               ("c" "c-header")
                               ("m" "objective-c-header")
                               ("mm" "objective-c++-header")
                               (_ "c++-header"))))
                (seq-subseq kept front at)
                (list (or header (nth at kept)))
                (seq-drop kept (1+ at)))))))

;;;###autoload
(defun +cpp/check ()
  "Check this file, errors only: its compile command, with -fsyntax-only.
The command is the one the kit's compile_commands.json holds for the
file, run with no output file where the kit's builds run.  A header with
none of its own is checked with the command of a source that includes it."
  (interactive)
  (unless (+cpp-project-p)
    (user-error "This kind of project cannot be checked"))
  (unless (and buffer-file-name (apply #'derived-mode-p +cpp-modes))
    (user-error "Nothing to check here: SPC k c checks a C or C++ file"))
  (require 'compile)
  (let* ((root (+core-project-root))
         (kit (and (+cpp--kind-p 'cmake) (+cpp--kit root)))
         (db (if kit (+cpp--compile-commands-file kit root) (+cpp--compdb-source root)))
         (file (expand-file-name buffer-file-name))
         (name (file-relative-name file root))
         (remedy (if (+cpp--kind-p 'make) "bear -- make writes it" "SPC k k configures")))
    (unless db
      (user-error "No compile_commands.json to check %s with: %s" name remedy))
    (let* ((entries (+cpp--compdb-entries db))
           (own (+cpp--compdb-entry entries file))
           (header (and (not own) (member (file-name-extension file) +cpp--header-extensions)))
           (entry (or own (and header (+cpp--compdb-includer entries file)))))
      (unless entry
        (if header
            (user-error "No compile command for %s, and no source in %s includes it"
                        name (file-relative-name db root))
          (user-error "No compile command for %s in %s: %s"
                      name (file-relative-name db root) remedy)))
      (+cpp--save-project-buffers)
      (let* ((dir (cadr entry))
             (line (format "cd %s && %s" (shell-quote-argument dir)
                           (mapconcat #'shell-quote-argument
                                      (+cpp--check-argv entry (unless own file))
                                      " ")))
             ;; Its paths are the command's, relative to its directory.
             (compilation-search-path (cons dir compilation-search-path)))
        (message "Checking %s%s, errors only..." name
                 (if own "" (format " with the command of %s" (file-relative-name (car entry) root))))
        (+cpp--compile "check" (if kit (+cpp--kit-shell kit line root) line))))))
