;;; private/notes/autoload/roam.el -*- lexical-binding: t; -*-
;;
;; What org-roam leaves to you: keeping the notes reachable from the agenda,
;; grouping them into maps, and noticing the ones that went nowhere.

(declare-function org-roam-node-list "org-roam-node")
(declare-function org-roam-node-id "org-roam-node")
(declare-function org-roam-node-tags "org-roam-node")
(declare-function org-roam-node-title "org-roam-node")
(declare-function org-roam-node-level "org-roam-node")

(declare-function org-roam-db-query "org-roam-db")
(declare-function org-roam-node-file "org-roam-node")

;;
;;; Tasks written inside notes

(defvar +notes--roam-todo-files nil
  "Cons of (TIME . FILES), the memo behind `+notes--roam-todo-files'.")

(defvar +notes-roam-todo-scan-interval 10
  "Seconds the list of notes holding a TODO is reused before scanning again.
Building an agenda calls `org-agenda-files' many times; this keeps that to
one scan.")

(defvar org-not-done-keywords)

(defun +notes--not-done-keywords ()
  "The keywords a task can be open under, read from `org-todo-keywords\='.
Not from `org-not-done-keywords\=': that one is buffer-local and nil
outside an Org buffer, and this runs from wherever the key was pressed,
so from a code buffer the checkbox sequence was dropped and a note whose
only task is a [ ] was not in the agenda."
  (let (out)
    (dolist (sequence org-todo-keywords (nreverse out))
      (let* ((entries (if (symbolp (car sequence)) (cdr sequence) sequence))
             (bar (seq-position entries "|"))
             ;; Everything before the bar is an open state; without a
             ;; bar, Org takes the last keyword for the closed one.
             (open (if bar (seq-take entries bar) (butlast entries))))
        (dolist (entry open)
          (push (replace-regexp-in-string "(.*)\\'" "" entry) out))))))

(defun +notes--roam-todo-regexp (&optional emacs)
  "What an open task looks like at the start of a line, for ripgrep, or
for Emacs with EMACS.  Built from `org-todo-keywords\=', so a keyword
added there is found in the notes as well."
  (let ((keywords (+notes--not-done-keywords)))
    (if emacs
        (concat "^\\*+ " (regexp-opt keywords t) " ")
      ;; ripgrep: every character that means something is escaped, which
      ;; the checkbox keywords [ ], [-] and [?] need.
      (concat "^\\*+ ("
              (mapconcat (lambda (k)
                           (replace-regexp-in-string "[][(){}.*+?^$|\\\\]" "\\\\\\&" k))
                         keywords "|")
              ") "))))

(defun +notes--roam-scan-todo-files ()
  "Roam files holding at least one task, by scanning the files themselves.
The org-roam database is not read here on purpose: this runs from
`org-agenda-files', which org-roam itself calls while it writes the
database."
  (let ((dir (and (boundp 'org-roam-directory)
                  (expand-file-name org-roam-directory))))
    (when (and dir (file-directory-p dir))
      (if (executable-find "rg")
          (with-temp-buffer
            (let ((default-directory dir))
              (call-process "rg" nil t nil "--files-with-matches"
                            "--glob" "*.org"
                            (+notes--roam-todo-regexp) "."))
            (mapcar (lambda (f) (expand-file-name f dir))
                    (split-string (buffer-string) "\n" t)))
        (let ((regexp (+notes--roam-todo-regexp 'emacs)))
          (seq-filter
           (lambda (file)
             (with-temp-buffer
               (insert-file-contents file)
               (re-search-forward regexp nil t)))
           (directory-files-recursively dir "\\.org\\'")))))))

(defun +notes--roam-todo-files ()
  "Roam files holding at least one task, scanned at most every few seconds."
  (let ((now (float-time)))
    (unless (and (car +notes--roam-todo-files)
                 (< (- now (car +notes--roam-todo-files))
                    +notes-roam-todo-scan-interval))
      (setq +notes--roam-todo-files
            (cons now (ignore-errors (+notes--roam-scan-todo-files)))))
    (cdr +notes--roam-todo-files)))

(defvar +notes-agenda-base-files)         ; config.el

(defun +notes--under-base-p (file)
  "Non-nil when FILE sits in a directory `+notes-agenda-base-files' names."
  (let ((dir (file-name-directory (expand-file-name file))))
    (seq-some (lambda (entry)
                (let ((entry (expand-file-name entry)))
                  (and (file-directory-p entry)
                       (file-equal-p entry dir))))
              +notes-agenda-base-files)))

(defvar +notes--agenda-files-last nil
  "The list the last refresh produced, so the refresh can tell its own
value from one somebody else set.")

(defvar +notes-daily-agenda-days 60
  "How many days back the daily notes are put in the agenda.
Older ones are still found when they hold a task; this is for the plain
timestamps a day's note carries, which no scan looks for.")

(defun +notes--recent-dailies ()
  "The daily notes of the last `+notes-daily-agenda-days\=' days."
  (when-let* (((boundp 'org-roam-dailies-directory))
              (dir (expand-file-name org-roam-dailies-directory
                                     org-roam-directory))
              ((file-directory-p dir))
              (oldest (time-subtract nil (days-to-time
                                          +notes-daily-agenda-days))))
    (seq-filter
     (lambda (file)
       (let ((name (file-name-base file)))
         (and (string-match-p "\\`[0-9]\\{4\\}-[0-9][0-9]-[0-9][0-9]\\'" name)
              (time-less-p oldest (date-to-time (concat name "T00:00:00"))))))
     (directory-files dir t "\\.org\\'"))))

;;;###autoload
(defun +notes--agenda-files-refresh-h (&rest _)
  "Set `org-agenda-files' to the base list plus the roam notes that hold
a task.  Before an agenda or a refile; a note already covered by a
directory in the base list is not added twice.  A value somebody else
put there, a caller binding the list around `org-agenda', is left as
it is."
  (when (or (null org-agenda-files)
            (equal org-agenda-files +notes-agenda-base-files)
            (equal org-agenda-files +notes--agenda-files-last))
    (setq +notes--agenda-files-last
          (append +notes-agenda-base-files
                  (+notes--recent-dailies)
                  (seq-remove #'+notes--under-base-p (+notes--roam-todo-files)))
          org-agenda-files +notes--agenda-files-last)))

;;;###autoload
(defun +notes--refile-files ()
  "Where a refile may go: the agenda files without the daily notes."
  (+notes--agenda-files-refresh-h)
  (let ((daily (expand-file-name "daily" org-roam-directory)))
    (seq-remove (lambda (file)
                  (file-in-directory-p (expand-file-name file) daily))
                (org-agenda-files))))

;;;###autoload
(defun +notes/roam-todo-files ()
  "List the roam notes that hold a task."
  (interactive)
  (setq +notes--roam-todo-files nil)      ; the point of asking is a fresh answer
  (let ((files (+notes--roam-todo-files)))
    (if (null files)
        (message "No roam note holds a task")
      (message "%d note(s) with tasks: %s"
               (length files)
               (mapconcat #'file-name-nondirectory files ", ")))))


;;;###autoload
(defun +notes/roam-guide ()
  "Open the guide: how to work with the note graph on purpose."
  (interactive)
  (find-file (file-name-concat doom-user-dir "docs/org-roam-guide.org")))

;;
;;; Promoting a heading into a note

(declare-function org-roam-extract-subtree "org-roam-node")
(declare-function org-roam-tag-add "org-roam-node")
(declare-function org-roam-db-update-file "org-roam-db")

;;;###autoload
(defun +notes/roam-extract ()
  "Move the subtree at point into its own note and leave a link where it was.
org-roam's own extract cuts the heading out and stops there.  This one also
stamps the new note with the date, asks for its tags, and puts a link back
in the place the heading came from, so the day still reads as a story."
  (interactive)
  (require 'org-roam)
  (org-back-to-heading t)
  (let* ((title (org-get-heading t t t t))
         (origin (copy-marker (line-beginning-position)))
         (source (current-buffer))
         (before (buffer-list)))
    ;; The extraction cuts and pastes through the kill ring. Keep it from
    ;; appending to whatever was killed last, from leaving the heading on
    ;; top of what you had yanked, and from reaching the system clipboard.
    (let ((last-command nil)
          (kill-ring kill-ring)
          (kill-ring-yank-pointer kill-ring-yank-pointer)
          (interprogram-cut-function nil))
      (org-roam-extract-subtree))
    ;; The new note is the org buffer that was not open before.
    (let ((target (seq-find (lambda (b) (and (not (memq b before))
                                             (buffer-file-name b)
                                             (string-suffix-p ".org" (buffer-file-name b))))
                            (buffer-list))))
      (unless target (user-error "The note was not created"))
      (with-current-buffer target
        (goto-char (point-min))
        ;; A journal entry carries the time it was written; keep that,
        ;; and date a heading that had none now.
        (unless (org-entry-get (point-min) "CREATED")
          (org-entry-put (point-min) "CREATED"
                         (format-time-string "[%Y-%m-%d %a %H:%M]")))
        (goto-char (point-min))
        (call-interactively #'org-roam-tag-add)
        ;; A blank line between the header and the text, like the templates.
        (goto-char (point-min))
        (when (re-search-forward "^#\\+filetags:.*$" nil t)
          (forward-line 1)
          (unless (looking-at-p "^$") (insert "\n")))
        (save-buffer)
        (org-roam-db-update-file (buffer-file-name))
        (let ((id (org-entry-get (point-min) "ID")))
          (with-current-buffer source
            (save-excursion
              (goto-char origin)
              (insert (format "- [[id:%s][%s]]\n" id title)))
            (save-buffer)))
        (message "%s is a note now, linked from where it was" title)))))

;;
;;; Maps of content

(defun +notes--roam-tags ()
  "Every tag used in the graph, sorted."
  (sort (seq-uniq (mapcan (lambda (node) (copy-sequence (org-roam-node-tags node)))
                          (org-roam-node-list)))
        #'string<))

(defun +notes--roam-nodes-tagged (tag)
  "File level nodes tagged TAG, by title."
  (sort (seq-filter (lambda (node)
                      (and (= 0 (org-roam-node-level node))
                           (member tag (org-roam-node-tags node))))
                    (org-roam-node-list))
        (lambda (a b) (string< (org-roam-node-title a) (org-roam-node-title b)))))

(defun +notes--roam-map-file (tag)
  "Path of the map note for TAG."
  (expand-file-name (format "maps/%s.org" tag) org-roam-directory))

(defun +notes--roam-map-links (tag)
  "The link list for the map of TAG."
  (let ((nodes (+notes--roam-nodes-tagged tag)))
    (if (null nodes)
        "Nothing is tagged this way yet.\n"
      (mapconcat (lambda (node)
                   (format "- [[id:%s][%s]]\n"
                           (org-roam-node-id node)
                           (org-roam-node-title node)))
                 nodes ""))))

;;;###autoload
(defun +notes/roam-map-of-content (tag)
  "Write a map of the notes tagged TAG, then open it.
The map is a roam note of its own, so it shows in the graph and can be
linked like any other.  Only the list between the markers is rewritten, so
whatever you write around it stays."
  (interactive (list (completing-read "Map the notes tagged: " (+notes--roam-tags))))
  (require 'org-roam)
  (let ((file (+notes--roam-map-file tag))
        (links (+notes--roam-map-links tag)))
    (make-directory (file-name-directory file) t)
    (with-current-buffer (find-file-noselect file)
      (if (zerop (buffer-size))
          (insert (format (concat ":PROPERTIES:\n:ID:       %s\n:CREATED:  %s\n"
                                  ":END:\n#+title: Map of %s\n#+filetags: :map:\n"
                                  "#+startup: content\n\n"
                                  "Everything tagged =%s=. Say here what the\n"
                                  "pieces have to do with each other; the list\n"
                                  "below is generated.\n\n* Notes\n"
                                  "# BEGIN MAP\n%s# END MAP\n")
                          (org-id-new)
                          (format-time-string "[%Y-%m-%d %a %H:%M]")
                          (capitalize tag) tag links))
        (save-excursion
          (goto-char (point-min))
          (if (re-search-forward "^# BEGIN MAP$" nil t)
              (let ((start (1+ (line-end-position))))
                (when (re-search-forward "^# END MAP$" nil t)
                  (delete-region start (line-beginning-position))
                  (goto-char start)
                  (insert links)))
            (goto-char (point-max))
            (insert (format "\n* Notes\n# BEGIN MAP\n%s# END MAP\n" links)))))
      (save-buffer)
      (pop-to-buffer (current-buffer)))
    (message "Map of %s: %d note(s). SPC n r m rebuilds it"
             tag (length (+notes--roam-nodes-tagged tag)))))


;;
;;; Reviewing the graph

(defun +notes--roam-linked-ids ()
  "Ids that appear on either end of an id link."
  (let ((ids (make-hash-table :test #'equal)))
    (dolist (row (ignore-errors
                   (org-roam-db-query
                    [:select [source dest] :from links :where (= type "id")])))
      (puthash (nth 0 row) t ids)
      (puthash (nth 1 row) t ids))
    ids))

(defvar +notes-roam-stub-length 150
  "A note with fewer characters than this, header aside, counts as a stub.")

(defun +notes--roam-body-length (file)
  "Characters in FILE that are neither the drawer, a keyword nor a heading."
  (with-temp-buffer
    (insert-file-contents file)
    (goto-char (point-min))
    ;; Drop the property drawer, the #+keywords and the headings themselves:
    ;; what is left is what was actually written.
    (when (looking-at-p "^:PROPERTIES:")
      (re-search-forward "^:END:$" nil t))
    (let ((body 0))
      (while (not (eobp))
        (let ((line (buffer-substring-no-properties
                     (line-beginning-position) (line-end-position))))
          (unless (string-match-p "\\`\\s-*\\(?:#\\+\\|\\*+ \\|\\'\\)" line)
            (cl-incf body (length (string-trim line)))))
        (forward-line 1))
      body)))

(defun +notes--roam-stub-p (node)
  "Non-nil when NODE's file has a header and little else."
  (let ((file (org-roam-node-file node)))
    (and (= 0 (org-roam-node-level node))
         (file-readable-p file)
         (< (+notes--roam-body-length file) +notes-roam-stub-length))))

(defun +notes--roam-insert-group (title nodes hint)
  "Insert a heading TITLE listing NODES, or HINT when there are none."
  (insert (format "* %s (%d)\n" title (length nodes)))
  (if (null nodes)
      (insert hint "\n\n")
    (dolist (node nodes)
      (insert (format "- [[id:%s][%s]]\n"
                      (org-roam-node-id node) (org-roam-node-title node))))
    (insert "\n")))

;;;###autoload
(defun +notes/roam-review ()
  "Show the notes that need attention: no links, no tags, barely written.
A graph is only useful while its notes are connected and findable, and this
is the list of the ones that are neither."
  (interactive)
  (require 'org-roam)
  (let* ((nodes (seq-filter (lambda (n) (= 0 (org-roam-node-level n)))
                            (org-roam-node-list)))
         (linked (+notes--roam-linked-ids))
         (orphans (seq-remove (lambda (n) (gethash (org-roam-node-id n) linked))
                              nodes))
         (untagged (seq-remove #'org-roam-node-tags nodes))
         (stubs (seq-filter #'+notes--roam-stub-p nodes))
         (buffer (get-buffer-create "*roam review*")))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert "#+title: Roam review\n"
                (format "#+date: %s\n\n" (format-time-string "%Y-%m-%d %H:%M"))
                (format "%d note%s in the graph.\n\n"
                        (length nodes) (if (= 1 (length nodes)) "" "s")))
        (+notes--roam-insert-group
         "Nothing links here, and it links nowhere" orphans
         "Every note is connected.")
        (+notes--roam-insert-group
         "No tags, so no map will ever find them" untagged
         "Every note is tagged.")
        (+notes--roam-insert-group
         "Started and left empty" stubs
         "Nothing left half written.")
        (insert "Fix a note by opening it, adding a link with SPC n r i,\n"
                "a tag with SPC m m o t, then rebuild its map with\n"
                "SPC n r m. SPC n r v again refreshes this list.\n")
        (goto-char (point-min))
        (org-mode)
        (setq-local revert-buffer-function
                    (lambda (&rest _) (+notes/roam-review)))
        (view-mode +1)))
    (pop-to-buffer buffer)))
