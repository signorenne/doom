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
(declare-function +notes--roam-db-ready "roam-db")
(declare-function +notes--roam-db-building "roam-db")

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

(defun +notes--active-task-file-p (file)
  "Whether FILE belongs to an active task context, outside archives.
The journal counts: a task typed into a daily note stays in view until it
is refiled into its project. Knowledge, sources and drafts never hold tasks."
  (let ((root (expand-file-name org-roam-directory)))
    (and (file-in-directory-p file root)
         (not (file-in-directory-p file (expand-file-name "archives/" root)))
         (or (equal (expand-file-name file) (+notes--inbox-file))
             (file-in-directory-p file (expand-file-name "projects/" root))
             (file-in-directory-p file (expand-file-name "areas/" root))
             (file-in-directory-p file (expand-file-name
                                        (if (boundp 'org-roam-dailies-directory)
                                            org-roam-dailies-directory
                                          "capture/journal/")
                                        root))))))

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
                            "--glob" "*.org" "--glob" "!archives/**"
                            (+notes--roam-todo-regexp) "."))
            (seq-filter #'+notes--active-task-file-p
                        (mapcar (lambda (f) (expand-file-name f dir))
                                (split-string (buffer-string) "\n" t))))
        (let ((regexp (+notes--roam-todo-regexp 'emacs)))
          (seq-filter
           (lambda (file)
             (and (+notes--active-task-file-p file)
                  (with-temp-buffer
                    (insert-file-contents file)
                    (re-search-forward regexp nil t))))
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

(defvar +notes-agenda-base-files)

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
  ;; capture/journal/, the value the config sets, until org-roam-dailies
  ;; is loaded: org-roam does not load it on its own, and the agenda
  ;; should not miss the dailies meanwhile.
  (when-let* ((dir (expand-file-name (if (boundp 'org-roam-dailies-directory)
                                         org-roam-dailies-directory
                                       "capture/journal/")
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
          (delete-dups
           (append (seq-filter #'+notes--active-task-file-p +notes-agenda-base-files)
                   (+notes--project-files)
                   ;; A course's timetable is plain dates, which no scan
                   ;; for tasks would find.
                   (+notes--course-files)
                   (+notes--recent-dailies)
                   (seq-remove #'+notes--under-base-p (+notes--roam-todo-files))))
          org-agenda-files +notes--agenda-files-last)))

(defvar +notes-documents)

;;;###autoload
(defun +notes--refile-files ()
  "The documents there are, the active projects and the active courses,
including those with no TODOs."
  (delete-dups
   (append (seq-filter #'file-exists-p
                       (mapcar (lambda (doc) (expand-file-name (cdr doc) org-directory))
                               +notes-documents))
           (+notes--project-files)
           (+notes--course-files))))

;;;###autoload
(defun +notes/roam-todo-files ()
  "List the roam notes that hold a task."
  (interactive)
  (setq +notes--roam-todo-files nil)      ; the point of asking is a fresh answer
  (let ((files (+notes--roam-todo-files)))
    (if (null files)
        (message "No roam note holds a task")
      ;; By their place in the vault: every project is an index.org.
      (message "%d note(s) with tasks: %s"
               (length files)
               (mapconcat (lambda (file) (file-relative-name file org-roam-directory))
                          files ", ")))))


(defvar org-roam-ui-mode)
(defvar org-roam-ui-open-on-start)
(declare-function org-roam-ui-open "org-roam-ui")

;;;###autoload
(defun +notes/roam-ui-open ()
  "Show the graph in the browser, once. org-roam-ui's own open starts its
server first, which opens the browser by itself, then opens it again."
  (interactive)
  (require 'org-roam-ui)
  (if (or org-roam-ui-mode (not org-roam-ui-open-on-start))
      (org-roam-ui-open)
    (org-roam-ui-mode 1)))

;;;###autoload
(defun +notes/roam-guide ()
  "Open the guide: how to work with the note graph on purpose."
  (interactive)
  (find-file (file-name-concat doom-user-dir "docs/org-roam-guide.org")))

;;
;;; Promoting a heading into a note

(declare-function org-roam-tag-add "org-roam-node")
(declare-function org-roam-tag-completions "org-roam-node")
(declare-function org-roam-promote-entire-buffer "org-roam-node")
(declare-function org-roam-db-update-file "org-roam-db")
(defvar org-roam-db-update-on-save)
;; Special, so the prompt's separator and hint below are crm's own, bound
;; before crm is loaded too.
(defvar crm-separator)
(defvar crm-prompt)

;;;###autoload
(defun +notes/roam-extract ()
  "Move the subtree at point into its own note and leave a link where it was.
org-roam's own extract cuts the heading out and stops there.  This one also
stamps the new note with the date, asks for its tags, and puts a link back
in the place the heading came from, so the day still reads as a story.
Where the note goes and its tags are asked before anything changes, so
C-g at either leaves the heading where it was."
  (interactive)
  (unless (derived-mode-p 'org-mode) (user-error "Extract a heading of an Org note"))
  (when (org-before-first-heading-p) (user-error "No heading here to extract"))
  (require 'org-roam)
  ;; Before anything is asked: a heading that cannot leave would leave a
  ;; note behind with no link to it.
  (barf-if-buffer-read-only)
  (org-back-to-heading t)
  ;; Not org-roam's extract: it asks again where to write once it has
  ;; given the heading an ID and saved, and cuts the heading out before
  ;; the new note exists. Here the note is written first, from a copy.
  (let* ((title (org-get-heading t t t t))
         (file (+notes--roam-read-subject (org-roam-node-create :title title)))
         (_ (when (file-exists-p file)
              (user-error "%s exists already; give the heading another title"
                          (file-relative-name file org-roam-directory))))
         ;; One hint of the separator, Doom's [CRM:]: Emacs's own said it
         ;; again before it.
         (tags (let ((crm-separator "[ \t]*:[ \t]*")
                     (crm-prompt "%p"))
                 (completing-read-multiple "Tag: " (org-roam-tag-completions))))
         (source (current-buffer))
         (start (point-marker))
         (end (save-excursion (org-end-of-subtree t t) (point-marker)))
         ;; A new subject's directory, made now that nothing is left to
         ;; ask, before Doom asks whether to make it.
         (note (progn (make-directory (file-name-directory file) t)
                      (find-file-noselect file)))
         id linked
         (link-back
          (lambda ()
            ;; Once, from the body or from the cleanup below.
            (unless linked
              (setq linked t)
              (with-current-buffer source
                (save-excursion
                  (delete-region start end)
                  (goto-char start)
                  (insert (format "- [[id:%s][%s]]\n" id title)))
                (save-buffer))))))
    (unwind-protect
        (with-current-buffer note
          (insert (with-current-buffer source
                    (buffer-substring-no-properties start end)))
          (goto-char (point-min))
          (while (> (org-current-level) 1) (org-promote-subtree))
          ;; A journal entry carries the time it was written; keep that,
          ;; and date a heading that had none now.
          (unless (org-entry-get (point) "CREATED")
            (org-entry-put (point) "CREATED" (format-time-string "[%Y-%m-%d %a %H:%M]")))
          (setq id (org-id-get-create))
          ;; On disk before the heading leaves the source, but kept from
          ;; the database until it has: an ID the heading or one under it
          ;; already had would be in two files, and org-roam then drops
          ;; the node.
          (let ((org-roam-db-update-on-save nil))
            (save-buffer))
          (funcall link-back)
          ;; org-roam makes the heading the title by killing its line. Keep
          ;; that from appending to whatever was killed last, now or at your
          ;; next kill, from sitting on top of what you had yanked, and from
          ;; reaching the system clipboard.
          (let ((last-command nil)
                (this-command this-command)
                (kill-ring kill-ring)
                (kill-ring-yank-pointer kill-ring-yank-pointer)
                (interprogram-cut-function nil))
            (org-roam-promote-entire-buffer))
          (when tags
            (goto-char (point-min))
            (org-roam-tag-add tags))
          ;; A blank line between the header and the text, like the templates.
          (goto-char (point-min))
          (when (or (re-search-forward "^#\\+filetags:.*$" nil t)
                    (re-search-forward "^#\\+title:.*$" nil t))
            (forward-line 1)
            (unless (looking-at-p "^$") (insert "\n")))
          (save-buffer)
          (org-roam-db-update-file file))
      ;; Once the note is on disk the heading's place holds the link to
      ;; it, whatever stopped the rest; before that nothing has changed.
      (if (file-exists-p file)
          (funcall link-back)
        (when (buffer-live-p note)
          (with-current-buffer note (set-buffer-modified-p nil))
          (kill-buffer note))))
    (message "%s is a note now, linked from where it was" title)))

;;
;;; Renaming a note

(declare-function org-roam-node-at-point "org-roam-node")
(declare-function org-roam-node-point "org-roam-node")
(declare-function org-roam-node-slug "org-roam-node")
(declare-function org-roam-node-create "org-roam-node")
(declare-function org-edit-headline "org")
(declare-function org-link-make-string "ol")
(declare-function org-roam-file-p "org-roam")
(declare-function org-find-entry-with-id "org")
(declare-function org-roam-node-from-id "org-roam-node")

(defvar +notes--renaming nil
  "Non-nil while a rename saves files, so that their saves rename nothing.")

(defvar-local +notes--saved-title nil
  "This note's #+title when it was visited or last saved.")

(defun +notes--file-title ()
  "This buffer's #+title, or nil."
  (save-excursion
    (save-restriction
      (widen)
      (goto-char (point-min))
      (let ((case-fold-search t))
        (when (re-search-forward "^#\\+title:[ \t]*\\(.*?\\)[ \t]*$" nil t)
          (match-string-no-properties 1))))))

(defun +notes--set-file-title (title)
  "Make TITLE this buffer's #+title, adding the line after the drawer."
  (save-excursion
    (save-restriction
      (widen)
      (goto-char (point-min))
      (let ((case-fold-search t))
        (if (re-search-forward "^\\(#\\+title:\\)[ \t]*.*$" nil t)
            (replace-match (concat (match-string 1) " " title) t t)
          (when (looking-at-p ":PROPERTIES:")
            (re-search-forward "^:END:\n" nil t))
          (insert "#+title: " title "\n"))))))

(defun +notes--slug (title)
  "The file name org-roam makes of TITLE."
  (org-roam-node-slug (org-roam-node-create :title title)))

(defun +notes--renamed-file (file old new)
  "FILE's name for the title NEW, when FILE is named for the title OLD,
plain or after a YYYYMMDD- date; nil when it is named some other way."
  (let ((base (file-name-base file)))
    (when (string-match (concat "\\`\\([0-9]\\{8\\}-\\)?" (regexp-quote (+notes--slug old)) "\\'")
                        base)
      (expand-file-name (concat (or (match-string 1 base) "") (+notes--slug new)
                                "." (file-name-extension file))
                        (file-name-directory file)))))

(defun +notes--save-quietly ()
  "Save this buffer without starting a rename."
  (let ((+notes--renaming t))
    (save-buffer)))

(defun +notes--relink (id old new)
  "Give the id: links to ID described as exactly OLD the description NEW,
in the files the database says link to ID.  A buffer with unsaved
changes is edited and left unsaved; any other open one is saved; a file
not open is written without visiting it.  Returns (LINKS FILES UNSAVED)."
  ;; Org's own link puts a zero-width space into a "]]" of the description
  ;; and after a "]" that ends it; the link completion inserts as you type
  ;; is as typed, so both are looked for.
  (let ((from (delete-dups (list (org-link-make-string (concat "id:" id) old)
                                 (format "[[id:%s][%s]]" id old))))
        (to (org-link-make-string (concat "id:" id) new))
        (case-fold-search nil)
        (links 0) (files 0) unsaved)
    (dolist (file (mapcar #'car (org-roam-db-query
                                 [:select :distinct [nodes:file] :from links
                                  :inner-join nodes :on (= links:source nodes:id)
                                  :where (and (= links:dest $s1) (= links:type "id"))]
                                 id)))
      (let ((count 0)
            (buffer (find-buffer-visiting file)))
        (cl-flet ((relink ()
                    (dolist (link from)
                      (goto-char (point-min))
                      (while (search-forward link nil t)
                        (replace-match to t t)
                        (cl-incf count)))))
          (if buffer
              (with-current-buffer buffer
                (let ((dirty (buffer-modified-p)))
                  (save-excursion (save-restriction (widen) (relink)))
                  (when (> count 0)
                    (if dirty (push file unsaved) (+notes--save-quietly)))))
            (with-temp-buffer
              (insert-file-contents file)
              (let ((coding last-coding-system-used))
                (relink)
                (when (> count 0)
                  (let ((coding-system-for-write coding))
                    (write-region nil nil file nil 'silent)))))))
        (when (> count 0)
          (cl-incf links count)
          (cl-incf files)
          (org-roam-db-update-file file))))
    (list links files (nreverse unsaved))))

(defun +notes--rename-report (old new renamed kept relinked)
  "Say what a rename did: RENAMED the new file or nil, KEPT why the name
stayed or nil, RELINKED what `+notes--relink' returned."
  (pcase-let ((`(,links ,files ,unsaved) relinked))
    (message "Renamed %S to %S%s%s; %d link%s in %d file%s updated%s"
             old new
             (if renamed (format ", now %s" (file-name-nondirectory renamed)) "")
             (if kept (format ", file name kept: %s" kept) "")
             links (if (= links 1) "" "s") files (if (= files 1) "" "s")
             (if unsaved
                 (format ", left unsaved in %s, which had changes"
                         (mapconcat #'file-name-nondirectory unsaved ", "))
               ""))))

(defun +notes--rename-file-node (id old new)
  "This buffer's file node ID, saved with the title NEW, was OLD: rename
its file when it is named for OLD, and its links, then say so."
  (let* ((file (buffer-file-name))
         (target (+notes--renamed-file file old new))
         kept)
    (cond ((or (null target) (equal target file)) (setq target nil))
          ((string-empty-p (+notes--slug new))
           (setq kept "the new title makes no file name"
                 target nil))
          ((file-exists-p target)
           (setq kept (format "%s exists" (file-name-nondirectory target))
                 target nil))
          (t
           ;; org-roam's advice on rename-file moves the file in the
           ;; database; the buffer has to be moved by hand.
           (rename-file file target)
           (set-visited-file-name target t t)))
    (+notes--rename-report old new target kept (+notes--relink id old new))))

(defun +notes--rename-node ()
  "The note at point to rename, or a user-error that says why there is none.
Only in the note's own file in the vault: a copy elsewhere carries the
same ID, and renaming it would rename the links to the real one."
  (let* ((base (or (buffer-base-buffer) (current-buffer)))
         (file (buffer-file-name base)))
    (unless (and (derived-mode-p 'org-mode) file
                 (with-current-buffer base (org-roam-file-p)))
      (user-error "Rename a note of the vault from its own buffer"))
    (when (buffer-local-value 'buffer-read-only base)
      (user-error "This buffer is read only"))
    ;; The links to rename are the database's.
    (+notes--roam-db-ready)
    (let ((node (org-roam-node-at-point)))
      (unless (and node (org-roam-node-title node) (org-roam-node-level node))
        (user-error "Not in a note the graph knows yet; save it first"))
      (unless (file-equal-p (org-roam-node-file node) file)
        (user-error "%S is in %s, not this file" (org-roam-node-title node)
                    (abbreviate-file-name (org-roam-node-file node))))
      node)))

;;;###autoload
(defun +notes/roam-rename (title)
  "Retitle the note at point TITLE, its file name and links following.
A file node's #+title changes, a heading node's heading, its keyword,
priority and tags kept, and the file is saved.  A file named for the old
title, plain or after a YYYYMMDD- date, is renamed for the new one; any
other name, a daily note's or a project's index.org, stays.  Every id:
link described by exactly the old title then reads the new one."
  (interactive (let ((old (org-roam-node-title (+notes--rename-node))))
                 (list (read-string (format-prompt "New title" old) nil nil old))))
  (let* ((node (+notes--rename-node))
         (old (org-roam-node-title node))
         (new (string-trim title)))
    ;; From an indirect buffer, a subtree of the note, the file and its
    ;; title are the base buffer's.
    (with-current-buffer (or (buffer-base-buffer) (current-buffer))
      (cond
       ((string-empty-p new) (user-error "A note needs a title"))
       ((equal old new) (message "The title is %S already" old))
       ((zerop (org-roam-node-level node))
        (+notes--set-file-title new)
        (+notes--save-quietly)
        (setq +notes--saved-title new)
        (+notes--rename-file-node (org-roam-node-id node) old new))
       (t
        ;; By its ID: the database's position is the last save's, and an
        ;; edit above the heading since would retitle another one.
        (save-excursion
          (save-restriction
            (widen)
            (goto-char (or (org-find-entry-with-id (org-roam-node-id node))
                           (user-error "The heading of %S is not in this buffer" old)))
            (org-edit-headline new)))
        (+notes--save-quietly)
        (+notes--rename-report old new nil nil
                               (+notes--relink (org-roam-node-id node) old new)))))))

(defun +notes--rename-on-save-h ()
  "Rename the note's file and links when this save changed its #+title.
Only the note's own file, in the vault: a buffer written out elsewhere
keeps the hook it was given, and a copy carries the note's ID.  While
the database is built for the first time it knows none of the links,
so the old title is kept and the first save after the build renames."
  (unless (or +notes--renaming (+notes--roam-db-building))
    (let ((title (+notes--file-title))
          (old +notes--saved-title))
      (setq +notes--saved-title title)
      (when-let* (((and old title (not (equal old title))))
                  ((org-roam-file-p))
                  (id (save-restriction (widen) (org-entry-get (point-min) "ID")))
                  (node (org-roam-node-from-id id))
                  ((file-equal-p (org-roam-node-file node) buffer-file-name)))
        (let ((+notes--renaming t))
          (+notes--rename-file-node id old title))))))

(defun +notes--remember-title-h ()
  "Keep the #+title the file has now: a revert brought it, not an edit."
  (setq +notes--saved-title (+notes--file-title)))

;;;###autoload
(defun +notes--rename-on-save-setup-h ()
  "Keep this note's title, so that a save that changes it renames it."
  (setq +notes--saved-title (+notes--file-title))
  (add-hook 'after-save-hook #'+notes--rename-on-save-h nil t)
  (add-hook 'after-revert-hook #'+notes--remember-title-h nil t))

;;
;;; Starred notes

(declare-function org-roam-tag-remove "org-roam-node")
(declare-function org-roam-node-read "org-roam-node")
(declare-function org-roam-node-visit "org-roam-node")
(declare-function org-collect-keywords "org")
(declare-function org-toggle-tag "org")

(defun +notes--file-tags ()
  "The tags in this buffer's #+filetags."
  (split-string (or (cadr (assoc "FILETAGS" (org-collect-keywords '("FILETAGS")))) "")
                ":" t))

;;;###autoload
(defun +notes/roam-star ()
  "Star the note at point, or unstar it: the tag starred, in #+filetags
for a file node, on the heading itself for a heading node."
  (interactive)
  (let ((node (or (org-roam-node-at-point) (user-error "Not in a note"))))
    (save-excursion
      (if (zerop (org-roam-node-level node))
          (if (member "starred" (+notes--file-tags))
              (progn (org-roam-tag-remove '("starred")) (message "Unstarred"))
            (org-roam-tag-add '("starred"))
            (message "Starred"))
        ;; Not org-roam-tag-add: it reads a heading's tags with the
        ;; inherited ones and would write the file's onto the heading.
        (goto-char (org-roam-node-point node))
        (let ((on (not (member "starred" (org-get-tags nil t)))))
          (org-toggle-tag "starred" (if on 'on 'off))
          (message (if on "Starred" "Unstarred")))))))

(defun +notes--roam-starred-ids ()
  "The ids of the starred notes: the files tagged starred, and the starred
headings of files that are not, which would otherwise be listed twice."
  (let* ((rows (org-roam-db-query
                [:select [nodes:id nodes:level nodes:file] :from tags
                 :inner-join nodes :on (= tags:node-id nodes:id)
                 :where (= tags:tag $s1)]
                "starred"))
         (files (delq nil (mapcar (lambda (row) (and (= 0 (nth 1 row)) (nth 2 row))) rows))))
    (delete-dups
     (delq nil (mapcar (lambda (row)
                         (when (or (= 0 (nth 1 row)) (not (member (nth 2 row) files)))
                           (nth 0 row)))
                       rows)))))

;;;###autoload
(defun +notes/roam-starred ()
  "Open one of the starred notes."
  (interactive)
  (require 'org-roam)
  (+notes--roam-db-ready)
  (let ((ids (+notes--roam-starred-ids)))
    (if (null ids)
        (message "No note is starred yet; SPC m m o s stars the one at point")
      (org-roam-node-visit
       (org-roam-node-read nil (lambda (node) (member (org-roam-node-id node) ids))
                           nil t "Starred: ")))))

;;
;;; Tags

(defun +notes--roam-tag-counts ()
  "(TAG . COUNT) for every tag in the graph, most used first, then by
name.  A heading note counts, and so does a tag it inherits: the tags
table holds them so."
  (let ((counts (make-hash-table :test #'equal))
        out)
    (dolist (row (org-roam-db-query [:select :distinct [tag node-id] :from tags]))
      (puthash (car row) (1+ (gethash (car row) counts 0)) counts))
    (maphash (lambda (tag n) (push (cons tag n) out)) counts)
    (sort out (lambda (a b) (or (> (cdr a) (cdr b))
                                (and (= (cdr a) (cdr b)) (string< (car a) (car b))))))))

(defun +notes--read-tag ()
  "Read a tag of the graph, each shown with how many notes carry it."
  (+notes--roam-db-ready)
  (let* ((counts (or (+notes--roam-tag-counts) (user-error "No note has a tag yet")))
         (annotate (lambda (tag)
                     (let ((n (cdr (assoc tag counts))))
                       (format "  %d note%s" n (if (= n 1) "" "s"))))))
    (let ((tag (completing-read
                "Tag: "
                (lambda (string pred action)
                  (if (eq action 'metadata)
                      `(metadata (display-sort-function . identity)
                                 (cycle-sort-function . identity)
                                 (annotation-function . ,annotate))
                    (complete-with-action action counts string pred)))
                nil t)))
      ;; RET on nothing returns nothing, even with a match required.
      (when (string-empty-p tag) (user-error "No tag picked"))
      tag)))

;;;###autoload
(defun +notes/roam-tags (tag)
  "Pick a TAG, each shown with how many notes carry it, then open one of
those notes."
  (interactive (progn (require 'org-roam) (list (+notes--read-tag))))
  (org-roam-node-visit
   (org-roam-node-read nil (lambda (node) (member tag (org-roam-node-tags node)))
                       nil t (format "#%s: " tag))))

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
  ;; Generated maps have their own directory, so a tag that shares a name
  ;; with an authored collection never writes into it.
  (expand-file-name (format "resources/collections/tags/%s.org" tag) org-roam-directory))

(defun +notes--roam-map-links (nodes)
  "The link list for a map of NODES."
  (if (null nodes)
      "Nothing is tagged this way yet.\n"
    (mapconcat (lambda (node)
                 (format "- [[id:%s][%s]]\n"
                         (org-roam-node-id node)
                         (org-roam-node-title node)))
               nodes "")))

(defvar +notes--roam-map-showing)

;;;###autoload
(defun +notes/roam-map-of-content (tag)
  "Write a map of the notes tagged TAG, then open it.
The map is a roam note of its own, so it shows in the graph and can be
linked like any other.  Only the list between the markers is rewritten, so
whatever you write around it stays.  A tag no note carries makes a new
map only when you say so."
  (interactive (progn
                 ;; Before the tags are read: the list comes from org-roam.
                 (require 'org-roam)
                 (list (completing-read "Map the notes tagged: " (+notes--roam-tags)))))
  ;; The tag names the map's file: nothing, or a slash, is no tag.
  (setq tag (string-trim tag))
  (cond ((string-empty-p tag) (user-error "A map needs a tag"))
        ((not (string-match-p "\\`[[:alnum:]_@#%]+\\'" tag))
         (user-error "%S is not a tag: letters, digits and _ @ # %% only" tag)))
  (require 'org-roam)
  (let* ((file (+notes--roam-map-file tag))
         (nodes (+notes--roam-nodes-tagged tag))
         (links (+notes--roam-map-links nodes)))
    ;; A tag no note carries is a typo more often than a subject to come.
    ;; Headings may carry it, but a map lists only whole notes.
    (when (and (null nodes) (not (file-exists-p file))
               (not (y-or-n-p (format "A map of %s would list nothing; make it anyway? " tag))))
      (user-error "No map made"))
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
      ;; A popup, by the rule in +roam.el.
      (let ((+notes--roam-map-showing t))
        (pop-to-buffer (current-buffer))))
    (message "Map of %s: %d note(s). SPC n r m rebuilds it" tag (length nodes))))


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
