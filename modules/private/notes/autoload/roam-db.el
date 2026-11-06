;;; private/notes/autoload/roam-db.el -*- lexical-binding: t; -*-
;;
;; The graph's database on a big vault. A full sync, the session's first
;; and the first build of a database, runs in a background Emacs with
;; this one's org-roam settings and rules, into a copy that then takes
;; the database's place; the files this Emacs wrote into the database
;; meanwhile go into the copy first, so no update is lost and the two
;; never write one file.
;;
;; The background Emacs loads this file with nothing of Doom around it:
;; plain Emacs Lisp only.

(require 'cl-lib)
(require 'subr-x)

(defvar org-roam-directory)
(defvar org-roam-db-location)
(defvar org-roam-db-gc-threshold)
(defvar org-link-parameters)
(defvar org-id-track-globally)
(defvar org-element-cache-persistent)
(defvar +notes--roam-count)
(defvar +core-build-niceness)
(declare-function org-get-tags "org")
(declare-function org-link-set-parameters "ol")
(declare-function org-roam-db-query "org-roam-db")
(declare-function org-roam-db-sync "org-roam-db")
(declare-function org-roam-db--close "org-roam-db")
(declare-function org-roam-db-update-file "org-roam-db")
(declare-function org-roam-db-clear-file "org-roam-db")
(declare-function org-roam-file-p "org-roam")
(declare-function +notes--roam-written-links-a "query")
(declare-function +notes--roam-written-citations-a "query")

(defconst +notes--roam-db-file (or load-file-name buffer-file-name)
  "This file, which the background Emacs loads.")

;;
;;; What a note writes into the database

;;;###autoload
(defun +notes--roam-include-node-p ()
  "Whether the heading at point is a node of the graph."
  (let ((tags (org-get-tags)))
    (not (or (member "noroam" tags)
             (member (or (bound-and-true-p org-fc-flashcard-tag) "fc") tags)))))

(defun +notes--roam-db-rules ()
  "Leave a live table's links and citations out of the database, here
and in the Emacs that builds it (autoload/query.el)."
  (advice-add 'org-roam-db-map-links :around #'+notes--roam-written-links-a)
  (advice-add 'org-roam-db-map-citations :around #'+notes--roam-written-citations-a))

(defvar +notes-roam-build-variables
  '(org-roam-directory org-roam-file-extensions org-roam-file-exclude-regexp
    org-roam-list-files-commands org-roam-db-node-include-function
    org-roam-db-extra-links-elements org-roam-db-extra-links-exclude-keys
    org-todo-keywords org-priority-highest org-priority-lowest
    org-priority-default org-use-tag-inheritance
    org-tags-exclude-from-inheritance org-use-property-inheritance
    org-fc-flashcard-tag +notes-block-names)
  "What the background build takes from this Emacs as the build starts:
everything that changes what a note writes into the database.  One not
bound here keeps its default there.  The link types and the rules of
`+notes--roam-db-rules' go along too.")

(defvar +notes--roam-build-link-types nil
  "In the background Emacs, the link types this one knows: Org reads a
link of a type it does not know as another kind of link.")

;;
;;; Building it in the background

(defvar +notes--roam-build nil
  "The build running now, a plist: :process, :db the copy it writes,
:settings what it reads, :target the database the copy replaces,
:directory the graph, :first when there was no database to read
meanwhile, :force, :loud, :start, :round, :summary.")

(defvar +notes--roam-build-next nil
  "A build asked for while one ran, to start once it ends: (FORCE . LOUD).")

(defvar +notes--roam-build-touched (make-hash-table :test #'equal)
  "The files this Emacs wrote into the database while a build ran, to
write into the copy before it takes the database's place.")

(defvar +notes--roam-build-result nil
  "How this session's last build ended: nil before the first, done,
failed, or failed-first for a first build.")

(defvar +notes--roam-build-buffer "*roam build*"
  "What the background Emacs says; kept when the build fails.")

(defun +notes--roam-build-clean (target)
  "Delete what a build of TARGET left a day ago or more: an Emacs that
ended without cleaning up."
  (let ((old (time-subtract nil (days-to-time 1))))
    (dolist (file (directory-files (file-name-directory target) t
                                   (concat "\\`" (regexp-quote (file-name-nondirectory target))
                                           "\\.build-")))
      (when (time-less-p (file-attribute-modification-time (file-attributes file)) old)
        (delete-file file)))))

(defun +notes--roam-build-write-settings (file db)
  "Write FILE, what the background Emacs takes from this one, with DB the
database it writes."
  (let ((coding-system-for-write 'utf-8-unix)
        (print-length nil) (print-level nil) (print-circle nil))
    (with-temp-file file
      (insert ";;; -*- lexical-binding: t; coding: utf-8 -*-\n"
              ";; One build of the roam database, written by autoload/roam-db.el.\n")
      (prin1 `(setq load-path ',load-path
                    native-comp-eln-load-path ',(bound-and-true-p native-comp-eln-load-path)
                    ;; Nothing compiled, nothing written outside the database.
                    native-comp-jit-compilation nil
                    native-comp-enable-subr-trampolines nil
                    org-roam-db-location ,db
                    +notes--roam-build-link-types ',(mapcar #'car org-link-parameters)
                    ,@(cl-loop for var in +notes-roam-build-variables
                               when (boundp var)
                               append (list var (list 'quote (symbol-value var)))))
             (current-buffer))
      (insert "\n"))))

(defun +notes--roam-build-run (files)
  "Start the background Emacs on the build's copy: a full sync, or only
FILES, which this Emacs wrote meanwhile."
  (let ((nice (and (bound-and-true-p +core-build-niceness) (executable-find "nice")))
        ;; Wherever the command came from, a remote buffer too.
        (default-directory (file-name-directory (plist-get +notes--roam-build :target))))
    (setq +notes--roam-build
          (plist-put
           +notes--roam-build :process
           (make-process
            :name "roam-build" :buffer (get-buffer-create +notes--roam-build-buffer)
            :noquery t :connection-type 'pipe
            :command `(,@(and nice (list nice "-n" (number-to-string +core-build-niceness)))
                       ,(expand-file-name invocation-name invocation-directory)
                       "--batch" "-Q" "-l" ,(plist-get +notes--roam-build :settings)
                       "-l" ,(file-name-sans-extension +notes--roam-db-file)
                       "-f" "+notes--roam-build-batch" ,@files)
            :sentinel #'+notes--roam-build-sentinel)))))

(defun +notes--roam-build-begin (force loud)
  "Start a build: FORCE builds the database anew, LOUD says so."
  ;; Doom's lang/org syncs in this Emacs before the first query; this
  ;; is the session's sync.
  (advice-remove 'org-roam-db-query '+org-roam-try-init-db-a)
  (let* ((target (expand-file-name org-roam-db-location))
         ;; With no file in it, the database is not the vault yet: the
         ;; lists wait for the build rather than show it. Opening an old
         ;; one, org-roam asks for a sync again: it follows this one.
         (first (let ((+notes--roam-build '(:opening t)))
                  (zerop (or (ignore-errors
                               (caar (org-roam-db-query [:select (funcall count) :from files])))
                             0))))
         (settings (progn (+notes--roam-build-clean target)
                          (make-temp-file (concat target ".build-") nil ".el")))
         (db (concat (file-name-sans-extension settings) ".db")))
    (clrhash +notes--roam-build-touched)
    (setq +notes--roam-build
          (list :target target :db db :settings settings :directory org-roam-directory
                :first first :force force :loud loud :start (float-time) :round 0))
    (with-current-buffer (get-buffer-create +notes--roam-build-buffer)
      (erase-buffer))
    (condition-case err
        (progn
          ;; Copied here, where nothing writes it now; a missing copy
          ;; is made anew there.
          (unless (or force first)
            (copy-file target db t)
            (when (file-exists-p (concat target "-journal"))
              (copy-file (concat target "-journal") (concat db "-journal") t)))
          (+notes--roam-build-write-settings settings db)
          (+notes--roam-build-run nil)
          (cond (first (message "Building the roam database in the background; the note lists wait for it"))
                (loud (message "%s the roam database in the background..."
                               (if force "Rebuilding" "Syncing")))))
      (error (+notes--roam-build-fail (error-message-string err))))))

;;;###autoload
(defun +notes--roam-db-sync (&optional force loud)
  "Sync the roam database in a background Emacs; FORCE builds it anew.
LOUD says when it starts and ends, as a first build always does.  One
asked for while a build runs follows it; a quiet one is that build."
  (require 'org-roam)
  (if (null +notes--roam-build)
      (+notes--roam-build-begin force loud)
    (when (or force loud)
      (setq +notes--roam-build-next
            (cons (or force (car +notes--roam-build-next))
                  (or loud (cdr +notes--roam-build-next))))
      (when loud
        (message "A roam database sync is running; another follows it")))))

(defun +notes--roam-build-summary ()
  "What the background Emacs said it did, a plist, or nil."
  (with-current-buffer +notes--roam-build-buffer
    (save-excursion
      (goto-char (point-max))
      (when (re-search-backward "^\\+notes-roam-build \\((.*)\\)$" nil t)
        (ignore-errors (car (read-from-string (match-string 1))))))))

(defun +notes--roam-build-failed-files ()
  "How many notes the background Emacs could not read."
  (with-current-buffer +notes--roam-build-buffer
    (how-many "Failed to process" (point-min) (point-max))))

(defun +notes--roam-build-error ()
  "The background Emacs's last error line, or how it ended."
  (with-current-buffer +notes--roam-build-buffer
    (save-excursion
      (goto-char (point-max))
      (if (re-search-backward "^.*\\(?:[Ee]rror\\|[Ff]ailed\\|denied\\|[Nn]o such\\|[Cc]annot\\).*$" nil t)
          (match-string-no-properties 0)
        (let ((process (plist-get +notes--roam-build :process)))
          (format "it ended with %s %s" (process-status process)
                  (process-exit-status process)))))))

(defun +notes--roam-build-cleanup (&optional keep-log)
  "End the build: its process, its files and, unless KEEP-LOG, what it said."
  (when-let* ((build +notes--roam-build))
    (setq +notes--roam-build nil)
    (let ((process (plist-get build :process)))
      (when (process-live-p process)
        (delete-process process)))
    (dolist (file (list (plist-get build :settings) (plist-get build :db)
                        (concat (plist-get build :db) "-journal")))
      (when (file-exists-p file)
        (delete-file file)))
    (unless keep-log
      (when-let* ((buffer (get-buffer +notes--roam-build-buffer)))
        (kill-buffer buffer)))))

(defun +notes--roam-build-follow ()
  "Start the build asked for while the last one ran."
  (when-let* ((next +notes--roam-build-next))
    (setq +notes--roam-build-next nil)
    (+notes--roam-db-sync (car next) (cdr next))))

(defun +notes--roam-build-fail (why)
  "End the build that failed, WHY, keeping the database as it was."
  (let ((first (plist-get +notes--roam-build :first)))
    (+notes--roam-build-cleanup 'keep-log)
    (setq +notes--roam-build-result (if first 'failed-first 'failed))
    (message "The roam database could not be %s: %s; see the buffer %s"
             (if first "built" "synced") why +notes--roam-build-buffer)
    (+notes--roam-build-follow)))

(defun +notes--roam-build-finish (swap)
  "End the build, the copy taking the database's place when SWAP."
  (let* ((build +notes--roam-build)
         (summary (plist-get build :summary))
         (failed (+notes--roam-build-failed-files))
         (seconds (round (- (float-time) (plist-get build :start)))))
    (when swap
      ;; The connection reads the old file even once it is replaced.
      (let ((org-roam-directory (plist-get build :directory)))
        (org-roam-db--close))
      (rename-file (plist-get build :db) (plist-get build :target) t))
    (+notes--roam-build-cleanup (> failed 0))
    (setq +notes--roam-build-result 'done
          +notes--roam-count nil)
    (let ((unread (if (> failed 0)
                      (format "; %d note%s could not be read, see the buffer %s"
                              failed (if (= failed 1) "" "s") +notes--roam-build-buffer)
                    "")))
      (cond ((or (plist-get build :first) (plist-get build :force))
             (message "Roam database %s: %d notes, in %d s%s"
                      (if (plist-get build :first) "built" "rebuilt")
                      (plist-get summary :nodes) seconds unread))
            ((or (plist-get build :loud) (> failed 0))
             (if (zerop (+ (plist-get summary :changed) (plist-get summary :removed)))
                 (message "Roam database: up to date%s" unread)
               (message "Roam database synced: %d file%s changed, %d removed%s"
                        (plist-get summary :changed)
                        (if (= 1 (plist-get summary :changed)) "" "s")
                        (plist-get summary :removed) unread)))))
    (+notes--roam-build-follow)))

(defun +notes--roam-build-end (process)
  "The background Emacs ended: replace the database, or first write
into the copy the files saved meanwhile."
  (let* ((build +notes--roam-build)
         (summary (and (eq (process-status process) 'exit)
                       (zerop (process-exit-status process))
                       (+notes--roam-build-summary))))
    (cond
     ((null summary) (+notes--roam-build-fail (+notes--roam-build-error)))
     (t
      ;; A round of saved files counts only what it wrote.
      (if (zerop (plist-get build :round))
          (setq build (plist-put build :summary summary))
        (plist-put (plist-get build :summary) :nodes (plist-get summary :nodes)))
      (cond
       ;; Nothing changed on disk: the database is what the copy is.
       ((not (or (plist-get build :first) (plist-get build :force)
                 (> (plist-get build :round) 0)
                 (> (+ (plist-get summary :changed) (plist-get summary :removed)) 0)))
        (+notes--roam-build-finish nil))
       ((> (hash-table-count +notes--roam-build-touched) 0)
        (let ((files (hash-table-keys +notes--roam-build-touched)))
          (clrhash +notes--roam-build-touched)
          (setq +notes--roam-build (plist-put build :round (1+ (plist-get build :round))))
          (+notes--roam-build-run files)))
       (t (+notes--roam-build-finish t)))))))

(defun +notes--roam-build-sentinel (process _event)
  "Go on with the build once its background Emacs ends."
  (when (and (not (process-live-p process))
             (eq process (plist-get +notes--roam-build :process)))
    (condition-case err
        (+notes--roam-build-end process)
      (error (+notes--roam-build-fail (error-message-string err))))))

(defun +notes--roam-build-touch-a (&optional file &rest _)
  "Remember FILE, written into the database while a build runs, for the
copy that replaces it."
  (when-let* (((bound-and-true-p +notes--roam-build))
              (file (or file (buffer-file-name (buffer-base-buffer)))))
    (puthash (expand-file-name file) t +notes--roam-build-touched)))

(defun +notes--roam-db-sync-a (fn &optional force loud)
  "Sync in a background Emacs, not in this one; FORCE builds the database
anew.  As a command, say when it starts and ends.  A batch Emacs syncs
as org-roam does, FN."
  (interactive (list current-prefix-arg t))
  (if noninteractive
      (funcall fn force)
    (+notes--roam-db-sync force loud)))

(defun +notes--roam-db-startup-h ()
  "Sync the database once a session, in the background."
  (unless (or +notes--roam-build +notes--roam-build-result)
    (+notes--roam-db-sync)))

;;;###autoload
(defun +notes--roam-db-building ()
  "While the database is built for the first time, how far it is: a
string, empty or \" (N%)\".  nil otherwise."
  (when (plist-get +notes--roam-build :first)
    (or (when-let* ((buffer (get-buffer +notes--roam-build-buffer)))
          (with-current-buffer buffer
            (save-excursion
              (goto-char (point-max))
              ;; The dots too: searching back, a lone last digit matches.
              (when (re-search-backward "\\.\\.\\.\\([0-9]+\\)%$" nil t)
                (format " (%s%%)" (match-string-no-properties 1))))))
        "")))

;;;###autoload
(defun +notes--roam-db-ready (&rest _)
  "Signal a user-error that says so while the database is being built
for the first time, or could not be: until then it is not the vault.
Starts the session's sync if nothing has yet."
  (+notes--roam-db-startup-h)
  (when-let* ((state (+notes--roam-db-building)))
    (user-error "The roam database is being built in the background%s; try again when it is done"
                state))
  (when (eq +notes--roam-build-result 'failed-first)
    (user-error "The roam database could not be built, see the buffer %s; SPC n r s tries again"
                +notes--roam-build-buffer)))

;;;###autoload
(defun +notes--roam-db-setup ()
  "Keep a big vault's database out of the way, for `after!' org-roam: the
full syncs in a background Emacs, starting with the session's, the
lists waiting for a first build."
  (+notes--roam-db-rules)
  (advice-remove 'org-roam-db-query '+org-roam-try-init-db-a)
  (advice-add 'org-roam-db-sync :around #'+notes--roam-db-sync-a)
  (advice-add 'org-roam-db-update-file :before #'+notes--roam-build-touch-a)
  (advice-add 'org-roam-db-clear-file :before #'+notes--roam-build-touch-a)
  (advice-add 'org-roam-node-list :before #'+notes--roam-db-ready)
  (advice-add 'org-roam-ref-read--completions :before #'+notes--roam-db-ready)
  (add-hook 'kill-emacs-hook #'+notes--roam-build-cleanup)
  (run-with-idle-timer 1 nil #'+notes--roam-db-startup-h))

;;
;;; In the background Emacs

(defun +notes--roam-build-hashes ()
  "Each file of the database with its hash."
  (let ((hashes (make-hash-table :test #'equal)))
    (pcase-dolist (`(,file ,hash) (org-roam-db-query [:select [file hash] :from files]))
      (puthash file hash hashes))
    hashes))

(defun +notes--roam-build-batch ()
  "Sync the database the settings name, or write only the files the
command line names, then say what changed.  For `emacs --batch'."
  (let ((files command-line-args-left))
    (setq command-line-args-left nil)
    ;; Nothing asks, nothing besides the database is written.
    (setq enable-local-variables :safe
          enable-local-eval nil
          large-file-warning-threshold nil
          org-id-track-globally nil
          org-element-cache-persistent nil
          org-roam-db-gc-threshold (* 128 1024 1024))
    (require 'org-roam)
    (load (expand-file-name "query" (file-name-directory +notes--roam-db-file)) nil t)
    (dolist (type +notes--roam-build-link-types)
      (unless (assoc type org-link-parameters)
        (org-link-set-parameters type)))
    (+notes--roam-db-rules)
    (let ((before (+notes--roam-build-hashes))
          (changed 0) (removed 0)
          ;; The vault's files are plain and local: no handler of a
          ;; remote, compressed or encrypted file has anything to do.
          ;; Asked about every name, they took half of a first build,
          ;; most in org-roam's search of the load path for org-ref at
          ;; every note.
          (file-name-handler-alist (and (file-remote-p org-roam-directory)
                                        file-name-handler-alist)))
      (if (null files)
          (org-roam-db-sync)
        (dolist (file files)
          (condition-case err
              (if (and (file-exists-p file) (org-roam-file-p file))
                  (org-roam-db-update-file file)
                (org-roam-db-clear-file file))
            (error
             (org-roam-db-clear-file file)
             (message "Failed to process %s with error %s" file (error-message-string err))))))
      (let ((after (+notes--roam-build-hashes)))
        (maphash (lambda (file hash)
                   (unless (equal hash (gethash file before)) (cl-incf changed)))
                 after)
        (maphash (lambda (file _) (unless (gethash file after) (cl-incf removed))) before)
        (princ (format "+notes-roam-build %S\n"
                       (list :files (hash-table-count after)
                             :nodes (caar (org-roam-db-query [:select (funcall count) :from nodes]))
                             :changed changed :removed removed)))))
    (org-roam-db--close)))
