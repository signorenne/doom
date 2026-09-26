;;; private/core/autoload/data.el -*- lexical-binding: t; -*-
;;
;; Validate, prettify and compact a data file, whatever format it is in.
;;
;; Validation is `bin/check-data', one program that reads each format
;; with its own real parser. It lives outside Emacs so it can be run over
;; every data file on the machine to catch a wrong verdict; three of the
;; checks it replaced were wrong on real files in ways no single test
;; file showed. Reshaping goes through the tool that knows the format and
;; keeps what the author wrote: comments, key names, number literals.

(defvar +data-checker (file-name-concat doom-user-dir "bin/check-data")
  "The program that says whether a data file is valid.")

(defvar +data-schemastore-url "https://www.schemastore.org/api/json/catalog.json"
  "Where SchemaStore publishes which schema belongs to which file name.")

(defvar +data-schemastore-max-age (* 7 24 60 60)
  "Seconds before the cached catalog is fetched again.")

(defun +data--kind (&optional buffer)
  "Which data format BUFFER holds, as a symbol, or nil."
  (with-current-buffer (or buffer (current-buffer))
    (cond ((derived-mode-p 'json-mode 'json-ts-mode 'jsonc-mode 'js-json-mode) 'json)
          ((derived-mode-p 'yaml-mode 'yaml-ts-mode) 'yaml)
          ((derived-mode-p 'toml-ts-mode 'conf-toml-mode) 'toml)
          ((derived-mode-p 'nxml-mode 'xml-mode) 'xml)
          ((derived-mode-p 'csv-mode) 'csv)
          ((derived-mode-p 'conf-mode) 'conf)
          ((and buffer-file-name
                (pcase (file-name-extension buffer-file-name)
                  ((or "json" "jsonc" "json5") 'json)
                  ((or "yaml" "yml") 'yaml)
                  ("toml" 'toml)
                  ((or "xml" "plist" "xsd" "xslt" "rss" "pom") 'xml)
                  ("csv" 'csv)
                  ((or "ini" "cfg" "conf") 'conf)
                  (_ nil)))))))

(defun +data--checker-format (kind)
  "What `bin/check-data' is asked to read, for KIND in this buffer, or nil.
A .plist may be binary, and only a .ini or .cfg is INI: a .conf file is
nginx, systemd or anything else, and checking it as INI would be wrong."
  (let ((file (or buffer-file-name "")))
    (pcase kind
      ((or 'json 'yaml 'toml 'csv) (symbol-name kind))
      ('xml (if (string-suffix-p ".plist" file) "plist" "xml"))
      ('conf (and (string-match-p "\\.\\(ini\\|cfg\\)\\'" file) "ini")))))

(defun +data--run (program &rest args)
  "Run PROGRAM with ARGS over the buffer, returning (STATUS . OUTPUT).
The buffer is not touched: this asks a question about it."
  (let ((out (generate-new-buffer " *data*")))
    (unwind-protect
        (cons (apply #'call-process-region (point-min) (point-max)
                     program nil out nil args)
              (with-current-buffer out (string-trim (buffer-string))))
      (kill-buffer out))))

(defun +data--check ()
  "Ask `bin/check-data' about this buffer: (STATUS . WHAT-IT-SAID), or nil."
  (when-let* ((format (+data--checker-format (+data--kind))))
    (+data--run +data-checker format (or buffer-file-name ""))))

(defun +data--replace (program &rest args)
  "Replace the buffer with what PROGRAM with ARGS makes of it.
Left alone when PROGRAM fails, so a file is never made worse by a tool
that could not read it."
  (unless (executable-find program)
    (user-error "No %s on PATH; SPC h r d says how to install it" program))
  (pcase-let ((`(,status . ,output) (apply #'+data--run program args)))
    (unless (eq status 0)
      (user-error "%s could not read this, so it is left as it was: %s"
                  program (car (split-string output "\n"))))
    (let ((point (point)))
      (replace-region-contents (point-min) (point-max) (lambda () output))
      (goto-char (min point (point-max))))))

;;;###autoload
(defun +data/validate ()
  "Say whether this file is valid, and take you to where it is not.
JSON, YAML, TOML, CSV, INI, XML and property lists are each read by their
own parser, so the verdict is the one the tools that consume the file
would give."
  (interactive)
  (let ((kind (+data--kind)))
    (unless kind (user-error "Not a data file this knows how to check"))
    (pcase (+data--check)
      ('nil (user-error "No check for this %s file: conf files come in too many formats to guess"
                        (file-name-extension (or buffer-file-name ""))))
      (`(0 . ,said) (message "%s" said))
      (`(2 . ,said) (message "%s" said))
      (`(1 . ,said)
       (if (string-match "\\`\\([0-9]+\\):\\([0-9]+\\): \\(.*\\)" said)
           (let ((line (string-to-number (match-string 1 said)))
                 (column (string-to-number (match-string 2 said)))
                 (what (match-string 3 said)))
             (push-mark)
             (goto-char (point-min))
             (forward-line (1- line))
             (move-to-column (max 0 (1- column)))
             (user-error "Line %d: %s" line what))
         (user-error "%s" said)))
      (`(,_ . ,said) (user-error "The check could not run: %s" said)))))

;;;###autoload
(defun +data/prettify ()
  "Lay this file out to be read, keeping what its author wrote."
  (interactive)
  (pcase (+data--kind)
    ('json
     ;; jq lays out every value and keeps big numbers exactly, but it
     ;; cannot read a comment; a file with them goes through prettier,
     ;; which keeps them where they were.
     (pcase (+data--check)
       (`(0 . ,(and said (guard (string-prefix-p "Valid JSON with comments" said))))
        (+data--replace "prettier" "--parser" "jsonc"
                        "--stdin-filepath" (or buffer-file-name "x.json")))
       (`(0 . ,_) (+data--replace "jq" "--indent" "2" "."))
       (`(,_ . ,said) (user-error "Not valid JSON, so left as it was: %s" said))))
    ;; prettier, not a YAML library's dump: a dump drops every comment,
    ;; and a YAML 1.1 reader turns the key on into true, which is how a
    ;; GitHub workflow would lose its trigger.
    ('yaml (+data--replace "prettier" "--parser" "yaml"
                           "--stdin-filepath" (or buffer-file-name "x.yaml")))
    ('toml (+data--replace "taplo" "format" "-"))
    ('xml (+data--replace "xmllint" "--format" "-"))
    ('csv (call-interactively #'csv-align-fields))
    (_ (user-error "Nothing here knows how to lay this out"))))

;;;###autoload
(defun +data/compact ()
  "Squeeze this file onto as few lines as it will take.
Only where that loses nothing: JSON without comments, XML and CSV."
  (interactive)
  (pcase (+data--kind)
    ('json
     (pcase (+data--check)
       (`(0 . ,(and said (guard (string-prefix-p "Valid JSON with comments" said))))
        (user-error "This has comments, and compacting would drop them"))
       (`(0 . ,_) (+data--replace "jq" "-c" "."))
       (`(,_ . ,said) (user-error "Not valid JSON, so left as it was: %s" said))))
    ('yaml (user-error "YAML has no compact form that keeps comments and key names"))
    ('toml (user-error "TOML has no compact form worth having"))
    ('xml (+data--replace "xmllint" "--noblanks" "-"))
    ('csv (call-interactively #'csv-unalign-fields))
    (_ (user-error "Nothing here knows how to compact this"))))

;;;###autoload
(defun +data/what-is-this ()
  "Say what this file is taken for, and what is checking it."
  (interactive)
  (let* ((kind (+data--kind))
         (server (and (bound-and-true-p eglot--managed-mode)
                      (plist-get (eglot--server-info (eglot-current-server)) :name))))
    (message "%s; %s"
             (if kind (upcase (symbol-name kind)) "Not a data file")
             (cond (server (format "checked as you type by %s" server))
                   ((+data--checker-format kind) "checked on SPC m v")
                   (t "nothing checks this kind of file")))))

