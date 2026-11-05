;;; private/uml/autoload/scaffold.el -*- lexical-binding: t; -*-
;;
;; A new diagram from a template, and a rendered file out of one.

(declare-function +uml-render "server")
(declare-function +uml--diagram "preview")

(defvar +uml-diagram-kinds
  '(("sequence"    . "who talks to whom, in order")
    ("state"       . "a state machine and its transitions")
    ("activity"    . "a flow, with decisions and branches")
    ("component"   . "boxes and the links between them")
    ("class"       . "classes, fields and relationships")
    ("er"          . "entities and their keys")
    ("c4-context"  . "C4 level 1: the system and who uses it")
    ("c4-container". "C4 level 2: the parts it is deployed as")
    ("c4-component". "C4 level 3: inside one part")
    ("timing"      . "signals against time, for a bus or a protocol")
    ("bitfield"    . "a register laid out bit by bit"))
  "The templates in `+uml-templates-dir', and what each is for.")

(defun +uml--read-kind ()
  "Ask which kind of diagram, showing what each is for."
  (let* ((width (apply #'max (mapcar (lambda (k) (length (car k)))
                                     +uml-diagram-kinds)))
         (choices (mapcar (lambda (kind)
                            (cons (format (format "%%-%ds  %%s" width)
                                          (car kind) (cdr kind))
                                  (car kind)))
                          +uml-diagram-kinds)))
    (cdr (assoc (completing-read "Diagram: " choices nil t) choices))))

;;;###autoload
(defun +uml/new-diagram (kind name)
  "Start a new diagram of KIND called NAME, from the template for it."
  (interactive
   (let ((kind (+uml--read-kind)))
     (list kind (read-string (format-prompt "Name" "diagram") nil nil "diagram"))))
  ;; A name, not a path: nothing, or a slash, would write "   .puml" or
  ;; outside this folder.
  (setq name (string-trim name))
  (cond ((string-empty-p name) (user-error "A diagram needs a name"))
        ((string-match-p "/" name) (user-error "Name the diagram, not a path: %s" name)))
  (let ((template (file-name-concat +uml-templates-dir (concat kind ".puml"))))
    (unless (file-exists-p template)
      (user-error "No template for %s in %s" kind +uml-templates-dir))
    (let ((file (expand-file-name
                 (if (string-suffix-p ".puml" name) name (concat name ".puml"))
                 default-directory)))
      (when (and (file-exists-p file)
                 (not (yes-or-no-p (format "%s exists. Replace it? " file))))
        (user-error "Left alone"))
      (copy-file template file t)
      (find-file file)
      ;; The template says TITLE where the diagram's own name goes, in
      ;; capitals: the keyword before it, title, is not one of them.
      (save-excursion
        (goto-char (point-min))
        (while (let ((case-fold-search nil))
                 (search-forward "TITLE" nil t))
          (replace-match (file-name-base file) t t)))
      (save-buffer)
      (message "%s diagram: %s" kind (file-name-nondirectory file)))))

;;;###autoload
(defun +uml/export (format file)
  "Write this diagram, or the one the view shows, to FILE as FORMAT."
  (interactive
   ;; Anywhere else it says so before asking anything.
   (with-current-buffer (+uml--diagram)
     (let* ((format (intern (completing-read (format-prompt "As" "svg") '("svg" "png") nil t nil nil "svg")))
            (default (concat (file-name-base (or (buffer-file-name) "diagram"))
                             "." (symbol-name format))))
       (list format (read-file-name "Write to: " nil nil nil default)))))
  (with-current-buffer (+uml--diagram)
    (setq file (expand-file-name file))
    (when (and (file-exists-p file)
               (not (y-or-n-p (format "%s exists; replace it? " (abbreviate-file-name file)))))
      (user-error "Nothing written"))
    ;; A diagram that does not parse, or a server that does not answer,
    ;; is the user's to fix, and leaves the file as it was.
    (let ((data (condition-case err
                    (+uml-render (buffer-substring-no-properties (point-min) (point-max)) format)
                  (error (user-error "%s; nothing written" (error-message-string err))))))
      (with-temp-file file
        (set-buffer-multibyte nil)
        (insert data))
      (message "Wrote %s" (abbreviate-file-name file)))))
