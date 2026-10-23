;;; private/notes/autoload/write.el -*- lexical-binding: t; -*-
;;
;; Writing into the notes without a capture: today's daily note, a task
;; for the inbox, a draft beside the graph. Other modules write through
;; these, the ai module for one, so every entry has the shape the
;; templates give it and the formats live in one place.

(defvar +notes-daily-name)
(defvar +notes-daily-head)
(defvar org-roam-directory)
(defvar org-roam-dailies-directory)
(declare-function org-roam-db-update-file "org-roam-db")
(declare-function org-roam-node-create "org-roam-node")
(declare-function org-roam-node-slug "org-roam-node")
(declare-function org-end-of-subtree "org")
(declare-function org-id-new "org-id")

(defun +notes--expand-time (template)
  "TEMPLATE with each %<FORMAT> replaced by the time now, as a capture
template would; nothing else in it is expanded."
  (replace-regexp-in-string "%<\\([^>]+\\)>"
                            (lambda (match)
                              (format-time-string (match-string 1 match)))
                            template t t))

(defun +notes--demote (text)
  "TEXT with every heading pushed below the entry it goes into.
A line starting with stars would otherwise become a sibling of the
entry, or a new top-level section of the file."
  (replace-regexp-in-string "^\\(\\*+\\) " "**\\1 " text))

(defun +notes--append-under (file heading entry)
  "Append ENTRY, a string, at the end of HEADING in FILE, which is made
when it is not there, then save.  The buffer stays open.
Refuses while the file is open with unsaved changes: saving it here
would save whatever was half typed in it, and this is called by the AI
tools, from outside the user\='s hands."
  (when-let* ((open (find-buffer-visiting file))
              ((buffer-modified-p open)))
    (user-error "%s has unsaved changes; save it first"
                (abbreviate-file-name file)))
  (with-current-buffer (find-file-noselect file)
    (save-excursion
      (goto-char (point-min))
      (if (re-search-forward (format "^\\* %s$" (regexp-quote heading)) nil t)
          (progn (org-end-of-subtree t t)
                 (unless (bolp) (insert "\n")))
        (goto-char (point-max))
        (unless (bolp) (insert "\n"))
        (insert (format "* %s\n" heading)))
      (insert entry))
    (save-buffer))
  file)

(defun +notes--stamp ()
  "The time now, as the CREATED property is written."
  (format-time-string "[%Y-%m-%d %a %H:%M]"))


;;
;;; Today's note

(defun +notes--make-node (file)
  "Give FILE an ID of its own and put it in the graph.
org-roam writes the ID when its own capture finishes, so a day first
written into from outside one, by the AI tools or by
`+notes-append-daily\=', had no node: nothing linked to it, nothing
found it, and the count did not see it."
  (when (fboundp 'org-id-get-create)
    (let ((buffer (find-file-noselect file)))
      (with-current-buffer buffer
        (org-with-point-at 1 (org-id-get-create))
        (save-buffer)
        (when (fboundp 'org-roam-db-update-file)
          (ignore-errors (org-roam-db-update-file file))))
      (kill-buffer buffer))))

;;;###autoload
(defun +notes-daily-file ()
  "Today's daily note, created from `+notes-daily-head' when it is not
there yet.  Returns its path."
  ;; The dailies directory is the dailies library's, which org-roam
  ;; loads on demand only.
  (require 'org-roam-dailies)
  (let* ((dir (expand-file-name org-roam-dailies-directory org-roam-directory))
         (file (expand-file-name (+notes--expand-time +notes-daily-name) dir)))
    (make-directory dir t)
    (unless (file-exists-p file)
      (with-temp-file file
        (insert (+notes--expand-time +notes-daily-head)))
      (+notes--make-node file))
    file))

;;;###autoload
(defun +notes-append-daily (text heading &optional title tags)
  "Append TEXT to today's daily note under HEADING, one of the day's
headings or a new one, as an entry named TITLE, or the time when there
is none, tagged TAGS, a list of strings.  Headings inside TEXT are
demoted below the entry.  Returns the file."
  (when (or (null text) (string-empty-p (string-trim text)))
    (error "Nothing to write"))
  (let ((file (+notes-daily-file)))
    (+notes--append-under
     file heading
     (format "** %s%s\n:PROPERTIES:\n:CREATED: %s\n:END:\n%s\n"
             (if (and title (not (string-empty-p (string-trim title))))
                 (string-trim title)
               (format-time-string "%H:%M"))
             (if tags (format "  :%s:" (string-join tags ":")) "")
             (+notes--stamp)
             (+notes--demote (string-trim text))))
    (ignore-errors (org-roam-db-update-file file))
    file))


;;
;;; The inbox

;;;###autoload
(defun +notes-add-inbox-todo (title &optional body source)
  "Add a TODO called TITLE to the inbox, with BODY under it and SOURCE,
who wrote it, as a property.  The shape of the inbox capture, so
refiling treats it the same.  Returns the file."
  (require 'org)
  (+notes-ensure-documents)
  (+notes--append-under
   (+notes--inbox-file) "Inbox"
   (format "** TODO %s\n:PROPERTIES:\n:CREATED: %s\n%s:END:\n%s"
           title
           (+notes--stamp)
           (if source (format ":SOURCE: %s\n" source) "")
           (if (and body (not (string-empty-p body)))
               (concat body "\n")
             ""))))


;;
;;; Drafts

;;;###autoload
(defun +notes-new-draft (title text &optional tags source)
  "Write a draft note called TITLE holding TEXT into capture/drafts, tagged
TAGS, a list of strings, and draft, with SOURCE as a property.  A draft
is a note in waiting: it is read and promoted by hand.  Refuses to
overwrite one.  Returns the file."
  (require 'org-roam)
  (when (or (null title) (string-empty-p (string-trim title)))
    (error "A draft needs a title"))
  (let* ((slug (org-roam-node-slug (org-roam-node-create :title title)))
         (dir (expand-file-name "capture/drafts" org-roam-directory))
         (file (expand-file-name (format "%s.org" slug) dir))
         (tags (seq-uniq (cons "draft" (or tags nil)))))
    (when (file-exists-p file)
      (error "A draft called %s is already there" title))
    (make-directory dir t)
    (with-temp-file file
      (insert (format ":PROPERTIES:\n:ID:       %s\n:CREATED:  %s\n%s:END:\n"
                      (org-id-new)
                      (+notes--stamp)
                      (if source (format ":SOURCE:   %s\n" source) ""))
              (format "#+title: %s\n#+filetags: :%s:\n\n" title
                      (string-join tags ":"))
              (string-trim (or text "")) "\n"))
    (ignore-errors (org-roam-db-update-file file))
    file))
