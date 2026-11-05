;;; private/git/autoload/live.el -*- lexical-binding: t; -*-
;;
;; A file's changes shown in place while it is edited: added lines
;; tinted, removed lines drawn above them as text that is not in the
;; buffer. One `git diff' of the buffer as it stands against the
;; baseline, run in the background after a pause in typing; each hunk
;; is one overlay, and a hunk that did not change keeps its overlay, so
;; a redraw touches only what moved. The same engine feeds the split
;; view (split.el), which draws the hunks on two sides instead.

(declare-function +ai-turn-tree "../../ai/autoload/turn")
(declare-function +git-split-mode "split")
(declare-function diff-hl-hunk-overlay-at "diff-hl")
(declare-function diff-hl-search-next-hunk "diff-hl")
(defvar +git-split-mode)
(defvar +git-live-delay)
(defvar +git-live-max-size)
(defvar +git-live-mode-map)

(defvar-local +git-live-baseline 'index
  "What this buffer's view compares with: `index', `head', the agent's
turn as `agent', or a commit as (commit . HASH).")
(put '+git-live-baseline 'permanent-local t)

(defvar-local +git--live-kind nil
  "`live' or `split' while the engine runs in this buffer, else nil.")

(defvar-local +git--live-root nil
  "The git toplevel of this buffer's file, a directory name.")

(defvar-local +git--live-rel nil
  "This buffer's file relative to `+git--live-root'.")

(defvar-local +git--live-label nil
  "How the modeline names the baseline: index, HEAD, a short hash.")

(defvar-local +git--live-blob nil
  "The baseline's blob id, `empty' for none, or nil before it is known.")

(defvar-local +git--live-base-file nil
  "The temp file holding the baseline's text.")

(defvar-local +git--live-process nil
  "The diff being taken.")

(defvar-local +git--live-timer nil
  "The one-shot timer of the next diff.")

(defvar-local +git--live-resolve nil
  "Non-nil when the baseline is to be looked up again before the diff.")

(defvar-local +git--live-tick nil
  "The buffer's tick the shown hunks were diffed at.")

(defvar-local +git--live-retried nil
  "Non-nil once a missing base file was written again for this diff.")

(defvar-local +git--live-hunks nil
  "The last diff's hunks, in order.")

(defvar-local +git--live-overlays nil
  "The overlays the last diff left in this buffer, in order.")

(defvar-local +git--live-watch nil
  "The file-notify watch on this buffer's file.")

(defvar-local +git--live-gitdir nil
  "The repository's git dir this buffer's view watches.")

(defvar-local +git--live-draw-function #'+git--live-draw-inline
  "How the hunks are drawn: in place, or by the split view.")

(defconst +git--live-hooks
  '((after-change-functions . +git--live-changed-h)
    (after-revert-hook . +git--live-reverted-h)
    (window-buffer-change-functions . +git--live-shown-h)
    (window-selection-change-functions . +git--live-selected-h)
    (window-scroll-functions . +git--live-scrolled-h)
    (kill-buffer-hook . +git--live-stop-h)
    (change-major-mode-hook . +git--live-stop-h)
    (clone-indirect-buffer-hook . +git--live-cloned-h)
    (after-set-visited-file-name-hook . +git--live-renamed-h))
  "The engine's buffer-local hooks, as (HOOK . FUNCTION).")

(defvar +git--live-buffers nil
  "Buffers the engine runs in.")

(defvar +git--live-repo-watches (make-hash-table :test #'equal)
  "Git dir to (WATCH . BUFFERS): one watch per repository with a view.")

(cl-defstruct (+git--hunk (:constructor +git--hunk-make)
                          (:copier nil))
  "One hunk of a -U0 diff: the old lines' start and count, the new
lines' start and count, and the removed text."
  old-start old-count new-start new-count old-text)


;;
;;; git

(defun +git--live-git (&rest args)
  "Run git with ARGS in the toplevel; its output, or nil when it fails."
  (let ((default-directory (or +git--live-root default-directory)))
    (with-temp-buffer
      (when (zerop (apply #'call-process "git" nil (list t nil) nil args))
        (string-trim-right (buffer-string))))))

(defun +git--live-toplevel (dir)
  "The git toplevel of DIR as a directory name, or nil."
  (let ((default-directory dir))
    (when-let* ((top (with-temp-buffer
                       (and (zerop (call-process "git" nil (list t nil) nil
                                                 "rev-parse" "--show-toplevel"))
                            (string-trim-right (buffer-string))))))
      (and (not (string-empty-p top))
           (file-name-as-directory (expand-file-name top))))))

;;;###autoload
(defun +git--live-refusal ()
  "Why this buffer cannot have a view, or nil, setting its toplevel."
  (cond ((not buffer-file-name) "This buffer has no file")
        ((file-remote-p buffer-file-name) "Not for remote files")
        ((> (buffer-size) +git-live-max-size)
         (format "Too large for a view: over %d characters" +git-live-max-size))
        ((bound-and-true-p +core-long-lines-p) "Lines too long for a view")
        ((save-excursion
           (save-restriction
             (widen)
             (goto-char (point-min))
             (search-forward "\0" (min (point-max) 8000) t)))
         "A binary file")
        ((not (setq +git--live-root
                    (+git--live-toplevel (file-name-directory buffer-file-name))))
         "Not in a git repository")))


;;
;;; The baseline

(defun +git--live-object ()
  "The baseline object of this buffer's file, as git names it, and its
label for the modeline, as (OBJECT . LABEL); OBJECT is nil when there is
none, such as an agent's turn not taken yet."
  (let ((rel +git--live-rel))
    (pcase +git-live-baseline
      ('index
       ;; Unmerged: the index holds the conflict's stages, not one text.
       (if (not (string-empty-p (or (+git--live-git "ls-files" "-u" "--" rel) "")))
           (cons (concat "HEAD:" rel) "HEAD, unmerged")
         (cons (concat ":" rel) "index")))
      ('head (cons (concat "HEAD:" rel) "HEAD"))
      ('agent
       (let ((turn (and (fboundp '+ai-turn-tree) (+ai-turn-tree +git--live-root))))
         (cons (and turn (concat (car turn) ":" rel))
               (if turn (format-time-string "agent turn %H:%M" (cdr turn))
                 "agent turn, none"))))
      (`(commit . ,hash) (cons (concat hash ":" rel) (substring hash 0 (min 7 (length hash))))))))

(defun +git--live-write-base (blob)
  "Write BLOB's text, or nothing for `empty', to the base file."
  (unless +git--live-base-file
    (setq +git--live-base-file (make-temp-file "git-live-")))
  (if (eq blob 'empty)
      (let ((coding-system-for-write 'no-conversion))
        (write-region "" nil +git--live-base-file nil 'quiet))
    (let ((default-directory +git--live-root))
      (call-process "git" nil (list :file +git--live-base-file) nil
                    "cat-file" "blob" blob))))

(defun +git--live-resolve-baseline ()
  "Look the baseline up; write its text when it changed.
Non-nil when it did."
  (pcase-let* ((`(,object . ,label) (+git--live-object))
               (blob (or (and object
                              (+git--live-git "rev-parse" "--verify" "--quiet" object))
                         'empty)))
    (let ((renamed (not (equal label +git--live-label))))
      (setq +git--live-label label)
      (cond ((not (equal blob +git--live-blob))
             (+git--live-write-base blob)
             (setq +git--live-blob blob)
             (run-hooks '+git--live-baseline-functions)
             t)
            ;; The same text under another name: the hunks on show stand.
            (renamed
             (when +git--live-tick
               (+git--live-set-status (length +git--live-hunks)))
             (run-hooks '+git--live-label-functions)
             nil)))))

(defvar-local +git--live-baseline-functions nil
  "Run in the buffer after its baseline's text changed.")

(defvar-local +git--live-label-functions nil
  "Run in the buffer after its baseline's name changed and its text did not.")


;;
;;; The diff

;;;###autoload
(defun +git--live-coding ()
  "The coding system the buffer is sent to git in and read back with."
  (let ((coding (or buffer-file-coding-system 'utf-8-unix)))
    (if (memq (coding-system-base coding) '(undecided no-conversion raw-text))
        'utf-8-unix
      coding)))

(defun +git--live-diff ()
  "Diff the buffer as it stands against the baseline, in the background."
  (unless (process-live-p +git--live-process)
    (let* ((buffer (current-buffer))
           (tick (buffer-chars-modified-tick))
           (coding (+git--live-coding))
           (out nil)
           (errors nil)
           (err (make-pipe-process :name "git-live-errors" :buffer nil :noquery t
                                   :filter (lambda (_proc string) (push string errors))
                                   :sentinel #'ignore))
           (default-directory +git--live-root))
      (setq +git--live-process
            (make-process
             :name "git-live" :buffer nil :stderr err :noquery t
             :connection-type 'pipe
             :coding (cons coding coding)
             :command (list "git" "--no-pager" "diff" "--no-index" "--no-color"
                            "--no-ext-diff" "--histogram" "-U0" "--"
                            +git--live-base-file "-")
             :filter (lambda (_proc string) (push string out))
             :sentinel
             (lambda (proc _event)
               (unless (process-live-p proc)
                 (unwind-protect
                     (when (buffer-live-p buffer)
                       (with-current-buffer buffer
                         (when (eq proc +git--live-process)
                           (setq +git--live-process nil)
                           (+git--live-answer (process-exit-status proc)
                                              (apply #'concat (nreverse out))
                                              (apply #'concat (nreverse errors))
                                              tick))))
                   (delete-process err))))))
      (save-restriction
        (widen)
        (process-send-region +git--live-process (point-min) (point-max)))
      (process-send-eof +git--live-process))))

(defun +git--live-answer (status out errors tick)
  "Take git's answer: exit STATUS, its OUT and ERRORS, for TICK."
  (cond
   ((null +git--live-kind))
   ((/= tick (buffer-chars-modified-tick))
    ;; The buffer moved on while git worked: this answer is for text
    ;; that is gone.
    (+git--live-schedule))
   ;; git exits 1 for a difference and for a base it cannot read; only
   ;; a difference prints one, and a good answer says nothing on stderr.
   ((and (string-empty-p (or errors ""))
         (or (eql status 0)
             (and (eql status 1) (string-prefix-p "diff --git" out))))
    (setq +git--live-retried nil)
    (if (string-match-p "^Binary files " out)
        (progn (message "A binary file: no view")
               (+git--live-stop-h))
      (let ((hunks (+git--live-parse out)))
        (setq +git--live-hunks hunks
              +git--live-tick tick)
        (funcall +git--live-draw-function hunks)
        (+git--live-set-status (length hunks))
        (+git--live-schedule-refine))))
   ((and (not +git--live-retried) +git--live-base-file
         (not (file-exists-p +git--live-base-file)))
    (setq +git--live-retried t
          +git--live-blob nil)
    (+git--live-resolve-baseline)
    (+git--live-diff))
   (t
    ;; The hunks on show are not this text's: the next run diffs again.
    (setq +git--live-tick nil)
    (+git--live-set-status
     "error" (car (split-string (string-trim (or errors "")) "\n"))))))

;;;###autoload
(defun +git--live-parse (out)
  "The hunks of OUT, git's -U0 answer, in order."
  (let (hunks)
    (with-temp-buffer
      (insert out)
      (goto-char (point-min))
      (while (re-search-forward
              "^@@ -\\([0-9]+\\)\\(?:,\\([0-9]+\\)\\)? \\+\\([0-9]+\\)\\(?:,\\([0-9]+\\)\\)? @@"
              nil t)
        (let ((old-start (string-to-number (match-string 1)))
              (old-count (if (match-string 2) (string-to-number (match-string 2)) 1))
              (new-start (string-to-number (match-string 3)))
              (new-count (if (match-string 4) (string-to-number (match-string 4)) 1))
              old new)
          (forward-line 1)
          (while (memq (char-after) '(?- ?+ ?\\))
            (pcase (char-after)
              (?- (push (buffer-substring (1+ (point)) (line-end-position)) old))
              (?+ (push (buffer-substring (1+ (point)) (line-end-position)) new)))
            (forward-line 1))
          ;; Lines equal on both sides differ only in the newline at the
          ;; end of the file, which nothing on screen shows.
          (unless (equal old new)
            (push (+git--hunk-make
                   :old-start old-start :old-count old-count
                   :new-start new-start :new-count new-count
                   :old-text (mapconcat (lambda (line) (concat line "\n"))
                                        (nreverse old) ""))
                  hunks)))))
    (nreverse hunks)))


;;
;;; Drawing

;;;###autoload
(defun +git--live-spans (hunks &optional old)
  "Each of HUNKS with the buffer region of its new lines, or its old
lines with OLD, as (HUNK BEG . END). A hunk with no lines on that side
is empty at the line that follows it."
  (save-excursion
    (save-restriction
      (widen)
      (goto-char (point-min))
      (let ((line 1) spans)
        (dolist (hunk hunks)
          (let* ((count (if old (+git--hunk-old-count hunk) (+git--hunk-new-count hunk)))
                 (start (if old (+git--hunk-old-start hunk) (+git--hunk-new-start hunk)))
                 (first (if (zerop count) (1+ start) start)))
            (forward-line (- first line))
            (setq line first)
            (let ((beg (point)))
              (push (cons hunk (cons beg (if (zerop count) beg
                                           (save-excursion (forward-line count) (point)))))
                    spans))))
        (nreverse spans)))))

;;;###autoload
(defun +git--live-delete-overlay (overlay)
  "Delete OVERLAY, the word marks and the lines above that belong to it."
  (mapc #'delete-overlay (overlay-get overlay '+git-live-words))
  (dolist (property '(+git-live-above +git-live-numberless))
    (when-let* ((other (overlay-get overlay property)))
      (delete-overlay other)))
  (delete-overlay overlay))

(defun +git--live-top (overlay pos text)
  "TEXT, whole lines, as drawn before POS for OVERLAY.
Above the buffer's first line, Emacs would number the first row drawn,
TEXT's, and leave the line itself blank: with absolute line numbers the
rows of that line get none of Emacs's, TEXT's lines blanks as wide, and
the line its 1. Elsewhere, TEXT as it is, and the first line's numbers
are Emacs's again."
  (when-let* ((numberless (overlay-get overlay '+git-live-numberless)))
    ;; Gone first: Emacs measures its numbers on the window's first lines.
    (delete-overlay numberless)
    (overlay-put overlay '+git-live-numberless nil))
  (if (not (and (= pos (point-min)) (eq display-line-numbers t)))
      text
    ;; Emacs pads a number to its width and one more column, then a
    ;; space, in the face `line-number'.
    (let* ((window (get-buffer-window (current-buffer) t))
           (width (if window
                      (with-selected-window window (line-number-display-width))
                    (max (or display-line-numbers-width 0)
                         (length (number-to-string (frame-height))))))
           (blank (propertize (make-string (+ width 2) ?\s) 'face 'line-number))
           (numberless (make-overlay (point-min) (min (1+ (point-min)) (point-max))))
           (start 0) lines)
      (overlay-put numberless '+git-live t)
      (overlay-put numberless 'display-line-numbers-disable t)
      (overlay-put overlay '+git-live-numberless numberless)
      (while (string-match "\n" text start)
        (push (concat blank (substring text start (match-end 0))) lines)
        (setq start (match-end 0)))
      (concat (apply #'concat (nreverse lines))
              ;; An empty buffer has no line to number.
              (and (< (point-min) (point-max))
                   (propertize (concat (string-pad "1" (1+ width) nil t) " ")
                               'face 'line-number))))))

;;;###autoload
(defun +git--live-put-above (overlay pos text)
  "Draw TEXT, whole lines, above the line that starts at POS, for OVERLAY.
They are drawn on the newline that ends the line before, so the line at
POS keeps its number and TEXT's lines show none, as VS Code draws them;
before POS when no line is above it."
  (let ((above (overlay-get overlay '+git-live-above)))
    (if (and (> pos (point-min)) (eq (char-before pos) ?\n))
        (progn
          (unless (and above (overlay-buffer above))
            ;; Text typed at the end of that line stays outside it.
            (setq above (make-overlay (1- pos) pos nil t nil))
            (overlay-put above '+git-live t)
            (overlay-put overlay '+git-live-above above))
          (+git--live-top overlay pos nil)
          (overlay-put above 'display (concat "\n" text)))
      (when above
        (delete-overlay above)
        (overlay-put overlay '+git-live-above nil))
      (overlay-put overlay 'before-string (+git--live-top overlay pos text)))))

;;;###autoload
(defun +git--live-reconcile (existing specs make)
  "Overlays for SPECS, keeping those of EXISTING that already match.
Each spec is (BEG END . IDENTITY); an overlay matches when it spans BEG
to END now and was made for an equal IDENTITY. MAKE is called with a
spec for each one that does not match. The others of EXISTING go."
  (let ((old (make-hash-table :test #'equal))
        result)
    (dolist (overlay existing)
      (when (overlay-buffer overlay)
        (puthash (cl-list* (overlay-start overlay) (overlay-end overlay)
                        (overlay-get overlay '+git-live-identity))
                 overlay old)))
    (dolist (spec specs)
      (let ((overlay (gethash spec old)))
        (if overlay
            (remhash spec old)
          (setq overlay (funcall make spec))
          (overlay-put overlay '+git-live-identity (cddr spec)))
        (push overlay result)))
    (maphash (lambda (_key overlay) (+git--live-delete-overlay overlay)) old)
    (nreverse result)))

(defun +git--live-ghost (text at)
  "TEXT drawn as removed lines, at AT."
  (concat (and (= at (point-max))
               (save-excursion (goto-char at) (not (bolp)))
               "\n")
          (propertize text 'face '+git-live-removed)))

;;;###autoload
(defun +git--live-draw-inline (hunks)
  "Draw HUNKS in place: new lines tinted, removed ones above them."
  (setq +git--live-overlays
        (+git--live-reconcile
         +git--live-overlays
         (mapcar (pcase-lambda (`(,hunk ,beg . ,end))
                   (cl-list* beg end (+git--hunk-new-count hunk)
                          (+git--hunk-old-text hunk)))
                 (+git--live-spans hunks))
         (pcase-lambda (`(,beg ,end ,_count . ,old-text))
           (let ((overlay (make-overlay beg end nil nil nil)))
             (overlay-put overlay '+git-live t)
             (overlay-put overlay '+git-live-old old-text)
             (overlay-put overlay 'priority -60)
             (when (< beg end)
               (overlay-put overlay 'face '+git-live-added))
             (unless (string-empty-p old-text)
               (+git--live-put-above overlay beg (+git--live-ghost old-text beg)))
             overlay)))))


;;
;;; The words that changed

;; Marked only in the hunks a window shows, and once per text: smerge
;; runs a diff of its own, with two temp files, for every hunk it
;; refines. A timer does it, so neither a keystroke nor a redisplay
;; waits for those diffs.

(defvar +git-live-refine)
(defvar +git-live-refine-max-lines)
(defvar smerge-refine-shadow-cursor)

(defvar-local +git--live-refine-timer nil
  "The one-shot timer that marks the changed words of the hunks on screen.")

(defvar-local +git--live-refine-function #'+git--live-refine-inline
  "How one hunk's changed words are marked: in place, or on two sides.")

;;;###autoload
(defun +git--live-refine-pair (old-beg old-end new-beg new-end)
  "Mark the words that changed from OLD-BEG..OLD-END to NEW-BEG..NEW-END,
markers that may be in two buffers. The word overlays made, as
\(REMOVED . ADDED)."
  (require 'smerge-mode)
  (let ((old-buffer (marker-buffer old-beg))
        (new-buffer (marker-buffer new-beg)))
    (cl-flet ((made (buffer beg end before face)
                (with-current-buffer buffer
                  (let (words)
                    ;; smerge also leaves an overlay over each whole
                    ;; region, with its shadow cursor's sensor on it.
                    (dolist (overlay (overlays-in beg end))
                      (unless (memq overlay before)
                        (if (and (overlay-get overlay '+git-live-word)
                                 (< (overlay-start overlay) (overlay-end overlay)))
                            (progn (overlay-put overlay 'face face)
                                   (overlay-put overlay 'priority -55)
                                   (push overlay words))
                          (delete-overlay overlay))))
                    words))))
      (let ((before-old (with-current-buffer old-buffer (overlays-in old-beg old-end)))
            (before-new (with-current-buffer new-buffer (overlays-in new-beg new-end)))
            (smerge-refine-shadow-cursor nil))
        (smerge-refine-regions old-beg old-end new-beg new-end nil nil
                               '((+git-live-word . removed))
                               '((+git-live-word . added)))
        (cons (made old-buffer old-beg old-end before-old '+git-live-removed-word)
              (made new-buffer new-beg new-end before-new '+git-live-added-word))))))

;;;###autoload
(defun +git--live-refine-inline (overlay)
  "Mark the changed words of OVERLAY's hunk, in the buffer and in the
removed lines drawn above it."
  (let* ((beg (overlay-start overlay))
         (end (overlay-end overlay))
         (old (overlay-get overlay '+git-live-old))
         (ghost (+git--live-ghost old beg))
         (offset (- (length ghost) (length old)))
         (new-beg (copy-marker beg))
         (new-end (copy-marker end))
         added)
    (mapc #'delete-overlay (overlay-get overlay '+git-live-words))
    (with-temp-buffer
      (insert old)
      (pcase-let ((`(,removed . ,new-words)
                   (+git--live-refine-pair (copy-marker (point-min)) (copy-marker (point-max))
                                           new-beg new-end)))
        (dolist (word removed)
          (add-face-text-property (+ offset (1- (overlay-start word)))
                                  (+ offset (1- (overlay-end word)))
                                  '+git-live-removed-word nil ghost))
        (setq added new-words)))
    (set-marker new-beg nil)
    (set-marker new-end nil)
    (+git--live-put-above overlay beg ghost)
    (overlay-put overlay '+git-live-words added)))

(defun +git--live-refinable-p (overlay)
  "Non-nil when OVERLAY's hunk has lines on both sides, few enough."
  (let ((old (overlay-get overlay '+git-live-old))
        (beg (overlay-start overlay))
        (end (overlay-end overlay)))
    (and (< beg end)
         (not (string-empty-p old))
         (<= (count-lines beg end) +git-live-refine-max-lines)
         (<= (cl-count ?\n old) +git-live-refine-max-lines))))

(defun +git--live-refine-visible ()
  "Mark the changed words of the hunks the windows show, once per text."
  (when (and +git-live-refine +git--live-kind)
    (dolist (window (get-buffer-window-list (current-buffer) nil t))
      (let* ((from (window-start window))
             (to (save-excursion
                   (goto-char from)
                   (forward-line (window-body-height window))
                   (point))))
        (dolist (overlay +git--live-overlays)
          (when (and (overlay-buffer overlay)
                     (< (overlay-start overlay) to)
                     (> (overlay-end overlay) from)
                     (+git--live-refinable-p overlay))
            (let ((text (buffer-substring-no-properties (overlay-start overlay)
                                                        (overlay-end overlay))))
              (unless (equal text (overlay-get overlay '+git-live-refined))
                (funcall +git--live-refine-function overlay)
                (overlay-put overlay '+git-live-refined text)))))))))

;;;###autoload
(defun +git--live-schedule-refine ()
  "Mark the changed words on screen after a short rest."
  (when (and +git-live-refine (not (timerp +git--live-refine-timer)))
    (let ((buffer (current-buffer)))
      (setq +git--live-refine-timer
            (run-with-idle-timer (if-let* ((idle (current-idle-time)))
                                     (time-add idle 0.1)
                                   0.1)
                                 nil
                                 (lambda ()
                                   (when (buffer-live-p buffer)
                                     (with-current-buffer buffer
                                       (setq +git--live-refine-timer nil)
                                       (+git--live-refine-visible)))))))))

;;;###autoload
(defun +git--live-scrolled-h (_window _start)
  "Mark the words of the hunks scrolled into view, after redisplay."
  (+git--live-schedule-refine))

(defun +git--live-set-status (what &optional detail)
  "Say in the modeline what the view compares with: WHAT is the number
of changes or a word; DETAIL goes in the tooltip."
  (setq +git--live-status
        (propertize (format "[vs %s: %s] " +git--live-label what)
                    'help-echo (or detail "SPC g SPC = changes the baseline")))
  (force-mode-line-update))


;;
;;; When to diff

;;;###autoload
(defun +git--live-schedule (&optional resolve)
  "Diff again after a rest; look the baseline up first with RESOLVE."
  (when resolve
    (setq +git--live-resolve t))
  (unless (timerp +git--live-timer)
    (let ((buffer (current-buffer)))
      ;; An idle timer counts from the start of the rest: one armed while
      ;; Emacs already rests, as for an agent's write, would otherwise
      ;; wait for the next.
      (setq +git--live-timer
            (run-with-idle-timer (if-let* ((idle (current-idle-time)))
                                     (time-add idle +git-live-delay)
                                   +git-live-delay)
                                 nil #'+git--live-run buffer)))))

(defun +git--live-run (buffer)
  "Diff BUFFER now if a window shows it, else when one does."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (setq +git--live-timer nil)
      (cond
       ((not +git--live-kind))
       ;; Hidden: the window that shows it again schedules a run.
       ((not (get-buffer-window buffer t)))
       ;; The base file is not rewritten under a running diff; its answer
       ;; schedules the next run.
       ((process-live-p +git--live-process)
        (+git--live-schedule))
       (t
        (let ((moved (and +git--live-resolve
                          (progn (setq +git--live-resolve nil)
                                 (+git--live-resolve-baseline)))))
          (when (or moved (not (eql +git--live-tick (buffer-chars-modified-tick))))
            (+git--live-diff))))))))

(defun +git--live-changed-h (&rest _)
  "Diff again once typing rests."
  (+git--live-schedule))

(defun +git--live-reverted-h ()
  "Diff the text a revert brought in."
  (+git--live-schedule))

(defun +git--live-shown-h (_window)
  "Catch up with what came while no window showed the buffer, and look
the baseline up again: the index may have moved meanwhile."
  (+git--live-schedule t))

(defun +git--live-selected-h (window)
  "Look the baseline up again when the buffer's window is selected; the
same hook runs when it is left, which needs nothing."
  (when (eq window (selected-window))
    (+git--live-schedule t)))

(defun +git--live-cloned-h ()
  "Leave the view to the buffer this one was cloned from: the watch, the
base file, the process and the old version are its own. The clone keeps
the hooks other packages put in it, and loses what the view drew."
  (save-restriction
    (widen)
    (dolist (overlay (overlays-in (point-min) (point-max)))
      (when (or (overlay-get overlay '+git-live) (overlay-get overlay '+git-live-word))
        (delete-overlay overlay))))
  (pcase-dolist (`(,hook . ,function) +git--live-hooks)
    (remove-hook hook function t))
  (remove-hook 'window-scroll-functions '+git--split-scrolled-h t)
  (dolist (variable '(+git--live-kind +git--live-root +git--live-rel +git--live-label
                      +git--live-blob +git--live-base-file +git--live-process
                      +git--live-timer +git--live-resolve +git--live-tick
                      +git--live-retried +git--live-hunks +git--live-overlays
                      +git--live-watch +git--live-gitdir +git--live-draw-function
                      +git--live-baseline-functions +git--live-label-functions
                      +git--live-refine-timer
                      +git--live-refine-function +git--live-status
                      +git-live-mode +git-split-mode +git--split-base +git--split-file
                      +git--split-overlays +git--split-expect +git--split-static))
    (kill-local-variable variable))
  (when (fboundp 'evil-normalize-keymaps)
    (evil-normalize-keymaps)))

(defun +git--live-renamed-h ()
  "Start the view again for the file's new name."
  (let ((kind +git--live-kind))
    (+git--live-stop)
    (if (+git--live-refusal)
        (+git--live-stop-h)
      (+git--live-start kind))))

(defun +git--live-stop-h ()
  "End the view of a buffer that is going or changing its major mode."
  (cond ((bound-and-true-p +git-live-mode) (+git-live-mode -1))
        ((bound-and-true-p +git-split-mode) (+git-split-mode -1))
        (t (+git--live-stop))))

;;;###autoload
(defun +git--live-refresh-all-h (&rest _)
  "Look every view's baseline up again: magit changed the repository."
  (dolist (buffer +git--live-buffers)
    (when (buffer-live-p buffer)
      (with-current-buffer buffer
        (+git--live-schedule t)))))

;;;###autoload
(defun +git--live-turn-h (root _tree)
  "Move the views on an agent's turn in ROOT to the turn just begun."
  (dolist (buffer +git--live-buffers)
    (when (buffer-live-p buffer)
      (with-current-buffer buffer
        (when (and (eq +git-live-baseline 'agent) (equal +git--live-root root))
          (+git--live-schedule t))))))


;;
;;; Watching the file and the repository

(defun +git--live-file-changed (buffer)
  "Revert BUFFER to its file when another process wrote it, unless it
was modified here (the guard of the AI module's reload)."
  (lambda (_event)
    (when (buffer-live-p buffer)
      (with-current-buffer buffer
        (unless (or (buffer-modified-p)
                    (verify-visited-file-modtime buffer)
                    (not (file-exists-p buffer-file-name)))
          (revert-buffer :ignore-auto :noconfirm :preserve-modes))))))

(defun +git--live-repo-changed (gitdir)
  "Look the baseline up again in the views of GITDIR's repository."
  (lambda (_event)
    (dolist (buffer (cdr (gethash gitdir +git--live-repo-watches)))
      (when (buffer-live-p buffer)
        (with-current-buffer buffer
          (+git--live-schedule t))))))

(defun +git--live-watch-repo ()
  "Count this buffer among the views of its repository, watched once."
  (when-let* ((gitdir (+git--live-git "rev-parse" "--absolute-git-dir")))
    (setq +git--live-gitdir gitdir)
    (let ((entry (gethash gitdir +git--live-repo-watches)))
      (unless entry
        (setq entry (list (ignore-errors
                            (file-notify-add-watch gitdir '(change)
                                                   (+git--live-repo-changed gitdir)))))
        (puthash gitdir entry +git--live-repo-watches))
      (cl-pushnew (current-buffer) (cdr entry)))))

(defun +git--live-unwatch-repo ()
  "Stop counting this buffer; the last view of a repository ends its watch."
  (when-let* ((gitdir +git--live-gitdir)
              (entry (gethash gitdir +git--live-repo-watches)))
    (setcdr entry (delq (current-buffer) (cdr entry)))
    (unless (cdr entry)
      (when (car entry) (file-notify-rm-watch (car entry)))
      (remhash gitdir +git--live-repo-watches)))
  (setq +git--live-gitdir nil))


;;
;;; Starting and stopping

;;;###autoload
(defun +git--live-start (kind)
  "Run the engine in this buffer for KIND, `live' or `split'.
The caller checked `+git--live-refusal', which set the toplevel."
  (when +git--live-kind
    (+git--live-stop))
  (setq +git--live-kind kind
        +git--live-rel (file-relative-name (file-truename buffer-file-name)
                                           (file-truename +git--live-root))
        +git--live-blob nil)
  (cl-pushnew (current-buffer) +git--live-buffers)
  (pcase-dolist (`(,hook . ,function) +git--live-hooks)
    (add-hook hook function nil t))
  (setq +git--live-watch
        (ignore-errors
          (file-notify-add-watch buffer-file-name '(change)
                                 (+git--live-file-changed (current-buffer)))))
  (+git--live-watch-repo)
  (+git--live-resolve-baseline)
  (+git--live-set-status "...")
  (+git--live-diff))

;;;###autoload
(defun +git--live-stop ()
  "Stop the engine in this buffer and take everything it drew away."
  (when (timerp +git--live-timer)
    (cancel-timer +git--live-timer))
  (when (timerp +git--live-refine-timer)
    (cancel-timer +git--live-refine-timer))
  (when (process-live-p +git--live-process)
    (delete-process +git--live-process))
  (mapc #'+git--live-delete-overlay +git--live-overlays)
  (pcase-dolist (`(,hook . ,function) +git--live-hooks)
    (remove-hook hook function t))
  (when +git--live-watch
    (file-notify-rm-watch +git--live-watch))
  (+git--live-unwatch-repo)
  (when (and +git--live-base-file (file-exists-p +git--live-base-file))
    (delete-file +git--live-base-file))
  (setq +git--live-buffers (delq (current-buffer) +git--live-buffers))
  (setq +git--live-kind nil +git--live-timer nil +git--live-process nil
        +git--live-refine-timer nil
        +git--live-overlays nil +git--live-hunks nil +git--live-watch nil
        +git--live-base-file nil +git--live-blob nil +git--live-tick nil
        +git--live-resolve nil +git--live-retried nil +git--live-status nil)
  (force-mode-line-update))


;;
;;; The live view

;;;###autoload
(define-minor-mode +git-live-mode
  "This buffer's changes in place: added lines tinted, removed lines
above them, kept up as the buffer is edited. Compared with the index,
or with what `+git/live-baseline' picked."
  :lighter nil
  :keymap +git-live-mode-map
  (cond
   ((not +git-live-mode) (+git--live-stop))
   ((when-let* ((why (+git--live-refusal)))
      (setq +git-live-mode nil)
      (message "%s" why)))
   (t
    (when (bound-and-true-p +git-split-mode)
      (+git-split-mode -1))
    (setq +git--live-draw-function #'+git--live-draw-inline)
    (+git--live-start 'live)))
  (when (fboundp 'evil-normalize-keymaps)
    (evil-normalize-keymaps)))

;;;###autoload
(defun +git/live ()
  "Show this file's changes in place, kept up as you edit; again to stop."
  (interactive)
  (+git-live-mode (if +git-live-mode -1 1))
  (when +git-live-mode
    (message "Changes against %s" +git--live-label)))


;;
;;; What the view compares with

(declare-function +git--read-commit "commit")

(defun +git--live-restart ()
  "Look the baseline up and diff now, dropping a diff on its way."
  (when (timerp +git--live-timer)
    (cancel-timer +git--live-timer)
    (setq +git--live-timer nil))
  (when (process-live-p +git--live-process)
    (let ((process +git--live-process))
      (setq +git--live-process nil)
      (delete-process process)))
  (+git--live-resolve-baseline)
  (+git--live-set-status "...")
  (+git--live-diff))

;;;###autoload
(defun +git/live-baseline ()
  "Pick what this buffer's view compares with: the index, HEAD, a
commit, or the project as it was when an agent's last turn began. Kept
for the buffer when the view is turned off and on again."
  (interactive)
  (unless buffer-file-name
    (user-error "This buffer has no file"))
  (let* ((root (or +git--live-root
                   (+git--live-toplevel (file-name-directory buffer-file-name))
                   (user-error "Not in a git repository")))
         (choice (completing-read
                  "Compare with: "
                  (append '("Index" "HEAD" "Commit...")
                          (and (fboundp '+ai-turn-tree) '("Agent's turn")))
                  nil t))
         (baseline
          (pcase choice
            ("Index" 'index)
            ("HEAD" 'head)
            ("Commit..."
             (require 'magit)
             (let* ((rev (+git--read-commit "Compare with"))
                    (default-directory root)
                    (hash (+git--live-git "rev-parse" "--verify" "--quiet"
                                          (concat rev "^{commit}"))))
               (unless hash
                 (user-error "No commit %s" rev))
               (cons 'commit hash)))
            ("Agent's turn"
             (if (+ai-turn-tree root)
                 'agent
               (message "No agent turn in this project yet")
               nil)))))
    (when baseline
      (setq +git-live-baseline baseline)
      (if (not +git--live-kind)
          (message "The next view of this buffer compares with %s" choice)
        (+git--live-restart)
        (message "Changes against %s" +git--live-label)))))


;;
;;; Moving through the changes

(defun +git--live-overlay-starts ()
  "Where the view's hunks start, in order."
  (sort (mapcar #'overlay-start
                (seq-filter #'overlay-buffer +git--live-overlays))
        #'<))

;;;###autoload
(defun +git/next-change ()
  "Go to the next change of the view; without one, the fringe's next."
  (interactive)
  (if (not +git--live-kind)
      (call-interactively #'+vc-gutter/next-hunk)
    (let ((here (line-end-position)))
      (if-let* ((next (seq-find (lambda (pos) (> pos here)) (+git--live-overlay-starts))))
          (progn (push-mark nil t) (goto-char next))
        (message "No more changes")))))

;;;###autoload
(defun +git/previous-change ()
  "Go to the previous change of the view; without one, the fringe's."
  (interactive)
  (if (not +git--live-kind)
      (call-interactively #'+vc-gutter/previous-hunk)
    (let ((here (line-beginning-position)))
      (if-let* ((previous (seq-find (lambda (pos) (< pos here))
                                    (nreverse (+git--live-overlay-starts)))))
          (progn (push-mark nil t) (goto-char previous))
        (message "No more changes")))))

(defun +git--live-overlay-at-point ()
  "The view's hunk on point's line."
  (let ((bol (line-beginning-position)))
    (seq-find (lambda (overlay)
                (and (overlay-buffer overlay)
                     (let ((beg (overlay-start overlay))
                           (end (overlay-end overlay)))
                       (if (= beg end) (= beg bol) (and (>= bol beg) (< bol end))))))
              +git--live-overlays)))

;;;###autoload
(defun +git/revert-change ()
  "Put the change on this line back as the baseline has it; without a
view, revert the fringe's hunk."
  (interactive)
  (if (not +git--live-kind)
      (progn
        ;; The fringe's own command fails on these with a Lisp error or
        ;; "No further hunks found", which says nothing of why.
        (cond ((not buffer-file-name)
               (user-error "This buffer has no file"))
              ((and (not (file-remote-p buffer-file-name))
                    (not (+git--live-toplevel (file-name-directory buffer-file-name))))
               (user-error "Not in a git repository"))
              ((not (and (fboundp 'diff-hl-hunk-overlay-at)
                         (or (diff-hl-hunk-overlay-at (point))
                             (diff-hl-search-next-hunk t))))
               (user-error "No change on this line or above it")))
        (call-interactively #'+vc-gutter/save-and-revert-hunk))
    (barf-if-buffer-read-only)
    (if-let* ((overlay (+git--live-overlay-at-point)))
        (let ((beg (overlay-start overlay))
              (end (overlay-end overlay))
              (old (overlay-get overlay '+git-live-old)))
          (save-excursion
            (goto-char beg)
            (delete-region beg end)
            (insert old)))
      (message "No change on this line"))))
