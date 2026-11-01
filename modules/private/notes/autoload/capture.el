;;; private/notes/autoload/capture.el -*- lexical-binding: t; -*-

(declare-function org-capture-get "org-capture")
(declare-function org-capture-put "org-capture")
(declare-function org-cliplink-capture "org-cliplink")
(declare-function doom-project-name "doom-projects")
(declare-function org-roam-node-create "org-roam-node")
(declare-function org-roam-node-slug "org-roam-node")
(declare-function org-roam-node-title "org-roam-node")
(declare-function org-id-new "org-id")
(declare-function outline-next-heading "outline")
(declare-function org-link-make-string "ol")

(defun +notes--capture-buffer ()
  "The buffer `org-capture' was called from."
  (or (org-capture-get :original-buffer) (current-buffer)))

;;;###autoload
(defun +notes--capture-src-lang ()
  "Babel language of the buffer `org-capture' was started from, from
core's one table of languages."
  (+core-language (with-current-buffer (+notes--capture-buffer) major-mode)
                  'babel))

;;;###autoload
(defun +notes--capture-project-name ()
  "Name of the project `org-capture' was started from, or \"-\"."
  (with-current-buffer (+notes--capture-buffer)
    (or (doom-project-name) "-")))


(defvar-local +notes-project-file nil
  "Explicit active PARA project for tasks from this buffer.")
(put '+notes-project-file 'safe-local-variable #'stringp)

(defun +notes--inbox-file ()
  "The authoritative inbox in the current knowledge graph."
  (expand-file-name "inbox.org" org-roam-directory))

(defun +notes--project-header (file)
  "FILE's header before its first heading, or an empty string."
  (with-temp-buffer
    (when (file-readable-p file)
      (insert-file-contents file)
      (goto-char (point-min))
      (buffer-substring-no-properties
       (point-min) (if (re-search-forward "^\\*+ " nil t)
                       (line-beginning-position) (point-max))))))

;;;###autoload
(defun +notes--project-files ()
  "Active PARA project files, including projects with no actions yet."
  (let ((dir (expand-file-name "projects/" org-roam-directory))
        (case-fold-search t))
    (when (file-directory-p dir)
      (seq-filter
       (lambda (file)
         (let ((head (+notes--project-header file)))
           (and (string-match-p "^#\\+filetags:.*:project:" head)
                (not (string-match-p "^:STATUS: *\\(paused\\|archived\\|completed\\) *$" head)))))
       (directory-files-recursively dir "\\`index\\.org\\'")))))

(defun +notes--project-title (file)
  "The title of project FILE."
  (let ((case-fold-search t) (head (+notes--project-header file)))
    (if (string-match "^#\\+title: *\\(.+\\)$" head)
        (string-trim (match-string 1 head))
      (file-name-nondirectory (directory-file-name (file-name-directory file))))))

(defun +notes--project-path (title)
  "Canonical project file for TITLE; refuse an unrelated slug collision."
  (require 'org-roam)
  (let* ((title (string-trim title))
         (slug (org-roam-node-slug (org-roam-node-create :title title)))
         (file (expand-file-name (concat "projects/" slug "/index.org") org-roam-directory)))
    (when (string-empty-p title) (user-error "A project needs an outcome title"))
    (when (or (string-empty-p slug) (not (file-in-directory-p file
                                                         (expand-file-name "projects/" org-roam-directory))))
      (user-error "Invalid project title"))
    (when (and (file-exists-p file)
               (not (equal title (+notes--project-title file))))
      (user-error "A different project already occupies %s" file))
    (when (and (file-exists-p file) (not (member file (+notes--project-files))))
      (user-error "Project is inactive; review it before resuming"))
    file))

(defun +notes--create-project (title)
  "Create the canonical active project TITLE if it does not exist."
  (let ((file (+notes--project-path title)))
    (unless (file-exists-p file)
      (make-directory (file-name-directory file) t)
      (with-temp-file file
        (insert (format ":PROPERTIES:\n:ID: %s\n:CREATED: %s\n:STATUS: active\n:END:\n#+title: %s\n#+filetags: :project:\n\n"
                        (org-id-new) (format-time-string "[%Y-%m-%d %a %H:%M]") title)
                "* Goal\n\n* Completion criteria\n\n* Next actions\n\n* Decisions\n\n* Progress\n\n* Knowledge and sources\n")))
    (setq +notes--roam-todo-files nil)
    file))

(defun +notes--resolve-project-file ()
  "Resolve the owning active project, or the inbox when unclassified.
An explicit buffer association wins. Otherwise match REPOSITORY against
its code root; ambiguous matches require selection. A code repository's
name never creates a PARA commitment by itself."
  (let* ((files (+notes--project-files))
         (origin (+notes--capture-buffer))
         (explicit (buffer-local-value '+notes-project-file origin))
         (current (buffer-file-name origin))
         (root (with-current-buffer origin
                 (when (fboundp '+core-project-root) (+core-project-root 'noerror))))
         (case-fold-search t)
         (matches (and root
                       (seq-filter
                        (lambda (file)
                          (let ((head (+notes--project-header file)))
                            ;; An empty value names no repository; it must
                            ;; not expand to the current directory.
                            (when (string-match "^\\(?::REPOSITORY:\\|#\\+repository:\\)[ \t]*\\([^ \t\n].*\\)$" head)
                              (let ((repo (string-trim (match-string 1 head))))
                                (equal (file-truename (file-name-as-directory (expand-file-name repo)))
                                       (file-truename (file-name-as-directory root)))))))
                        files))))
    (cond
     (explicit
      (let ((file (expand-file-name explicit org-roam-directory)))
        (unless (member file files) (user-error "Explicit project is not active: %s" file))
        file))
     ((member current files) current)
     ((= (length matches) 1) (car matches))
     ((null files) (+notes--inbox-file))
     (t
      (let* ((choices (cons (cons "Inbox (unclassified)" (+notes--inbox-file))
                            (mapcar (lambda (file)
                                      (cons (concat (+notes--project-title file) " ["
                                                    (file-relative-name file org-roam-directory) "]") file))
                                    (or matches files))))
             (choice (completing-read "Owning project: " choices nil t)))
        (cdr (assoc choice choices)))))))

(defun +notes--capture-at (file heading &optional text)
  "Visit FILE and target its top-level HEADING, adding it when absent.
Point stays on HEADING, where `org-capture' files an entry template as
its last child.  With TEXT, point moves to the end of HEADING's own
text instead, where a plain template is inserted as written."
  (set-buffer (find-file-noselect file))
  (widen)
  (goto-char (point-min))
  (if (re-search-forward (concat "^\\* " (regexp-quote heading) "[ \t]*$") nil t)
      (beginning-of-line)
    (goto-char (point-max))
    (unless (bolp) (insert "\n"))
    (insert "* " heading "\n")
    (forward-line -1))
  (when text
    (outline-next-heading)))

;;;###autoload
(defun +notes--capture-project-task ()
  "Target a task to the shared active project resolver or the inbox."
  (let ((file (+notes--resolve-project-file)))
    (+notes--capture-at file (if (equal file (+notes--inbox-file)) "Inbox" "Next actions"))))

;;;###autoload
(defun +notes--capture-project-goal ()
  "Create or reuse one project and capture its goal.
A project this capture creates is remembered, so aborting the capture
removes it again instead of leaving an empty active project."
  (let* ((title (read-string "Project outcome: "))
         (existed (file-exists-p (+notes--project-path title)))
         (file (+notes--create-project title)))
    (unless existed (org-capture-put :+notes-new-project file))
    (+notes--capture-at file "Goal" t)))

;;;###autoload
(defun +notes--roam-project-path (node)
  "The shared canonical project path for Org-roam NODE."
  (+notes--roam-path (+notes--project-path (org-roam-node-title node))))

;;;###autoload
(defun +notes--roam-subject-path (node)
  "Choose a knowledge subject home for NODE, within resources/wiki."
  (let* ((root (expand-file-name "resources/wiki/" org-roam-directory))
         (dir (read-directory-name "Subject directory: " root nil t))
         (file (expand-file-name (concat (org-roam-node-slug node) ".org") dir)))
    (unless (file-in-directory-p file root) (user-error "Choose a directory under resources/wiki"))
    file))

;;;###autoload
(defun +notes--capture-project-progress ()
  "Target progress to its owning project, or the unclassified inbox."
  (let ((file (+notes--resolve-project-file)))
    (+notes--capture-at file (if (equal file (+notes--inbox-file)) "Inbox" "Progress"))))

;;;###autoload
(defun +notes--roam-path (path)
  "Prepare PATH's parent inside the graph and return its absolute path."
  (let ((file (expand-file-name path org-roam-directory)))
    (unless (file-in-directory-p file (expand-file-name org-roam-directory))
      (user-error "Capture destination must remain inside the graph"))
    (make-directory (file-name-directory file) t)
    file))

(defun +notes--roam-new-path (path)
  "Like `+notes--roam-path', for a note that must be new: a file there
already would get the template written into it."
  (let ((file (+notes--roam-path path)))
    (when (file-exists-p file)
      (user-error "%s exists already; give the new note another title"
                  (file-relative-name file org-roam-directory)))
    file))

(defvar org-roam-capture--node)
(declare-function org-roam-node-file "org-roam-node")

;;;###autoload
(defun +notes--roam-new-only-h ()
  "Refuse a course, lecture, case study or design doc for a node that has
a file already: org-roam would write the template into that file."
  (when (and (member (org-capture-get :key) '("C" "l" "k" "D"))
             (org-roam-node-file org-roam-capture--node))
    (user-error "%S is a note already, %s; to make a new one of that title, type it and press M-RET"
                (org-roam-node-title org-roam-capture--node)
                (file-relative-name (org-roam-node-file org-roam-capture--node) org-roam-directory))))

;;
;;; Courses

;;;###autoload
(defun +notes--course-files ()
  "The active courses: each areas/university/<course>/index.org tagged
:course:, not paused, archived or completed."
  (let ((dir (expand-file-name "areas/university/" org-roam-directory))
        (case-fold-search t))
    (when (file-directory-p dir)
      (seq-filter
       (lambda (file)
         (and (file-exists-p file)
              (let ((head (+notes--project-header file)))
                (and (string-match-p "^#\\+filetags:.*:course:" head)
                     (not (string-match-p "^:STATUS: *\\(paused\\|archived\\|completed\\) *$" head))))))
       (mapcar (lambda (sub) (expand-file-name "index.org" sub))
               (seq-filter #'file-directory-p (directory-files dir t "\\`[^.]")))))))

(defun +notes--file-id (file)
  "The ID in FILE's top drawer, or nil."
  (let ((case-fold-search t) (head (+notes--project-header file)))
    (and (string-match "^:ID: *\\(\\S-+\\)" head) (match-string 1 head))))

(defun +notes--read-course (buffer)
  "The index of the course BUFFER's file belongs to: the active course
whose folder holds it, else one picked among the active courses.  A
capture passes the buffer it was started from; a command, its own."
  (let* ((courses (+notes--course-files))
         (file (buffer-file-name (or (buffer-base-buffer buffer) buffer))))
    (cond ((and file (seq-find (lambda (course) (file-in-directory-p file (file-name-directory course)))
                               courses)))
          ((null courses) (user-error "No active course yet; SPC n r n C makes one"))
          (t (let ((choices (mapcar (lambda (course) (cons (+notes--project-title course) course))
                                    courses)))
               (cdr (assoc (completing-read "Course: " choices nil t) choices)))))))

(defun +notes--capture-course ()
  "The course of this capture, read once and kept with the capture."
  (or (org-capture-get :+notes-course)
      (let ((course (+notes--read-course (+notes--capture-buffer))))
        (org-capture-put :+notes-course course)
        course)))

;;;###autoload
(defun +notes--roam-course-path (node)
  "The index of a new course NODE: areas/university/<slug>/index.org.
An existing course is never written into."
  (let* ((slug (org-roam-node-slug node))
         (file (expand-file-name (concat "areas/university/" slug "/index.org") org-roam-directory)))
    (when (string-empty-p slug) (user-error "A course needs a title"))
    (when (file-exists-p file) (user-error "Course already exists: %s" (abbreviate-file-name file)))
    (+notes--roam-path file)))

;;;###autoload
(defun +notes--roam-lecture-path (node)
  "A new lecture NODE of the capture's course, in its lectures/ folder,
named for the day."
  (+notes--roam-new-path
   (expand-file-name (format "lectures/%s-%s.org" (format-time-string "%Y%m%d") (org-roam-node-slug node))
                     (file-name-directory (+notes--capture-course)))))

;;;###autoload
(defun +notes--capture-course-link ()
  "An id: link to the course of this capture, titled as it is."
  (let ((course (+notes--capture-course)))
    (org-link-make-string (concat "id:" (or (+notes--file-id course)
                                            (user-error "%s has no ID" (abbreviate-file-name course))))
                          (+notes--project-title course))))

;;;###autoload
(defun +notes--capture-course-deadline ()
  "Target an assignment or an exam to its course's Assignments and exams."
  (+notes--capture-at (+notes--capture-course) "Assignments and exams"))

(declare-function org-agenda-files "org")
(declare-function org-fc-review "org-fc-review")
(declare-function +notes--agenda-files-refresh-h "roam")

(defvar +notes--university-courses nil
  "(FOLDER . TITLE) of each active course, read once for each block of
the University view rather than for each of its items.")

;;;###autoload
(defun +notes--university-files ()
  "The agenda files under areas/university/: the courses, the lectures
with a task, the University document when it holds one."
  (setq +notes--university-courses
        (mapcar (lambda (course) (cons (file-name-directory course) (+notes--project-title course)))
                (+notes--course-files)))
  (+notes--agenda-files-refresh-h)
  (let ((dir (expand-file-name "areas/university/" org-roam-directory)))
    (seq-filter (lambda (file) (file-in-directory-p file dir))
                (mapcar #'expand-file-name (org-agenda-files t)))))

;;;###autoload
(defun +notes--university-group (item)
  "The University agenda's group of ITEM: the title of the active course
whose folder holds its file, else University."
  (let* ((marker (or (get-text-property 0 'org-hd-marker item)
                     (get-text-property 0 'org-marker item)))
         (file (and marker (buffer-file-name (marker-buffer marker))))
         (course (and file (seq-find (lambda (course) (file-in-directory-p file (car course)))
                                     +notes--university-courses))))
    (if course (cdr course) "University")))

;;;###autoload
(defun +notes/course-review ()
  "Review the cards of a course: the one this note belongs to, else one
picked among the active courses."
  (interactive)
  (org-fc-review (list :paths (list (file-name-directory (+notes--read-course (current-buffer)))))))
