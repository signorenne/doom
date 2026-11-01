;;; private/notes/config.el -*- lexical-binding: t; -*-
;;
;; One vault of notes and one Org-roam graph: Zettelkasten knowledge and
;; PARA work, the documents among them. Books and papers are a library
;; of their own, which citar reads (+study.el).

;;
;;; Documents

;; Read by Doom when org and org-roam load. Both are the vault, core's
;; `+core-notes-dir'.
(defvar +notes-knowledge-dir +core-notes-dir
  "Root of the org-roam graph: the vault, `+core-notes-dir'.
The documents, the inbox and the agenda take the two for one folder.")
(setq org-directory (directory-file-name +core-notes-dir)
      org-roam-directory (directory-file-name +notes-knowledge-dir)
      org-roam-db-location (expand-file-name "org-roam-knowledge.db" doom-cache-dir))
;; Shared capture and project helpers are needed before the agenda loads.
(load! "autoload/capture")

(defvar +notes-documents
  '(("inbox"    . "inbox.org")              ; everything captured lands here first
    ("projects" . "projects/index.org")     ; links to each project's own file
    ("someday"  . "someday.org")            ; parked tasks, kept out of the agenda
    ("reading"  . "resources/reading.org")  ; books and articles to read
    ("snippets" . "resources/snippets.org") ; code snippets
    ("habits"   . "areas/habits.org"))      ; org-habit entries
  "Documents `+notes/bootstrap' creates: (NAME . FILE) under `org-directory',
each from templates/org/NAME.org and each a node of the graph.")

(defvar +notes-knowledge-directories
  '("projects" "areas" "archives/projects" "archives/areas"
    "capture/journal" "capture/meetings" "capture/drafts"
    "resources/wiki" "resources/wiki/people"
    "resources/sources/papers" "resources/sources/manuals"
    "resources/sources/websites" "resources/collections/tags" "assets")
  "Folders of the vault, the PARA layout the captures write into, made
when org loads.  assets/ holds the diagrams and pictures of no one note.")

(defvar +notes-templates-dir (file-name-concat doom-user-dir "templates/org/")
  "Where the starter documents are copied from.")

(defvar +notes-docs
  '(:groups (("notes" "Notes" (org org-agenda) org-mode-map org-agenda-mode-map))
    :sections ((org-mode . "Org")
               (org-agenda-mode . "Org")
               (org-roam-mode . "Notes and roam")))
  "How the cheat sheet documents this module; see `+docs--module-docs'.")

;; Doom's own captures and `org-default-notes-file' write to these: the
;; vault's inbox and project index.
(setq +org-capture-todo-file (+notes--inbox-file)
      +org-capture-notes-file "inbox.org"
      +org-capture-projects-file "projects/index.org")


;;
;;; Workflow

(defvar +notes-agenda-base-files nil
  "The agenda files as configured.  Before an agenda or a refile the roam
notes that hold a task are added on top; see `+notes--agenda-files-refresh-h'.")

(defvar +notes-board-states '("TODO" "NEXT" "STRT" "WAIT" "DONE")
  "A board's columns when it names none, in order.")

(defvar +notes-board-done-days 14
  "How many days a task closed in a done state stays on a board.")

(defvar +notes-block-names '("notes-query" "notes-list" "notes-board")
  "The dynamic blocks a note writes again as it is shown and saved;
autoload/query.el writes them.")

(after! org
  ;; A missing vault would break the agenda, so create its tree early.
  (+notes--ensure-directories)
  ;; Not the whole of capture/journal: that is one agenda file per day ever
  ;; written, opened on every agenda build. The dailies that hold a task
  ;; are found by the scan whatever their date, and the recent ones are
  ;; added for the plain timestamps a day's note carries. Of the
  ;; documents, the inbox and the habits; someday is not for now.
  (setq +notes-agenda-base-files
        (list (+notes--inbox-file) (+notes--document-path "habits"))
        org-agenda-files +notes-agenda-base-files
        ;; Doom's keywords plus NEXT, the next action of a project.
        org-todo-keywords
        '((sequence "TODO(t)" "NEXT(n)" "PROJ(p)" "LOOP(r)" "STRT(s)"
                    "WAIT(w@/!)" "HOLD(h@/!)" "IDEA(i)"
                    "|" "DONE(d!)" "KILL(k@)")
          (sequence "[ ](T)" "[-](S)" "[?](W)" "|" "[X](D)"))
        org-todo-keyword-faces
        '(("NEXT" . +org-todo-active)
          ("STRT" . +org-todo-active)
          ("[-]"  . +org-todo-active)
          ("WAIT" . +org-todo-onhold)
          ("HOLD" . +org-todo-onhold)
          ("[?]"  . +org-todo-onhold)
          ("PROJ" . +org-todo-project)
          ("KILL" . +org-todo-cancel))
        org-log-done 'time
        org-log-into-drawer t
        org-log-reschedule 'time
        org-log-redeadline 'time
        org-enforce-todo-dependencies t
        org-priority-default ?B
        org-tag-alist '((:startgroup)
                        ("@home" . ?h) ("@lab" . ?l)
                        ("@pc" . ?p) ("@errand" . ?e)
                        (:endgroup)
                        ("emacs" . ?E) ("cpp" . ?c) ("embedded" . ?m)
                        ("qt" . ?q) ("ai" . ?a) ("reading" . ?r)
                        ("idea" . ?i) ("noroam" . ?n))
        ;; Refile into the documents and the notes with tasks, not into
        ;; a daily note, of which there is one more every day.
        org-refile-targets '((nil :maxlevel . 3)
                             (+notes--refile-files :maxlevel . 2))
        org-refile-use-outline-path 'file
        org-outline-path-complete-in-steps nil
        org-refile-allow-creating-parent-nodes 'confirm
        org-image-actual-width '(500)
        ;; A file dropped on a note is copied into its attachment folder,
        ;; with no question: Org's own drop handler comes before Doom's
        ;; in an org buffer, and macOS drops with the action private,
        ;; which takes the default method.
        org-yank-dnd-method 'attach
        org-yank-dnd-default-attach-method 'cp
        org-ellipsis " [...]")
  (add-to-list 'org-modules 'org-habit)

  ;; The browser hands pages over through emacsclient; SPC n d P registers
  ;; the handler with the desktop. Doom loads org-protocol the first time
  ;; an org-protocol:// link arrives, and org-roam-protocol with it.

  ;; Any capture first makes sure the documents exist (created from templates).
  (advice-add #'org-capture :before #'+notes-ensure-documents)

  ;; The live tables (autoload/query.el): C-c C-x x offers them, and a
  ;; note's are written again when it is shown and when it is saved. A
  ;; note a capture wrote into is set up again, since a new index had no
  ;; blocks when its mode started.
  (org-dynamic-block-define "notes-query" #'+notes/insert-query)
  (org-dynamic-block-define "notes-list" #'+notes/insert-list)
  (org-dynamic-block-define "notes-board" #'+notes/insert-board)
  (add-hook 'org-mode-hook #'+notes--blocks-setup)
  (add-hook 'doom-switch-buffer-hook #'+notes--blocks-shown-h)
  ;; A note put in a window that is not selected is shown once selected.
  (add-hook 'doom-switch-window-hook #'+notes--blocks-shown-h)
  (add-hook 'org-capture-after-finalize-hook #'+notes--blocks-capture-h))

;; A note opens with its pictures shown, when it links one. Not through
;; `org-startup-with-link-previews', which reads the context of every link
;; in the file to find the pictures among them, so a long note full of
;; links and with no picture paid for it each time it opened. Org's own
;; link regexp finds the links first, and only a link that names a
;; picture lets Org look; a #+startup keyword still decides, and a buffer
;; Org starts without its startup work, an export's or a source block's,
;; gets none.
(defvar org-link-any-re)
(defvar org-inhibit-startup)
(defvar org-startup-with-link-previews)
(declare-function org-link-preview-region "ol")
(declare-function org-in-regexp "org-macs")

(defun +notes--picture-link-p ()
  "Non-nil when a link in this buffer names a picture.
The names first, which few notes hold, then whether one sits in a link:
going through every link of a long note is the slow part."
  (save-excursion
    (goto-char (point-min))
    (let ((case-fold-search t)
          (picture (concat "\\.\\(?:" (regexp-opt image-file-name-extensions) "\\)\\b"
                           "\\|data:image/"))
          found)
      (while (and (not found) (re-search-forward picture nil t))
        (setq found (save-excursion
                      (goto-char (match-beginning 0))
                      (org-in-regexp org-link-any-re 1))))
      found)))

(add-hook! 'org-mode-hook
  (defun +notes--show-pictures-h ()
    "Show the note's pictures as it opens, when it has any."
    (unless (or org-inhibit-startup
                org-startup-with-link-previews
                (local-variable-p 'org-startup-with-link-previews))
      (when (+notes--picture-link-p)
        ;; As Org's startup does: the previews of a buffer that runs
        ;; org-mode again are made anew, not added to.
        (org-link-preview-region nil t)))))

;; A picture pasted under a heading with no ID goes into the note's
;; folder, as a dropped one does: org-download-clipboard gives the heading
;; an ID first, which would make it a note of its own. A heading with an
;; ID keeps its own folder.
(declare-function org-entry-get "org")

(defadvice! +notes--paste-into-note-a (fn &rest args)
  "Paste the picture into the note's attachment folder, not a new one."
  :around #'org-download-clipboard
  (if (and (derived-mode-p 'org-mode)
           (not (org-entry-get nil "ID"))
           (org-entry-get nil "ID" t))
      (cl-letf (((symbol-function 'org-id-get-create) #'ignore))
        (apply fn args))
    (apply fn args)))

(defvar +notes-commit-idle 600
  "Seconds of idle time after which the notes are committed, nil to never.")

(defvar +notes--timer nil
  "The idle timer that commits the notes, so a reload replaces it.")

(defun +notes--watch ()
  "Commit the notes while Emacs sits idle and again on the way out.
Called at startup and by `+notes/init-repo'; safe to call twice.
Checking for .git here rather than calling into the module keeps
startup from loading it; .git is a file in a worktree."
  (when (timerp +notes--timer)
    (cancel-timer +notes--timer)
    (setq +notes--timer nil))
  (when (and +notes-commit-idle
             (file-exists-p (expand-file-name ".git" org-directory)))
    (setq +notes--timer
          (run-with-idle-timer +notes-commit-idle t #'+notes--autocommit-in-background))
    (add-hook 'kill-emacs-hook #'+notes--autocommit)))

(+notes--watch)

;; The pomodoro timer: its chime through PulseAudio where there is one,
;; and its alerts sent the way every notification of this config goes,
;; D-Bus on Linux and Notification Center on a Mac.
(after! org-pomodoro
  (setq org-pomodoro-audio-player (or (executable-find "paplay")
                                      org-pomodoro-audio-player))
  (alert-define-style '+notes-desktop
                      :title "The desktop's notifications"
                      :notifier (lambda (info)
                                  (+core-os-notify (plist-get info :title)
                                                   (plist-get info :message))))
  (unless (seq-find (lambda (rule) (eq (nth 1 rule) '+notes-desktop))
                    alert-internal-configuration)
    (alert-add-rule :category "org-pomodoro" :style '+notes-desktop)))


;;
;;; File templates

;; New .org files outside the roam tree get a header (snippets/org-mode/__org);
;; roam files get theirs from the capture templates.
(set-file-template! "\\.org\\'" :trigger "__org" :mode 'org-mode)


;;
;;; The rest, by topic

(load! "+capture")                      ; the capture templates
(load! "+agenda")                       ; the dashboard and the reviews
(load! "+roam")                         ; the note graph
(load! "+study")                        ; citations, cards, transclusion
(load! "+export")                       ; looks, maps, export, babel


;;
;;; Spelling and style

;; The notes are spelt British, colour and centre, and American is taken
;; as well, since code and quotes bring it in. The words of this config
;; and its tools, config, keymap, clangd, magit, are in dictionary.pws
;; beside this file, which zg adds to. Italian is not spell checked, its
;; word forms being too many to hold in memory; LanguageTool reads it.
(setq ispell-dictionary "en_GB"
      ispell-personal-dictionary (expand-file-name "dictionary.pws" (dir!)))

(declare-function spell-fu-dictionary-add "spell-fu")
(declare-function spell-fu-get-ispell-dictionary "spell-fu")

(add-hook! 'spell-fu-mode-hook
  (defun +notes--spell-american-too-h ()
    "Take American spelling as well as British."
    (spell-fu-dictionary-add (spell-fu-get-ispell-dictionary "en_US"))))

;; org-modern draws the tags, the keywords, the dates and the labels in
;; faces of its own, which Doom's list of faces not to check does not
;; know, so a note's tags, :config: and :cpp:, would be read as prose.
(after! spell-fu
  (dolist (face '(org-modern-tag org-modern-label org-modern-todo org-modern-done
                  org-modern-priority org-modern-date-active org-modern-time-active
                  org-modern-date-inactive org-modern-time-inactive
                  org-modern-block-name org-modern-internal-target
                  org-modern-radio-target))
    (cl-pushnew face (alist-get 'org-mode +spell-excluded-faces-alist))))

;; A possessive is spelt right when its word is: config's when config is
;; known, and SDK's when SDK alone, in capitals, is left alone.
(defadvice! +notes--spell-possessive-a (fn pos-beg pos-end word)
  "Check a possessive, config's, as the word it is made of."
  :around #'spell-fu-check-word
  (if (string-match "\\`\\(.+\\)['\u2019]s\\'" word)
      (funcall fn pos-beg (+ pos-beg (match-end 1)) (match-string 1 word))
    (funcall fn pos-beg pos-end word)))

;; The three word lists are loaded while Emacs sits idle after starting,
;; in a buffer no one sees, so the first note does not wait for them.
(defun +notes--warm-up-h (_mode)
  "Load the spelling word lists ahead of the first note."
  (with-temp-buffer
    (spell-fu-mode 1)
    (spell-fu-mode -1)))

(add-hook '+core-warm-up-functions #'+notes--warm-up-h 50)

;; writegood marks the passive voice, vague words and a word said twice
;; as you type, and in these notes what it marks is not an error: "is
;; generated", or "m M" from SPC m M. It also makes every font-lock rule
;; of its buffer ignore case, org's too, so a heading called Done is
;; taken for the DONE keyword and its fontification fails. Off where
;; Doom turns it on; LanguageTool, SPC n w c, reads the style.
(dolist (hook '(org-mode-hook markdown-mode-hook rst-mode-hook
                asciidoc-mode-hook latex-mode-hook LaTeX-mode-hook))
  (remove-hook hook #'writegood-mode))


;;
;;; Code in notes and documents

;; A code block in markdown or org is coloured by running the mode its
;; language names in a hidden buffer, the whole block at each key typed in
;; it. markdown takes a tree-sitter mode only when that mode appears in
;; `auto-mode-alist', and org never looks for one, while Emacs's own
;; remapping, which opens a .c file in c-ts-mode, is in neither, so a C
;; block would go to the slower cc-mode. A block gets the mode a file of
;; its language opens in.
(defvar +notes--block-modes (make-hash-table :test #'eq)
  "Each mode a block has named, to the mode a file of its language opens
in: asking Emacs is 150 microseconds, and it was asked for every block
of the screen at every key.")

(defun +notes--block-mode-remap-a (mode)
  "MODE as a file of its language would open in, tree-sitter's if so."
  (if (and mode (fboundp 'major-mode-remap))
      (or (gethash mode +notes--block-modes)
          (puthash mode (major-mode-remap mode) +notes--block-modes))
    mode))

(advice-add 'markdown-get-lang-mode :filter-return #'+notes--block-mode-remap-a)
(advice-add 'org-src-get-lang-mode :filter-return #'+notes--block-mode-remap-a)

;; markdown-mode tries every * and _ of a line as the start of an italic
;; or a bold, and asks for each whether it sits in inline code by matching
;; the code of its text block again from the start, which is slow on a
;; long line full of names like espressif__mdns. The code of a block is
;; matched once for each state of the buffer.
(defvar-local +notes--md-code nil
  "(TICK START END . SPANS): the inline code of the text block START to
END, each span the match data `markdown-match-code' leaves.")

(declare-function markdown-match-code "markdown-mode")
(declare-function markdown-beginning-of-text-block "markdown-mode")
(declare-function markdown-end-of-text-block "markdown-mode")

(defun +notes--md-code-spans (start end)
  "The inline code spans of the text block START to END."
  (let ((tick (buffer-chars-modified-tick)))
    (if (and (eql (nth 0 +notes--md-code) tick)
             (eql (nth 1 +notes--md-code) start)
             (eql (nth 2 +notes--md-code) end))
        (nthcdr 3 +notes--md-code)
      (let (spans)
        (save-excursion
          (save-match-data
            (goto-char start)
            (while (markdown-match-code end)
              (push (match-data t) spans))))
        (setq spans (nreverse spans)
              +notes--md-code (cons tick (cons start (cons end spans))))
        spans))))

(defun +notes--md-inline-code-at-pos-a (_fn pos &optional from)
  "Whether POS is in inline code, as `markdown-inline-code-at-pos' says,
from the spans of its block found once; the match data set the same."
  (save-excursion
    (let* ((known (and (eql (nth 0 +notes--md-code) (buffer-chars-modified-tick))
                       (<= (nth 1 +notes--md-code) pos)
                       (< pos (nth 2 +notes--md-code))))
           ;; The block's bounds, found again only for a position outside
           ;; the one known, since finding them is the costly part.
           (end (if known (nth 2 +notes--md-code)
                  (goto-char pos) (markdown-end-of-text-block) (point)))
           (start (if known (nth 1 +notes--md-code)
                    (goto-char pos) (markdown-beginning-of-text-block) (point)))
           ;; The first span from FROM that does not end before POS, as
           ;; the loop it replaces stops at.
           (span (seq-find (lambda (data)
                             (and (or (null from) (>= (car data) (1- from)))
                                  (>= (nth 1 data) pos)))
                           (+notes--md-code-spans start end))))
      (when span
        (set-match-data span)
        (let ((group (if (eq (char-after (match-beginning 0)) ?`) 0 1)))
          (and (<= (match-beginning group) pos)
               (> (match-end 0) pos)))))))

(advice-add 'markdown-inline-code-at-pos :around #'+notes--md-inline-code-at-pos-a)


;;
;;; Grammar

;; LanguageTool reads a buffer and says what is clumsy in it, not only
;; what is misspelt. The language is detected per buffer rather than
;; fixed, since the notes are written in two; the mother tongue is
;; told to it as well, which is how it catches the words that look like
;; the English ones and are not.
;;
;; The classpath is set because Doom's points at
;; /usr/share/java/languagetool, which on openSUSE holds the top jars
;; and not the libs/ beside them, so a check would die on a missing
;; class. The directory is looked for rather than named, and its libs
;; go on the classpath with it.
(after! langtool
  (setq langtool-default-language 'auto
        langtool-mother-tongue "it")
  (when-let* ((dir (seq-find
                    (lambda (d)
                      (file-exists-p
                       (file-name-concat d "languagetool-commandline.jar")))
                    '("/usr/share/languagetool"
                      "/usr/share/java/languagetool"
                      "/usr/local/share/languagetool"))))
    (setq langtool-java-classpath
          (concat (file-name-concat dir "*") ":"
                  (file-name-concat dir "libs" "*")))))


;;
;;; Keybindings

(map! :leader
      (:prefix "n"
       :desc "Notes menu"             "SPC" #'+notes/menu
       :desc "Notes layout"           "h" #'+notes/layout
       :desc "Commit the notes"       "g" #'+notes/commit
       :desc "Sync with the remote"   "G" #'+notes/sync
       :desc "Review the cards due"   "p" #'org-fc-review-all
       :desc "The bibliography"       "B" #'citar-open
       ;; SPC n b is Doom's citar-open-notes already.
       :desc "Card dashboard"         "P" #'org-fc-dashboard
       :desc "org-ql find"            "q" #'+notes/query
       :desc "org-ql search"          "Q" #'org-ql-search
       (:prefix ("w" . "writing")
        :desc "Check the grammar"     "c" #'langtool-check
        :desc "Correct what it found" "f" #'langtool-correct-buffer
        :desc "What is wrong here"    "w" #'langtool-show-message-at-point
        :desc "Done checking"         "d" #'langtool-check-done)
       (:prefix ("d" . "documents")
        :desc "Set up the vault"      "b" #'+notes/bootstrap
        :desc "Choose document"       "d" #'+notes/open-document
        :desc "Inbox"                 "i" (cmd! (+notes/open-document "inbox"))
        :desc "Projects"              "p" (cmd! (+notes/open-document "projects"))
        :desc "Someday"               "s" (cmd! (+notes/open-document "someday"))
        :desc "Reading"               "r" (cmd! (+notes/open-document "reading"))
        :desc "Snippets"              "n" (cmd! (+notes/open-document "snippets"))
        :desc "Habits"                "h" (cmd! (+notes/open-document "habits"))
        :desc "Writing mode"          "w" #'+notes/writing-mode
        :desc "Browser capture setup" "P" #'+notes/install-protocol-handler)
       (:prefix "r"
        :desc "Search notes (consult)" "/" #'consult-org-roam-search
        :desc "Backlinks"              "B" #'consult-org-roam-backlinks
        :desc "Forward links"          "L" #'consult-org-roam-forward-links
        :desc "Map of a tag"           "m" #'+notes/roam-map-of-content
        :desc "Rename this note"       "N" #'+notes/roam-rename
        :desc "Starred notes"          "S" #'+notes/roam-starred
        :desc "Notes by tag"           "t" #'+notes/roam-tags
        :desc "Review the graph"       "v" #'+notes/roam-review
        :desc "Tasks hidden in notes"  "h" #'+notes/roam-todo-files
        :desc "How to work with roam"  "?" #'+notes/roam-guide
        :desc "Graph UI (browser)"     "u" #'org-roam-ui-open
        :desc "Graph UI mode"          "U" #'org-roam-ui-mode))
      ;; Doom's usual key for the timer, which packages.el installs.
      (:prefix "t"
       :desc "Pomodoro timer"          "t" #'org-pomodoro)
      (:prefix "o"
       (:prefix "a"
        :desc "Dashboard"             "x" #'+notes/dashboard
        :desc "Weekly review"         "w" #'+notes/weekly-review
        :desc "Next actions"          "n" #'+notes/next-actions
        :desc "Projects"              "p" #'+notes/projects
        :desc "Inbox"                 "i" #'+notes/inbox)))

;; Org lines up the table you are in when you leave a cell, and leaves
;; the rest of the file as it found it. This lines up all of them.
(map! :after org
      :map org-mode-map
      :localleader
      (:prefix "b"
       :desc "Align every table in the file" "A" #'+notes/align-tables))

;; The live tables, which act on the note at point.
(map! :after org
      :map org-mode-map
      :localleader
      (:prefix ("Q" . "live tables")
       :desc "Insert a query table"   "q" #'+notes/insert-query
       :desc "Insert a list of notes" "l" #'+notes/insert-list
       :desc "Insert a board"         "b" #'+notes/insert-board
       :desc "Refresh this note's tables" "u" #'+notes/blocks-refresh))

;; Making a card out of a heading you already wrote, on the localleader
;; because it acts on the heading at point.
(map! :after org
      :map org-mode-map
      :localleader
      (:prefix ("F" . "flashcards")
       :desc "Ask it forwards"        "n" #'org-fc-type-normal-init
       :desc "Ask it both ways"       "d" #'org-fc-type-double-init
       :desc "Type the answer"        "i" #'org-fc-type-text-input-init
       :desc "Blank out a part"       "c" #'org-fc-type-cloze-init
       :desc "Review this file"       "r" #'org-fc-review-buffer
       :desc "Dashboard"              "D" #'org-fc-dashboard
       :desc "Suspend this card"      "s" #'org-fc-suspend-card
       :desc "Bring it back"          "S" #'org-fc-unsuspend-card))

;; Transclusion, on the localleader because it only means anything in a
;; buffer: turn the link at point into an include, then show or hide them.
(map! :after org
      :map org-mode-map
      :localleader
      (:prefix ("N" . "transclude")
       :desc "Link at point becomes an include" "n" #'org-transclusion-make-from-link
       :desc "Show this one"                    "a" #'org-transclusion-add
       :desc "Show all of them"                 "A" #'org-transclusion-add-all
       :desc "Hide this one"                    "r" #'org-transclusion-remove
       :desc "Hide all of them"                 "R" #'org-transclusion-remove-all
       :desc "Refresh"                          "g" #'org-transclusion-refresh
       :desc "Open the source"                  "o" #'org-transclusion-open-source
       :desc "Turn the mode on or off"          "t" #'org-transclusion-mode))

;; Doom's roam keys live on SPC m m; the one it leaves out is the move that
;; grows a graph: promote this heading to a note and leave a link behind.
(map! :after org-roam
      :map org-mode-map
      :localleader
      (:prefix "m"
       :desc "Extract subtree to a note" "e" #'+notes/roam-extract
       (:prefix "o"
        :desc "Star or unstar this note" "s" #'+notes/roam-star)))

(map! :after org
      :map org-mode-map
      :localleader
      (:prefix ("M" . "mind map")
       :desc "Whole file"    "M" #'org-mind-map-write
       :desc "Current tree"  "t" #'org-mind-map-write-current-tree
       :desc "Current branch" "b" #'org-mind-map-write-current-branch)
      :desc "Writing mode"   "W" #'+notes/writing-mode)
