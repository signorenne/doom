;;; private/core/+undo.el -*- lexical-binding: t; -*-
;;
;; Undo as a graph, not a line. Emacs keeps every state a buffer has been
;; in, the ones undone too; u and C-r walk one path through them, and an
;; edit after an undo puts the rest out of their reach. vundo, which Doom
;; installs, draws all of them as a tree to move through: U opens it.

;; One `u' undoes one edit, not a whole insert session.
(setq evil-want-fine-undo t)

;; And typing is undone a word at a time, as in VS Code and Qt Creator.
;; Emacs gathers up to twenty typed characters into one undo step and
;; cuts it wherever the twentieth falls, often mid-word. A step also
;; ends where a new word starts: the letter typed after a space, a
;; bracket or a comma begins the next one.
(defadvice! +core--undo-by-word-a (fn)
  "Keep the undo step ending before the word about to be typed, instead
of running the typing on into it."
  :around #'undo-auto-amalgamate
  (if (and (characterp last-command-event)
           (memq (char-syntax last-command-event) '(?w ?_))
           (not (bobp))
           (not (memq (char-syntax (char-before)) '(?w ?_))))
      ;; What the function does at its twentieth character: the boundary
      ;; before this one stays, and the count starts again from here.
      (setq undo-auto--last-boundary-cause 0
            undo-auto--this-command-amalgamating t)
    (funcall fn)))

(map! :n "U" #'vundo)
(map! :leader :desc "Undo graph as you undo" "t u" #'+core/undo-graph-popup)

(declare-function vundo-popup-mode "vundo-popup")
(declare-function vundo--popup-advice "vundo-popup")

(defun +core/undo-graph-popup ()
  "Show the undo graph for a moment at each undo and redo, or stop.
vundo's popup is a mode of one buffer that changes undo in all of them,
so turning it off from another buffer took two presses; this is one."
  (interactive)
  (require 'vundo-popup)
  (let ((on (not (advice-member-p #'vundo--popup-advice 'undo))))
    (vundo-popup-mode (if on 1 -1))
    (message "The undo graph %s"
             (if on "shows for a moment at each undo" "stays hidden until U"))))


;;
;;; The graph

(defvar +core--undo-moves
  '(vundo-forward vundo-backward vundo-next vundo-previous vundo-stem-root
    vundo-stem-end vundo-next-root vundo-goto-last-saved vundo-goto-next-saved
    +core/undo-graph-down +core/undo-graph-up +core/undo-graph-newer
    +core/undo-graph-start +core/undo-graph-end)
  "The commands that move through the undo graph, and the buffer with them.")

(defvar-local +core--undo-diff-follow nil
  "Non-nil while the diff follows the state the graph is on.")

(after! vundo
  (setq vundo-window-max-height 10)

  ;; The graph is one long line per branch, and its first drawing is
  ;; most of its cost. Every character of it would go through the check
  ;; for a composition, which nothing in a tree of box drawing needs.
  ;; Nor does it need the flash that follows the cursor into a window,
  ;; which looks along that long line for its end.
  (add-hook! 'vundo-mode-hook
    (defun +core--undo-graph-h ()
      "Set up the undo graph's buffer."
      (setq-local auto-composition-mode nil)
      (setq header-line-format
            (let ((key (lambda (k) (propertize k 'face 'help-key-binding))))
              (concat " " (funcall key "h l") " older, newer  "
                      (funcall key "j k") " branch below, above  "
                      (funcall key "H L") " its start, end  "
                      (funcall key "s S") " saved  "
                      (funcall key "d") " what changed  "
                      (funcall key "RET") " keep this  "
                      (funcall key "q") " put it back")))
      (add-hook 'pre-command-hook #'+core--undo-note-trail-h nil t)
      (add-hook 'post-command-hook #'+core--undo-diff-follow-h nil t)))
  (when (modulep! :ui nav-flash)
    (cl-pushnew 'vundo-mode +nav-flash-exclude-modes))

  (+core--undo-graph-keys-h 'vundo))

;; evil-collection gives the graph h j k l and puts vundo's own d back
;; after this module is read, so these go in once it has.
(defun +core--undo-graph-keys-h (mode &rest _)
  "The graph's keys that evil-collection has not got, its d, and the
moves by the drawing in place of vundo's."
  (when (eq mode 'vundo)
    (map! :map vundo-mode-map
          :n [remap evil-next-line]     #'+core/undo-graph-down
          :n [remap evil-previous-line] #'+core/undo-graph-up
          :n [remap evil-forward-char]  #'+core/undo-graph-newer
          :n [remap evil-window-top]    #'+core/undo-graph-start
          :n [remap evil-window-bottom] #'+core/undo-graph-end
          :n "s" #'vundo-goto-last-saved
          :n "S" #'vundo-goto-next-saved
          :n "d" #'+core/undo-diff)
    ;; C-n, C-j and the rest of vundo's own keys for the same moves.
    (map! :map vundo-mode-map
          [remap vundo-next]      #'+core/undo-graph-down
          [remap vundo-previous]  #'+core/undo-graph-up
          [remap vundo-forward]   #'+core/undo-graph-newer
          [remap vundo-stem-root] #'+core/undo-graph-start
          [remap vundo-stem-end]  #'+core/undo-graph-end)))

(add-hook 'evil-collection-setup-hook #'+core--undo-graph-keys-h)

;; vundo's j and k go only to the other branches of the fork just
;; behind you. Each branch is a line of the drawing, so these keys move
;; by the drawing instead: j and k to the line below and above, onto the
;; state drawn nearest, H and L to the ends of the line. l after h goes
;; back the way h came, rather than taking the top branch at every fork.
(declare-function vundo-m-children "vundo")
(declare-function vundo-m-point "vundo")
(declare-function vundo--move-to-node "vundo")
(declare-function vundo--trim-undo-list "vundo")
(declare-function vundo--sans-nil "vundo")
(declare-function vundo-backward "vundo")
(defvar vundo--prev-mod-list)
(defvar vundo--prev-undo-list)
(defvar vundo-after-undo-functions)

(defvar-local +core--undo-trail nil
  "Each fork to the child the graph was last beyond it through.")

(defun +core--undo-note-trail-h ()
  "Note at each fork above the state the graph is on the way down to it,
before a key moves it, so l can follow that way back."
  (when-let* ((mods (bound-and-true-p vundo--prev-mod-list))
              (node (vundo--current-node mods)))
    (unless +core--undo-trail
      (setq +core--undo-trail (make-hash-table :test #'eq :weakness 'key)))
    (let ((parent (vundo-m-parent node)))
      (while parent
        (when (cdr (vundo-m-children parent))
          (puthash parent node +core--undo-trail))
        (setq node parent
              parent (vundo-m-parent node))))))

(defun +core--undo-go (where nothing)
  "Take the graph to the state WHERE returns for the one it is on, or say
NOTHING when that is none. vundo's own moves check the same first: its
check is a macro, and compiling it in would load vundo at every start."
  (unless (derived-mode-p 'vundo-mode)
    (user-error "Not in the undo graph"))
  (unless (buffer-live-p vundo--orig-buffer)
    (user-error "The buffer of this graph is gone"))
  (if (not (eq (vundo--sans-nil (buffer-local-value 'buffer-undo-list
                                                    vundo--orig-buffer))
               (vundo--sans-nil vundo--prev-undo-list)))
      ;; Edited since it was drawn.
      (progn (vundo--refresh-buffer vundo--orig-buffer (current-buffer))
             (message "The graph is drawn again from the text as it is"))
    (let* ((source (vundo--current-node vundo--prev-mod-list))
           (dest (funcall where source)))
      (if (or (null dest) (eq dest source))
          (message "%s" nothing)
        (vundo--move-to-node source dest vundo--orig-buffer vundo--prev-mod-list)
        (vundo--trim-undo-list vundo--orig-buffer dest vundo--prev-mod-list)
        (vundo--refresh-buffer vundo--orig-buffer (current-buffer) 'incremental)
        (run-hook-with-args 'vundo-after-undo-functions vundo--orig-buffer)))))

(defun +core--undo-row ()
  "The states drawn on the line point is on, as (COLUMN . NODE)."
  (let ((end (line-end-position))
        row)
    (save-excursion
      (forward-line 0)
      (while (< (point) end)
        (when-let* ((node (get-text-property (point) 'vundo-node)))
          (push (cons (current-column) node) row))
        (goto-char (next-single-property-change (point) 'vundo-node nil end))))
    row))

(defun +core--undo-across (node lines)
  "The state drawn nearest NODE, LINES lines below it, above when LINES is
negative, or on the last line there is that way; nil when there is none.
Of two as near, the older."
  (save-excursion
    (goto-char (1- (vundo-m-point node)))
    (let ((column (current-column))
          (step (if (< lines 0) -1 1))
          (left (abs lines))
          found)
      (while (and (> left 0)
                  (let ((start (line-beginning-position)))
                    (forward-line step)
                    (/= (line-beginning-position) start)))
        (when-let* ((row (+core--undo-row)))
          (setq left (1- left)
                found nil)
          (pcase-dolist (`(,col . ,candidate) row)
            (let ((distance (abs (- col column))))
              (when (or (null found)
                        (< distance (car found))
                        (and (= distance (car found)) (< col (cadr found))))
                (setq found (list distance col candidate)))))))
      (nth 2 found))))

(defun +core--undo-newer (node count)
  "The state COUNT steps newer than NODE: at a fork, down the branch last
taken beyond it, else the one drawn beside it."
  (let (children)
    (while (and (> count 0) (setq children (vundo-m-children node)))
      (let ((taken (and +core--undo-trail (gethash node +core--undo-trail))))
        (setq node (if (memq taken children) taken (car children))
              count (1- count)))))
  node)

(defun +core/undo-graph-down (count)
  "Go to the branch drawn COUNT lines below, onto the state drawn nearest."
  (interactive "p" vundo-mode)
  (+core--undo-go (lambda (node) (+core--undo-across node count))
                  (if (< count 0) "No branch above" "No branch below")))

(defun +core/undo-graph-up (count)
  "Go to the branch drawn COUNT lines above, onto the state drawn nearest."
  (interactive "p" vundo-mode)
  (+core--undo-go (lambda (node) (+core--undo-across node (- count)))
                  (if (< count 0) "No branch below" "No branch above")))

(defun +core/undo-graph-newer (count)
  "Go COUNT states newer; at a fork, down the branch you came back from."
  (interactive "p" vundo-mode)
  (if (< count 0)
      (vundo-backward (- count))
    (+core--undo-go (lambda (node) (+core--undo-newer node count))
                    "The newest state of this branch")))

(defun +core/undo-graph-start ()
  "Go to the first state of this branch's line."
  (interactive nil vundo-mode)
  (+core--undo-go
   (lambda (node)
     ;; vundo draws a first child beside its parent, the others below.
     (let (parent)
       (while (and (setq parent (vundo-m-parent node))
                   (eq node (car (vundo-m-children parent))))
         (setq node parent)))
     node)
   "The first state of this branch"))

(defun +core/undo-graph-end ()
  "Go to the last state of this branch's line."
  (interactive nil vundo-mode)
  (+core--undo-go
   (lambda (node)
     (while (vundo-m-children node)
       (setq node (car (vundo-m-children node))))
     node)
   "The newest state of this branch"))

;; Drawing the graph makes a lot of garbage, and a collection in the
;; middle of it slows the drawing; it can wait for the next pause.
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

(declare-function vundo-m-parent "vundo")
(declare-function vundo--current-node "vundo")
(defvar vundo--prev-mod-list)
(defvar vundo-diff--marked-node)

(defun +core--undo-diff-follow-h ()
  "Diff the state the graph just moved to, while the diff is on show.
The oldest state has nothing before it: vundo said so at every step
there and left the last diff up, so the diff says it instead. An error
in a command hook takes the hook away, so one is only said."
  (when-let* (((and +core--undo-diff-follow (memq this-command +core--undo-moves)))
              (window (+core--undo-diff-window)))
    (with-demoted-errors "Undo graph diff: %S"
      (if (or (bound-and-true-p vundo-diff--marked-node)
              (vundo-m-parent (vundo--current-node vundo--prev-mod-list)))
          (vundo-diff)
        (with-current-buffer (window-buffer window)
          (let ((inhibit-read-only t))
            (erase-buffer)
            (insert "The oldest state kept: nothing before it to compare with.\n")))))))

;; When what the history recorded no longer matches the text, a step
;; fails, and would fail the same way at every key, q included. A step
;; that fails draws the graph again from the text as it is, and a q that
;; cannot go back keeps the text and closes the graph. vundo sets where
;; q goes back to only when the graph opens, so after a new drawing q
;; keeps the text too.
(declare-function vundo--refresh-buffer "vundo")
(declare-function vundo-confirm "vundo")
(defvar vundo--orig-buffer)
(defvar vundo--roll-back-to-this)

(defun +core--undo-step-safely-a (fn &rest args)
  "Run FN, a step through the undo graph; when the step cannot be made,
say so and draw the graph again from the buffer as it is now."
  (condition-case err
      (apply fn args)
    (error
     (when (and (derived-mode-p 'vundo-mode) (buffer-live-p vundo--orig-buffer))
       (with-demoted-errors "Undo graph: %S"
         (vundo--refresh-buffer vundo--orig-buffer (current-buffer)))
       (setq vundo--roll-back-to-this nil))
     (message "That step cannot be made (%s): the graph is drawn again from the text as it is, and q leaves it so"
              (error-message-string err)))))

(defun +core--undo-quit-safely-a (fn &rest args)
  "Run FN, leaving the undo graph; when the way back cannot be taken, keep
the text as it is and close the graph."
  (condition-case err
      (apply fn args)
    (error
     (when (derived-mode-p 'vundo-mode)
       (vundo-confirm))
     (message "Could not go back to where you started (%s): the text stays as it is, u and C-r still work"
              (error-message-string err)))))

(after! vundo
  (dolist (command (cons 'vundo-diff +core--undo-moves))
    (advice-add command :around #'+core--undo-step-safely-a '((depth . -50))))
  (advice-add 'vundo-quit :around #'+core--undo-quit-safely-a '((depth . -50))))


;;
;;; What an undo changed

;; An undo puts the cursor at one end of what it changed and says no more,
;; so a u that restores a line far off, or a word in the middle of the
;; screen, goes by unseen. The lines it changed light up for a moment,
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
