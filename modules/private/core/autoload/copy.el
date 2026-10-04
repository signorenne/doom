;;; private/core/autoload/copy.el -*- lexical-binding: t; -*-
;;
;; Copying things about the file you are in: its name, its path in the
;; forms a terminal or a chat wants, a line reference, a block of code
;; with the reference on top. SPC f k shows them all with their values.

(require 'transient)

(declare-function +core-project-root-or-nil "lib")

(defun +core--project-path (file)
  "FILE relative to the project, or abbreviated when there is no project.
The project is `+core-project-root\=''s, which knows the CMake and
PlatformIO roots the cpp module registers; `doom-project-root\=' does not,
and gave an absolute path in a tree projectile does not claim."
  (if-let* ((root (+core-project-root-or-nil)))
      (file-relative-name file root)
    (abbreviate-file-name file)))

(defun +core--yank (text what)
  "Put TEXT on the kill ring and say WHAT it was."
  (kill-new text)
  (message "Copied the %s: %s" what
           (if (string-match-p "\n" text)
               (format "%d lines" (length (split-string text "\n" t)))
             text)))

;;;###autoload
(defun +core/yank-file-name ()
  "Copy the name of this file, without its directory."
  (interactive)
  (+core--yank (file-name-nondirectory (+core-file-at-point)) "file name"))

;;;###autoload
(defun +core/yank-file-directory ()
  "Copy the absolute directory this file is in."
  (interactive)
  (+core--yank (file-name-directory (expand-file-name (+core-file-at-point)))
               "directory"))

;;;###autoload
(defun +core/yank-file-path ()
  "Copy the absolute path of this file, with ~ expanded."
  (interactive)
  (+core--yank (expand-file-name (+core-file-at-point)) "absolute path"))

;;;###autoload
(defun +core/yank-project-path ()
  "Copy the path of this file relative to the project root."
  (interactive)
  (+core--yank (+core--project-path (expand-file-name (+core-file-at-point)))
               "project path"))

(defun +core--line-reference ()
  "path:line for point, or path:first-last for the region."
  (let ((path (+core--project-path (expand-file-name (+core-file-at-point)))))
    (if (use-region-p)
        (format "%s:%d-%d" path
                (line-number-at-pos (region-beginning))
                (line-number-at-pos (max (region-beginning) (1- (region-end)))))
      (format "%s:%d" path (line-number-at-pos)))))

;;;###autoload
(defun +core/yank-file-line ()
  "Copy path:line, or path:first-last with a region, relative to the project.
The form an issue, a review or an agent understands."
  (interactive)
  (+core--yank (+core--line-reference) "reference"))

;;;###autoload
(defun +core/yank-code-block ()
  "Copy the region, or the whole buffer, as a fenced code block.
The first line is the path:line reference, then the fence with the
language, so it pastes into a chat or an issue as it is."
  (interactive)
  (let* ((beg (if (use-region-p) (region-beginning) (point-min)))
         (end (if (use-region-p) (region-end) (point-max)))
         (text (string-trim-right (buffer-substring-no-properties beg end))))
    (+core--yank (format "%s\n```%s\n%s\n```\n"
                         (+core--line-reference)
                         (+core-language major-mode)
                         text)
                 "code block")))

;;;###autoload
(defun +core/yank-symbol ()
  "Copy the symbol under the cursor."
  (interactive)
  (+core--yank (or (thing-at-point 'symbol t)
                   (user-error "No symbol under the cursor"))
               "symbol"))

;;
;;; The menu

(defun +core--copy-description (label value)
  "Menu line: LABEL, then VALUE shortened to fit."
  (let ((shown (if (> (length value) 60)
                   (concat "..." (substring value (- (length value) 57)))
                 value)))
    (format "%-12s %s" label (propertize shown 'face 'font-lock-comment-face))))

(defun +core--copy-file-value (fn)
  "FN applied to this file, or an empty string outside a file buffer."
  (condition-case nil
      (funcall fn (expand-file-name (+core-file-at-point)))
    (user-error "")))

;;;###autoload (autoload '+core/copy-menu "private/core/autoload/copy" nil t)
(transient-define-prefix +core/copy-menu ()
  "Copy something about this file; each line shows what you would get."
  [:description
   (lambda () (format "Copy from %s"
                      (propertize (condition-case nil
                                      (abbreviate-file-name (+core-file-at-point))
                                    (user-error "no file"))
                                  'face 'bold)))
   ["Path"
    ("n" +core/yank-file-name
     :description (lambda () (+core--copy-description
                              "name" (+core--copy-file-value #'file-name-nondirectory))))
    ("p" +core/yank-project-path
     :description (lambda () (+core--copy-description
                              "in project" (+core--copy-file-value #'+core--project-path))))
    ("a" +core/yank-file-path
     :description (lambda () (+core--copy-description
                              "absolute" (+core--copy-file-value #'identity))))
    ("d" +core/yank-file-directory
     :description (lambda () (+core--copy-description
                              "directory" (+core--copy-file-value #'file-name-directory))))]
   ["Here"
    ("l" +core/yank-file-line
     :description (lambda () (+core--copy-description
                              "path:line" (condition-case nil (+core--line-reference)
                                            (user-error "")))))
    ("c" "code block, region or buffer" +core/yank-code-block)
    ("s" +core/yank-symbol
     :description (lambda () (+core--copy-description
                              "symbol" (or (thing-at-point 'symbol t) ""))))
    ("g" "link on the forge, this line or region" +vc/browse-at-remote-kill
     :if (lambda () (fboundp '+vc/browse-at-remote-kill)))]
   ["The file"
    ("t" "its whole text" +core/copy-file-contents)
    ("f" "the file itself, to paste in another app" +core/files-to-clipboard)]])
