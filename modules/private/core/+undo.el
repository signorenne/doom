;;; private/core/+undo.el -*- lexical-binding: t; -*-
;;
;; Undo as a graph, not a line. Emacs keeps every state a buffer has been
;; in, the ones undone too; u and C-r walk one path through them, and an
;; edit after an undo puts the rest out of their reach. vundo, which Doom
;; installs, draws all of them as a tree to move through: U opens it.

;; One `u' undoes one edit, not a whole insert session.
(setq evil-want-fine-undo t)

(map! :n "U" #'vundo)


;;
;;; The graph

(defvar +core--undo-moves
  '(vundo-forward vundo-backward vundo-next vundo-previous vundo-stem-root
    vundo-stem-end vundo-next-root vundo-goto-last-saved vundo-goto-next-saved)
  "The commands that move through the undo graph, and the buffer with them.")

(defvar-local +core--undo-diff-follow nil
  "Non-nil while the diff follows the state the graph is on.")

(after! vundo
  (setq vundo-window-max-height 10)

  ;; The graph is one long line per branch, 6 700 characters for three
  ;; thousand states, and its first drawing is most of its cost. Every
  ;; character of it went through the check for a composition, which
  ;; nothing in a tree of box drawing needs: without it the graph opens
  ;; in 300 ms instead of 600. Nor does it need the flash that follows
  ;; the cursor into a window, which looked along that line for its end.
  (add-hook! 'vundo-mode-hook
    (defun +core--undo-graph-h ()
      "Set up the undo graph's buffer."
      (setq-local auto-composition-mode nil)
      (setq header-line-format
            (let ((key (lambda (k) (propertize k 'face 'help-key-binding))))
              (concat " " (funcall key "h l") " older, newer  "
                      (funcall key "j k") " branches  "
                      (funcall key "s S") " saved  "
                      (funcall key "d") " what changed  "
                      (funcall key "RET") " keep this  "
                      (funcall key "q") " put it back")))
      (add-hook 'post-command-hook #'+core--undo-diff-follow-h nil t)))
  (when (modulep! :ui nav-flash)
    (pushnew! +nav-flash-exclude-modes 'vundo-mode))

  (+core--undo-graph-keys-h 'vundo))

;; evil-collection gives the graph h j k l and puts vundo's own d back
;; after this module is read, so these go in once it has.
(defun +core--undo-graph-keys-h (mode &rest _)
  "The graph's keys that evil-collection has not got, and its d."
  (when (eq mode 'vundo)
    (map! :map vundo-mode-map
          :n "s" #'vundo-goto-last-saved
          :n "S" #'vundo-goto-next-saved
          :n "d" #'+core/undo-diff)))

(add-hook 'evil-collection-setup-hook #'+core--undo-graph-keys-h)

;; Drawing the graph makes a lot of garbage, and a collection in the
;; middle of it was a sixth of the wait; it can wait for the next pause.
(defadvice! +core--undo-graph-no-gc-a (fn &rest args)
  :around #'vundo
  (let ((gc-cons-threshold (max gc-cons-threshold (* 256 1024 1024))))
    (apply fn args)))

;; The diff of a state against the one before it, on the right as you
;; move, the way undo-tree shows it: d shows it and d hides it.
(set-popup-rule! "^\\*vundo-diff-" :side 'right :size 0.45 :select nil :quit t :ttl 0)

(defun +core--undo-diff-window ()
  "The window showing the diff of the graph's state, or nil."
  (get-buffer-window (concat "*vundo-diff-" (buffer-name vundo--orig-buffer) "*")))

(defun +core/undo-diff ()
  "Show what the graph's state changed from the one before it, or from
the state marked with m, and keep showing it as you move; again, hide it."
  (interactive nil vundo-mode)
  (if-let* ((window (+core--undo-diff-window)))
      (progn (setq +core--undo-diff-follow nil)
             (quit-window nil window))
    (setq +core--undo-diff-follow t)
    (vundo-diff)))

(defun +core--undo-diff-follow-h ()
  "Diff the state the graph just moved to, while the diff is on show."
  (when (and +core--undo-diff-follow
             (memq this-command +core--undo-moves)
             (+core--undo-diff-window))
    (vundo-diff)))


;;
;;; What an undo changed

;; An undo puts the cursor at one end of what it changed and says no more,
;; so a u that restored a line far off, or a word in the middle of the
;; screen, went by unseen. The lines it changed light up for a moment,
;; after u, C-r and each step through the graph.
(defface +core-undo-changed '((t (:inherit region :extend t)))
  "The lines an undo, a redo or a step in the undo graph just changed."
  :group 'undo)

(defvar +core-undo-flash-time 0.3
  "Seconds the lines an undo changed stay lit; 0 lights none.")

(defvar +core--undo-changed nil
  "Markers (BEG . END) of what the undo running now changed.")

(defun +core--undo-note-h (beg end _length)
  "Keep the span BEG to END the undo running now changed; fifty are plenty."
  (when (length< +core--undo-changed 50)
    (push (cons (copy-marker beg) (copy-marker end t)) +core--undo-changed)))

(defun +core--undo-flash (buffer spans)
  "Light up in BUFFER the lines of SPANS, for `+core-undo-flash-time'."
  (let (lines overlays)
    (with-current-buffer buffer
      (dolist (span spans)
        (push (cons (save-excursion (goto-char (car span)) (line-beginning-position))
                    (save-excursion (goto-char (cdr span)) (line-beginning-position 2)))
              lines)
        (set-marker (car span) nil)
        (set-marker (cdr span) nil))
      (when (and (> +core-undo-flash-time 0) (get-buffer-window buffer))
        ;; Neighbours and overlaps become one stretch of lines.
        (dolist (line (sort lines (lambda (a b) (< (car a) (car b)))))
          (if (and overlays (<= (car line) (overlay-end (car overlays))))
              (move-overlay (car overlays) (overlay-start (car overlays))
                            (max (cdr line) (overlay-end (car overlays))))
            (let ((ov (make-overlay (car line) (cdr line))))
              (overlay-put ov 'face '+core-undo-changed)
              (overlay-put ov 'priority -40)
              (push ov overlays))))
        (run-at-time +core-undo-flash-time nil #'mapc #'delete-overlay overlays)))))

(defun +core--undo-watch-a (fn &rest args)
  "Run FN, an undo, a redo or a step through the undo graph, and light up
the lines it changed in the buffer it changed."
  (let ((buffer (or (bound-and-true-p vundo--orig-buffer) (current-buffer)))
        (+core--undo-changed nil))
    (with-current-buffer buffer
      (add-hook 'after-change-functions #'+core--undo-note-h nil t))
    (unwind-protect (apply fn args)
      (when (buffer-live-p buffer)
        (with-current-buffer buffer
          (remove-hook 'after-change-functions #'+core--undo-note-h t))))
    (when (buffer-live-p buffer)
      (+core--undo-flash buffer +core--undo-changed))))

(after! undo-fu
  (dolist (command '(undo-fu-only-undo undo-fu-only-redo undo-fu-only-redo-all))
    (advice-add command :around #'+core--undo-watch-a)))

(after! vundo
  (dolist (command (cons 'vundo-quit +core--undo-moves))
    (advice-add command :around #'+core--undo-watch-a)))
