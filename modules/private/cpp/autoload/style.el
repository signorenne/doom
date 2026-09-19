;;; private/cpp/autoload/style.el -*- lexical-binding: t; -*-
;;
;; clang-format and clang-tidy, on a buffer or on the project, where the
;; kit runs.

(declare-function +cpp--save-project-buffers "project")
(declare-function +cpp-kit-dir "kit")
(declare-function clang-format-buffer "clang-format")
(declare-function clang-format-region "clang-format")


;;
;;; Style gates

(defvar +cpp-tidy-file-filter
  "^(?!.*/build/).*/(src|include|modules|tests|examples)/"
  "Regexp choosing which files `+cpp/tidy-project' lints.
The compilation database also lists generated code, moc output and fetched
dependencies; this keeps them out of the report.")

;;;###autoload
(defun +cpp/format-buffer (&optional beg end)
  "Run clang-format on the buffer, or on BEG to END.
Uses the project's .clang-format, or LLVM style when there is none."
  (interactive (when (use-region-p) (list (region-beginning) (region-end))))
  (require 'clang-format)
  (if (and beg end)
      (clang-format-region beg end)
    (clang-format-buffer)))

(defun +cpp--git-sources (root)
  "Tracked C and C++ files under ROOT."
  (let ((default-directory root))
    (with-temp-buffer
      (unless (zerop (call-process "git" nil t nil "ls-files"
                                   "*.c" "*.cc" "*.cpp" "*.h" "*.hh" "*.hpp"))
        (user-error "git ls-files failed: %s" (string-trim (buffer-string))))
      (split-string (buffer-string) "\n" t))))

;;;###autoload
(defun +cpp/format-project ()
  "Run clang-format over every tracked C and C++ file in the project."
  (interactive)
  (unless (executable-find "clang-format")
    (user-error "clang-format is not installed"))
  (let* ((root (+core-project-root))
         (files (+cpp--git-sources root))
         (default-directory root))
    (unless files
      (user-error "No tracked C or C++ files in %s"
                  (abbreviate-file-name root)))
    (when (y-or-n-p (format "Format %d file(s) in %s? "
                            (length files)
                            (abbreviate-file-name root)))
      (+cpp--compile "clang-format"
                     (mapconcat #'shell-quote-argument
                                (append (list "clang-format" "-i") files)
                                " ")))))

;;;###autoload
(defun +cpp/tidy-project ()
  "Run clang-tidy over the project through run-clang-tidy, where the kit
runs, on the kit's compilation database.  With a prefix argument, apply
the fixes clang-tidy proposes."
  (interactive)
  (let* ((root (+core-project-root))
         (kit (+cpp--kit root))
         (dir (+cpp-kit-dir kit)))
    (unless (+cpp--compile-commands-file kit root)
      (user-error "No compile_commands.json in %s, configure first with SPC k c"
                  dir))
    (+cpp--compile "clang-tidy"
                   (+cpp--kit-shell
                    kit
                    (mapconcat #'shell-quote-argument
                               (append (list "run-clang-tidy" "-p" dir "-quiet")
                                       (when current-prefix-arg (list "-fix"))
                                       (list +cpp-tidy-file-filter))
                               " ")))))

;;;###autoload
(defun +cpp/tidy-file (&optional fix)
  "Run clang-tidy on this buffer's file, where the kit runs.
With FIX, a prefix argument, apply the fixes it proposes and revert."
  (interactive "P")
  (unless buffer-file-name
    (user-error "This buffer is not visiting a file"))
  (+cpp--save-project-buffers)
  (let ((kit (+cpp--kit)))
    (+cpp--compile "clang-tidy"
                   (+cpp--kit-shell
                    kit
                    (mapconcat #'shell-quote-argument
                               (append (list "clang-tidy" (format "-p=%s" (+cpp-kit-dir kit)))
                                       (when fix (list "--fix"))
                                       (list buffer-file-name))
                               " ")))))
