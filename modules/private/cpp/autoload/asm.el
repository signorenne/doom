;;; private/cpp/autoload/asm.el -*- lexical-binding: t; -*-
;;
;; Assembly, live: rmsbolt compiles the buffer with the compiler and the
;; flags the compilation database records for it, shows the assembly in
;; the other window, and highlights the lines that came from the line the
;; cursor is on. For a kit whose compiler lives in a container, the
;; compile runs there.

(defvar rmsbolt-command)
(defvar rmsbolt-default-directory)
(defvar rmsbolt-mode)
(declare-function rmsbolt-mode "rmsbolt")
(declare-function rmsbolt-compile "rmsbolt")
(declare-function +cpp--kit "kit")
(declare-function +cpp--kit-shell "container")
(declare-function +cpp-kit-container "kit")
(declare-function +cpp-kit-abs-dir "kit")
(declare-function +cpp-kit-name "kit")
(declare-function +cpp--compile-commands-file "kit")
(declare-function +cpp--kind-p "project")

(defvar-local +cpp--asm-kit nil
  "The kit an rmsbolt compile of this buffer runs with, when it is a
CMake project; set by `+cpp/assembly', cleared when the view goes.")

(defun +cpp--asm-wrap-a (fn command &optional mode name-function &rest args)
  "Advice on `compilation-start': an rmsbolt compile of a CMake project
runs where the kit runs.  rmsbolt starts the compilation from the source
buffer, so the buffer-local kit is visible here.  Only rmsbolt's own
compilation is wrapped: a build from this buffer is already wrapped by
the kit, and wrapping it twice nests one container enter in another."
  (apply fn
         (if (and +cpp--asm-kit
                  (bound-and-true-p rmsbolt-mode)
                  (functionp name-function)
                  (equal (funcall name-function mode) "*rmsbolt-compilation*"))
             (+cpp--kit-shell +cpp--asm-kit command
                              (or (bound-and-true-p rmsbolt-default-directory)
                                  default-directory))
           command)
         mode name-function args))

(defun +cpp--asm-entries (db)
  "The entries of compilation database DB, each (FILE DIRECTORY COMMAND)."
  (with-temp-buffer
    (insert-file-contents db)
    (goto-char (point-min))
    (mapcar (lambda (entry)
              (let ((dir (gethash "directory" entry))
                    (file (gethash "file" entry)))
                (list (expand-file-name file dir)
                      dir
                      (or (gethash "command" entry)
                          (combine-and-quote-strings
                           (append (gethash "arguments" entry) nil))))))
            (json-parse-buffer :array-type 'array))))

(defun +cpp--asm-strip (command file directory)
  "COMMAND without its output, its -c or -S, LTO, and the source FILE,
named absolutely or relative to DIRECTORY, the entry's.  Done on the
string: a database command may carry escaped quotes that no tokeniser
of ours reads back the way the shell will."
  (let ((out (concat " " command " ")))
    ;; Each pattern eats the word and the space after it; the space
    ;; before it stays, so the next pattern still finds its own.
    (dolist (re (list "-o[ \t]+[^ \t]+[ \t]"
                      "-[cS][ \t]"
                      "-flto[^ \t]*[ \t]"
                      (concat (regexp-quote file) "[ \t]")
                      (concat (regexp-quote (file-relative-name file directory))
                              "[ \t]")))
      (setq out (replace-regexp-in-string (concat "[ \t]" re) " " out t t)))
    (string-trim out)))

(defun +cpp--asm-flags-near (file kit)
  "The compiler and flags for FILE from KIT's database: its own entry,
else borrowed from the nearest file, the one with the same stem in its
directory, else any file of its directory.  Returns (DIRECTORY COMMAND
BORROWED-FROM), BORROWED-FROM nil for the file's own entry; nil without
a database or an entry."
  (when-let* ((db (+cpp--compile-commands-file kit))
              ((file-readable-p db))
              (entries (+cpp--asm-entries db)))
    (let* ((file (expand-file-name file))
           (dir (file-name-directory file))
           (stem (car (split-string (file-name-nondirectory file) "\\.")))
           (mine (seq-find (lambda (e) (file-equal-p (car e) file)) entries))
           (near (or (seq-find (lambda (e)
                                 (and (file-equal-p (file-name-directory (car e)) dir)
                                      (equal (car (split-string (file-name-nondirectory (car e)) "\\."))
                                             stem)))
                               entries)
                     (seq-find (lambda (e) (file-equal-p (file-name-directory (car e)) dir))
                               entries))))
      (cond (mine (list (nth 1 mine)
                        (+cpp--asm-strip (nth 2 mine) (car mine) (nth 1 mine))
                        nil))
            (near (list (nth 1 near)
                        (+cpp--asm-strip (nth 2 near) (car near) (nth 1 near))
                        (car near)))))))

;;;###autoload
(defun +cpp/assembly ()
  "Show the assembly this file compiles to, beside it, and keep it fresh.
The lines of assembly that come from the line the cursor is on are
highlighted, and the view recompiles as you edit.  Again, and it stops.
C and C++ use the compilation database; Rust, Go, Zig, Java and a few
more use their own compiler."
  (interactive)
  (require 'rmsbolt)
  (unless buffer-file-name
    (user-error "This buffer is not visiting a file"))
  (if (bound-and-true-p rmsbolt-mode)
      (progn (rmsbolt-mode -1)
             (kill-local-variable '+cpp--asm-kit)
             ;; The advice stays while another buffer still has a view.
             (unless (seq-some (lambda (buffer)
                                 (buffer-local-value '+cpp--asm-kit buffer))
                               (buffer-list))
               (advice-remove #'compilation-start #'+cpp--asm-wrap-a))
             (message "Assembly view off"))
    ;; Intermediate files go under the home directory, which a container
    ;; shares; /tmp it does not.
    (let ((temporary-file-directory (expand-file-name "~/.cache/rmsbolt/")))
      (make-directory temporary-file-directory t)
      (setq +cpp--asm-kit (and (+cpp--kind-p 'cmake) (+cpp--kit)))
      ;; The flags come from the kit's database rather than from a link
      ;; rmsbolt would look for above the file.  A file the kit does not
      ;; build, foo.arm.cpp under a PC kit, has no entry of its own:
      ;; borrow the flags of its nearest sibling rather than fall back to
      ;; a bare g++ that knows no include path.
      (kill-local-variable 'rmsbolt-command)
      (kill-local-variable 'rmsbolt-default-directory)
      (when-let* ((near (and +cpp--asm-kit
                             (+cpp--asm-flags-near buffer-file-name +cpp--asm-kit))))
        (setq-local rmsbolt-default-directory (nth 0 near)
                    rmsbolt-command (nth 1 near))
        (when (nth 2 near)
          (message "%s is not built by kit %s; compiling it with the flags of %s"
                   (file-name-nondirectory buffer-file-name)
                   (+cpp-kit-name +cpp--asm-kit)
                   (file-name-nondirectory (nth 2 near)))))
      (advice-add #'compilation-start :around #'+cpp--asm-wrap-a)
      (rmsbolt-mode 1)
      (rmsbolt-compile))
    (message "Assembly view: the other window follows the cursor; %s turns it off"
             (substitute-command-keys "\\[+cpp/assembly]"))))
