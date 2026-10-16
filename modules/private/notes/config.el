;;; private/notes/config.el -*- lexical-binding: t; -*-
;;
;; Zettelkasten knowledge and PARA work in one Org-roam graph.
;; Legacy Org documents and the reference library keep their own root.

;;
;;; Documents

;; Read by Doom when org and org-roam load. org-directory, the legacy
;; documents and library, comes from core; the graph is the knowledge
;; and work repository.
(defvar +notes-knowledge-dir +core-notes-dir
  "Root of the personal knowledge and work repository; init.el sets it.
Unset, it is `+core-notes-dir', so the documents and the graph share a root.")
(setq org-directory (directory-file-name +core-notes-dir)
      org-roam-directory (directory-file-name +notes-knowledge-dir)
      org-roam-db-location (expand-file-name "org-roam-knowledge.db" doom-cache-dir))
;; Shared capture and project helpers are needed before the agenda loads.
(load! "autoload/capture")

(defvar +notes-documents
  '(("inbox"    . "notes/gtd/inbox.org")     ; everything captured lands here first
    ("todo"     . "notes/gtd/todo.org")      ; processed next actions and waiting items
    ("projects" . "notes/gtd/projects.org")  ; PROJ trees with next actions and logs
    ("notes"    . "notes/gtd/notes.org")     ; code snippets
    ("ideas"    . "notes/gtd/ideas.org")     ; IDEA entries
    ("reading"  . "notes/gtd/reading.org")   ; links, articles, books
    ("someday"  . "notes/gtd/someday.org")   ; parked tasks
    ("habits"   . "notes/gtd/habits.org")    ; org-habit entries
    ("ai"       . "notes/gtd/ai.org")        ; AI agent session log
    ("mindmap"  . "notes/maps/mindmap.org")) ; example mind map (org-mind-map)
  "Documents `+notes/bootstrap' creates: (NAME . FILE) under `org-directory'.
Inbox and projects are repointed below into the knowledge repository.")

(defvar +notes-legacy-documents (copy-tree +notes-documents)
  "Original document destinations, retained for the labelled legacy view.")
(defvar +notes-legacy-agenda-files nil
  "Existing task files under the legacy Org root.")
(setq +notes-documents (copy-tree +notes-legacy-documents))
(setcdr (assoc "inbox" +notes-documents) (+notes--inbox-file))
(setcdr (assoc "projects" +notes-documents)
        (expand-file-name "projects/index.org" org-roam-directory))

(defvar +notes-directories '("notes/gtd" "notes/roam" "notes/roam/daily"
                           "notes/roam/concepts" "notes/roam/solutions"
                           "notes/roam/howtos" "notes/roam/hardware" "notes/roam/refs"
                           "notes/roam/questions" "notes/roam/projects" "notes/roam/people"
                           "notes/roam/meetings" "notes/roam/maps" "notes/roam/drafts"
                           "notes/maps" "notes/study/certifications"
                           "library/books/digital" "library/books/scanned/image_only"
                           "library/books/scanned/partial" "library/books/review"
                           "library/books/inbox" "library/datasheets"
                           "research/academic/papers" "research/resources" ".attach")
  "Subdirectories of `org-directory' created by `+notes/bootstrap'.")

(defvar +notes-knowledge-directories
  '("projects" "areas" "archives/projects" "archives/areas"
    "capture/journal" "capture/drafts" "resources/wiki" "resources/wiki/people"
    "resources/sources/papers" "resources/sources/manuals"
    "resources/sources/websites" "resources/collections/tags" "assets")
  "Subdirectories of `org-roam-directory', the PARA layout the captures
write into, created with the others.")

(defvar +notes-templates-dir (file-name-concat doom-user-dir "templates/org/")
  "Where the starter documents are copied from.")

(defvar +notes-docs
  '(:groups (("notes" "Notes" (org org-agenda) org-mode-map org-agenda-mode-map))
    :sections ((org-mode . "Org")
               (org-agenda-mode . "Org")
               (org-roam-mode . "Notes and roam")))
  "How the cheat sheet documents this module; see `+docs--module-docs'.")

;; Doom's project captures write to these.
(setq +org-capture-todo-file (+notes--inbox-file)
      +org-capture-notes-file "notes/gtd/notes.org"
      +org-capture-projects-file "notes/gtd/projects.org")


;;
;;; Workflow

(defvar +notes-agenda-base-files nil
  "The agenda files as configured.  Before an agenda or a refile the roam
notes that hold a task are added on top; see `+notes--agenda-files-refresh-h'.")

(after! org
  ;; A missing legacy org-directory would break the agenda, so create the
  ;; tree early.
  (+notes--ensure-directories)
  ;; Not the whole of capture/journal: that is one agenda file per day ever
  ;; written, opened on every agenda build. The dailies that hold a task
  ;; are found by the scan whatever their date, and the recent ones are
  ;; added for the plain timestamps a day's note carries.
  (setq +notes-legacy-agenda-files
        (mapcar (lambda (doc) (expand-file-name (cdr doc) org-directory))
                (seq-remove (lambda (doc) (equal (car doc) "mindmap"))
                            +notes-legacy-documents))
        +notes-agenda-base-files (list (+notes--inbox-file))
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
        org-ellipsis " [...]")
  (add-to-list 'org-modules 'org-habit)

  ;; The browser hands pages over through emacsclient; SPC n d P registers
  ;; the handler with the desktop. Doom loads org-protocol the first time
  ;; an org-protocol:// link arrives, and org-roam-protocol with it.

  ;; Any capture first makes sure the documents exist (created from templates).
  (advice-add #'org-capture :before #'+notes-ensure-documents))

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
          (run-with-idle-timer +notes-commit-idle t #'+notes--autocommit))
    (add-hook 'kill-emacs-hook #'+notes--autocommit)))

(+notes--watch)

;; The pomodoro timer, set up as Doom's org module did with +pomodoro:
;; its chime through PulseAudio where there is one, and its alerts as the
;; desktop's notifications, here the way every notification of this
;; config goes, D-Bus on Linux and Notification Center on a Mac.
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
;; beside this file, which zg adds to: gathered from the notes, the
;; READMEs and the cheat sheet, where 300 of them were marked as errors.
;; Italian is not checked here, twenty million word forms to hold in
;; memory; LanguageTool reads it, below.
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
;; know: a note's tags, :config: and :cpp:, were read as prose.
(after! spell-fu
  (dolist (face '(org-modern-tag org-modern-label org-modern-todo org-modern-done
                  org-modern-priority org-modern-date-active org-modern-time-active
                  org-modern-date-inactive org-modern-time-inactive
                  org-modern-block-name org-modern-internal-target
                  org-modern-radio-target))
    (cl-pushnew face (alist-get 'org-mode +spell-excluded-faces-alist))))

;; A possessive is spelt right when its word is: config's was marked with
;; config known, and SDK's when SDK alone, in capitals, is left alone.
(defadvice! +notes--spell-possessive-a (fn pos-beg pos-end word)
  "Check a possessive, config's, as the word it is made of."
  :around #'spell-fu-check-word
  (if (string-match "\\`\\(.+\\)['\u2019]s\\'" word)
      (funcall fn pos-beg (+ pos-beg (match-end 1)) (match-string 1 word))
    (funcall fn pos-beg pos-end word)))

;; The first note of a session loaded the three word lists, some 60 ms;
;; they are loaded while Emacs waits after starting instead
;; (`+core-warm-up-functions'), in a buffer no one sees.
(defun +notes--warm-up-h (_mode)
  "Load the spelling word lists ahead of the first note."
  (with-temp-buffer
    (spell-fu-mode 1)
    (spell-fu-mode -1)))

(add-hook '+core-warm-up-functions #'+notes--warm-up-h 50)

;; writegood marks the passive voice, a list of vague words and a word
;; said twice, as you type: 116 marks in these notes and not one of them
;; an error, "is generated" and "is checked" among them, and "m M" from
;; SPC m M as a word said twice. It also makes every font-lock rule of
;; its buffer ignore case, org's too: a heading called Done was taken
;; for the DONE keyword with no title, and its fontification failed.
;; Off where Doom turns it on; LanguageTool, SPC n w c, reads the style.
(dolist (hook '(org-mode-hook markdown-mode-hook rst-mode-hook
                asciidoc-mode-hook latex-mode-hook LaTeX-mode-hook))
  (remove-hook hook #'writegood-mode))


;;
;;; Code in notes and documents

;; A code block in markdown or org is coloured by running the mode its
;; language names in a hidden buffer, the whole block at each key typed in
;; it. markdown takes a tree-sitter mode only when that mode appears in
;; `auto-mode-alist', and org never looks for one, while Emacs's own
;; remapping, which opens a .c file in c-ts-mode, is in neither: a C block
;; went to cc-mode, 25 ms for 230 lines at every key. A block gets the mode
;; a file of its language opens in.
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
;; the code of its text block again from the start: a paragraph that is
;; one long line full of names like espressif__mdns took a quarter of a
;; second at every line moved, a first screen of it thirteen. The code of
;; a block is matched once for each state of the buffer.
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
           ;; the one known: finding them was most of what was left.
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
;; fixed, since the notes here are written in two; the mother tongue is
;; told to it as well, which is how it catches the words that look like
;; the English ones and are not.
;;
;; The classpath is set here because Doom's points at
;; /usr/share/java/languagetool, which on openSUSE holds the three top
;; jars and not the libs/ beside them, so a check dies on a missing
;; class. The directory is looked for rather than named, and its libs
;; goes on the classpath with it.
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
        :desc "Create missing documents" "b" #'+notes/bootstrap
        :desc "Choose document"       "d" #'+notes/open-document
        :desc "Inbox"                 "i" (cmd! (+notes/open-document "inbox"))
        :desc "Legacy todo"           "t" (cmd! (+notes/open-document "todo"))
        :desc "Projects"              "p" (cmd! (+notes/open-document "projects"))
        :desc "Legacy snippets"       "n" (cmd! (+notes/open-document "notes"))
        :desc "Legacy ideas"          "I" (cmd! (+notes/open-document "ideas"))
        :desc "Legacy reading"        "r" (cmd! (+notes/open-document "reading"))
        :desc "Legacy someday"        "s" (cmd! (+notes/open-document "someday"))
        :desc "Legacy habits"         "h" (cmd! (+notes/open-document "habits"))
        :desc "Legacy AI sessions"    "a" (cmd! (+notes/open-document "ai"))
        :desc "Legacy maps (dired)"   "M"
        (cmd! (dired (file-name-concat org-directory "notes/maps")))
        :desc "Writing mode"          "w" #'+notes/writing-mode
        :desc "Browser capture setup" "P" #'+notes/install-protocol-handler)
       (:prefix "r"
        :desc "Search notes (consult)" "/" #'consult-org-roam-search
        :desc "Backlinks"              "B" #'consult-org-roam-backlinks
        :desc "Forward links"          "L" #'consult-org-roam-forward-links
        :desc "Map of a tag"           "m" #'+notes/roam-map-of-content
        :desc "Review the graph"       "v" #'+notes/roam-review
        :desc "Tasks hidden in notes"  "h" #'+notes/roam-todo-files
        :desc "How to work with roam"  "?" #'+notes/roam-guide
        :desc "Graph UI (browser)"     "u" #'org-roam-ui-open
        :desc "Graph UI mode"          "U" #'org-roam-ui-mode))
      ;; Doom's key for it, kept since its org module stopped bringing
      ;; the timer; packages.el brings it now.
      (:prefix "t"
       :desc "Pomodoro timer"          "t" #'org-pomodoro)
      (:prefix "o"
       (:prefix "a"
        :desc "Dashboard"             "x" #'+notes/dashboard
        :desc "Weekly review"         "w" #'+notes/weekly-review
        :desc "Next actions"          "n" #'+notes/next-actions
        :desc "Projects"              "p" #'+notes/projects
        :desc "Inbox"                 "i" #'+notes/inbox
        ;; The legacy Org/GTD task files, read only by habit: no capture
        ;; writes there any more.
        :desc "Legacy tasks"          "L" (cmd! (org-agenda nil "L")))))

;; Org lines up the table you are in when you leave a cell, and leaves
;; the rest of the file as it found it. This lines up all of them.
(map! :after org
      :map org-mode-map
      :localleader
      (:prefix "b"
       :desc "Align every table in the file" "A" #'+notes/align-tables))

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
       :desc "Extract subtree to a note" "e" #'+notes/roam-extract))

(map! :after org
      :map org-mode-map
      :localleader
      (:prefix ("M" . "mind map")
       :desc "Whole file"    "M" #'org-mind-map-write
       :desc "Current tree"  "t" #'org-mind-map-write-current-tree
       :desc "Current branch" "b" #'org-mind-map-write-current-branch)
      :desc "Writing mode"   "W" #'+notes/writing-mode)
