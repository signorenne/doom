;;; private/notes/+roam.el -*- lexical-binding: t; -*-
;;
;; org-roam: the note templates, the dailies, the protocol captures from
;; the browser, consult over the graph, the graph UI.

(defvar +notes-roam-head
  ":PROPERTIES:\n:CREATED:  %U\n:END:\n#+title: ${title}\n#+filetags: "
  "How every roam note starts: when it was written, its title, its tags.
The date makes a note sortable and reviewable; everything after the tags
belongs to the template that uses this.")

(defvar +notes-project-body
  (concat "* Dashboard\n"
          "Tasks by state:\n#+BEGIN: notes-board :from folder\n#+END:\n\n"
          "Design documents:\n#+BEGIN: notes-list :from folder :tags (\"design\") :columns (title (property \"STATUS\") modified)\n#+END:\n\n"
          "Decisions:\n#+BEGIN: notes-query :from folder :query \"ltags:decision\" :columns (heading (property \"STATUS\") (property \"DATE\"))\n#+END:\n\n"
          "Case studies:\n#+BEGIN: notes-list :from vault :tags (\"case_study\") :links-to this\n#+END:\n\n"
          "* Goal\n\n* Completion criteria\n\n* Next actions\n\n* Decisions\n\n* Progress\n\n* Knowledge and sources\n")
  "How a new project index is laid out, below its head: a dashboard of
live tables, then the headings a project is worked under.  Both ways of
making a project write it, so it has no capture escape.")

(defvar +notes-course-body
  (concat "* Overview\n- Teacher:\n- Term:\n- Exam:\n\n"
          "* Timetable\nEach class is a repeating date in angle brackets, as this one in square ones: [2026-11-03 Tue 10:00-12:00 +1w]\n\n"
          "* Assignments and exams\n\n"
          "* Lectures\n#+BEGIN: notes-list :from folder :tags (\"lecture\") :columns (title created) :sort created\n#+END:\n\n"
          "* Board\n#+BEGIN: notes-board :from folder\n#+END:\n\n"
          "* Deadlines\n#+BEGIN: notes-query :from folder :query \"todo: deadline:to=14\" :columns (deadline todo heading file) :sort deadline\n#+END:\n\n"
          "* Case studies\n#+BEGIN: notes-list :from vault :tags (\"case_study\") :links-to this\n#+END:\n\n"
          "* Sources\n")
  "How a new course index is laid out, below its head: the timetable, what
is due, and live tables of its lectures, tasks and case studies.  No
capture escape: the template adds its own.")

;; The daily note, in capture template syntax: %<...> is the date. The
;; dailies template below and `+notes-daily-file', which other modules
;; write today's note through, read the same two strings.
(defvar +notes-daily-name "%<%Y-%m-%d>.org"
  "The file name of a daily note, under the dailies directory.")

(defvar +notes-daily-head
  "#+title: %<%Y-%m-%d %A>\n#+filetags: :daily:\n\n* Journal\n\n* Tasks\n\n* Notes\n"
  "How a daily note starts: its title, its tag, and the three headings a
day is written under.")

(after! org-roam
  ;; A task written inside a note reaches the agenda like any other: the
  ;; file list is set before an agenda or a refile, not advised, so a
  ;; view that binds its own list, or a restriction, keeps it. Every
  ;; command that reads the list is covered, the todo list and org-ql
  ;; too. org-ql-search reads it at its prompt, before advice on the
  ;; command itself runs, so the prompt is refreshed too.
  (dolist (command '(org-agenda org-refile org-todo-list org-ql-search
                     org-ql-view--complete-buffers-files))
    (advice-add command :before #'+notes--agenda-files-refresh-h))

  ;; A live table's links are not the note's: the database, and the
  ;; backlinks, the graph and its review with it, read only the links
  ;; and citations written outside the tables (autoload/query.el, set up
  ;; below). Nor are its cells mentions: the roam buffer's unlinked
  ;; mentions leave them out.
  (advice-add 'org-roam-unlinked-references-section :around #'+notes--roam-unlinked-a)

  ;; Made for a big vault (autoload/roam-db.el): those rules, and the
  ;; full syncs, the session's first and a first build, in a background
  ;; Emacs with the settings below, its result then taking the
  ;; database's place; the node list kept until the database changes.
  (+notes--roam-db-setup)

  ;; Journal and knowledge capture share the repository graph root.
  ;; org-roam matches these against the path relative to that root, so a
  ;; top-level .private/ must match at the start as well as after a slash.
  ;; Private progress, caches and Git internals never become nodes.
  (setq org-roam-file-exclude-regexp
        '("\\(?:\\`\\|/\\)\\.\\(?:private\\|cache\\|git\\)/")
        org-roam-dailies-directory "capture/journal/"
        ;; Plain org-roam-extract-subtree also files under resources/wiki;
        ;; +notes/roam-extract asks for the subject directory instead.
        org-roam-extract-new-file-path "%(+notes--roam-path \"resources/wiki/${slug}.org\")"
        ;; One template per kind; knowledge chooses a subject home. The
        ;; headings that say what to write: an empty note is still a shape
        ;; to fill. The finder shows the directory as the note's type. The
        ;; head holds the properties, the title and the tags only: org-roam
        ;; puts the note's ID where the head ends, and a heading there
        ;; would take the ID and be the node instead of the file.
        org-roam-capture-templates
        `(("c" "concept: what a thing is" plain
           "* In one sentence\n%?\n\n* How it works\n\n* Example\n\n* Where it bites\n\n* Related\n\n* Sources\n"
           :target (file+head "${+notes--roam-subject-path}"
                              ,(concat +notes-roam-head ":concept:\n\n"))
           :unnarrowed t :empty-lines-before 1)
          ("s" "solution: a bug and its fix" plain
           "* Symptom\n%?\n\n* Cause\n\n* Fix\n\n* How to verify\n\n* Applies to\nBoard, SDK, compiler, version.\n"
           :target (file+head "${+notes--roam-subject-path}"
                              ,(concat +notes-roam-head ":fix:\n\n"))
           :unnarrowed t :empty-lines-before 1)
          ("h" "howto: a procedure" plain
           "* When\n%?\n\n* Steps\n\n* Gotchas\n\n* Sources\n"
           :target (file+head "${+notes--roam-subject-path}"
                              ,(concat +notes-roam-head ":howto:\n\n"))
           :unnarrowed t :empty-lines-before 1)
          ("b" "hardware: a board, a part, a probe" plain
           "* What it is\n%?\n\n* Pinout and links\n\n* Toolchain\n\n* Gotchas\n"
           :target (file+head "${+notes--roam-subject-path}"
                              ,(concat +notes-roam-head ":hardware:\n\n"))
           :unnarrowed t :empty-lines-before 1)
          ("r" "reference: a source" plain
           "* Key points\n%?\n\n* Quotes\n\n* My take\n"
           :target (file+head "%(+notes--roam-path \"resources/sources/manuals/${slug}.org\")"
                              ,(concat (replace-regexp-in-string ":END:" ":ROAM_REFS: ${ref}\n:END:" +notes-roam-head t t) ":ref:\n\n"))
           :unnarrowed t :empty-lines-before 1)
          ;; The one citar fills. `r' asks for the source; citar has
          ;; already handed over the key, so this one does not ask again.
          ;; The file is named for the key as well, which is how citar
          ;; finds the note again.
          ("R" "reference: a source citar already knows" plain
           "* Key points\n%?\n\n* Quotes\n\n* My take\n"
           :target (file+head "%(+notes--roam-path \"resources/sources/papers/${citar-citekey}.org\")"
                              ,(concat +notes-roam-head ":ref:\n"
                                       "#+source: [cite:@${citar-citekey}]\n\n"))
           :unnarrowed t :empty-lines-before 1)
          ;; q and C are org-capture's own keys in its menu, Abort and
          ;; Customize: the question is on Q and the course on u.
          ("Q" "question: something to work out" plain
           "* Answer in one line\n%?\n\n* What I do not understand\n\n* What I tried\n\n* Answer\n"
           :target (file+head "${+notes--roam-subject-path}"
                              ,(concat +notes-roam-head ":question:\n\n"))
           :unnarrowed t :empty-lines-before 1)
          ;; Active, as one made with SPC X P is: a project with no
          ;; status counted as active, and now says so.
          ("p" "project" plain
           ,(replace-regexp-in-string "^\\* Goal\n" "* Goal\n%?\n" +notes-project-body t t)
           :target (file+head "${+notes--roam-project-path}"
                              ,(concat (replace-regexp-in-string ":END:" ":STATUS: active\n:END:" +notes-roam-head t t)
                                       ":project:\n#+repository: \n#+kit: \n\n"))
           :unnarrowed t :empty-lines-before 1)
          ("P" "person" plain
           "* Context\n%?\n\n* Notes\n"
           :target (file+head "%(+notes--roam-path \"resources/wiki/people/${slug}.org\")"
                              ,(concat +notes-roam-head ":person:\n\n"))
           :unnarrowed t :empty-lines-before 1)
          ;; Not among the dailies: org-roam takes every file of their
          ;; folder for a day, and a meeting there was the next day of
          ;; the last one.
          ("m" "meeting" plain
           "* Attendees\n%?\n\n* Agenda\n\n* Notes\n\n* Actions\n"
           :target (file+head "%(+notes--roam-path \"capture/meetings/%<%Y%m%d>-${slug}.org\")"
                              ,(concat +notes-roam-head ":meeting:\n\n"))
           :unnarrowed t :empty-lines-before 1)
          ;; A course is a folder of its own under areas/university/,
          ;; its index the hub, its lectures beside it; it has a status,
          ;; as a project has, so a finished one leaves the agenda.
          ("u" "course: a university course's hub" plain
           ,(replace-regexp-in-string "^- Teacher:$" "- Teacher: %?" +notes-course-body t t)
           :target (file+head "${+notes--roam-course-path}"
                              ,(concat (replace-regexp-in-string ":END:" ":STATUS: active\n:END:" +notes-roam-head t t)
                                       ":course:\n\n"))
           :unnarrowed t :empty-lines-before 1)
          ("l" "lecture: a class of a course" plain
           "Course: %(+notes--capture-course-link)\n\n* Summary\n%?\n\n* Notes\n\n* Questions\n\n* Cards\n"
           :target (file+head "${+notes--roam-lecture-path}"
                              ,(concat +notes-roam-head ":lecture:\n\n"))
           :unnarrowed t :empty-lines-before 1)
          ;; A design document is a note in its project's design/; its
          ;; status goes draft, review, accepted, by hand.
          ("D" "design doc: how a project's part will be built" plain
           "* Context\n%?\n\n* Goals\n\n* Non-goals\n\n* Requirements\n\n* Design\n\n* Alternatives\n\n* Risks\n\n* Open questions\n"
           :target (file+head "${+notes--roam-design-path}"
                              ,(concat (replace-regexp-in-string ":END:" ":STATUS: draft\n:END:" +notes-roam-head t t)
                                       ":design:\n\n"))
           :unnarrowed t :empty-lines-before 1)
          ;; One folder for every case study; the link on its For: line
          ;; is how its course or project lists it.
          ("k" "case study: a real case, worked through" plain
           "For: %(+notes--capture-owner-link)\n\n* Context\n%?\n\n* Problem\n\n* Analysis\n\n* Options\n\n* Decision\n\n* Outcome\n\n* Lessons\n\n* Sources\n"
           :target (file+head "${+notes--roam-case-study-path}"
                              ,(concat +notes-roam-head ":case_study:\n\n"))
           :unnarrowed t :empty-lines-before 1))
        ;; A journal entry is a heading under * Journal, named for what it
        ;; is about, with the time in a property. That way SPC m m e turns
        ;; it into a note whose title is the idea, not the hour.
        org-roam-dailies-capture-templates
        `(("d" "journal" entry
           "* %?\n:PROPERTIES:\n:CREATED: %U\n:END:\n"
           :target (file+head+olp ,+notes-daily-name ,+notes-daily-head
                                  ("Journal"))))
        ;; Headings tagged :noroam: stay out of the graph, and so do the
        ;; flashcards: org-fc gives every card an ID, which would make
        ;; each one a node.
        org-roam-db-node-include-function #'+notes--roam-include-node-p
        ;; Under the backlinks, the lines that name the note without
        ;; linking to it: the links still to be made.
        org-roam-mode-sections '(org-roam-backlinks-section
                                 org-roam-reflinks-section
                                 org-roam-unlinked-references-section)))

;; A course, a lecture, a case study or a design doc is always a new note:
;; picked from the finder, an existing node would get the template added
;; to its own file.
(add-hook 'org-roam-capture-preface-hook #'+notes--roam-new-only-h)

;; In a note, the cursor on a link says what it points to: the title line
;; in the echo area, the first lines too on SPC c H (autoload/preview.el).
(add-hook 'org-roam-find-file-hook #'+notes--link-eldoc-setup-h)

;; Saving a note whose #+title changed renames it as SPC n r N does: the
;; file, when it is named for the old title, and the links that say it.
(add-hook 'org-roam-find-file-hook #'+notes--rename-on-save-setup-h)

;; The map SPC n r m writes opens in a popup on the right, as the cheat
;; sheet does, rather than splitting the frame, and ESC closes it. Only
;; then: a map reached by a link opens as any note does.
(defvar +notes--roam-map-showing nil
  "Non-nil while `+notes/roam-map-of-content' shows the map it wrote.")

(defun +notes--roam-map-popup-p (&rest _)
  "Non-nil while the map SPC n r m wrote is being shown."
  +notes--roam-map-showing)

(set-popup-rule! #'+notes--roam-map-popup-p
  :side 'right :size 0.5 :select t :quit t :ttl nil :modeline t)

;; What org-protocol://roam-ref captures with: one note per page, found
;; again by URL.
(after! org-roam-protocol
  (setq org-roam-capture-ref-templates
        `(("w" "web page" plain
           "* Key points\n%?\n\n* Quotes\n%i\n\n* My take\n"
           :target (file+head "%(+notes--roam-path \"resources/sources/websites/${slug}.org\")"
                              ,(concat +notes-roam-head ":ref:\n"
                                       "#+source: ${ref}\n\n"))
           :unnarrowed t :empty-lines-before 1))))

;; The list of notes to fix (SPC n r v) and the browser's bookmarklets
;; open at the bottom and close with ESC or q. The list is kept while you
;; work through it.
(set-popup-rule! "^\\*roam review\\*$" :side 'bottom :size 0.4 :select t :quit t :ttl nil)
(set-popup-rule! "^\\*org-protocol bookmarklets\\*$" :side 'bottom :size 0.4 :select t :quit t)

(use-package! consult-org-roam
  :after org-roam
  :config
  (setq consult-org-roam-grep-func #'consult-ripgrep
        consult-org-roam-buffer-narrow-key ?r
        consult-org-roam-buffer-after-buffers t)
  (consult-org-roam-mode +1))

;; org-roam-ui's defaults are the ones wanted: the theme synced, the
;; graph following the buffer, updated on save, opened when the mode
;; starts.
(use-package! org-roam-ui
  :after org-roam
  :defer t)
