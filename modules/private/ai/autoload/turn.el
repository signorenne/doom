;;; private/ai/autoload/turn.el -*- lexical-binding: t; -*-
;;
;; The project as it was when an agent's turn began: a git tree of the
;; whole working tree, tracked and untracked files alike, written
;; through a copy of the index so the real one is never touched. The
;; git views compare a file with it to show only what the agent changed
;; since (git/autoload/live.el). Kept in memory, per repository, until
;; the next turn or the end of the session.

(defvar +ai-turn-functions)

(defvar +ai--turn-trees (make-hash-table :test #'equal)
  "Git toplevel to (TREE . TIME): the snapshot of the last turn.")

(defvar +ai--turn-running (make-hash-table :test #'equal)
  "Git toplevels whose snapshot is being taken.")

;;;###autoload
(defun +ai--turn-root (dir)
  "The git toplevel of DIR as a directory name, or nil."
  (when (and dir (file-directory-p dir) (not (file-remote-p dir)))
    (let ((default-directory dir))
      (with-temp-buffer
        (when (zerop (call-process "git" nil (list t nil) nil "rev-parse" "--show-toplevel"))
          (let ((top (string-trim-right (buffer-string))))
            (unless (string-empty-p top)
              (file-name-as-directory (expand-file-name top)))))))))

;;;###autoload
(defun +ai-turn-tree (dir)
  "The snapshot of DIR's repository at the start of the last agent turn,
as (TREE . TIME), or nil. DIR is its toplevel or any directory in it."
  (or (gethash (file-name-as-directory (expand-file-name dir)) +ai--turn-trees)
      (when-let* ((root (+ai--turn-root dir)))
        (gethash root +ai--turn-trees))))

(defun +ai--turn-index (root)
  "The path of ROOT's index, which a worktree keeps in its own git dir."
  (let ((default-directory root))
    (with-temp-buffer
      (when (zerop (call-process "git" nil (list t nil) nil "rev-parse" "--git-path" "index"))
        (expand-file-name (string-trim-right (buffer-string)) root)))))

;;;###autoload
(defun +ai--turn-snapshot (dir)
  "Snapshot the working tree of DIR's repository in the background,
then run `+ai-turn-functions' with its toplevel and the tree. A turn
that begins while the last snapshot is still being taken keeps that one."
  (when-let* ((root (+ai--turn-root dir))
              ((not (gethash root +ai--turn-running)))
              (index (+ai--turn-index root)))
    (let ((temp (make-temp-file "ai-turn-index-"))
          (time (current-time))
          (out nil))
      (puthash root t +ai--turn-running)
      (if (file-exists-p index)
          (copy-file index temp t)
        (delete-file temp))
      (let ((default-directory root)
            (process-environment (cons (concat "GIT_INDEX_FILE=" temp) process-environment)))
        (make-process
         :name "ai-turn-snapshot" :buffer nil :noquery t :connection-type 'pipe
         :command '("sh" "-c" "git add -A && git write-tree")
         :stderr (make-pipe-process :name "ai-turn-errors" :buffer nil :noquery t
                                    :filter #'ignore :sentinel #'ignore)
         :filter (lambda (_proc string) (push string out))
         :sentinel
         (lambda (proc _event)
           (unless (process-live-p proc)
             (remhash root +ai--turn-running)
             (when (file-exists-p temp)
               (delete-file temp))
             (let ((tree (car (last (split-string (apply #'concat (nreverse out)) "\n" t)))))
               (when (and (zerop (process-exit-status proc)) tree)
                 (puthash root (cons tree time) +ai--turn-trees)
                 (run-hook-with-args '+ai-turn-functions root tree))))))))))
