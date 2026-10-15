;;; private/notes/+capture.el -*- lexical-binding: t; -*-
;;
;; The capture templates, one per document they write into. Doom's own
;; t, n and j are replaced; the two helpers a template calls at capture
;; time, the babel language and the project name, are autoloaded from
;; autoload/capture.el. A note and a meeting are roam notes, kinds in
;; +roam.el, so that they link to people, projects and each other; the
;; menu's c n and c m make them.

(defun +notes--capture-templates ()
  "Capture into the knowledge inbox or the owning PARA project."
  ;; %a is a link back to where the capture was made, the file and line
  ;; or the mail; empty when there is nothing to point at.
  `(("t" "Todo to inbox" entry
     (file+headline ,(+notes--inbox-file) "Inbox")
     "* TODO %?\n:PROPERTIES:\n:CREATED: %U\n:END:\n%a\n%i" :prepend t)
    ("T" "Todo with date to inbox" entry
     (file+headline ,(+notes--inbox-file) "Inbox")
     "* TODO %?\nSCHEDULED: %^{Scheduled}t\n:PROPERTIES:\n:CREATED: %U\n:END:\n%a\n%i" :prepend t)
    ("i" "Idea" entry
     (file+headline ,(+notes--inbox-file) "Inbox")
     "* IDEA %^{Idea}\n:PROPERTIES:\n:CREATED: %U\n:END:\n%?" :prepend t)
    ("l" "Link (clipboard URL)" entry
     (file+headline ,(+notes--inbox-file) "Inbox")
     "* %(org-cliplink-capture)\n:PROPERTIES:\n:CREATED: %U\n:END:\n%?" :prepend t)
    ("r" "Reading: book or article" entry
     (file+headline ,(+notes--inbox-file) "Inbox")
     "* TODO %^{Title}\n:PROPERTIES:\n:CREATED: %U\n:AUTHOR: %^{Author}\n:URL: %^{URL}\n:END:\n%?" :prepend t)
    ("c" "Code snippet" entry
     (file+headline ,(+notes--inbox-file) "Inbox")
     "* %^{Description}  :snippet:\n:PROPERTIES:\n:CREATED: %U\n:PROJECT: %(+notes--capture-project-name)\n:END:\n%a\n#+begin_src %(+notes--capture-src-lang)\n%i\n#+end_src\n%?" :prepend t)
    ("b" "Bug from the code" entry
     (file+headline ,(+notes--inbox-file) "Inbox")
     "* TODO %^{What}  :bug:\n:PROPERTIES:\n:CREATED: %U\n:PROJECT: %(+notes--capture-project-name)\n:END:\n%a\n%i\n%?" :prepend t)
    ("P" "Project goal" plain
     (function +notes--capture-project-goal) "%?" :unnarrowed t)
    ("pt" "Task for an active PARA project" entry
     (function +notes--capture-project-task)
     "* TODO %?\n:PROPERTIES:\n:CREATED: %U\n:END:\n%a\n%i")
    ("ot" "Task for an active PARA project" entry
     (function +notes--capture-project-task)
     "* TODO %?\n:PROPERTIES:\n:CREATED: %U\n:END:\n%a\n%i")
    ("h" "Habit" entry
     (file+headline ,(+notes--inbox-file) "Inbox")
     "* TODO %^{Habit}\nSCHEDULED: <%<%Y-%m-%d %a> .+1d/3d>\n:PROPERTIES:\n:STYLE: habit\n:CREATED: %U\n:END:\n%?")
    ("w" "Web page, from the browser" entry
     (file+headline ,(+notes--inbox-file) "Inbox")
     "* TODO %:description  :web:\n:PROPERTIES:\n:CREATED: %U\n:URL: %:link\n:END:\n%i\n%?" :prepend t)
    ("a" "AI session log" entry
     (function +notes--capture-project-progress)
     "* %^{Topic}  :ai:\n:PROPERTIES:\n:CREATED: %U\n:PROJECT: %(+notes--capture-project-name)\n:AGENT: %^{Agent|claude-code|agent-shell|gptel}\n:END:\n%?")))

;; An aborted P capture must not leave an empty active project behind:
;; +notes--capture-project-goal records a project it created, and this
;; removes it again when the capture is killed.
(defvar +notes--roam-todo-files)          ; autoload/roam.el
(declare-function org-capture-get "org-capture")

(defun +notes--discard-aborted-project-h ()
  "Delete the project file an aborted goal capture created."
  (when-let* (((bound-and-true-p org-note-abort))
              (file (org-capture-get :+notes-new-project))
              ((file-exists-p file)))
    (when-let* ((buffer (find-buffer-visiting file)))
      (with-current-buffer buffer (set-buffer-modified-p nil))
      (kill-buffer buffer))
    (delete-file file)
    (let ((dir (file-name-directory file)))
      (when (directory-empty-p dir) (delete-directory dir)))
    (setq +notes--roam-todo-files nil)))

(add-hook 'org-capture-after-finalize-hook #'+notes--discard-aborted-project-h)

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
