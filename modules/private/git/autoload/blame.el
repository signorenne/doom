;;; private/git/autoload/blame.el -*- lexical-binding: t; -*-
;;
;; Who wrote the line point rests on, and when, at the end of it.
;;
;; One `git blame' of the whole buffer, run in the background and kept;
;; each line is then read from that. It is fed the buffer's own text, so
;; an edited buffer is blamed as it stands, and taken again only when
;; the buffer has changed since. blamer, which this replaces, started a
;; second Emacs for every line point rested on, twice, each after
;; searching the whole load path for its own library: a third of the
;; editor's time while moving through a file went there.

(declare-function flymake-diagnostics "flymake")
(defvar +git-blame-line-mode)

(defvar +git-blame-idle 0.5
  "Seconds point rests on a line before its blame is shown.")

(defvar +git-blame-column 40
  "The blame starts at this column, or three past the line's end.")

(defvar +git-blame-summary-length 50
  "The commit summary is cut to this many characters.")

(defface +git-blame-face '((t :inherit shadow :slant italic))
  "The blame at the end of the line."
  :group 'vc)

(defvar-local +git--blame-lines nil
  "The commit behind each line, a vector indexed from 1.")

(defvar-local +git--blame-commits nil
  "Commit to (AUTHOR MAIL TIME SUMMARY).")

(defvar-local +git--blame-tick nil
  "The buffer's modification tick the blame was taken at, or nil.")

(defvar-local +git--blame-failed nil
  "The tick at which git could not blame the buffer: an untracked file.
Tried again once the buffer changes or is saved.")

(defvar-local +git--blame-process nil
  "The blame being taken.")

(defvar-local +git--blame-overlay nil
  "The blame on show.")

(defvar-local +git--blame-shown nil
  "(LINE-START . TICK) of the blame on show.")

(defvar +git--blame-timer nil
  "The one idle timer that shows the blame, in whichever buffer is current.")


;;
;;; Taking the blame

(defun +git--blame-take ()
  "Blame this buffer as it stands, in the background.
git's answer is gathered in a string and its complaints go nowhere: two
buffers killed when git was done died under whatever was walking the
buffer list and waiting on a process meanwhile, eglot connecting a
server among them, which then stopped on \"Selecting deleted buffer\"."
  (unless (process-live-p +git--blame-process)
    (let* ((buffer (current-buffer))
           (tick (buffer-chars-modified-tick))
           ;; The whole file, narrowed or not: git blames the file, and
           ;; its lines are counted from the top of it.
           (size (save-restriction (widen) (line-number-at-pos (point-max))))
           (chunks nil)
           (err (make-pipe-process :name "git-blame-errors" :buffer nil
                                   :noquery t :filter #'ignore :sentinel #'ignore))
           (default-directory (file-name-directory buffer-file-name)))
      (setq +git--blame-process
            (make-process
             :name "git-blame" :buffer nil :stderr err :noquery t
             :connection-type 'pipe
             ;; Sent as the file is written, line endings included, so its
             ;; lines are the ones git compares against the commit.
             :coding (cons 'utf-8-unix (or buffer-file-coding-system 'utf-8-unix))
             :command (list "git" "--no-pager" "blame" "--porcelain"
                            "--contents" "-" "--"
                            (file-name-nondirectory buffer-file-name))
             :filter (lambda (_proc string) (push string chunks))
             :sentinel
             (lambda (proc _event)
               (unless (process-live-p proc)
                 (unwind-protect
                     (when (buffer-live-p buffer)
                       (with-current-buffer buffer
                         (if (zerop (process-exit-status proc))
                             (progn (+git--blame-read
                                     (apply #'concat (nreverse chunks)) tick size)
                                    ;; Answered while point rests: show it
                                    ;; now; mid-movement, wait for the rest.
                                    (when (current-idle-time) (+git--blame-show)))
                           (setq +git--blame-failed tick))))
                   (delete-process err))))))
      (save-restriction
        (widen)
        (process-send-region +git--blame-process (point-min) (point-max)))
      (process-send-eof +git--blame-process))))

(defun +git--blame-read (out tick size)
  "Keep OUT, git blame's porcelain as a string, as this buffer's blame at
TICK, a buffer of SIZE lines."
  (let ((lines (make-vector (+ size 2) nil))
        (commits (make-hash-table :test #'equal))
        info)
    (with-temp-buffer
      (insert out)
      (goto-char (point-min))
      (while (not (eobp))
        (cond
         ;; The line itself, a tab in front: nothing to read.
         ((eq (char-after) ?\t))
         ;; A commit and the line it made, one per line of the file.
         ((looking-at "\\([0-9a-f]\\{40\\}\\) [0-9]+ \\([0-9]+\\)")
          (let ((commit (match-string 1))
                (line (string-to-number (match-string 2))))
            (when (< line (length lines))
              (aset lines line commit))
            (setq info (or (gethash commit commits)
                           (puthash commit (make-vector 4 nil) commits)))))
         ;; What is said about a commit, the first time it appears.
         ((and info (looking-at "\\(author\\|author-mail\\|author-time\\|summary\\) \\(.*\\)"))
          (let ((value (match-string 2)))
            (pcase (match-string 1)
              ("author" (aset info 0 value))
              ("author-mail" (aset info 1 (string-trim value "<" ">")))
              ("author-time" (aset info 2 (string-to-number value)))
              ("summary" (aset info 3 value))))))
        (forward-line 1)))
    (setq +git--blame-lines lines
          +git--blame-commits commits
          +git--blame-tick tick
          +git--blame-failed nil)))


;;
;;; Showing it

(defun +git--blame-age (time)
  "How long ago TIME was, in words."
  (let* ((seconds (- (float-time) time))
         (days (/ seconds 86400.0)))
    (cond ((< seconds 60) "just now")
          ((< seconds 3600) (+git--blame-ago (/ seconds 60) "minute"))
          ((< seconds 86400) (+git--blame-ago (/ seconds 3600) "hour"))
          ((< days 2) "yesterday")
          ((< days 7) (+git--blame-ago days "day"))
          ((< days 30) (+git--blame-ago (/ days 7) "week"))
          ((< days 365) (+git--blame-ago (/ days 30) "month"))
          (t (+git--blame-ago (/ days 365) "year")))))

(defun +git--blame-ago (n unit)
  "N UNITs ago, in words."
  (let ((n (floor n)))
    (if (= n 1)
        (format "a%s %s ago" (if (string-match-p "\\`[aeiou]" unit) "n" "") unit)
      (format "%d %ss ago" n unit))))

(defun +git--blame-text (commit info)
  "What is said of the line COMMIT made, INFO being what git said of it."
  (if (string-match-p "\\`0+\\'" commit)
      "Not committed yet"
    (format "%s, %s: %s"
            (if (or (equal (aref info 1) user-mail-address)
                    (equal (aref info 0) user-full-name))
                "You"
              (or (aref info 0) "?"))
            (if (aref info 2) (+git--blame-age (aref info 2)) "?")
            (truncate-string-to-width (or (aref info 3) "")
                                      +git-blame-summary-length nil nil "..."))))

(defun +git--line-has-diagnostic-p ()
  "Non-nil when flymake has something to say about the line point is on.
It is drawn at the end of the line too, and is the one to read."
  (and (bound-and-true-p flymake-mode)
       (flymake-diagnostics (line-beginning-position) (line-end-position))
       t))

(defun +git--blame-hide ()
  "Take the blame off the line it is on."
  (when (overlayp +git--blame-overlay)
    (delete-overlay +git--blame-overlay))
  (setq +git--blame-overlay nil
        +git--blame-shown nil))

(defun +git--blame-draw ()
  "Put the blame of the line point is on at its end."
  (let* ((line (line-number-at-pos nil t))
         (commit (and (< line (length +git--blame-lines))
                      (aref +git--blame-lines line)))
         (info (and commit (gethash commit +git--blame-commits))))
    (when info
      (let* ((eol (line-end-position))
             (column (save-excursion (goto-char eol) (current-column)))
             (at (max (+ column 3) +git-blame-column))
             (room (- (window-max-chars-per-line) at 1)))
        (+git--blame-hide)
        (when (> room 12)
          (let ((overlay (make-overlay eol eol nil t nil))
                (text (concat (make-string (- at column) ?\s)
                              (propertize (truncate-string-to-width
                                           (+git--blame-text commit info) room nil nil "...")
                                          'face '+git-blame-face))))
            ;; With point at the end of the line, as A leaves it, the
            ;; cursor was drawn after the note; this puts it before.
            (put-text-property 0 1 'cursor t text)
            (overlay-put overlay 'after-string text)
            (setq +git--blame-overlay overlay
                  +git--blame-shown (cons (line-beginning-position)
                                          (buffer-chars-modified-tick)))))))))

(defun +git--blame-show ()
  "Show the blame of the line point rests on, taking the blame first
when the buffer has changed since the last one."
  (with-current-buffer (window-buffer (selected-window))
    (when (and +git-blame-line-mode
               buffer-file-name
               (not +git--blame-shown)
               (not (region-active-p))
               (not (bound-and-true-p evil-insert-state-minor-mode))
               (not (+git--line-has-diagnostic-p)))
      (let ((tick (buffer-chars-modified-tick)))
        (cond ((eql tick +git--blame-tick) (+git--blame-draw))
              ((not (eql tick +git--blame-failed)) (+git--blame-take)))))))

(defun +git--blame-moved-h ()
  "Take the blame off a line point has left, or one that was edited."
  (when (and +git--blame-shown
             (or (/= (car +git--blame-shown) (line-beginning-position))
                 (/= (cdr +git--blame-shown) (buffer-chars-modified-tick))))
    (+git--blame-hide)))

(defun +git--blame-stop-h ()
  "Stop the blame being taken for a buffer that is going."
  (when (process-live-p +git--blame-process)
    (delete-process +git--blame-process)))

(defun +git--blame-forget-h ()
  "Take the blame again next time: saved, or committed."
  (setq +git--blame-tick nil
        +git--blame-failed nil))

;;;###autoload
(defun +git--blame-forget-all-h (&rest _)
  "Take every buffer's blame again when next shown: a commit changed it."
  (dolist (buffer (buffer-list))
    (when (buffer-local-value '+git-blame-line-mode buffer)
      (with-current-buffer buffer
        (+git--blame-forget-h)
        (+git--blame-hide)))))


;;
;;; The mode

;;;###autoload
(define-minor-mode +git-blame-line-mode
  "Who wrote the line point rests on, and when, at the end of it."
  :lighter nil
  (cond
   (+git-blame-line-mode
    (add-hook 'post-command-hook #'+git--blame-moved-h nil t)
    (add-hook 'after-save-hook #'+git--blame-forget-h nil t)
    (add-hook 'kill-buffer-hook #'+git--blame-stop-h nil t)
    ;; Not shown while typing: one shown already goes as insert begins.
    (add-hook 'evil-insert-state-entry-hook #'+git--blame-hide nil t)
    (unless (timerp +git--blame-timer)
      (setq +git--blame-timer
            (run-with-idle-timer +git-blame-idle t #'+git--blame-show))))
   (t
    (remove-hook 'post-command-hook #'+git--blame-moved-h t)
    (remove-hook 'after-save-hook #'+git--blame-forget-h t)
    (remove-hook 'kill-buffer-hook #'+git--blame-stop-h t)
    (remove-hook 'evil-insert-state-entry-hook #'+git--blame-hide t)
    (+git--blame-stop-h)
    (+git--blame-hide)
    (setq +git--blame-lines nil
          +git--blame-commits nil
          +git--blame-tick nil
          +git--blame-failed nil))))
