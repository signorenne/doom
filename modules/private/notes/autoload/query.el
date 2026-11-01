;;; private/notes/autoload/query.el -*- lexical-binding: t; -*-
;;
;; Live tables in a note, as Org dynamic blocks: headings an Org QL query
;; finds (notes-query), notes from the graph's database (notes-list), and
;; tasks in columns by state (notes-board). A note's blocks are written
;; again when it is shown and when it is saved.

(require 'org)
(require 'org-element)

(defvar +notes-board-states)
(defvar +notes-board-done-days)
(defvar +notes-block-names)
(defvar org-roam-directory)
(defvar org-roam-file-exclude-regexp)
(declare-function org-ql-select "org-ql")
(declare-function org-ql--query-string-to-sexp "org-ql")
(declare-function org-roam-db-query "org-roam-db")
(declare-function +notes--agenda-files-refresh-h "roam")

;;
;;; What a block reads

(defun +notes--vault-dir ()
  "The vault, as a directory name."
  (file-name-as-directory (expand-file-name org-roam-directory)))

(defun +notes--block-file ()
  "The file of the note the block is in, through an indirect buffer too."
  (or buffer-file-name (buffer-file-name (buffer-base-buffer))))

(defun +notes--excluded-p (relative)
  "Whether RELATIVE, a path in the vault, is left out of a folder: what
org-roam leaves out, and the attachments."
  (let ((regexps (bound-and-true-p org-roam-file-exclude-regexp)))
    (or (string-match-p "\\(?:\\`\\|/\\)\\.attach/" relative)
        (seq-some (lambda (re) (string-match-p re relative))
                  (if (listp regexps) regexps (list regexps))))))

(defun +notes--folder-files (dir)
  "The notes in DIR and every folder below it, by path."
  (let ((vault (+notes--vault-dir)))
    (sort (seq-remove
           (lambda (file)
             (or (string-prefix-p ".#" (file-name-nondirectory file)) ; a lock
                 (+notes--excluded-p (file-relative-name file vault))))
           (directory-files-recursively
            dir "\\.org\\'" nil
            (lambda (sub)
              (not (+notes--excluded-p
                    (file-name-as-directory (file-relative-name sub vault)))))))
          #'string<)))

(defun +notes--from-dir (from)
  "The folder :from FROM names, or nil for one that is not a folder."
  (pcase from
    ((or 'nil 'folder)
     (file-name-directory
      (or (+notes--block-file) (user-error "The note has no file yet"))))
    ((pred stringp)
     (let ((dir (file-name-as-directory (expand-file-name from (+notes--vault-dir)))))
       (unless (file-in-directory-p dir (+notes--vault-dir))
         (user-error ":from %S is outside the vault" from))
       (unless (file-directory-p dir)
         (user-error "No folder %s" from))
       dir))))

(defun +notes--agenda-file-list ()
  "The agenda files, as the agenda builds them, by path."
  (+notes--agenda-files-refresh-h)
  (sort (mapcar #'expand-file-name (org-agenda-files t)) #'string<))

(defun +notes--ql-buffers (name from)
  "The buffers block NAME reads :from FROM, each opened as the agenda
opens its files: a file in the background starts no mode hooks."
  (if (eq from 'file)
      (list (current-buffer))
    (mapcar #'org-get-agenda-file-buffer
          (pcase from
            ('agenda (+notes--agenda-file-list))
            ('vault
             (user-error ":from vault reads every note; use agenda or a \"DIR/\""))
            ((or 'nil 'folder (pred stringp))
             (let ((dir (+notes--from-dir from)))
               ;; A query over every note would open thousands of files.
               (when (file-equal-p dir (+notes--vault-dir))
                 (user-error ":from folder at the vault root reads every note; use agenda or a \"DIR/\""))
               (+notes--folder-files dir)))
            (_ (user-error "Unknown :from %S for %s" from name))))))

;;
;;; Cells

(defun +notes--cell (text)
  "TEXT as a table cell: a bar would split it, and an active timestamp
would put the table in the agenda."
  (replace-regexp-in-string
   "<\\([0-9]\\{4\\}-[0-9][0-9]-[0-9][0-9][^>\n]*\\)>" "[\\1]"
   (replace-regexp-in-string "|" "\\vert{}" (or text "") t t)
   t))

(defun +notes--link-path (file)
  "FILE as a link from the block's note: relative to it."
  (file-relative-name file (file-name-directory (or (+notes--block-file) default-directory))))

(defun +notes--heading-link (file id text)
  "A link to the heading TEXT in FILE, whose ID is ID or nil, for a cell.
The description is TEXT as a cell holds it, made before the link: made
after, a timestamp at its end would close the link early."
  (let ((same (and (+notes--block-file)
                   (string= (expand-file-name file) (expand-file-name (+notes--block-file)))))
        (description (+notes--cell text)))
    (cond (id (org-link-make-string (concat "id:" id) description))
          ;; Neither survives in a cell: a heading search with a bar, or
          ;; with an active timestamp made inactive, finds nothing.
          ((string-match-p "|\\|<[0-9]\\{4\\}-" text)
           (org-link-make-string (concat "file:" (+notes--cell (+notes--link-path file))) description))
          (same (org-link-make-string (org-link-heading-search-string text) description))
          (t (org-link-make-string
              (concat "file:" (+notes--cell (+notes--link-path file)) "::"
                      (org-link-heading-search-string text))
              description)))))

(defun +notes--file-link (file)
  "A link to FILE, described by its path in the vault, for a cell."
  (org-link-make-string (concat "file:" (+notes--cell (+notes--link-path file)))
                        (+notes--cell (file-relative-name file (+notes--vault-dir)))))

(defun +notes--ts-date (timestamp)
  "TIMESTAMP, an Org timestamp object or nil, as YYYY-MM-DD."
  (if timestamp
      (format "%04d-%02d-%02d"
              (org-element-property :year-start timestamp)
              (org-element-property :month-start timestamp)
              (org-element-property :day-start timestamp))
    ""))

(defun +notes--created-date (value)
  "The date of a CREATED property VALUE, as YYYY-MM-DD, or \"\"."
  (if (and value (string-match "[0-9]\\{4\\}-[0-9][0-9]-[0-9][0-9]" value))
      (match-string 0 value)
    ""))

(defun +notes--columns (spec allowed default)
  "The columns SPEC names, each (KEY HEADER PROPERTY): KEY one of ALLOWED
or `property'.  DEFAULT when SPEC is nil."
  (unless (listp spec) (user-error ":columns must be a list"))
  (mapcar
   (lambda (column)
     (pcase column
       (`(property ,(and name (pred stringp)))
        (list 'property (capitalize name) name))
       (`((property ,(and name (pred stringp))) ,(and header (pred stringp)))
        (list 'property header name))
       ((and key (pred symbolp) (guard (memq key allowed)))
        (list key (capitalize (symbol-name key)) nil))
       (`(,(and key (pred symbolp) (guard (memq key allowed))) ,(and header (pred stringp)))
        (list key header nil))
       (_ (user-error "Unknown column %S" column))))
   (or spec default)))

(defun +notes--column-properties (columns)
  "The property names COLUMNS read."
  (delq nil (mapcar (lambda (column) (nth 2 column)) columns)))

(defun +notes--take (rows take)
  "The first TAKE of ROWS, or all of them when TAKE is nil."
  (cond ((null take) rows)
        ((natnump take) (seq-take rows take))
        (t (user-error ":take must be a number"))))

;;
;;; Headings, through Org QL

(defconst +notes--ql-sorts '(date deadline scheduled closed todo priority reverse)
  "The Org QL sort methods a block takes: all but random, which would
write the table differently each time.")

(defun +notes--ql-sort (sort)
  "SORT checked, as `org-ql-select' takes it."
  (dolist (method (ensure-list sort) sort)
    (unless (memq method +notes--ql-sorts)
      (user-error "Unknown :sort %S" method))))

(defun +notes--ql-query (query &optional optional)
  "The Org QL string QUERY as a query.  Only a string: a list would be
code, and a block is read from a note.  Nil when OPTIONAL and QUERY is."
  (cond ((and optional (null query)) nil)
        ((stringp query)
         (require 'org-ql)
         (org-ql--query-string-to-sexp query))
        (t (user-error ":query must be a string"))))

(defun +notes--ql-item (properties)
  "The heading at point for a table: Org's element, which Org QL sorts,
with what the columns read from the buffer.  Nothing that depends on the
block's file: Org QL keeps the result for the next block that asks."
  (let ((element (org-element-headline-parser (line-end-position))))
    (org-element-put-property
     element :+notes-row
     (list (or buffer-file-name (buffer-file-name (buffer-base-buffer)))
           (org-entry-get nil "ID")
           (substring-no-properties (org-get-heading t t t t))
           (org-get-tags nil t)
           (mapcar (lambda (name) (org-entry-get nil name)) properties)))))

(defun +notes--ql-items (name params query properties)
  "The headings of block NAME with PARAMS that match QUERY, with
PROPERTIES read for each."
  (require 'org-ql)
  (org-ql-select (+notes--ql-buffers name (plist-get params :from)) query
    :action (apply-partially #'+notes--ql-item properties)
    :sort (+notes--ql-sort (plist-get params :sort))))

(defun +notes--ql-cell (column item)
  "What COLUMN shows of ITEM, a heading `+notes--ql-items' found."
  (pcase-let ((`(,file ,id ,text ,tags ,values) (org-element-property :+notes-row item)))
    (pcase (car column)
      ('todo (+notes--cell (org-element-property :todo-keyword item)))
      ('priority (if-let* ((p (org-element-property :priority item))) (char-to-string p) ""))
      ('heading (+notes--heading-link file id text))
      ('tags (if tags (+notes--cell (concat ":" (string-join tags ":") ":")) ""))
      ((and key (or 'deadline 'scheduled 'closed))
       (+notes--ts-date (org-element-property (intern (format ":%s" key)) item)))
      ('file (+notes--file-link file))
      ('property (+notes--cell (nth (seq-position (nth 3 column) (nth 2 column)) values))))))

(defun +notes--query-table (params)
  "notes-query: (HEADER . ROWS) of the headings PARAMS asks for."
  (let* ((columns (+notes--columns (plist-get params :columns)
                                   '(todo priority heading tags deadline scheduled closed file)
                                   '(todo heading deadline file)))
         (properties (+notes--column-properties columns))
         ;; Each column knows where its property sits in the item's values.
         (columns (mapcar (lambda (column)
                            (if (nth 2 column)
                                (append column (list properties))
                              column))
                          columns))
         (items (+notes--ql-items "notes-query" params
                                  (+notes--ql-query (plist-get params :query))
                                  properties)))
    (cons (mapcar (lambda (column) (+notes--cell (cadr column))) columns)
          (mapcar (lambda (item)
                    (mapcar (lambda (column) (+notes--ql-cell column item)) columns))
                  (+notes--take items (plist-get params :take))))))

;;
;;; Notes, from the database

(defun +notes--list-rows (params)
  "The nodes notes-list PARAMS asks for: (ID FILE LEVEL TITLE PROPERTIES
MTIME POS) each, in no order.  The database narrows them roughly, by tag,
link and folder; the exact choice is made here."
  (require 'org-roam)
  (let* ((from (or (plist-get params :from) 'folder))
         (tags (plist-get params :tags))
         (links (plist-get params :links-to))
         (property (plist-get params :property))
         (level (or (plist-get params :level) 'file))
         (vault (+notes--vault-dir))
         (dir (pcase from
                ('vault vault)
                ((or 'folder (pred stringp)) (+notes--from-dir from))))
         (files (pcase from
                  ('file (list (expand-file-name
                                (or (+notes--block-file) (user-error "The note has no file yet")))))
                  ('agenda (+notes--agenda-file-list))
                  ((guard dir) nil)
                  (_ (user-error "Unknown :from %S" from))))
         (this (and links
                    (if (eq links 'this)
                        (or (org-with-wide-buffer (org-entry-get (point-min) "ID"))
                            (user-error ":links-to this needs the note to have an ID"))
                      (user-error ":links-to takes only this"))))
         (where
          (delq nil
                `((like nodes:file ,(concat (or dir vault) "%"))
                  ,(pcase level
                     ('file '(= nodes:level 0))
                     ('heading '(> nodes:level 0))
                     ('any nil)
                     (_ (user-error ":level must be file, heading or any")))
                  ,@(progn
                      (unless (and (listp tags) (seq-every-p #'stringp tags))
                        (user-error ":tags must be a list of strings"))
                      (mapcar (lambda (tag)
                                `(in nodes:id [:select [node-id] :from tags :where (= tag ,tag)]))
                              tags))
                  ,(and this
                        `(in nodes:id [:select [source] :from links
                                       :where (and (= dest ,this) (= type "id"))]))))))
    (unless (or (null property)
                (and (consp property) (= (length property) 2) (seq-every-p #'stringp property)))
      (user-error ":property must be (\"NAME\" \"VALUE\")"))
    (seq-filter
     (lambda (row)
       (let ((file (expand-file-name (nth 1 row))))
         (and (if files (member file files) (string-prefix-p (or dir vault) file))
              (not (+notes--excluded-p (file-relative-name file vault)))
              (or (null property)
                  (equal (cdr (assoc-string (car property) (nth 4 row) t))
                         (cadr property))))))
     (org-roam-db-query
      `[:select [nodes:id nodes:file nodes:level nodes:title nodes:properties files:mtime nodes:pos]
        :from nodes :inner-join files :on (= nodes:file files:file)
        :where ,(if (cdr where) `(and ,@where) (car where))]))))

(defun +notes--created-time (row)
  "The time of ROW's CREATED property, or nil."
  (when-let* ((value (cdr (assoc-string "CREATED" (nth 4 row) t)))
              ((string-match org-ts-regexp-inactive value)))
    (org-time-string-to-time (match-string 0 value))))

(defun +notes--list-sort (rows sort)
  "ROWS in the order SORT names; ties by title, then file, then place in
it, so a database built again in another order writes the same table."
  (let ((by-title (lambda (a b)
                    (let ((x (downcase (nth 3 a))) (y (downcase (nth 3 b))))
                      (or (string< x y)
                          (and (string= x y)
                               (or (string< (nth 1 a) (nth 1 b))
                                   (and (string= (nth 1 a) (nth 1 b))
                                        (< (nth 6 a) (nth 6 b)))))))))
        (newest (lambda (key)
                  (lambda (a b)
                    (let ((x (funcall key a)) (y (funcall key b)))
                      (cond ((and x y (time-less-p y x)) t)
                            ((and x y (time-less-p x y)) nil)
                            ((and x (not y)) t)
                            ((and y (not x)) nil)))))))
    (pcase (or sort 'title)
      ('title (sort rows by-title))
      ('modified (sort (sort rows by-title) (funcall newest (lambda (row) (nth 5 row)))))
      ('created (sort (sort rows by-title) (funcall newest #'+notes--created-time)))
      (_ (user-error ":sort must be title, modified or created")))))

(defun +notes--list-tags (ids)
  "ID to its sorted tags, for the nodes IDS."
  (let ((table (make-hash-table :test #'equal)))
    (when ids
      (dolist (row (org-roam-db-query [:select [node-id tag] :from tags :where (in node-id $v1)]
                                      (vconcat ids)))
        (push (cadr row) (gethash (car row) table))))
    table))

(defun +notes--list-table (params)
  "notes-list: (HEADER . ROWS) of the notes PARAMS asks for."
  (let* ((columns (+notes--columns (plist-get params :columns)
                                   '(title tags file modified created) '(title)))
         (rows (+notes--take (+notes--list-sort (+notes--list-rows params)
                                                (plist-get params :sort))
                             (plist-get params :take)))
         (tags (and (assq 'tags columns) (+notes--list-tags (mapcar #'car rows)))))
    (cons (mapcar (lambda (column) (+notes--cell (cadr column))) columns)
          (mapcar
           (lambda (row)
             (pcase-let ((`(,id ,file ,_level ,title ,properties ,mtime ,_pos) row))
               (mapcar
                (lambda (column)
                  (pcase (car column)
                    ('title (org-link-make-string (concat "id:" id) (+notes--cell title)))
                    ('tags (if-let* ((list (gethash id tags)))
                               (+notes--cell (concat ":" (string-join (sort list #'string<) ":") ":"))
                             ""))
                    ('file (+notes--file-link file))
                    ('modified (if mtime (format-time-string "%Y-%m-%d" mtime) ""))
                    ('created (+notes--created-date (cdr (assoc-string "CREATED" properties t))))
                    ('property (+notes--cell (cdr (assoc-string (nth 2 column) properties t))))))
                columns)))
           rows))))

;;
;;; Tasks on a board

(defun +notes--board-table (params)
  "notes-board: (HEADER . ROWS), a column per state, the Nth card of each
column in row N."
  (let* ((states (or (plist-get params :states) +notes-board-states))
         (days (or (plist-get params :done-days) +notes-board-done-days))
         (oldest (and (natnump days)
                      (format-time-string "%Y-%m-%d" (time-subtract nil (days-to-time days))))))
    (unless (and (consp states) (seq-every-p #'stringp states))
      (user-error ":states must be a list of strings"))
    (dolist (state states)
      (unless (member state org-todo-keywords-1)
        (user-error "unknown state %s" state)))
    (unless (or oldest (eq days 'all))
      (user-error ":done-days must be a number or all"))
    (let* ((user (+notes--ql-query (plist-get params :query) t))
           (items (+notes--ql-items "notes-board" params
                                    `(and (todo ,@states) ,@(and user (list user)))
                                    nil))
           (columns (mapcar #'list states)))
      (dolist (item items)
        (let* ((state (org-element-property :todo-keyword item))
               (closed (org-element-property :closed item)))
          ;; A finished task stays a while, and only one Org closed.
          (when (or (not (member state org-done-keywords))
                    (and closed (or (null oldest)
                                    (not (string< (+notes--ts-date closed) oldest)))))
            (push (+notes--ql-cell '(heading) item) (cdr (assoc state columns))))))
      (setq columns (mapcar (lambda (column) (nreverse (cdr column))) columns))
      (cons (mapcar #'+notes--cell states)
            (cl-loop for n below (apply #'max 0 (mapcar #'length columns))
                     collect (mapcar (lambda (column) (or (nth n column) "")) columns))))))

;;
;;; Writing a block

(defun +notes--block-content (name params)
  "What block NAME holds for PARAMS: (HEADER . ROWS), or a string, the
message its comment line gives.  Never signals: Org has emptied the
block before its writer runs, and an error would leave it so."
  (condition-case err
      (pcase name
        ("notes-query" (+notes--query-table params))
        ("notes-list" (+notes--list-table params))
        ("notes-board" (+notes--board-table params)))
    (error (error-message-string err))))

(defun +notes--block-text (name content indent)
  "The lines of block NAME holding CONTENT, each indented by INDENT.
The cells of CONTENT are made for a cell already, by `+notes--cell'."
  (let ((prefix (make-string indent ?\s)))
    (if (stringp content)
        (concat prefix "# " name ": " (replace-regexp-in-string "\n" " " content))
      (mapconcat (lambda (row)
                   (concat prefix
                           (if (eq row 'rule) "|-"
                             (concat "| " (string-join row " | ") " |"))))
                 (cons (car content) (cons 'rule (cdr content)))
                 "\n"))))

(defun +notes--block-write (name params)
  "Write block NAME at point, which Org has emptied, for PARAMS."
  (let ((content (+notes--block-content name params))
        (start (point)))
    (insert (+notes--block-text name content 0))
    (when (consp content)
      (goto-char start)
      (org-table-align))))

;;;###autoload
(defun org-dblock-write:notes-query (params)
  "Write a notes-query block: headings an Org QL string query finds."
  (+notes--block-write "notes-query" params))

;;;###autoload
(defun org-dblock-write:notes-list (params)
  "Write a notes-list block: notes of the graph by tag, link and property."
  (+notes--block-write "notes-list" params))

;;;###autoload
(defun org-dblock-write:notes-board (params)
  "Write a notes-board block: tasks in columns by state."
  (+notes--block-write "notes-board" params))

;;
;;; Refreshing a note's blocks

(defvar-local +notes--blocks-stale nil
  "Non-nil while this note's blocks wait to be written as it is shown.")

(defvar-local +notes--blocks-timer nil
  "The timer that writes this note's blocks once it is shown.")

(defun +notes--block-start-re ()
  "A #+BEGIN: line, in any case, of a block the module writes; the name
in group 1, the parameters in group 2."
  (concat "^[ \t]*#\\+[Bb][Ee][Gg][Ii][Nn]:[ \t]+\\(" (regexp-opt +notes-block-names)
          "\\)\\(?:[ \t]+\\(.*\\)\\)?$"))

(defun +notes--block-cells (text)
  "TEXT's lines, a table line as its cells: what makes two writes of a
block the same, whatever their alignment."
  (mapcar (lambda (line)
            (cond ((string-prefix-p "|-" line) 'rule)
                  ((string-prefix-p "|" line)
                   (mapcar #'string-trim (split-string (string-remove-suffix "|" (substring line 1)) "|")))
                  (t line)))
          (split-string text "\n" t "[ \t]+")))

(defconst +notes--quote-types '("src" "example" "export" "comment" "verse")
  "The #+begin_ blocks whose lines are quoted text, not Org.")

(defun +notes--quote-end (type env)
  "Where the quote that begins on this line ends, past its end line, or
nil when it quotes nothing.  TYPE is its #+begin_ name, ENV its LaTeX
environment.  As Org reads one: closed by its own end line within its
section.  The end is found first and a heading looked for only up to
it; a section's end looked for at each quote made a long note's scan
grow with quotes times section."
  (when (or env (member (downcase type) +notes--quote-types))
    (save-excursion
      (end-of-line)
      (let ((begin (point))
            (case-fold-search t))
        (when (re-search-forward (if env
                                     (format org-element--latex-end-environment (regexp-quote env))
                                   (format "^[ \t]*#\\+END_%s[ \t]*$" (regexp-quote type)))
                                 nil t)
          (let ((end (point)))
            (goto-char begin)
            (unless (re-search-forward (org-get-limited-outline-regexp t) end t)
              end)))))))

(defun +notes--block-end ()
  "Where the #+END: line of the block whose #+BEGIN: line point is on
starts, or nil when there is none before the next heading or #+BEGIN:
line: one that lacks it must not take another's.  A quote inside it is
passed over, so an #+END: quoted there is not its own."
  (save-excursion
    (forward-line 1)
    ;; In any case, as Org reads an end line: #+End: closes a block too.
    (let ((case-fold-search t)
          (heading (org-get-limited-outline-regexp t))
          (begin-dynamic "[ \t]*#\\+[Bb][Ee][Gg][Ii][Nn]:")
          (begin-quote "[ \t]*#\\+[Bb][Ee][Gg][Ii][Nn]_\\(\\S-+\\)")
          result done)
      (while (and (not done)
                  (re-search-forward (concat org-dblock-end-re "\\|" heading "\\|^" begin-dynamic
                                             "\\|^" begin-quote "\\|" org-element--latex-begin-environment)
                                     nil t))
        (goto-char (match-beginning 0))
        (cond ((looking-at org-dblock-end-re) (setq result (point) done t))
              ((or (looking-at heading) (looking-at begin-dynamic)) (setq done t))
              ((looking-at begin-quote)
               (goto-char (or (+notes--quote-end (match-string 1) nil) (line-end-position))))
              ((looking-at org-element--latex-begin-environment)
               (goto-char (or (+notes--quote-end nil (match-string 1)) (line-end-position))))
              (t (end-of-line))))
      result)))

(defun +notes--next-block (&optional bound)
  "Move to the start of the next #+BEGIN: line of a block the module
writes, before BOUND, and return non-nil; nil when there is none.  Lines
quoted in a source, example, export, comment or verse block, or in a
LaTeX environment, are passed over, as `+notes--quote-end' reads them:
Org's parse itself, after a block with no #+END:, can read a quoted line
as a real one.  Point ends past BOUND when BOUND was in a quote."
  (let ((case-fold-search nil)
        (re (concat "\\(?:" (+notes--block-start-re) "\\)"
                    "\\|^[ \t]*#\\+[Bb][Ee][Gg][Ii][Nn]_\\(\\S-+\\)"
                    "\\|" org-element--latex-begin-environment))
        found)
    (while (and (not found)
                (or (null bound) (< (point) bound))
                (re-search-forward re bound t))
      (if (match-beginning 1)
          (setq found (goto-char (match-beginning 0)))
        ;; With no end, the scan goes on from the begin line.
        (when-let* ((end (+notes--quote-end (match-string 3) (match-string 4))))
          (goto-char end))))
    found))

(defun +notes--block-refresh-here ()
  "Write the block on the #+BEGIN: line at point again, and move past it.
Return non-nil when there was a block Org can read.  A write that would
give the same cells changes nothing, so the buffer stays as it was."
  (when (let ((case-fold-search nil)) (looking-at (+notes--block-start-re)))
    (let* ((name (match-string-no-properties 1))
           (params (condition-case nil
                       (read (concat "(" (or (match-string-no-properties 2) "") ")"))
                     (error 'unreadable)))
           (indent (current-indentation))
           (beg (copy-marker (line-beginning-position 2)))
           ;; The marker moves on over what is written at its place.
           (end (when-let* ((pos (+notes--block-end))) (copy-marker pos t))))
      ;; As Org leaves a block it cannot read.
      (when (and end (listp params))
        (let* ((content (save-excursion (goto-char beg) (+notes--block-content name params)))
               (text (+notes--block-text name content indent)))
          (unless (equal (+notes--block-cells (buffer-substring-no-properties beg end))
                         (+notes--block-cells text))
            (goto-char beg)
            (delete-region beg end)
            (insert text "\n")
            (when (consp content)
              (goto-char beg)
              (org-table-align)))
          (goto-char end)
          (forward-line 1)
          t)))))

(defun +notes--blocks-refresh ()
  "Write this note's blocks again; return how many there are, or nil
without font-lock, by which `org-table-align' measures links."
  (when font-lock-mode
    (let ((count 0))
      (save-excursion
        (save-restriction
          (widen)
          (goto-char (point-min))
          (while (+notes--next-block)
            (if (+notes--block-refresh-here)
                (cl-incf count)
              (forward-line 1)))))
      count)))

(defun +notes--blocks-refresh-shown (buffer)
  "Write BUFFER's blocks, now that it is shown, leaving it as modified as
it was: opening a note is not changing it."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (setq +notes--blocks-timer nil)
      (when +notes--blocks-stale
        (let ((modified (buffer-modified-p))
              (inhibit-message t)
              (message-log-max nil))
          (when (ignore-errors (+notes--blocks-refresh))
            (setq +notes--blocks-stale nil))
          (restore-buffer-modified-p modified))))))

(defun +notes--blocks-schedule ()
  "Write this note's blocks once the command that showed it is done,
outside redisplay."
  (unless (timerp +notes--blocks-timer)
    (setq +notes--blocks-timer
          (run-at-time 0 nil #'+notes--blocks-refresh-shown (current-buffer)))))

(defun +notes--blocks-save-h ()
  "Write this note's blocks before it is saved."
  (unless (buffer-base-buffer)
    (let ((inhibit-message t)
          (message-log-max nil))
      (when (ignore-errors (+notes--blocks-refresh))
        (setq +notes--blocks-stale nil)))))

(defun +notes--has-blocks-p ()
  "Whether this buffer holds a block the module writes.  Every note asks
as it opens, and most have none: a plain search for the names first,
which costs much less than the line's regexp over a long note."
  (save-excursion
    (save-restriction
      (widen)
      (let ((case-fold-search nil))
        (and (seq-some (lambda (name)
                         (goto-char (point-min))
                         (search-forward name nil t))
                       +notes-block-names)
             (progn (goto-char (point-min))
                    (re-search-forward (+notes--block-start-re) nil t)))))))

;;;###autoload
(defun +notes--blocks-setup (&optional written)
  "Have this note's blocks written as it is shown and as it is saved,
when it has any.  Only a note of the vault in its own buffer: never a
capture's indirect copy, and never a buffer that cannot be saved.  With
WRITTEN, the caller writes them now."
  (if (and buffer-file-name
           (not (buffer-base-buffer))
           (not buffer-read-only)
           ;; The cheaper test first: telling the folder costs more.
           (+notes--has-blocks-p)
           (file-in-directory-p buffer-file-name (+notes--vault-dir)))
      (progn
        (add-hook 'before-save-hook #'+notes--blocks-save-h nil t)
        (add-hook 'after-revert-hook #'+notes--blocks-setup nil t)
        (setq +notes--blocks-stale (not written))
        (when (and (not written) (get-buffer-window (current-buffer) t))
          (+notes--blocks-schedule)))
    (remove-hook 'before-save-hook #'+notes--blocks-save-h t)
    (remove-hook 'after-revert-hook #'+notes--blocks-setup t)
    (setq +notes--blocks-stale nil)))

;;;###autoload
(defun +notes--blocks-shown-h ()
  "Write the blocks of the note just shown, when they wait for it."
  (when (and +notes--blocks-stale (not (buffer-base-buffer)))
    (+notes--blocks-schedule)))

;;;###autoload
(defun +notes--blocks-capture-h ()
  "Set up the note a capture wrote into: a new index had no blocks yet
when its mode started."
  (when-let* ((buffer (org-capture-get :buffer))
              ((buffer-live-p buffer)))
    (with-current-buffer buffer
      (+notes--blocks-setup))))

;;;###autoload
(defun +notes/blocks-refresh ()
  "Write every notes-query, notes-list and notes-board block of this note
again."
  (interactive nil org-mode)
  (let ((count (or (+notes--blocks-refresh)
                   (user-error "Turn font-lock on first: tables are aligned by what it shows"))))
    (message "Refreshed %d block%s" count (if (= count 1) "" "s"))))

;;
;;; Inserting a block

(defun +notes--in-block-p ()
  "Whether point is in a block or a drawer, between its first and last
lines, a drawer's :END: line being outside it: Org counts the blank lines
after either as its own."
  (let ((pos (point)))
    (seq-some (lambda (element)
                (let ((last (save-excursion
                              (goto-char (org-element-property :end element))
                              (skip-chars-backward " \t\n")
                              (point))))
                  (and (memq (org-element-type element)
                             '(dynamic-block center-block comment-block example-block export-block
                               quote-block special-block src-block verse-block
                               drawer property-drawer))
                       (<= (org-element-property :begin element) pos)
                       ;; A drawer's :END: line is outside it: the block
                       ;; goes after the drawer.
                       (if (memq (org-element-type element) '(drawer property-drawer))
                           (< pos (save-excursion (goto-char last) (line-beginning-position)))
                         (<= pos last)))))
              (org-element-lineage (org-element-at-point) nil t))))

(defun +notes--insert-block (name params)
  "Insert block NAME with PARAMS on the line after point, and write it."
  (unless (derived-mode-p 'org-mode)
    (user-error "Blocks go in an Org note"))
  (when (+notes--in-block-p)
    (user-error "Point is inside a block or a drawer; insert it outside"))
  ;; Below a heading's dates and drawers: between them, the block would
  ;; part the heading from its SCHEDULED line or its ID.
  (if (save-excursion (beginning-of-line) (or (org-at-heading-p) (org-at-planning-p)))
      (progn (org-end-of-meta-data t)
             ;; Before the blank lines it passed, which stay with the body.
             (skip-chars-backward " \t\n")
             (forward-line 1))
    (forward-line 1))
  (unless (bolp) (insert "\n"))
  (let ((start (point)))
    (insert "#+BEGIN: " name " " params "\n#+END:\n")
    (+notes--blocks-setup t)
    (goto-char start)
    (+notes--block-refresh-here)
    (goto-char start)))

(defun +notes--at-vault-root-p ()
  "Whether this note sits at the vault's root."
  (and (+notes--block-file)
       (file-equal-p (file-name-directory (+notes--block-file)) (+notes--vault-dir))))

;;;###autoload
(defun +notes/insert-query (query)
  "Insert a notes-query block of the headings QUERY, an Org QL string,
finds in this note's folder."
  (interactive (list (read-string "Query: " "todo:")))
  (+notes--insert-block "notes-query"
                        (format ":from %s :query %S"
                                (if (+notes--at-vault-root-p) "agenda" "folder") query)))

;;;###autoload
(defun +notes/insert-list (tags)
  "Insert a notes-list block of the notes in this note's folder that carry
every one of TAGS, a comma-separated string."
  (interactive (list (read-string "Tags (comma-separated, may be empty): ")))
  (let ((tags (split-string tags "," t "[ \t]+")))
    (+notes--insert-block "notes-list"
                          (concat ":from " (if (+notes--at-vault-root-p) "vault" "folder")
                                  (if tags (format " :tags %S" tags) "")))))

;;;###autoload
(defun +notes/insert-board ()
  "Insert a notes-board block of the tasks in this note's folder."
  (interactive)
  (+notes--insert-block "notes-board"
                        (concat ":from " (if (+notes--at-vault-root-p) "agenda" "folder"))))
