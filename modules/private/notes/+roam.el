;;; private/notes/+roam.el -*- lexical-binding: t; -*-
;;
;; org-roam: the note templates, the dailies, the protocol captures from
;; the browser, consult over the graph, the graph UI.

(defun +notes--roam-include-node-p ()
  "Whether the heading at point is a node of the graph."
  (let ((tags (org-get-tags)))
    (not (or (member "noroam" tags)
             (member (or (bound-and-true-p org-fc-flashcard-tag) "fc") tags)))))

(defvar +notes-roam-head
  ":PROPERTIES:\n:CREATED:  %U\n:END:\n#+title: ${title}\n#+filetags: "
  "How every roam note starts: when it was written, its title, its tags.
The date makes a note sortable and reviewable; everything after the tags
belongs to the template that uses this.")

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
  ;; view that binds its own list, or a restriction, keeps it.
  ;; Every command that reads the list, not only the agenda: the todo
  ;; list and org-ql went through neither, so in a session that had not
  ;; opened an agenda they missed every task written inside a note.
  ;; org-ql-search reads it at its prompt, before advice on the command
  ;; itself runs, so the prompt is refreshed too.
  (dolist (command '(org-agenda org-refile org-todo-list org-ql-search
                     org-ql-view--complete-buffers-files))
    (advice-add command :before #'+notes--agenda-files-refresh-h))

  ;; The dailies live in daily/, the package's default.
  (setq ;; Where an extracted heading goes: a concept unless the prompt is
        ;; given another kind's directory. The root holds no notes; every
        ;; kind has its directory and the file is named by the slug.
        org-roam-extract-new-file-path "concepts/${slug}.org"
        ;; One template per kind of note, each a directory, a tag, and the
        ;; headings that say what to write: an empty note is still a shape
        ;; to fill. The finder shows the directory as the note's type. The
        ;; head holds the properties, the title and the tags only: org-roam
        ;; puts the note's ID where the head ends, and a heading there
        ;; would take the ID and be the node instead of the file.
        org-roam-capture-templates
        `(("c" "concept: what a thing is" plain
           "* In one sentence\n%?\n\n* How it works\n\n* Example\n\n* Where it bites\n\n* Related\n\n* Sources\n"
           :target (file+head "concepts/${slug}.org"
                              ,(concat +notes-roam-head ":concept:\n\n"))
           :unnarrowed t :empty-lines-before 1)
          ("s" "solution: a bug and its fix" plain
           "* Symptom\n%?\n\n* Cause\n\n* Fix\n\n* How to verify\n\n* Applies to\nBoard, SDK, compiler, version.\n"
           :target (file+head "solutions/${slug}.org"
                              ,(concat +notes-roam-head ":fix:\n\n"))
           :unnarrowed t :empty-lines-before 1)
          ("h" "howto: a procedure" plain
           "* When\n%?\n\n* Steps\n\n* Gotchas\n\n* Sources\n"
           :target (file+head "howtos/${slug}.org"
                              ,(concat +notes-roam-head ":howto:\n\n"))
           :unnarrowed t :empty-lines-before 1)
          ("b" "hardware: a board, a part, a probe" plain
           "* What it is\n%?\n\n* Pinout and links\n\n* Toolchain\n\n* Gotchas\n"
           :target (file+head "hardware/${slug}.org"
                              ,(concat +notes-roam-head ":hardware:\n\n"))
           :unnarrowed t :empty-lines-before 1)
          ("r" "reference: a source" plain
           "* Key points\n%?\n\n* Quotes\n\n* My take\n"
           :target (file+head "refs/${slug}.org"
                              ,(concat +notes-roam-head ":ref:\n"
                                       "#+source: %^{Source, a URL or citation}\n\n"))
           :unnarrowed t :empty-lines-before 1)
          ;; The one citar fills. `r' asks for the source because there
          ;; is nothing to ask instead; here citar has just handed over
          ;; the key, so asking again is asking the user to retype what
          ;; the tool knows. The file is named for the key as well, which
          ;; is how citar finds the note again.
          ("R" "reference: a source citar already knows" plain
           "* Key points\n%?\n\n* Quotes\n\n* My take\n"
           :target (file+head "refs/${citar-citekey}.org"
                              ,(concat +notes-roam-head ":ref:\n"
                                       "#+source: [cite:@${citar-citekey}]\n\n"))
           :unnarrowed t :empty-lines-before 1)
          ("q" "question: something to work out" plain
           "* Answer in one line\n%?\n\n* What I do not understand\n\n* What I tried\n\n* Answer\n"
           :target (file+head "questions/${slug}.org"
                              ,(concat +notes-roam-head ":question:\n\n"))
           :unnarrowed t :empty-lines-before 1)
          ("p" "project" plain
           "* Goal\n%?\n\n* Status\n\n* Decisions\n\n* Log\n"
           :target (file+head "projects/${slug}.org"
                              ,(concat +notes-roam-head ":project:\n"
                                       "#+repository: \n#+kit: \n\n"))
           :unnarrowed t :empty-lines-before 1)
          ("P" "person" plain
           "* Context\n%?\n\n* Notes\n"
           :target (file+head "people/${slug}.org"
                              ,(concat +notes-roam-head ":person:\n\n"))
           :unnarrowed t :empty-lines-before 1)
          ("m" "meeting" plain
           "* Attendees\n%?\n\n* Agenda\n\n* Notes\n\n* Actions\n"
           :target (file+head "meetings/%<%Y%m%d>-${slug}.org"
                              ,(concat +notes-roam-head ":meeting:\n\n"))
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
        org-roam-db-node-include-function #'+notes--roam-include-node-p))

;; org-protocol://roam-ref lands here: one note per page, found again by URL.
(after! org-roam-protocol
  (setq org-roam-capture-ref-templates
        `(("w" "web page" plain
           "* Key points\n%?\n\n* Quotes\n%i\n\n* My take\n"
           :target (file+head "refs/${slug}.org"
                              ,(concat +notes-roam-head ":ref:\n"
                                       "#+source: ${ref}\n\n"))
           :unnarrowed t :empty-lines-before 1))))

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
