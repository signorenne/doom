;;; private/notes/autoload/menu.el -*- lexical-binding: t; -*-

(require 'transient)

(defvar +notes-documents)
(declare-function +notes--capture-templates "+capture")
(declare-function org-capture "org-capture")
(declare-function org-roam-capture "org-roam-capture")
(declare-function org-roam-node-find "org-roam-node")
(declare-function org-roam-db-query "org-roam-db")

(defvar +notes--inbox-count nil
  "((FILE MTIME) . COUNT), the memo behind `+notes--inbox-count'.")

(defun +notes--inbox-count ()
  "Number of TODO entries in the inbox, or nil when there is no inbox.
Counted again only when the file has changed: the menu asks on every
redraw, and read the whole inbox each time."
  (let ((file (expand-file-name "inbox.org" org-directory)))
    (when (file-readable-p file)
      (let ((key (list file (file-attribute-modification-time
                             (file-attributes file)))))
        (unless (equal key (car +notes--inbox-count))
          (setq +notes--inbox-count
                (cons key (with-temp-buffer
                            (insert-file-contents file)
                            (how-many "^\\*+ TODO " (point-min) (point-max))))))
        (cdr +notes--inbox-count)))))

(defvar +notes--roam-count nil
  "(TIME . COUNT), the memo behind `+notes--roam-count'.")

(defun +notes--roam-count ()
  "How many notes the graph holds, or nil when roam is not set up.
One count query, remembered for a minute: the menu asks on every
redraw, and building a struct per node took the whole graph each time."
  (when (and (fboundp 'org-roam-db-query) (file-directory-p org-roam-directory))
    (let ((now (float-time)))
      (unless (and +notes--roam-count (< (- now (car +notes--roam-count)) 60))
        (setq +notes--roam-count
              (cons now (ignore-errors
                          (caar (org-roam-db-query
                                 [:select (funcall count) :from nodes :where (= level 0)]))))))
      (cdr +notes--roam-count))))

(defun +notes--capture-suffixes (_children)
  "The capture column of `+notes/menu': one entry per template of
`+notes--capture-templates', on c and the template's own key, so a
template added there is in the menu as well, then the two roam kinds a
day needs, a note and a meeting.  The browser template is left out,
org-protocol fills it; the bookmarklets entry covers it."
  (transient-parse-suffixes
   '+notes/menu
   (append
    (cl-loop for (key description) in (+notes--capture-templates)
             unless (equal key "w")
             collect (list (concat "c " key) description
                           (let ((key key))
                             (lambda () (interactive) (org-capture nil key)))))
    '(("c n" "Note, a kind in the graph" (lambda () (interactive) (org-roam-capture nil "c")))
      ("c m" "Meeting, in the graph" (lambda () (interactive) (org-roam-capture nil "m")))
      ("c w" "From the browser" +notes/protocol-bookmarklets)
      ("c SPC" "Pick a template" org-capture)))))

(defun +notes--menu-description ()
  "Header for `+notes/menu': where the notes are and what is waiting."
  (let ((count (+notes--inbox-count))
        (nodes (+notes--roam-count)))
    (format "%s   inbox: %s   roam: %s"
            (propertize (abbreviate-file-name org-directory) 'face 'bold)
            (cond ((null count) "no documents yet (d b)")
                  ((zerop count) "empty")
                  (t (format "%d to refile" count)))
            (cond ((null nodes) "missing")
                  ((zerop nodes) "empty, r f starts a note")
                  (t (format "%d notes" nodes))))))

;; The SPC n keys, laid out: d the documents, c the captures, r roam, as
;; on the leader; the agenda views under a, SPC o a there; and the
;; single keys the leader has, g G p P B. q closes the menu and ? then
;; a key explains it, so nothing sits on those.
;;;###autoload (autoload '+notes/menu "private/notes/autoload/menu" nil t)
(transient-define-prefix +notes/menu ()
  "Notes and tasks: documents, capture, agenda, roam, the same keys as SPC n."
  [:description +notes--menu-description
   ["Documents (d)"
    ("d i" "Inbox"        (lambda () (interactive) (+notes/open-document "inbox")))
    ("d t" "Todo"         (lambda () (interactive) (+notes/open-document "todo")))
    ("d p" "Projects"     (lambda () (interactive) (+notes/open-document "projects")))
    ("d n" "Snippets"     (lambda () (interactive) (+notes/open-document "notes")))
    ("d r" "Reading"      (lambda () (interactive) (+notes/open-document "reading")))
    ("d d" "Any document" +notes/open-document)
    ("d j" "Today's daily note" org-roam-dailies-goto-today)
    ("d w" "Writing mode" +notes/writing-mode)
    ("d b" "Create missing documents" +notes/bootstrap)]
   ["Capture (c)" :class transient-column :setup-children +notes--capture-suffixes]
   ["Agenda (a)"
    ("a x" "Dashboard"      +notes/dashboard)
    ("a w" "Weekly review"  +notes/weekly-review)
    ("a n" "Next actions"   +notes/next-actions)
    ("a p" "Projects"       +notes/projects)
    ("a i" "Inbox"          +notes/inbox)
    ("a t" "Todo list"      org-todo-list)
    ("a q" "Query (org-ql)" +notes/query)]]
  [["Roam (r)"
    ("r f" "Find or create node" org-roam-node-find)
    ("r n" "Capture node"        org-roam-capture)
    ("r /" "Search notes"        consult-org-roam-search)
    ("r B" "Backlinks"           consult-org-roam-backlinks)
    ("r m" "Map of a tag"        +notes/roam-map-of-content)
    ("r v" "Review the graph"    +notes/roam-review)
    ("r h" "Tasks hidden in notes" +notes/roam-todo-files)
    ("r u" "Graph in browser"    org-roam-ui-open)
    ("r s" "Sync database"       org-roam-db-sync)
    ("r ?" "How to work with roam" +notes/roam-guide)]
   ["Keep"
    ("g" "Commit the notes"    +notes/commit)
    ("G" "Sync with the remote" +notes/sync)
    ("H" "What changed"        +notes/log)
    ("V" "Version the notes (git init)" +notes/init-repo
     :if (lambda () (not (+notes-repo-p))))
    ("p" "Review the cards due" org-fc-review-all)
    ("P" "Card dashboard"      org-fc-dashboard)
    ("B" "The bibliography"    citar-open)]
   ["Write"
    ("M" "Mind map"         org-mind-map-write)
    ("e" "Export dispatch"  org-export-dispatch)
    ("z" "Presentation"     org-tree-slide-mode)
    ("k" "Pomodoro"         org-pomodoro)]])
