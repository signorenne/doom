;;; private/core/autoload/data.el -*- lexical-binding: t; -*-
;;
;; Validate, prettify and compact a data file, whatever format it is in.
;;
;; Validation is `bin/check-data', one program that reads each format
;; with its own real parser. It lives outside Emacs so it can be run over
;; many real files at once to catch a wrong verdict. Reshaping goes
;; through the tool that knows the format and keeps what the author
;; wrote: comments, key names, number literals.

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


;;
;;; Schemas for JSON

;; The YAML server fetches SchemaStore's catalog itself; the JSON one
;; does not, and without it only checks that a file parses: "name": 123
;; in a package.json passes. So the catalog is fetched here, cached, and
;; handed to the JSON server alone, in the notification VS Code uses for
;; it. Not in `eglot-workspace-configuration': eglot sends all of that
;; to every server it starts, and the catalog is too large for some
;; (plantuml-lsp quits on a message over 64 KB).

(defun +data--schemastore-file ()
  "Where the catalog is kept between sessions."
  (file-name-concat doom-cache-dir "schemastore-catalog.json"))

(defun +data--schemastore-stale-p ()
  "Non-nil when the cached catalog is missing or old."
  (let ((file (+data--schemastore-file)))
    (or (not (file-exists-p file))
        (> (float-time (time-since (file-attribute-modification-time
                                    (file-attributes file))))
           +data-schemastore-max-age))))

(defvar +data--json-schemas nil
  "The cached catalog as the JSON server takes it, read once.")

(defvar +data--json-servers (make-hash-table :test #'eq :weakness 'key)
  "The JSON servers that have the catalog, so each is sent it once:
the server forgets every schema it had fetched when it is sent again.")

;;;###autoload
(defun +data-schemastore-associations ()
  "SchemaStore's catalog as the JSON server's schema associations, a
vector of (:uri URL :fileMatch [PATTERN...]), or nil."
  (let ((file (+data--schemastore-file)))
    (when (file-exists-p file)
      (condition-case nil
          (with-temp-buffer
            (insert-file-contents file)
            (let ((catalog (json-parse-buffer :object-type 'plist :array-type 'list)))
              (vconcat
               (cl-loop for schema in (plist-get catalog :schemas)
                        for match = (plist-get schema :fileMatch)
                        when (and match (plist-get schema :url))
                        collect (list :uri (plist-get schema :url)
                                      :fileMatch (vconcat match))))))
        (error nil)))))

(defun +data--json-schemas-send (server)
  "Give SERVER, a JSON server, the catalog."
  (unless +data--json-schemas
    (setq +data--json-schemas (or (+data-schemastore-associations) [])))
  (when (and (length> +data--json-schemas 0) (jsonrpc-running-p server))
    ;; Params that are an array are the arguments, one by one; the one
    ;; argument here is itself an array, so it goes in one of its own.
    (jsonrpc-notify server "json/schemaAssociations" (vector +data--json-schemas))
    (puthash server t +data--json-servers)))

;;;###autoload
(defun +data--json-schemas-h ()
  "Give the server of this JSON buffer the catalog, once."
  (when (and (eglot-managed-p) (eq (+data--kind) 'json))
    (when-let* ((server (eglot-current-server)))
      (unless (gethash server +data--json-servers)
        (+data--json-schemas-send server)))))

;;;###autoload
(defun +data-apply-json-schemas ()
  "Read the cached catalog again and give it to every JSON server
running. Returns how many file patterns it covers."
  (setq +data--json-schemas nil)
  (when (featurep 'eglot)
    (let (servers)
      (dolist (buffer (buffer-list))
        (with-current-buffer buffer
          (when (and (eglot-managed-p) (eq (+data--kind) 'json))
            (cl-pushnew (eglot-current-server) servers))))
      (mapc #'+data--json-schemas-send (delq nil servers))))
  (length +data--json-schemas))

;;;###autoload
(defun +data/refresh-schemas (&optional quietly)
  "Fetch SchemaStore's catalog again, in the background.
QUIETLY says nothing unless something went wrong."
  (interactive)
  (let ((file (+data--schemastore-file)))
    (url-retrieve
     +data-schemastore-url
     (lambda (status)
       (unwind-protect
           (if-let* ((err (plist-get status :error)))
               (message "SchemaStore catalog not fetched: %s" (cdr err))
             (goto-char (point-min))
             (when (re-search-forward "\r?\n\r?\n" nil t)
               (let ((body (buffer-substring-no-properties (point) (point-max))))
                 ;; Only a catalog replaces the cache, never an error page.
                 (when (ignore-errors
                         (plist-get (json-parse-string (decode-coding-string body 'utf-8)
                                                       :object-type 'plist)
                                    :schemas))
                   (make-directory (file-name-directory file) t)
                   (let ((coding-system-for-write 'binary))
                     (write-region body nil file nil 'silent))
                   (let ((n (+data-apply-json-schemas)))
                     (unless quietly
                       (message "SchemaStore: %d file patterns now have a schema" n)))))))
         (kill-buffer)))
     nil t t)))

;;;###autoload
(defun +data-schemas-setup-h ()
  "Refresh the cached catalog in the background when it is missing or
old. A JSON server is given it when it takes on its first buffer."
  (when (+data--schemastore-stale-p)
    (run-with-idle-timer 2 nil #'+data/refresh-schemas t)))
