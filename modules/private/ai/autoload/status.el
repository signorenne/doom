;;; private/ai/autoload/status.el -*- lexical-binding: t; -*-
;;
;; Who needs you: a chat or a Claude terminal waiting for a permission,
;; or done while you were elsewhere. The state changes on events only;
;; nothing polls, and the hooks that clear it are on only while it holds
;; something.

(defvar +ai--status-string)
(defvar +ai-notify)
(defvar agent-shell--state)
(defvar agent-shell-display-action)
(declare-function agent-shell-jump-to-latest-permission-button-row "agent-shell")
(declare-function agent-shell-subscribe-to "agent-shell")
(declare-function claude-code-ide--get-buffer-name "claude-code-ide")
(declare-function claude-code-ide-switch-to-buffer "claude-code-ide")

(defvar +ai--attention nil
  "Buffers that need you, as (BUFFER KIND TIME); KIND is permission or done.")

(defun +ai--frame-focused-p (frame)
  "Non-nil when FRAME has the keyboard, or cannot tell, as a terminal
frame cannot: one you look at would otherwise notify all the time."
  (frame-focus-state frame))

(defun +ai--seen-p (buffer kind)
  "Non-nil when you can see BUFFER: in a focused frame's selected window,
or for KIND done in any window of a focused frame."
  (seq-some (lambda (window)
              (let ((frame (window-frame window)))
                (and (+ai--frame-focused-p frame)
                     (or (eq kind 'done)
                         (eq window (frame-selected-window frame))))))
            (get-buffer-window-list buffer nil t)))

(defun +ai--status-project (buffer)
  "The name of BUFFER's project, from its directory."
  (file-name-nondirectory
   (directory-file-name (buffer-local-value 'default-directory buffer))))

(defun +ai--status-update ()
  "Remake the modeline entry from `+ai--attention' and arm the clearing."
  (let* ((permission (seq-find (lambda (entry) (eq (nth 1 entry) 'permission))
                               +ai--attention))
         (entry (or permission (car +ai--attention)))
         (kind (nth 1 entry)))
    (setq +ai--status-string
          (if (not entry)
              ""
            (propertize
             (format " AI %s: %s "
                     (if (cdr +ai--attention)
                         (length +ai--attention)
                       (+ai--status-project (car entry)))
                     (if (eq kind 'permission) "permission" "done"))
             'face (if (eq kind 'permission) '+ai-status-permission '+ai-status-done)
             'help-echo "mouse-1: go to it (SPC l j)"
             'mouse-face 'mode-line-highlight
             'local-map (make-mode-line-mouse-map 'mouse-1 #'+ai/attend)))))
  (if +ai--attention
      (progn
        (add-hook 'window-buffer-change-functions #'+ai--attention-clear-h)
        (add-hook 'window-selection-change-functions #'+ai--attention-clear-h)
        (add-function :after after-focus-change-function #'+ai--attention-clear-h))
    (remove-hook 'window-buffer-change-functions #'+ai--attention-clear-h)
    (remove-hook 'window-selection-change-functions #'+ai--attention-clear-h)
    (remove-function after-focus-change-function #'+ai--attention-clear-h))
  (force-mode-line-update t))

(defun +ai--attention-clear-h (&rest _)
  "Drop the entries whose buffer you can see now, or that are gone."
  (let ((kept (seq-filter (lambda (entry)
                            (and (buffer-live-p (car entry))
                                 (not (+ai--seen-p (car entry) (nth 1 entry)))))
                          +ai--attention)))
    (unless (equal kept +ai--attention)
      (setq +ai--attention kept)
      (+ai--status-update))))

(defun +ai--attention-forget-h ()
  "Drop this buffer's entries as it dies."
  (when (assq (current-buffer) +ai--attention)
    (setq +ai--attention (assq-delete-all (current-buffer) +ai--attention))
    (+ai--status-update)))

(defun +ai--attention-record (buffer kind title body)
  "Note that BUFFER needs you for KIND, unless you can see it.
A desktop notification TITLE, BODY goes once per buffer and kind, until
the entry clears."
  (unless (+ai--seen-p buffer kind)
    (unless (seq-find (lambda (entry) (and (eq (car entry) buffer)
                                           (eq (nth 1 entry) kind)))
                      +ai--attention)
      ;; done means nothing once the same buffer asks for something.
      (setq +ai--attention
            (append (seq-remove (lambda (entry) (eq (car entry) buffer))
                                +ai--attention)
                    (list (list buffer kind (float-time)))))
      (with-current-buffer buffer
        (add-hook 'kill-buffer-hook #'+ai--attention-forget-h nil t))
      (+ai--status-update)
      (when +ai-notify
        (+core-os-notify title body)))))

;;;###autoload
(defun +ai--chat-event (buffer event)
  "Note what the agent-shell EVENT of chat BUFFER asks of you."
  (when (buffer-live-p buffer)
    (let ((kind (pcase (map-elt event :event)
                  ('permission-request 'permission)
                  ('turn-complete 'done)))
          (agent (or (map-nested-elt (buffer-local-value 'agent-shell--state buffer)
                                     '(:agent-config :mode-line-name))
                     "Agent"))
          (project (+ai--status-project buffer)))
      (when kind
        (+ai--attention-record
         buffer kind agent
         (format "%s: %s" project
                 (if (eq kind 'permission) "needs permission" "finished")))))))

;;;###autoload
(defun +ai--chat-status-h ()
  "Tell the status about this chat's permission requests and finished turns."
  (let ((buffer (current-buffer)))
    (dolist (event '(permission-request turn-complete))
      (agent-shell-subscribe-to
       :shell-buffer buffer
       :event event
       :on-event (lambda (event) (+ai--chat-event buffer event))))))

;;;###autoload
(defun +ai--terminal-event (dir kind)
  "Note that DIR's Claude terminal needs you for KIND."
  (when-let* (((require 'claude-code-ide nil t))
              (buffer (get-buffer (claude-code-ide--get-buffer-name
                                   (file-name-as-directory dir)))))
    (+ai--attention-record
     buffer kind "Claude Code"
     (format "%s: %s" (file-name-nondirectory (directory-file-name dir))
             (if (eq kind 'permission) "needs you" "finished")))))

;;;###autoload
(defun +ai/attend ()
  "Go to the chat or terminal that needs you, the one waiting longest.
On a chat, to its permission button."
  (interactive)
  (let* ((entry (car (sort (copy-sequence +ai--attention)
                           (lambda (a b) (< (nth 2 a) (nth 2 b))))))
         (buffer (car entry)))
    (unless entry
      (user-error "Nothing needs you"))
    (cond ((get-buffer-window buffer)
           (select-window (get-buffer-window buffer)))
          ((with-current-buffer buffer (derived-mode-p 'agent-shell-mode))
           (pop-to-buffer buffer agent-shell-display-action))
          (t (with-current-buffer buffer (claude-code-ide-switch-to-buffer))))
    (when (and (eq (nth 1 entry) 'permission)
               (derived-mode-p 'agent-shell-mode))
      (agent-shell-jump-to-latest-permission-button-row))))
