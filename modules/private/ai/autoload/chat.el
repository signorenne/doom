;;; private/ai/autoload/chat.el -*- lexical-binding: t; -*-
;;
;; agent-shell chats: the Emacs tools they reach, the permissions they ask
;; for, and the window the editor works in.

(defvar +ai--chat-permission-request)
(defvar +ai-auto-allowed-tools)
(defvar acp-logging-enabled)
(defvar agent-shell-context-sources)
(defvar agent-shell-mcp-servers)
(defvar agent-shell-preferred-agent-config)
(defvar agent-shell-session-strategy)
(declare-function +ai--tool-root-allowed-p "claude")
(declare-function agent-shell "agent-shell")
(declare-function agent-shell--prompt-input-start "agent-shell-prompt")
(declare-function agent-shell-cwd "agent-shell-project")
(declare-function agent-shell-insert "agent-shell")
(declare-function agent-shell-interrupt "agent-shell")
(declare-function agent-shell-open-transcript "agent-shell")
(declare-function agent-shell-cycle-session-mode "agent-shell")
(declare-function agent-shell-set-session-mode "agent-shell")
(declare-function agent-shell-set-session-model "agent-shell")
(declare-function agent-shell-set-session-thought-level "agent-shell")
(declare-function agent-shell-view-traffic "agent-shell")
(declare-function agent-shell-project-buffers "agent-shell")
(declare-function evil-insert-state "evil-states")
(declare-function agent-shell-subscribe-to "agent-shell")
(declare-function claude-code-ide-mcp-server-ensure-server "claude-code-ide-mcp-server")
(declare-function claude-code-ide-mcp-server-get-config "claude-code-ide-mcp-server")
(declare-function claude-code-ide-mcp-server-get-session-context "claude-code-ide-mcp-server")
(declare-function claude-code-ide-mcp-server-session-ended "claude-code-ide-mcp-server")
(declare-function claude-code-ide-mcp-server-session-started "claude-code-ide-mcp-server")

;;
;;; The editor window

(defun +ai--editor-window-p (window)
  "Non-nil when WINDOW shows code: no chat, diff, terminal or popup."
  (let ((buffer (window-buffer window)))
    (not (or (window-dedicated-p window)
             (and (fboundp '+popup-window-p) (+popup-window-p window))
             (string-match-p "^\\*claude-code\\[" (buffer-name buffer))
             (with-current-buffer buffer
               (derived-mode-p 'agent-shell-mode 'agent-shell-diff-mode
                               'agent-shell-viewport-view-mode
                               'agent-shell-viewport-edit-mode))))))

;;;###autoload
(defun +ai--editor-window ()
  "The window the editor works in, or nil: the most recently used one
of this frame that shows code."
  (seq-find #'+ai--editor-window-p
            (sort (window-list-1 nil 'nomini)
                  (lambda (a b) (> (window-use-time a) (window-use-time b))))))

;;;###autoload
(defun +ai--editor-window-for-display (_buffer _alist)
  "The editor window, as `display-buffer's some-window function wants it.
With none, display-buffer takes the largest window that is not dedicated."
  (+ai--editor-window))


;;
;;; Chat commands

;;;###autoload
(defun +ai--chat-buffer ()
  "This project's chat, the one agent-shell lists first, or nil.
In a chat, that chat."
  (require 'agent-shell)
  (if (derived-mode-p 'agent-shell-mode)
      (current-buffer)
    (car (agent-shell-project-buffers))))

(defun +ai--chat-buffer-or-error ()
  "This project's chat, or a user error when there is none."
  (or (+ai--chat-buffer) (user-error "No chat for this project")))

(defun +ai--chat-at-prompt ()
  "Put point at the end of the selected chat's prompt, in insert state."
  (with-current-buffer (window-buffer (selected-window))
    (when (derived-mode-p 'agent-shell-mode)
      (goto-char (point-max))
      (when (bound-and-true-p evil-local-mode)
        (evil-insert-state)))))

;;;###autoload
(defun +ai--chat-start-quietly ()
  "Start this project's chat without leaving this window; return it.
No context goes in: the caller inserts its own."
  (require 'agent-shell)
  (let ((agent-shell-context-sources nil))
    (save-selected-window
      (agent-shell '(4))))
  (+ai--chat-buffer))

;;;###autoload
(defun +ai/chat ()
  "Open or focus this project's chat, the region or the error at point
in its prompt.  From the chat, go back to the editor window."
  (interactive)
  (if (derived-mode-p 'agent-shell-mode)
      (select-window (or (+ai--editor-window) (user-error "No editor window")))
    (require 'agent-shell)
    (call-interactively #'agent-shell)
    (+ai--chat-at-prompt)))

;;;###autoload
(defun +ai/chat-new (&optional pick)
  "Start a new chat for this project.  With PICK (\\[universal-argument]),
choose the agent, the usual one first."
  (interactive "P")
  (require 'agent-shell)
  (let ((agent-shell-preferred-agent-config
         (if pick
             ;; preselect always shows the picker, so it is no default.
             (cons 'preselect (if (consp agent-shell-preferred-agent-config)
                                  (cdr agent-shell-preferred-agent-config)
                                agent-shell-preferred-agent-config))
           agent-shell-preferred-agent-config)))
    (agent-shell '(4)))
  (+ai--chat-at-prompt))

;;;###autoload
(defun +ai/chat-resume ()
  "Start a chat that first lists this project's earlier sessions."
  (interactive)
  (require 'agent-shell)
  (let ((agent-shell-session-strategy 'prompt))
    (agent-shell '(4)))
  (+ai--chat-at-prompt))

;;;###autoload
(defun +ai/chat-hide ()
  "Hide this project's chat; it keeps running."
  (interactive)
  (let ((chat (+ai--chat-buffer-or-error)))
    (dolist (window (get-buffer-window-list chat nil t))
      (quit-window nil window))))

;;;###autoload
(defun +ai/chat-stop ()
  "End this project's chat, after asking."
  (interactive)
  (let ((chat (+ai--chat-buffer-or-error)))
    (when (y-or-n-p (format "End %s? " (buffer-name chat)))
      (kill-buffer chat))))

;;;###autoload
(defun +ai/chat-interrupt ()
  "Interrupt this project's chat, from any buffer."
  (interactive)
  (with-current-buffer (+ai--chat-buffer-or-error)
    (call-interactively #'agent-shell-interrupt)))

;;;###autoload
(defun +ai/chat-transcript ()
  "Open the transcript of this project's chat, from any buffer."
  (interactive)
  (with-current-buffer (+ai--chat-buffer-or-error)
    (call-interactively #'agent-shell-open-transcript)))

;;;###autoload
(defun +ai/chat-set-mode ()
  "Choose the permission mode of this project's chat, from any buffer."
  (interactive)
  (with-current-buffer (+ai--chat-buffer-or-error)
    (call-interactively #'agent-shell-set-session-mode)))

;;;###autoload
(defun +ai/chat-cycle-mode ()
  "Go to the next permission mode of this project's chat, from any buffer."
  (interactive)
  (with-current-buffer (+ai--chat-buffer-or-error)
    (call-interactively #'agent-shell-cycle-session-mode)))

;;;###autoload
(defun +ai/chat-set-model ()
  "Choose the model of this project's chat, from any buffer."
  (interactive)
  (with-current-buffer (+ai--chat-buffer-or-error)
    (call-interactively #'agent-shell-set-session-model)))

;;;###autoload
(defun +ai/chat-set-thought-level ()
  "Choose the thought level of this project's chat, from any buffer."
  (interactive)
  (with-current-buffer (+ai--chat-buffer-or-error)
    (call-interactively #'agent-shell-set-session-thought-level)))

;;;###autoload
(defun +ai/chat-traffic ()
  "Show the ACP traffic of this project's chat, from any buffer.
Logging is off by default and keeps nothing from before it is on, so
this turns it on and says so."
  (interactive)
  (let ((chat (+ai--chat-buffer-or-error)))
    (unless acp-logging-enabled
      (setq acp-logging-enabled t)
      (message "ACP logging is on; traffic from before now was not kept"))
    (with-current-buffer chat
      (call-interactively #'agent-shell-view-traffic))))

(defun +ai--chat-file-mention (path)
  "PATH as an @-mention; quoted when it holds a space, as agent-shell does."
  (if (string-match-p "[[:space:]]" path)
      (format "@\"%s\"" path)
    (concat "@" path)))

;;;###autoload
(defun +ai/chat-mention ()
  "Put an @-mention of this file and its lines into the project's chat.
The file goes whole: agent-shell reads no line suffix, so the lines are
a hint for the agent.  Focus stays here."
  (interactive)
  (unless buffer-file-name
    (user-error "Not a file buffer"))
  (let* ((lines (if (use-region-p)
                    (let ((beg (line-number-at-pos (region-beginning)))
                          (end (line-number-at-pos
                                ;; A region ending at a line's start leaves that line out.
                                (if (and (> (region-end) (region-beginning))
                                         (save-excursion (goto-char (region-end)) (bolp)))
                                    (1- (region-end))
                                  (region-end)))))
                      (if (= beg end)
                          (format "(line %d)" beg)
                        (format "(lines %d-%d)" beg end)))
                  (format "(line %d)" (line-number-at-pos))))
         (file buffer-file-name)
         (chat (or (+ai--chat-buffer) (+ai--chat-start-quietly)))
         (path (file-relative-name file (with-current-buffer chat (agent-shell-cwd)))))
    (deactivate-mark)
    (agent-shell-insert :text (format "%s %s " (+ai--chat-file-mention path) lines)
                        :no-focus t :shell-buffer chat)))


;;
;;; Keys in the chat

;;;###autoload
(defun +ai--chat-at-prompt-filter (command)
  "COMMAND with point in the chat's prompt, else nil."
  (when-let* ((start (agent-shell--prompt-input-start)))
    (and (>= (point) start) command)))

;;;###autoload
(defun +ai--chat-on-button-filter (command)
  "COMMAND with point on a permission button, else nil."
  (when-let* ((map (get-char-property (point) 'keymap)))
    (and (keymapp map) (lookup-key map (kbd "C-c C-c")) command)))

;;;###autoload
(defun +ai/chat-reject ()
  "Reject the permission whose button point is on, and stop the turn,
so you can say what to do instead."
  (interactive)
  (let* ((map (get-char-property (point) 'keymap))
         (command (and (keymapp map) (lookup-key map (kbd "C-c C-c")))))
    (unless (commandp command)
      (user-error "Point is not on a permission button"))
    (call-interactively command)))


;;
;;; Emacs tools for chats

(defvar-local +ai--chat-session-id nil
  "This chat's session in claude-code-ide's tool server, or nil.")

(defun +ai--chat-tools-end-h ()
  "Take this chat's session out of the tool server."
  (when +ai--chat-session-id
    (claude-code-ide-mcp-server-session-ended +ai--chat-session-id)
    (setq +ai--chat-session-id nil)))

;;;###autoload
(defun +ai--chat-tools-h ()
  "Give this chat the Emacs tools through claude-code-ide's server.
Runs in the chat buffer before its session request is built.  The
session carries the chat's directory, so a tool works on this chat's
project, whatever buffer is current when the call arrives.  A chat
outside your home gets none."
  (let ((dir (file-name-as-directory (expand-file-name (agent-shell-cwd)))))
    (if (or +ai--chat-session-id
            (not (+ai--tool-root-allowed-p dir))
            (not (require 'claude-code-ide nil t))
            (not (claude-code-ide-mcp-server-ensure-server)))
        (unless +ai--chat-session-id
          (message "Emacs tools unavailable"))
      (let* ((base (format "agent-shell-%s-%s"
                           ;; The id goes into the URL as it is, and the
                           ;; server never decodes it: "my proj" would be
                           ;; sent as my%20proj and match no session.
                           (replace-regexp-in-string
                            "[^A-Za-z0-9._-]" "_"
                            (file-name-nondirectory (directory-file-name dir)))
                           (format-time-string "%Y%m%d-%H%M%S")))
             (id base)
             (n 1))
        ;; Two chats of a project started within the same second.
        (while (claude-code-ide-mcp-server-get-session-context id)
          (setq id (format "%s-%d" base (cl-incf n))))
        (claude-code-ide-mcp-server-session-started id dir (current-buffer))
        (setq +ai--chat-session-id id)
        (setq-local agent-shell-mcp-servers
                    (append (default-value 'agent-shell-mcp-servers)
                            `(((name . "emacs-tools")
                               (type . "http")
                               (url . ,(map-nested-elt
                                        (claude-code-ide-mcp-server-get-config id)
                                        '(mcpServers emacs-tools url)))))))
        (add-hook 'kill-buffer-hook #'+ai--chat-tools-end-h nil t)
        (agent-shell-subscribe-to
         :shell-buffer (current-buffer)
         :event 'clean-up
         :on-event (lambda (_event)
                     (claude-code-ide-mcp-server-session-ended id)))))))

(defun +ai--chat-edit-landed (event)
  "Reload the buffers of the files a finished edit of the chat wrote.
EVENT is agent-shell's tool-call-update.  A buffer you modified is
left alone."
  (let ((tool-call (map-nested-elt event '(:data :tool-call))))
    (when (and (equal (map-elt tool-call :kind) "edit")
               (equal (map-elt tool-call :status) "completed"))
      (seq-doseq (location (map-elt tool-call :locations))
        (when-let* ((path (map-elt location 'path))
                    (buffer (find-buffer-visiting path)))
          (with-current-buffer buffer
            (unless (or (buffer-modified-p)
                        (verify-visited-file-modtime buffer))
              (revert-buffer :ignore-auto :noconfirm :preserve-modes))))))))

;;;###autoload
(defun +ai--chat-reload-h ()
  "Reload a file's buffer as soon as one of this chat's edits lands."
  (agent-shell-subscribe-to
   :shell-buffer (current-buffer)
   :event 'tool-call-update
   :on-event #'+ai--chat-edit-landed))

;;;###autoload
(defun +ai--chat-permission-responder (request)
  "Allow an Emacs read tool at once; leave every other tool to the buttons.
REQUEST is agent-shell's permission alist.  The tool is judged by the
name in the ACP request, mcp__SERVER__TOOL for an MCP tool, never by the
title: the model writes a shell command's title itself.  A request with
no name, from an agent that sends none, shows its buttons."
  (when-let* ((name (map-nested-elt +ai--chat-permission-request
                                    '(params toolCall name)))
              ((member name (mapcar (lambda (tool) (concat "mcp__emacs-tools__" tool))
                                    +ai-auto-allowed-tools)))
              (option (seq-find (lambda (option)
                                  (equal (map-elt option :kind) "allow_once"))
                                (map-elt request :options))))
    (funcall (map-elt request :respond) (map-elt option :option-id))
    t))
