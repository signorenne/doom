;;; private/ai/autoload/notes.el -*- lexical-binding: t; -*-
;;
;; The note graph, as tools Claude can call. It can search, read and follow
;; links freely; writing is deliberately narrow: append to today's note,
;; add a task to the inbox, or leave a draft, each through the notes
;; module, so what it writes has the shape of what you write. Promoting a
;; draft into the graph stays your job, because that is the part that
;; makes you remember it.

(declare-function claude-code-ide-make-tool "claude-code-ide-mcp-server")
(declare-function org-roam-node-list "org-roam-node")
(declare-function org-roam-node-file "org-roam-node")
(declare-function org-roam-node-id "org-roam-node")
(declare-function org-roam-node-tags "org-roam-node")
(declare-function org-roam-node-title "org-roam-node")
(declare-function org-roam-node-level "org-roam-node")
(declare-function org-roam-node-from-id "org-roam-node")
(declare-function org-roam-db-query "org-roam-db")

(defvar +ai-notes-max-chars 12000
  "How much of a note, or of a result list, a tool returns at most.")

(defun +ai--notes-truncate (text)
  "TEXT, cut to `+ai-notes-max-chars' with a line saying so."
  (if (<= (length text) +ai-notes-max-chars)
      text
    (concat (substring text 0 +ai-notes-max-chars)
            "\n[cut here, ask for a specific note to see the rest]")))

(defun +ai--notes-nodes ()
  "Every file level node in the graph."
  (require 'org-roam)
  (seq-filter (lambda (node) (= 0 (org-roam-node-level node)))
              (org-roam-node-list)))

(defun +ai--notes-resolve (reference)
  "The node REFERENCE names, by id or by title.
Signals with the near misses when the title matches several notes, so the
caller can ask again precisely."
  (require 'org-roam)
  (or (ignore-errors (org-roam-node-from-id reference))
      (let* ((nodes (+ai--notes-nodes))
             (exact (seq-filter
                     (lambda (n) (string-equal-ignore-case
                                  reference (org-roam-node-title n)))
                     nodes))
             (partial (seq-filter
                       (lambda (n) (string-match-p (regexp-quote (downcase reference))
                                                   (downcase (org-roam-node-title n))))
                       nodes)))
        (cond ((= 1 (length exact)) (car exact))
              ((= 1 (length partial)) (car partial))
              ((null partial)
               (error "No note called %s" reference))
              (t (error "%s matches several notes: %s" reference
                        (mapconcat #'org-roam-node-title partial ", ")))))))

(defun +ai--notes-describe (node)
  "One line describing NODE: title, tags, when it was written."
  (format "%s | tags: %s | %s | id: %s"
          (org-roam-node-title node)
          (or (string-join (org-roam-node-tags node) ",") "none")
          (file-name-nondirectory (org-roam-node-file node))
          (org-roam-node-id node)))

;;
;;; Reading

(defun +ai--notes-search (query)
  "Lines matching QUERY in the knowledge graph and the legacy `org-directory'.
ripgrep skips hidden and ignored paths, so private progress and caches
stay out of the answer."
  (require 'org)
  (unless (executable-find "rg") (error "ripgrep (rg) is not installed"))
  (let ((roots (seq-uniq
                (seq-filter #'file-directory-p
                            (mapcar (lambda (dir) (file-name-as-directory (expand-file-name dir)))
                                    (delq nil (list (bound-and-true-p org-roam-directory)
                                                    org-directory)))))))
    (with-temp-buffer
      (apply #'call-process "rg" nil t nil "--line-number" "--no-heading"
             "--color=never" "--smart-case" "--glob" "*.org"
             "--max-count" "5" "-e" query roots)
      (if (= (point-min) (point-max))
          (format "Nothing matches %s in %s" query
                  (mapconcat #'abbreviate-file-name roots ", "))
        (+ai--notes-truncate (buffer-string))))))

(defun +ai--notes-list (&optional tag since)
  "Notes in the graph, filtered by TAG and by SINCE, a YYYY-MM-DD date."
  (let* ((nodes (+ai--notes-nodes))
         (nodes (if (and tag (not (string-empty-p tag)))
                    (seq-filter (lambda (n) (member tag (org-roam-node-tags n)))
                                nodes)
                  nodes))
         (nodes (if (and since (not (string-empty-p since)))
                    (seq-filter
                     (lambda (n)
                       (string> (format-time-string
                                 "%Y-%m-%d"
                                 (file-attribute-modification-time
                                  (file-attributes (org-roam-node-file n))))
                                since))
                     nodes)
                  nodes)))
    (if (null nodes)
        "No note matches."
      (+ai--notes-truncate
       (mapconcat #'+ai--notes-describe
                  (sort nodes (lambda (a b) (string< (org-roam-node-title a)
                                                     (org-roam-node-title b))))
                  "\n")))))

(defun +ai--notes-read (reference)
  "The text of the note REFERENCE names."
  (let ((node (+ai--notes-resolve reference)))
    (with-temp-buffer
      (insert-file-contents (org-roam-node-file node))
      (+ai--notes-truncate (buffer-string)))))

(defun +ai--notes-links (reference)
  "What points at the note REFERENCE names, and what it points at."
  (require 'org-roam)
  (let* ((node (+ai--notes-resolve reference))
         (id (org-roam-node-id node))
         (back (org-roam-db-query
                [:select [source] :from links :where (= dest $s1) :and (= type "id")]
                id))
         (forward (org-roam-db-query
                   [:select [dest] :from links :where (= source $s1) :and (= type "id")]
                   id))
         (title (lambda (row)
                  (when-let* ((n (ignore-errors (org-roam-node-from-id (car row)))))
                    (org-roam-node-title n)))))
    ;; `string-join' of nothing is "", which would read as a missing answer.
    (cl-flet ((titles (rows)
                (if-let* ((names (delq nil (mapcar title rows))))
                    (string-join names ", ")
                  "nothing")))
      (format "%s\n\nLinked from: %s\n\nLinks to: %s"
              (+ai--notes-describe node)
              (titles back)
              (titles forward)))))

;;
;;; Writing

;; The notes module writes; these say what Claude did, in its words.
;; Registered only with that module on, so the functions are there.

(defun +ai--notes-append (text &optional heading title)
  "Append TEXT under HEADING in today's daily note, as an entry named
TITLE, or the time when there is none.
Claude writes here rather than into your notes: the day is a draft, the
graph is not.  A title makes the entry a note in waiting: SPC m m e
turns it into one called that, rather than 15:30."
  (let* ((heading (if (and heading (not (string-empty-p heading))) heading "Notes"))
         (file (+notes-append-daily text heading title '("claude"))))
    (format "Written under %s in %s" heading (abbreviate-file-name file))))

(defun +ai--notes-draft (title text &optional tags)
  "Write a draft note called TITLE holding TEXT, tagged TAGS and :draft:.
Drafts live apart from the graph until they are read and promoted."
  (let ((file (+notes-new-draft title text
                                (split-string (or tags "") "[ ,]+" t)
                                "claude")))
    (format "Draft written to %s. It is tagged :draft:, so SPC n r m draft maps them"
            (abbreviate-file-name file))))

(defun +ai--notes-add-todo (title &optional body)
  "Add a TODO with TITLE and BODY to the org inbox."
  (let ((file (+notes-add-inbox-todo title body "claude-code")))
    (format "Added TODO \"%s\" to %s" title (abbreviate-file-name file))))

;;
;;; Registration

;;;###autoload
(defun +ai--register-notes-tools ()
  "Give Claude the notes: search, read, follow links, the inbox, drafts."
  (claude-code-ide-make-tool
   :function #'+ai--notes-add-todo
   :name "emacs_org_add_todo"
   :description
   (concat "Add a TODO to the knowledge repository's inbox. Use it "
           "when they ask to remember or follow up on something.")
   :args '((:name "title" :type string
            :description "Short imperative task title")
           (:name "body" :type string :optional t
            :description "Details, context or links"))
   :category "Org")
  (claude-code-ide-make-tool
   :function #'+ai--notes-search
   :name "emacs_notes_search"
   :description
   (concat "Search the user's Org notes, the knowledge repository that is "
           "the org-roam graph and the legacy Org directory, and return "
           "matching lines as file:line:text. Use it "
           "before answering anything about what they already know, wrote "
           "or decided.")
   :args '((:name "query" :type string
            :description "Regular expression, case insensitive"))
   :category "Notes")
  (claude-code-ide-make-tool
   :function #'+ai--notes-list
   :name "emacs_notes_list"
   :description
   (concat "List the notes in the graph, one per line with title, tags, "
           "file and id. Filter by tag, or by the date a note was last "
           "changed, to answer questions like what they studied this month.")
   :args '((:name "tag" :type string :optional t
            :description "Only notes carrying this tag, such as concept")
           (:name "since" :type string :optional t
            :description "Only notes touched after this YYYY-MM-DD date"))
   :category "Notes")
  (claude-code-ide-make-tool
   :function #'+ai--notes-read
   :name "emacs_notes_read"
   :description
   (concat "Return the full text of one note, named by its title or its id. "
           "Titles may be partial as long as they match a single note.")
   :args '((:name "reference" :type string
            :description "The note's title, or its id"))
   :category "Notes")
  (claude-code-ide-make-tool
   :function #'+ai--notes-links
   :name "emacs_notes_links"
   :description
   (concat "Show what links to a note and what it links to. Use it to walk "
           "the graph the way the user does, rather than guessing what is "
           "related.")
   :args '((:name "reference" :type string
            :description "The note's title, or its id"))
   :category "Notes")
  (claude-code-ide-make-tool
   :function #'+ai--notes-append
   :name "emacs_notes_append"
   :description
   (concat "Append text to today's daily note, under a heading. This is "
           "where anything you write for the user belongs: they read the "
           "day and promote what is worth keeping. Never rewrite their "
           "existing notes.")
   :args '((:name "text" :type string
            :description "Org text; keep it short and say where it came from")
           (:name "heading" :type string :optional t
            :description "Journal, Tasks or Notes; Notes by default")
           (:name "title" :type string :optional t
            :description "A short name for the entry, what it is about"))
   :category "Notes")
  (claude-code-ide-make-tool
   :function #'+ai--notes-draft
   :name "emacs_notes_draft"
   :description
   (concat "Write a new note as a draft in capture/drafts, tagged :draft:. Use "
           "it when the user asks for a note on a subject. They review and "
           "promote it; do not treat a draft as part of the graph.")
   :args '((:name "title" :type string
            :description "The idea the note is about, as a noun phrase")
           (:name "text" :type string
            :description "The body, in Org markup")
           (:name "tags" :type string :optional t
            :description "Topic tags, separated by spaces"))
   :category "Notes"))
