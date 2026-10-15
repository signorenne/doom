;;; private/notes/+agenda.el -*- lexical-binding: t; -*-
;;
;; The agenda: the dashboard, the weekly review and the smaller views,
;; grouped by org-super-agenda; org-ql for questions the agenda cannot ask.

(after! org-agenda
  (setq org-agenda-start-on-weekday nil
        org-deadline-warning-days 7
        org-agenda-skip-scheduled-if-done t
        org-agenda-skip-deadline-if-done t
        org-agenda-skip-deadline-prewarning-if-scheduled 'pre-scheduled
        ;; Not here: set globally it takes a task scheduled ahead out of
        ;; every todo view there is, the inbox and the weekly review
        ;; with them, so a task could be counted by the menu and shown
        ;; by nothing. The dashboard, which is the view it was meant
        ;; for, sets it itself.
        org-agenda-tags-column 0
        org-agenda-block-separator ?-
        org-agenda-time-grid '((daily today require-timed)
                               (800 1000 1200 1400 1600 1800 2000)
                               "      " "----------------")
        org-agenda-current-time-string "<-- now --------------------------"))

(use-package! org-super-agenda
  :after org-agenda
  :config
  (setq org-super-agenda-header-map nil) ; keep evil's keys in agenda buffers
  (org-super-agenda-mode +1)
  (setq org-agenda-custom-commands
        `(("x" "Dashboard"
           ((agenda "" ((org-agenda-span 'day)
                        (org-agenda-start-day nil) ; Doom defaults to "-3d"
                        (org-agenda-overriding-header "")
                        (org-super-agenda-groups
                         ;; Groups take items in list order: Habits
                         ;; sits before Today, which would otherwise
                         ;; claim them as scheduled today.
                         '((:name "Overdue"
                            :deadline past :scheduled past :order 1)
                           (:name "Habits" :habit t :order 3)
                           (:name "Today"
                            :time-grid t :date today
                            :scheduled today :deadline today :order 2)
                           (:name "Coming up" :deadline future :order 4)))))
            (alltodo "" ((org-agenda-overriding-header "")
                         ;; What is scheduled ahead is not today's
                         ;; business: the agenda block above shows it on
                         ;; the day, and the weekly review has it whole.
                         (org-agenda-todo-ignore-scheduled 'future)
                         (org-super-agenda-groups
                          '((:name "Inbox, to refile"
                             :file-path "inbox\\.org" :order 1)
                            (:name "Next actions" :todo "NEXT" :order 2)
                            (:name "In progress" :todo "STRT" :order 3)
                            (:name "Waiting" :todo "WAIT" :order 4)
                            (:name "On hold" :todo "HOLD" :order 5)
                            (:name "Projects" :todo "PROJ" :order 6)
                            (:name "Ideas" :todo "IDEA" :order 7)
                            ;; A habit is the day's business, shown above.
                            (:discard (:habit t))
                            ;; Plain tasks, wherever they were written:
                            ;; the scan puts notes with tasks in the
                            ;; agenda files for this group.
                            (:name "Tasks" :todo ("TODO" "LOOP" "[ ]" "[-]" "[?]")
                             :order 8)
                            (:discard (:anything t))))))))
          ("w" "Weekly review"
           ((agenda "" ((org-agenda-span 'week)
                        (org-agenda-start-on-weekday 1)
                        (org-agenda-start-day nil)))
            (todo "WAIT|HOLD"
                  ((org-agenda-overriding-header "Waiting or on hold")))
            ;; A project is stuck when its * Next actions holds no NEXT or
            ;; STRT task. The prefix names the project: every project
            ;; file is called index.org, so its category says nothing.
            (stuck ""
                   ((org-agenda-overriding-header "Projects without a next action")
                    (org-agenda-files (+notes--project-files))
                    (org-stuck-projects
                     '("+LEVEL=1+ITEM=\"Next actions\"" ("NEXT" "STRT") nil ""))
                    (org-agenda-prefix-format "  %(+notes--project-title buffer-file-name) ")))
            ;; A tags-todo block honours the ignore options only when told.
            (tags-todo "+TODO=\"TODO\""
                       ((org-agenda-overriding-header "Unscheduled tasks")
                        (org-agenda-tags-todo-honor-ignore-options t)
                        (org-agenda-todo-ignore-scheduled t)
                        (org-agenda-todo-ignore-deadlines t)))))
          ("n" "Next actions" todo "NEXT")
          ("p" "Active project context"
           ((alltodo "" ((org-agenda-files (+notes--project-files))
                         (org-agenda-overriding-header "Active project actions")))))
          ("L" "Legacy tasks (existing Org/GTD files)"
           ((alltodo "" ((org-agenda-files +notes-legacy-agenda-files)
                         (org-agenda-overriding-header "Legacy tasks")))))
          ("i" "Inbox"
           ((alltodo ""
                     ((org-agenda-files
                       (list ,(+notes--inbox-file)))
                      (org-agenda-overriding-header "Inbox"))))))))

(use-package! org-ql
  :defer t)
