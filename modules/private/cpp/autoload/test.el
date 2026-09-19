;;; private/cpp/autoload/test.el -*- lexical-binding: t; -*-
;;
;; Run the test point is inside, or a whole test executable, where the
;; kit runs.


;;
;;; Running one test

(defun +cpp--test-framework ()
  "Which test framework this buffer uses: `doctest', `qt' or nil."
  (save-excursion
    (goto-char (point-min))
    (cond ((re-search-forward "^#include <doctest/" 5000 t) 'doctest)
          ((re-search-forward "^#include <QTest>" 5000 t) 'qt))))

(defun +cpp--doctest-case-at-point ()
  "Name of the doctest case point is inside, or nil."
  (save-excursion
    (when (re-search-backward
           "^\\s-*TEST_CASE\\(?:_TEMPLATE\\)?\\s-*(\\s-*\"\\([^\"]+\\)\""
           nil t)
      (match-string-no-properties 1))))

(defun +cpp--qt-slot-at-point ()
  "Name of the QtTest slot point is inside, or nil."
  (save-excursion
    (when (re-search-backward
           "^\\(?:void\\s-+\\)?\\(?:[A-Za-z_][A-Za-z0-9_]*::\\)?\\([a-z][A-Za-z0-9_]*\\)\\s-*(\\s-*)"
           nil t)
      (match-string-no-properties 1))))

(defun +cpp--test-binaries ()
  "Test executables of the kit, newest first.
What ctest registered, which knows a tests/ subdirectory and any other
layout; when nothing is registered, the executables named test at the
top of the build directory or in its bin/."
  (when-let* ((build (+cpp--build-directory))
              ((file-directory-p build)))
    (let ((files (or (seq-uniq
                      (delq nil
                            (mapcar (lambda (artifact)
                                      (and (eq (alist-get 'type artifact) 'cmake-test)
                                           (alist-get 'arg0 artifact)))
                                    (+cpp--artifacts))))
                     (append (file-expand-wildcards
                              (expand-file-name "bin/*test*" build))
                             (file-expand-wildcards
                              (expand-file-name "*test*" build))))))
      (thread-last files
                   (seq-filter #'file-executable-p)
                   (seq-remove #'file-directory-p)
                   (seq-sort-by (lambda (f)
                                  (float-time
                                   (file-attribute-modification-time
                                    (file-attributes f))))
                                #'>)))))

(defun +cpp--test-binary ()
  "The test executable to run, asking when there is more than one."
  (let ((binaries (+cpp--test-binaries)))
    (pcase (length binaries)
      (0 (user-error "No test executable in %s, build first with SPC k b"
                     (abbreviate-file-name (or (+cpp--build-directory) "?"))))
      (1 (car binaries))
      (_ (completing-read "Test binary: " binaries nil t)))))

;;;###autoload
(defun +cpp/test-at-point ()
  "Run only the test point is inside.
Reads the case name from the buffer and passes it to the test binary:
--test-case for doctest, the slot name for QtTest.  Build first; this runs
what is in the build directory."
  (interactive)
  (let* ((framework (or (+cpp--test-framework)
                        (user-error "No doctest or QTest include in this file")))
         (name (or (pcase framework
                     ('doctest (+cpp--doctest-case-at-point))
                     ('qt (+cpp--qt-slot-at-point)))
                   (user-error "Point is not inside a test case")))
         (binary (+cpp--test-binary)))
    (+cpp--compile "test"
                   (+cpp--kit-shell
                    (+cpp--kit)
                    (mapconcat
                     #'shell-quote-argument
                     (pcase framework
                       ('doctest (list binary (format "--test-case=%s" name)))
                       ('qt (list binary name)))
                     " ")))))

;;;###autoload
(defun +cpp/test-binary ()
  "Run a whole test executable, choosing it when there are several."
  (interactive)
  (+cpp--compile "test" (+cpp--kit-shell (+cpp--kit)
                                         (shell-quote-argument (+cpp--test-binary)))))
