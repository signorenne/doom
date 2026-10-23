;;; private/core/autoload/docsets.el -*- lexical-binding: t; -*-
;;
;; Installs the offline documentation SPC s k searches, Doom's Dash
;; docsets, with nothing done by hand: the first file of a language
;; opened starts a background download of the docsets Doom names for it
;; (`set-docsets!'), bin/install-docset trying each mirror. The C and
;; C++ docsets are large, so each is downloaded only once.

(defvar dash-docs-docsets)
(declare-function doom-profile-data-dir "doom-lib")

(defvar +core-docsets-auto-install t
  "Non-nil installs the docsets of a file's language when it opens.")

(defvar +core-docsets-skip '("Boost")
  "Docsets never installed by themselves: Boost, which Doom names for
C++, is large and no project here uses it.")

(defvar +core--docsets-started nil
  "Docsets whose installation this session started, done or not.")

(defun +core--docsets-dir ()
  "Where Doom's lookup keeps the docsets."
  (doom-profile-data-dir t "docsets/"))

(defun +core--docsets-missing (names)
  "The docsets of NAMES that are not installed."
  (seq-remove (lambda (name)
                (file-directory-p (expand-file-name (concat name ".docset")
                                                    (+core--docsets-dir))))
              names))

(defun +core--docsets-install (names)
  "Install the docsets NAMES in the background, one process each."
  (dolist (name names)
    (push name +core--docsets-started)
    (message "Docset %s: downloading in the background for SPC s k" name)
    (make-process
     :name (concat "install-docset " name)
     :buffer (generate-new-buffer (format " *install-docset %s*" name))
     :noquery t
     :command (list (expand-file-name "bin/install-docset" doom-user-dir)
                    name (+core--docsets-dir))
     :sentinel
     (lambda (process _event)
       (unless (process-live-p process)
         (let ((said (with-current-buffer (process-buffer process)
                       (string-trim (buffer-string)))))
           (kill-buffer (process-buffer process))
           (if (zerop (process-exit-status process))
               (message "Docset %s: installed, SPC s k searches it" name)
             (message "Docset %s: not installed (%s); M-x +core/install-docsets tries again"
                      name said))))))))

;;;###autoload
(defun +core--docsets-h ()
  "Start installing the docsets of this file's language that are missing."
  (when-let* ((+core-docsets-auto-install)
              ((not (file-remote-p default-directory)))
              (names (seq-difference (bound-and-true-p dash-docs-docsets)
                                     (append +core-docsets-skip +core--docsets-started)))
              (missing (+core--docsets-missing names)))
    (+core--docsets-install missing)))

;;;###autoload
(defun +core/install-docsets (&optional all)
  "Install the docsets of this buffer's language that are missing, again
if a try failed; with ALL, the skipped ones too."
  (interactive "P")
  (let* ((names (bound-and-true-p dash-docs-docsets))
         (names (if all names (seq-difference names +core-docsets-skip)))
         (missing (+core--docsets-missing names)))
    (cond ((null names) (user-error "No docsets are named for %s" major-mode))
          ((null missing) (message "Docsets %s: installed" (string-join names ", ")))
          (t (setq +core--docsets-started (seq-difference +core--docsets-started missing))
             (+core--docsets-install missing)))))
