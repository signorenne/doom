;;; private/notes/autoload/roam-db.el -*- lexical-binding: t; -*-
;;
;; The graph's database on a big vault. A full sync, the session's first
;; and the first build of a database, runs in a background Emacs with
;; this one's org-roam settings and rules, into a copy that then takes
;; the database's place; the files this Emacs wrote into the database
;; meanwhile go into the copy first, so no update is lost and the two
;; never write one file. Any Emacs with a connection to the old file
;; opens the new one at its next query. The node list the finder shows
;; is kept until the database changes.
;;
;; The background Emacs loads this file with nothing of Doom around it:
;; plain Emacs Lisp only.

(require 'cl-lib)
(require 'seq)
(require 'subr-x)

(defvar org-roam-directory)
(defvar org-roam-db-location)
(defvar org-roam-db-version)
(defvar org-roam-db-gc-threshold)
(defvar emacsql--transaction-level)
(defvar org-roam-node-display-template)
(defvar org-roam-node-default-sort)
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
(declare-function org-roam-db--close-all "org-roam-db")
(declare-function org-roam-db--get-connection "org-roam-db")
(declare-function emacsql "emacsql")
(declare-function emacsql-live-p "emacsql")
(declare-function emacsql-close "emacsql")
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
meanwhile, :force, :loud, :start, :round, :summary, :timer and :timeout
for a build that gets stuck, :stuck once it was stopped.")

(defvar +notes--roam-build-next nil
  "A build asked for while one ran, to start once it ends: (FORCE . LOUD).")

(defvar +notes--roam-build-touched (make-hash-table :test #'equal)
  "The files this Emacs wrote into the database while a build ran, to
write into the copy before it takes the database's place.")

(defvar +notes--roam-build-result nil
  "How this session's last build ended: nil before the first, done,
failed, or failed-first for a first build.")

(defvar +notes--roam-build-buffer "*roam build*"
  "What the background Emacs says while it runs.")

(defvar +notes--roam-build-log "*roam build log*"
  "What it said, kept when it failed or could not read a note.")

(defvar +notes-roam-build-timeout 1800
  "Seconds a build may run before it is stopped as stuck.")

(defvar +notes--roam-startup-timer nil
  "The timer that starts the session's sync.")

(defconst +notes--roam-db-incomplete 1
  "The application_id of a database this Emacs made itself: it holds only
the notes saved since, until a build replaces it.")

(defvar +notes--roam-db-inodes (make-hash-table :test #'eq :weakness 'key)
  "For each open connection, the inode of the database file it opened.")

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
            :sentinel #'+notes--roam-build-sentinel)))
    ;; Anything that asks fails there rather than wait for ever.
    (process-send-eof (plist-get +notes--roam-build :process))))

(defun +notes--roam-build-stuck (build)
  "Stop BUILD if it still runs, in whichever round: it is stuck."
  (when (and (eq build +notes--roam-build)
             (process-live-p (plist-get build :process)))
    (plist-put build :stuck t)
    (delete-process (plist-get build :process))))

(defun +notes--roam-build-begin (force loud)
  "Start a build: FORCE builds the database anew, LOUD says so."
  ;; Doom's lang/org syncs in this Emacs before the first query; this
  ;; is the session's sync.
  (advice-remove 'org-roam-db-query '+org-roam-try-init-db-a)
  (let* ((target (expand-file-name org-roam-db-location))
         ;; With no file in it, or only those saved since this Emacs
         ;; made it, the database is not the vault yet: the lists wait
         ;; for the build rather than show it. Opening an old one,
         ;; org-roam asks for a sync again: this one is that sync. A
         ;; missing one is not made here, which takes most of 0.1 s.
         (first (or (not (file-exists-p target))
                    (let ((+notes--roam-build '(:opening t)))
                      (condition-case nil
                          (or (zerop (caar (org-roam-db-query [:select (funcall count) :from files])))
                              (eql (caar (org-roam-db-query "PRAGMA application_id"))
                                   +notes--roam-db-incomplete))
                        (error t)))))
         (settings (progn (make-directory (file-name-directory target) t)
                          (+notes--roam-build-clean target)
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
          (setq +notes--roam-build
                (plist-put (plist-put +notes--roam-build :timeout +notes-roam-build-timeout)
                           :timer (run-at-time +notes-roam-build-timeout nil
                                               #'+notes--roam-build-stuck +notes--roam-build)))
          (cond (first (message "Building the roam database in the background; the note lists wait for it"))
                (loud (message "%s the roam database in the background..."
                               (if force "Rebuilding" "Syncing")))))
      (error (+notes--roam-build-fail (error-message-string err))))))

;;;###autoload
(defun +notes--roam-db-sync (&optional force loud)
  "Sync the roam database in a background Emacs; FORCE builds it anew.
LOUD says when it starts and ends, as a first build always does.  One
asked for while a build runs follows it; a quiet one is that build, and
so is a FORCE one when that build makes the database anew already."
  (require 'org-roam)
  (let* ((build +notes--roam-build)
         (anew (or (plist-get build :first) (plist-get build :force)))
         (force (and force (not anew))))
    (cond ((null build) (+notes--roam-build-begin force loud))
          ;; Asked for while the build starts: that build is the one.
          ((plist-get build :opening))
          ((or force loud)
           (setq +notes--roam-build-next
                 (cons (or force (car +notes--roam-build-next))
                       (or loud (cdr +notes--roam-build-next))))
           (when loud
             (message "A roam database sync is running; another follows it"))))))

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
  (if (plist-get +notes--roam-build :stuck)
      (format "it still ran after %d s and was stopped" (plist-get +notes--roam-build :timeout))
    (with-current-buffer +notes--roam-build-buffer
      (save-excursion
        (goto-char (point-max))
        (if (re-search-backward "^.*\\(?:[Ee]rror\\|[Ff]ailed\\|denied\\|[Nn]o such\\|[Cc]annot\\).*$" nil t)
            (match-string-no-properties 0)
          (let ((process (plist-get +notes--roam-build :process)))
            (format "it ended with %s %s" (process-status process)
                    (process-exit-status process))))))))

(defun +notes--roam-build-cleanup (&optional keep-log)
  "End the build: its process, its files and what it said, kept under
the log's name with KEEP-LOG, where the next build does not write."
  (when-let* ((build +notes--roam-build))
    (setq +notes--roam-build nil)
    (when (timerp (plist-get build :timer))
      (cancel-timer (plist-get build :timer)))
    (let ((process (plist-get build :process)))
      (when (process-live-p process)
        (delete-process process)))
    (dolist (file (list (plist-get build :settings) (plist-get build :db)
                        (concat (plist-get build :db) "-journal")))
      (when (file-exists-p file)
        (delete-file file)))
    (when-let* ((buffer (get-buffer +notes--roam-build-buffer)))
      (if (not keep-log)
          (kill-buffer buffer)
        (when-let* ((old (get-buffer +notes--roam-build-log)))
          (kill-buffer old))
        (with-current-buffer buffer
          (rename-buffer +notes--roam-build-log))))))

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
             (if first "built" "synced") why +notes--roam-build-log)
    (+notes--roam-build-follow)))

(defun +notes--roam-build-finish (swap)
  "End the build, the copy taking the database's place when SWAP."
  (let* ((build +notes--roam-build)
         (summary (plist-get build :summary))
         (failed (+notes--roam-build-failed-files))
         (seconds (round (- (float-time) (plist-get build :start)))))
    (when swap
      ;; A connection reads the old file even once it is replaced, and
      ;; org-roam keeps one per graph directory, a daily's capture too.
      (org-roam-db--close-all)
      (rename-file (plist-get build :db) (plist-get build :target) t))
    (+notes--roam-build-cleanup (> failed 0))
    (setq +notes--roam-build-result 'done
          +notes--roam-count nil)
    (let ((unread (if (> failed 0)
                      (format "; %d note%s could not be read, see the buffer %s"
                              failed (if (= failed 1) "" "s") +notes--roam-build-log)
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

(defun +notes--roam-db-discard-outdated ()
  "Delete the database when org-roam has just opened it and found it of an
older schema, which is when it asks for a forced sync; non-nil then.
Left in place, it would fail every query until the build replaced it."
  (when-let* ((conn (org-roam-db--get-connection))
              ((emacsql-live-p conn))
              ((< (or (caar (emacsql conn "PRAGMA user_version")) 0) org-roam-db-version)))
    (emacsql-close conn)
    (delete-file org-roam-db-location)
    t))

(defun +notes--roam-db-sync-a (fn &optional force loud)
  "Sync in a background Emacs, not in this one; FORCE builds the database
anew.  As a command, say when it starts and ends.  A batch Emacs syncs
as org-roam does, FN."
  (interactive (list current-prefix-arg t))
  (cond (noninteractive (funcall fn force))
        ;; A database of an older schema goes; a first build makes it.
        ((and force (+notes--roam-db-discard-outdated))
         (+notes--roam-db-sync nil loud))
        (t (+notes--roam-db-sync force loud))))

(defun +notes--roam-db-follow-a (fn)
  "The connection FN opens, opened again when its database file was
replaced since, by another Emacs's build or by hand: a connection reads
the file it opened even once that is gone.  What this Emacs wrote there
meanwhile is not in the new one, so a sync follows.  A database made
here is marked incomplete: until a build replaces it, it holds only the
notes saved since."
  (let* ((conn (org-roam-db--get-connection))
         (opened (and conn (gethash conn +notes--roam-db-inodes)))
         (inode (file-attribute-inode-number (file-attributes org-roam-db-location)))
         (replaced (and opened (not (equal opened inode))
                        (zerop emacsql--transaction-level)
                        (emacsql-live-p conn))))
    (when replaced
      (emacsql-close conn))
    (setq conn (funcall fn))
    (unless (gethash conn +notes--roam-db-inodes)
      (unless inode
        (emacsql conn (format "PRAGMA application_id = %d" +notes--roam-db-incomplete)))
      (puthash conn (file-attribute-inode-number (file-attributes org-roam-db-location))
               +notes--roam-db-inodes))
    (when replaced
      (run-at-time 0 nil #'+notes--roam-db-sync))
    conn))

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
                +notes--roam-build-log)))

;;
;;; The node list

(defvar +notes--roam-node-cache nil
  "(KEY . CANDIDATES): the node list as the finder shows it, with what
`+notes--roam-node-cache-key' gave when it was made.")

(defun +notes--roam-node-cache-key ()
  "What the node list depends on: the database file as it is on disk,
and how the list is shown."
  (let ((attributes (file-attributes org-roam-db-location)))
    (list (expand-file-name org-roam-db-location)
          (file-attribute-inode-number attributes)
          (file-attribute-modification-time attributes)
          (file-attribute-size attributes)
          org-roam-directory org-roam-node-display-template org-roam-node-default-sort
          ;; The width a candidate is padded to: the frame's under
          ;; vertico (Doom's lang/org), the window's otherwise.
          (if (bound-and-true-p vertico-mode) (frame-width) (window-width))
          (minibufferp))))

(defun +notes--roam-node-cache-a (fn &optional filter-fn sort-fn)
  "The node list FN makes, made again only once the database changed: the
finder opens at once from the second time.  FILTER-FN and SORT-FN apply
to the kept list as FN would apply them."
  (+notes--roam-db-ready)
  (let ((nodes (if (equal (car +notes--roam-node-cache) (+notes--roam-node-cache-key))
                   (cdr +notes--roam-node-cache)
                 (let ((nodes (funcall fn)))
                   (setq +notes--roam-node-cache (cons (+notes--roam-node-cache-key) nodes))
                   nodes))))
    (setq nodes (if filter-fn
                    (seq-filter (lambda (candidate) (funcall filter-fn (cdr candidate))) nodes)
                  (copy-sequence nodes)))
    (if sort-fn (sort nodes sort-fn) nodes)))

;;;###autoload
(defun +notes--roam-db-setup ()
  "Keep a big vault's database out of the way, for `after!' org-roam: the
full syncs in a background Emacs, starting with the session's, the
node list kept, the lists waiting for a first build."
  (+notes--roam-db-rules)
  (advice-remove 'org-roam-db-query '+org-roam-try-init-db-a)
  (advice-add 'org-roam-db :around #'+notes--roam-db-follow-a)
  (advice-add 'org-roam-db-sync :around #'+notes--roam-db-sync-a)
  (advice-add 'org-roam-db-update-file :before #'+notes--roam-build-touch-a)
  (advice-add 'org-roam-db-clear-file :before #'+notes--roam-build-touch-a)
  (advice-add 'org-roam-node-read--completions :around #'+notes--roam-node-cache-a)
  (advice-add 'org-roam-node-list :before #'+notes--roam-db-ready)
  (advice-add 'org-roam-ref-read--completions :before #'+notes--roam-db-ready)
  (add-hook 'kill-emacs-hook #'+notes--roam-build-cleanup)
  ;; Once: a reload of the config sets this up again.
  (when (timerp +notes--roam-startup-timer)
    (cancel-timer +notes--roam-startup-timer))
  (unless (or +notes--roam-build +notes--roam-build-result)
    (setq +notes--roam-startup-timer
          (run-with-idle-timer 1 nil #'+notes--roam-db-startup-h))))

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
          ;; The vault is local: no handler of a remote or compressed
          ;; file has anything to do, only that of an encrypted note,
          ;; which org-roam lists too. Asked about every name, they took
          ;; half of a first build, most in org-roam's search of the load
          ;; path for org-ref at every note.
          (file-name-handler-alist
           (if (file-remote-p org-roam-directory)
               file-name-handler-alist
             (seq-filter (lambda (entry) (memq (cdr entry) '(epa-file-handler age-file-handler)))
                         file-name-handler-alist))))
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
