;;; private/notes/+capture.el -*- lexical-binding: t; -*-
;;
;; The capture templates, one per document they write into. Doom's own
;; t, n and j are replaced. A note and a meeting are roam notes, so that
;; they link to people, projects and each other; the menu's c n and c m
;; make them.

(defun +notes--capture-templates ()
  "Capture into the inbox, the owning PARA project, or the document a
habit, a reading or a snippet belongs in."
  ;; %a is a link back to where the capture was made, the file and line
  ;; or the mail; empty when there is nothing to point at.
  `(("t" "Todo to inbox" entry
     (file+headline ,(+notes--inbox-file) "Inbox")
     "* TODO %?\n:PROPERTIES:\n:CREATED: %U\n:END:\n%a\n%i" :prepend t)
    ("T" "Todo with a date" entry
     (file+headline ,(+notes--inbox-file) "Inbox")
     "* TODO %?\nSCHEDULED: %^{Scheduled}t\n:PROPERTIES:\n:CREATED: %U\n:END:\n%a\n%i" :prepend t)
    ("i" "Idea" entry
     (file+headline ,(+notes--inbox-file) "Inbox")
     "* IDEA %^{Idea}\n:PROPERTIES:\n:CREATED: %U\n:END:\n%?" :prepend t)
    ("l" "Clipboard link" entry
     (file+headline ,(+notes--inbox-file) "Inbox")
     "* %(org-cliplink-capture)\n:PROPERTIES:\n:CREATED: %U\n:END:\n%?" :prepend t)
    ("r" "Book or article" entry
     (file+headline ,(+notes--document-path "reading") "Queue")
     "* TODO %^{Title}\n:PROPERTIES:\n:CREATED: %U\n:AUTHOR: %^{Author}\n:URL: %^{URL}\n:END:\n%?" :prepend t)
    ("c" "Code snippet" entry
     (file+headline ,(+notes--document-path "snippets") "Snippets")
     "* %^{Description}  :snippet:\n:PROPERTIES:\n:CREATED: %U\n:PROJECT: %(+notes--capture-project-name)\n:END:\n%a\n#+begin_src %(+notes--capture-src-lang)\n%i\n#+end_src\n%?" :prepend t)
    ("b" "Bug from the code" entry
     (file+headline ,(+notes--inbox-file) "Inbox")
     "* TODO %^{What}  :bug:\n:PROPERTIES:\n:CREATED: %U\n:PROJECT: %(+notes--capture-project-name)\n:END:\n%a\n%i\n%?" :prepend t)
    ("P" "Project goal" plain
     (function +notes--capture-project-goal) "%?" :unnarrowed t)
    ("pt" "Task for a project" entry
     (function +notes--capture-project-task)
     "* TODO %?\n:PROPERTIES:\n:CREATED: %U\n:END:\n%a\n%i")
    ("ot" "Task for a project, as pt" entry
     (function +notes--capture-project-task)
     "* TODO %?\n:PROPERTIES:\n:CREATED: %U\n:END:\n%a\n%i")
    ("h" "Habit" entry
     (file+headline ,(+notes--document-path "habits") "Habits")
     "* TODO %^{Habit}\nSCHEDULED: <%<%Y-%m-%d %a> .+1d/3d>\n:PROPERTIES:\n:STYLE: habit\n:CREATED: %U\n:END:\n%?")
    ("w" "Web page, from the browser" entry
     (file+headline ,(+notes--inbox-file) "Inbox")
     "* TODO %:description  :web:\n:PROPERTIES:\n:CREATED: %U\n:URL: %:link\n:END:\n%i\n%?" :prepend t)
    ("a" "AI session log" entry
     (function +notes--capture-project-progress)
     "* %^{Topic}  :ai:\n:PROPERTIES:\n:CREATED: %U\n:PROJECT: %(+notes--capture-project-name)\n:AGENT: %^{Agent|claude-code|agent-shell|gptel}\n:END:\n%?")
    ("d" "Project decision" entry
     (function +notes--capture-project-decision)
     "* %^{Decision}  :decision:\n:PROPERTIES:\n:ID: %(org-id-new)\n:STATUS: %^{Status|accepted|proposed}\n:DATE: %<%Y-%m-%d>\n:CREATED: %U\n:END:\nContext: %?\nDecision:\nConsequences:\nAlternatives:\n")
    ("e" "Assignment or exam" entry
     (function +notes--capture-course-deadline)
     "* TODO %^{What}  :%^{Kind|assignment|exam}:\nDEADLINE: %^{Due}t\n:PROPERTIES:\n:CREATED: %U\n:END:\n%?")))

;; An aborted P capture must not leave an empty active project behind:
;; +notes--capture-project-goal records a project it created, and this
;; removes it again when the capture is killed.
(defvar +notes--roam-todo-files)
(declare-function org-capture-get "org-capture")

(defun +notes--discard-aborted-project-h ()
  "Delete the project file an aborted goal capture created, and say so:
the last word was its save's, \"written\"."
  (when-let* (((bound-and-true-p org-note-abort))
              (file (org-capture-get :+notes-new-project))
              ((file-exists-p file))
              (title (+notes--project-title file)))
    (when-let* ((buffer (find-buffer-visiting file)))
      (with-current-buffer buffer (set-buffer-modified-p nil))
      (kill-buffer buffer))
    (delete-file file)
    (let ((dir (file-name-directory file)))
      (when (directory-empty-p dir) (delete-directory dir)))
    (setq +notes--roam-todo-files nil)
    (message "Capture aborted: the new project %S is not kept" title)))

(add-hook 'org-capture-after-finalize-hook #'+notes--discard-aborted-project-h)

(after! org
  ;; Extend Doom's set. The private keys are removed first, so a reload
  ;; adds nothing twice. So are Doom's pn, pc, on and oc: they write a
  ;; notes.org or a changelog.org into the code's repository, or a
  ;; heading named for it into the project index, and a repository is
  ;; not a project by itself here.
  ;;
  ;; Through `org-capture-upgrade-templates', which is what the option's
  ;; own :set does: a plain `setq' skips it, and an old-format template
  ;; would then reach org unconverted.
  (let ((mine (+notes--capture-templates)))
    (setq org-capture-templates
          (org-capture-upgrade-templates
           (append mine
                   (seq-remove (lambda (tpl)
                                 (or (member (car tpl) '("t" "n" "j" "pn" "pc" "on" "oc"))
                                     (assoc (car tpl) mine)))
                               org-capture-templates))))))
