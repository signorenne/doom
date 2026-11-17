;;; private/notes/autoload/panel.el -*- lexical-binding: t; -*-
;;
;; The roam panel, the list at the right of the notes that link to the
;; note in front. org-roam rebuilt it as each command ended, quoting the
;; whole section around every link, and searched the vault for the notes
;; that name this one without a link: entering a note with many backlinks
;; held Emacs for a second or more. Here it follows the note once the note
;; has been still for a moment, lists each linking note once, quotes the
;; passage that links for the first few and names the rest, and searches
;; for the unlinked mentions when that section is opened.

(require 'magit-section)
(require 'org-roam)

(defvar +notes-roam-panel-delay 0.3
  "Seconds the note in front stays put before the roam panel follows it.")

(defvar +notes-roam-quoted-backlinks 20
  "How many of a note's backlinks the roam panel quotes; it names the rest.")

(defvar +notes-roam-quote-chars 500
  "A paragraph longer than this is quoted by the sentence with the link.")

(defvar +notes--roam-panel-timer nil
  "The timer that brings the roam panel to the note in front.")

;;;###autoload
(defun +notes--roam-panel-later-a ()
  "Bring the roam panel to the note in front once it has been still.
Replaces org-roam's redisplay after every command."
  (when (get-buffer-window org-roam-buffer 'visible)
    (when (timerp +notes--roam-panel-timer)
      (cancel-timer +notes--roam-panel-timer))
    (setq +notes--roam-panel-timer
          (run-with-idle-timer +notes-roam-panel-delay nil
                               #'+notes--roam-panel-follow (current-buffer)))))

(defun +notes--roam-panel-follow (buffer)
  "Show the note at point in BUFFER in the roam panel, while BUFFER is in front."
  (setq +notes--roam-panel-timer nil)
  (when (and (buffer-live-p buffer)
             (eq buffer (window-buffer (selected-window)))
             (get-buffer-window org-roam-buffer 'visible))
    (with-current-buffer buffer
      (org-roam-buffer-persistent-redisplay))))

(defun +notes--roam-backlinks (node)
  "The notes that link to NODE, each once with its first link.
As `org-roam-backlinks-get' with :unique, in one query: that one reads
every linking note on its own, a second for a note linked 300 times.
The notes carry what the panel shows and opens: ID, title, file, place."
  (mapcar (pcase-lambda (`(,id ,pos ,properties ,title ,file ,point ,level))
            (org-roam-backlink-create
             :source-node (org-roam-node-create :id id :title title :file file
                                                :point point :level level)
             :target-node node :point pos :properties properties))
          (org-roam-db-query
           [:select [links:source (funcall min links:pos) links:properties
                     nodes:title nodes:file nodes:pos nodes:level]
            :from links :join nodes :on (= links:source nodes:id)
            :where (= links:dest $s1) :and (= links:type "id")
            :group :by links:source]
           (org-roam-node-id node))))

;;;###autoload
(defun +notes--roam-backlinks-section (node)
  "List the notes that link to NODE, each once.
The first `+notes-roam-quoted-backlinks' come with the passage that
links; the others by title, which RET opens all the same."
  (when-let* ((backlinks (seq-sort #'org-roam-backlinks-sort
                                   (+notes--roam-backlinks node))))
    (magit-insert-section (org-roam-backlinks)
      (magit-insert-heading "Backlinks:")
      (seq-do-indexed
       (lambda (backlink i)
         (let ((source (org-roam-backlink-source-node backlink)))
           (if (< i +notes-roam-quoted-backlinks)
               (org-roam-node-insert-section
                :source-node source
                :point (org-roam-backlink-point backlink)
                :properties (org-roam-backlink-properties backlink))
             (when (= i +notes-roam-quoted-backlinks)
               (insert (propertize (format "%d more:\n" (- (length backlinks) i))
                                   'font-lock-face 'org-roam-dim)))
             (magit-insert-section section (org-roam-node-section)
               (insert (propertize (org-roam-node-title source)
                                   'font-lock-face 'org-roam-title))
               (magit-insert-heading)
               (oset section node source)))))
       backlinks)
      (insert ?\n))))

;;;###autoload
(defun +notes--roam-unlinked-section (node)
  "The notes that name NODE without linking it, searched once the section
is opened: the search reads the whole vault.  Opened, it stays open for
NODE alone, its value being NODE's ID; another note starts closed."
  (magit-insert-section section (+notes-roam-unlinked (org-roam-node-id node) t)
    (magit-insert-heading "Unlinked references (TAB to search)")
    (magit-insert-section-body
      (org-roam-unlinked-references-section node)
      (let ((found (car (last (oref section children)))))
        (unless (and found (oref found children))
          (insert (propertize "none found\n" 'font-lock-face 'org-roam-dim) ?\n))))))

;;;###autoload
(defun +notes--roam-quote ()
  "The passage around the link at point, for the roam panel.
A paragraph or list item whole, or the sentence with the link when it
is long; a table row's cells on one line; a heading's text."
  (let* ((link (point))
         (element (org-element-at-point)))
    (string-trim
     (pcase (org-element-type element)
       ('table-row
        (mapconcat #'identity
                   (split-string (buffer-substring-no-properties
                                  (line-beginning-position) (line-end-position))
                                 "|" t "[ \t]+")
                   " | "))
       ('headline (org-element-property :raw-value element))
       (_
        (let* ((beg (or (org-element-contents-begin element) (org-element-begin element)))
               (end (or (org-element-contents-end element) (org-element-end element)))
               (text (buffer-substring-no-properties beg end)))
          (if (<= (length text) +notes-roam-quote-chars)
              text
            (save-excursion
              (goto-char link)
              (let ((from (max beg (progn (backward-sentence) (point))))
                    (to (min end (progn (goto-char link) (forward-sentence) (point)))))
                (concat "... " (buffer-substring-no-properties from to) " ..."))))))))))
