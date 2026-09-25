;;; private/core/autoload/data.el -*- lexical-binding: t; -*-
;;
;; Validate, prettify and compact a data file, whatever format it is in.
;;
;; The language servers validate as you type where they are running;
;; these are for the answer on demand, for a format with no server, and
;; for reshaping a file you have been handed.

(defun +data--kind (&optional buffer)
  "Which data format BUFFER holds, as a symbol, or nil."
  (with-current-buffer (or buffer (current-buffer))
    (cond ((derived-mode-p 'json-mode 'json-ts-mode 'jsonc-mode 'js-json-mode) 'json)
          ((derived-mode-p 'yaml-mode 'yaml-ts-mode) 'yaml)
          ((derived-mode-p 'toml-ts-mode 'conf-toml-mode) 'toml)
          ((derived-mode-p 'nxml-mode 'xml-mode 'sgml-mode) 'xml)
          ((derived-mode-p 'csv-mode) 'csv)
          ((derived-mode-p 'conf-mode) 'conf)
          ;; A file named like one of them, opened in something else.
          ((and buffer-file-name
                (pcase (file-name-extension buffer-file-name)
                  ((or "json" "jsonc" "json5") 'json)
                  ((or "yaml" "yml") 'yaml)
                  ("toml" 'toml)
                  ((or "xml" "plist" "xsd" "xslt" "rss" "pom") 'xml)
                  ("csv" 'csv)
                  ((or "ini" "cfg" "conf") 'conf)
                  (_ nil)))))))

(defun +data--run (command &rest args)
  "Run COMMAND with ARGS over the buffer, returning (STATUS . OUTPUT).
The buffer is not touched: this is for asking a question about it."
  (let ((out (generate-new-buffer " *data check*")))
    (unwind-protect
        (cons (apply #'call-process-region (point-min) (point-max)
                     command nil out nil args)
              (with-current-buffer out (string-trim (buffer-string))))
      (kill-buffer out))))

(defun +data--replace (command &rest args)
  "Replace the buffer with what COMMAND with ARGS makes of it.
The buffer is left alone when the command fails, so a file is never
destroyed by a tool that could not read it."
  (let* ((result (apply #'+data--run command args))
         (status (car result))
         (output (cdr result)))
    (if (not (eq status 0))
        (user-error "%s: %s" command (car (split-string output "\n")))
      (let ((point (point)))
        (replace-region-contents (point-min) (point-max) (lambda () output))
        (goto-char (min point (point-max)))
        (message "%s, %d lines" (capitalize (symbol-name (+data--kind)))
                 (count-lines (point-min) (point-max)))))))

(defun +data--validate-elisp ()
  "Validate JSON with Emacs itself, when jq is not installed.
Returns nil when it parses, or a message saying where it does not."
  (condition-case err
      (progn (save-excursion
               (goto-char (point-min))
               (json-parse-buffer :object-type 'alist))
             nil)
    (json-parse-error
     (format "line %s: %s"
             (line-number-at-pos (or (nth 3 err) (point)))
             (error-message-string err)))
    (error (error-message-string err))))

;;;###autoload
(defun +data/validate ()
  "Say whether this file is valid, and where it is not.

JSON, YAML and TOML are parsed by the tool that knows them; XML is
checked for well-formedness and against its schema when it names one;
a CSV is checked for rows that do not have the same number of fields
as its header."
  (interactive)
  (pcase (+data--kind)
    ('json
     (if (executable-find "jq")
         (pcase-let ((`(,status . ,output) (+data--run "jq" "empty")))
           (if (eq status 0)
               (message "Valid JSON")
             (user-error "%s" (car (split-string output "\n")))))
       (if-let* ((problem (+data--validate-elisp)))
           (user-error "%s" problem)
         (message "Valid JSON (checked by Emacs; install jq for a better message)"))))
    ('yaml
     (unless (executable-find "python3")
       (user-error "No python3, which is what reads the YAML here"))
     (pcase-let ((`(,status . ,output)
                  (+data--run "python3" "-c" "
import sys, yaml
try:
    list(yaml.safe_load_all(sys.stdin))
    print('ok')
except Exception as e:
    print(str(e).replace(chr(10), ' '), file=sys.stderr); sys.exit(1)")))
       (if (eq status 0) (message "Valid YAML")
         (user-error "%s" (car (split-string output "\n"))))))
    ('toml
     (unless (executable-find "taplo")
       (user-error "No taplo, which is what reads the TOML here"))
     (pcase-let ((`(,status . ,output) (+data--run "taplo" "check" "-")))
       (if (eq status 0) (message "Valid TOML")
         (user-error "%s" (car (split-string output "\n"))))))
    ('xml
     (unless (executable-find "xmllint")
       (user-error "No xmllint; openSUSE: zypper in libxml2-tools"))
     (pcase-let ((`(,status . ,output) (+data--run "xmllint" "--noout" "-")))
       (if (eq status 0) (message "Well-formed XML")
         (user-error "%s" (car (split-string output "\n"))))))
    ('csv (+data--validate-csv))
    ('conf (+data--validate-conf))
    (_ (user-error "Not a data file this knows how to check"))))

(defun +data--validate-csv ()
  "Say which rows do not hold as many fields as the header."
  (let* ((lines (split-string (buffer-string) "\n" t))
         (sep (if (bound-and-true-p csv-separators) (car csv-separators) ","))
         (width (length (split-string (car lines) sep)))
         (bad '()))
    (cl-loop for line in (cdr lines)
             for n from 2
             for fields = (length (split-string line sep))
             unless (= fields width)
             do (push (format "line %d has %d, not %d" n fields width) bad))
    (if bad
        (user-error "%d row(s) do not match the header: %s"
                    (length bad) (string-join (nreverse (seq-take bad 3)) "; "))
      (message "Every row has %d fields" width))))

(defun +data--validate-conf ()
  "Say which keys are set twice in this file."
  (let ((seen (make-hash-table :test 'equal))
        (dupes '()))
    (save-excursion
      (goto-char (point-min))
      (let ((section ""))
        (while (not (eobp))
          (let ((line (string-trim (buffer-substring-no-properties
                                    (line-beginning-position) (line-end-position)))))
            (cond
             ((string-match "\\`\\[\\(.*\\)\\]\\'" line)
              (setq section (match-string 1 line)))
             ((string-match "\\`\\([^#;=]+\\)=" line)
              (let ((key (concat section "/" (string-trim (match-string 1 line)))))
                (if (gethash key seen)
                    (push (format "%s (line %d and %d)" key (gethash key seen)
                                  (line-number-at-pos))
                          dupes)
                  (puthash key (line-number-at-pos) seen))))))
          (forward-line 1))))
    (if dupes
        (user-error "Set twice: %s" (string-join (nreverse (seq-take dupes 3)) "; "))
      (message "No key is set twice"))))

;;;###autoload
(defun +data/prettify ()
  "Lay this file out to be read: indented, one thing per line."
  (interactive)
  (pcase (+data--kind)
    ('json (if (executable-find "jq")
               (+data--replace "jq" "--indent" (number-to-string +data-jq-indent) ".")
             (json-pretty-print-buffer)
             (message "Prettified with Emacs; install jq to keep key order")))
    ('yaml (+data--replace "python3" "-c" "
import sys, yaml
print(yaml.dump_all(yaml.safe_load_all(sys.stdin), default_flow_style=False,
                    sort_keys=False, allow_unicode=True), end='')"))
    ('toml (+data--replace "taplo" "format" "-"))
    ('xml (+data--replace "xmllint" "--format" "-"))
    ('csv (call-interactively #'csv-align-fields))
    (_ (user-error "Nothing here knows how to lay this out"))))

;;;###autoload
(defun +data/compact ()
  "Squeeze this file onto as few lines as it will take."
  (interactive)
  (pcase (+data--kind)
    ('json (if (executable-find "jq")
               (+data--replace "jq" "-c" ".")
             (user-error "No jq, which is what compacts JSON here")))
    ('yaml (+data--replace "python3" "-c" "
import sys, yaml
print(yaml.dump_all(yaml.safe_load_all(sys.stdin), default_flow_style=True,
                    sort_keys=False, allow_unicode=True), end='')"))
    ('xml (+data--replace "xmllint" "--noblanks" "-"))
    ('csv (call-interactively #'csv-unalign-fields))
    ('toml (user-error "TOML has no compact form worth having"))
    (_ (user-error "Nothing here knows how to compact this"))))

;;;###autoload
(defun +data/what-is-this ()
  "Say what this file is taken for, and what is checking it."
  (interactive)
  (let* ((kind (+data--kind))
         (server (and (bound-and-true-p eglot--managed-mode)
                      (ignore-errors
                        (eglot-project-nickname (eglot-current-server))))))
    (message "%s, %s%s"
             (if kind (capitalize (symbol-name kind)) "not a data file")
             (if server (format "validated live by a server (%s)" server)
               "checked on SPC m v")
             (if (and kind (not server)) ", no server running here" ""))))
