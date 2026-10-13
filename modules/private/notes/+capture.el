;;; private/notes/+capture.el -*- lexical-binding: t; -*-
;;
;; The capture templates, one per document they write into. Doom's own
;; t, n and j are replaced; the two helpers a template calls at capture
;; time, the babel language and the project name, are autoloaded from
;; autoload/capture.el. A note and a meeting are roam notes, kinds in
;; +roam.el, so that they link to people, projects and each other; the
;; menu's c n and c m make them.

(defun +notes--capture-templates ()
  "Capture templates that write into `+notes-documents'."
  ;; %a is a link back to where the capture was made, the file and line
  ;; or the mail; empty when there is nothing to point at.
  `(("t" "Todo to inbox" entry
     (file+headline "inbox.org" "Inbox")
     "* TODO %?\n:PROPERTIES:\n:CREATED: %U\n:END:\n%a\n%i" :prepend t)
    ("T" "Todo with date to inbox" entry
     (file+headline "inbox.org" "Inbox")
     "* TODO %?\nSCHEDULED: %^{Scheduled}t\n:PROPERTIES:\n:CREATED: %U\n:END:\n%a\n%i" :prepend t)
    ("i" "Idea" entry
     (file+headline "ideas.org" "Ideas")
     "* IDEA %^{Idea}\n:PROPERTIES:\n:CREATED: %U\n:END:\n%?" :prepend t)
    ("l" "Link (clipboard URL)" entry
     (file+headline "reading.org" "Links")
     "* %(org-cliplink-capture)\n:PROPERTIES:\n:CREATED: %U\n:END:\n%?" :prepend t)
    ("r" "Reading: book or article" entry
     (file+headline "reading.org" "Queue")
     "* TODO %^{Title}\n:PROPERTIES:\n:CREATED: %U\n:AUTHOR: %^{Author}\n:URL: %^{URL}\n:END:\n%?" :prepend t)
    ("c" "Code snippet" entry
     (file+headline "notes.org" "Snippets")
     "* %^{Description}  :snippet:\n:PROPERTIES:\n:CREATED: %U\n:PROJECT: %(+notes--capture-project-name)\n:END:\n%a\n#+begin_src %(+notes--capture-src-lang)\n%i\n#+end_src\n%?" :prepend t)
    ("b" "Bug from the code" entry
     (file+headline "inbox.org" "Inbox")
     "* TODO %^{What}  :bug:\n:PROPERTIES:\n:CREATED: %U\n:PROJECT: %(+notes--capture-project-name)\n:END:\n%a\n%i\n%?" :prepend t)
    ("P" "Project" entry
     (file+headline "projects.org" "Projects")
     "* PROJ %^{Project}\n:PROPERTIES:\n:CATEGORY: %\\1\n:CREATED: %U\n:END:\n** Goal\n%?\n** Next actions\n*** NEXT \n** Notes\n** Log\n" :prepend t)
    ("h" "Habit" entry
     (file+headline "habits.org" "Habits")
     "* TODO %^{Habit}\nSCHEDULED: <%<%Y-%m-%d %a> .+1d/3d>\n:PROPERTIES:\n:STYLE: habit\n:CREATED: %U\n:END:\n%?")
    ("w" "Web page, from the browser" entry
     (file+headline "reading.org" "Links")
     "* TODO %:description  :web:\n:PROPERTIES:\n:CREATED: %U\n:URL: %:link\n:END:\n%i\n%?" :prepend t)
    ("a" "AI session log" entry
     (file+olp+datetree "ai.org")
     "* %^{Topic}  :ai:\n:PROPERTIES:\n:CREATED: %U\n:PROJECT: %(+notes--capture-project-name)\n:AGENT: %^{Agent|claude-code|agent-shell|gptel}\n:END:\n%?")))

(after! org
  ;; Extend Doom's set. The private keys are removed first, so a reload
  ;; adds nothing twice.
  ;;
  ;; Through `org-capture-upgrade-templates', which is what the option's
  ;; own :set does: a plain `setq' on this one variable skips it, and an
  ;; old-format template then reaches org unconverted. Every template
  ;; here is current format, so this changes nothing today and keeps
  ;; changing nothing if one is ever pasted in from somewhere older.
  (let ((mine (+notes--capture-templates)))
    (setq org-capture-templates
          (org-capture-upgrade-templates
           (append mine
                   (seq-remove (lambda (tpl)
                                 (or (member (car tpl) '("t" "n" "j"))
                                     (assoc (car tpl) mine)))
                               org-capture-templates))))))
