;;; private/ai/autoload/chat.el -*- lexical-binding: t; -*-
;;
;; agent-shell chats: the Emacs tools they reach, the permissions they ask
;; for, and the window the editor works in.

(defvar +ai--chat-permission-buffer)
(defvar +ai--chat-permission-request)
(defvar +ai-auto-allowed-tools)
(defvar +ai-chat-output-lines)
(defvar +ai-edit-functions)
(defvar acp-logging-enabled)
(defvar agent-shell--state)
(defvar agent-shell-activity-group-expand-by-default)
(defvar agent-shell-context-sources)
(defvar agent-shell-display-action)
(defvar agent-shell-ui--fold-toggle-state)
(defvar agent-shell-mcp-servers)
(defvar agent-shell-preferred-agent-config)
(defvar agent-shell-session-strategy)
(declare-function +ai--turn-root "turn")
(declare-function +ai--turn-snapshot "turn")
(declare-function +ai--tool-root-allowed-p "claude")
(declare-function +ai--tools-name-taken "claude")
(declare-function agent-shell "agent-shell")
(declare-function agent-shell--prompt-input-start "agent-shell-prompt")
(declare-function agent-shell--read-shell-buffer "agent-shell")
(declare-function agent-shell-cwd "agent-shell-project")
(declare-function agent-shell-insert "agent-shell")
(declare-function agent-shell-ui-toggle-all-fragments "agent-shell-ui")
(declare-function agent-shell-interrupt "agent-shell")
(declare-function agent-shell-open-transcript "agent-shell")
(declare-function agent-shell-cycle-session-mode "agent-shell")
(declare-function agent-shell-set-session-mode "agent-shell")
(declare-function agent-shell-set-session-model "agent-shell")
(declare-function agent-shell-set-session-thought-level "agent-shell")
(declare-function acp-traffic-buffer "acp")
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

(defun +ai--editor-window-or-new ()
  "The editor window of this frame, else of another frame on show, else
a new one left of the selected window, as when the chat is full size or
in a frame of its own.  A new one shows the file the selected window
showed before, else the file visited last."
  (or (+ai--editor-window)
      (seq-some (lambda (frame)
                  ;; Not a child frame: a completion popup is one.
                  (unless (or (eq frame (selected-frame)) (frame-parent frame))
                    (with-selected-frame frame (+ai--editor-window))))
                (visible-frame-list))
      (let* ((window (selected-window))
             (code (or (seq-some (pcase-lambda (`(,buffer . ,_))
                                   (and (buffer-live-p buffer) (buffer-file-name buffer) buffer))
                                 (window-prev-buffers window))
                       (seq-find #'buffer-file-name (buffer-list))
                       (other-buffer (window-buffer window) t)))
             ;; A side window splits into another side window.
             (new (split-window (if (window-parameter window 'window-side)
                                    (window-main-window)
                                  window)
                                nil 'left)))
        (set-window-buffer new code)
        new)))

(defun +ai--select-window (window)
  "Select WINDOW, and its frame when that is another."
  (select-frame-set-input-focus (window-frame window))
  (select-window window))


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
in its prompt.  From the chat, go back to the editor window, opening one
when the chat has the frame to itself."
  (interactive)
  (if (derived-mode-p 'agent-shell-mode)
      (+ai--select-window (+ai--editor-window-or-new))
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
(defun +ai/chat-switch ()
  "Show another chat, picked by name, in the chat's side window.
agent-shell's own switch puts it in the window you are in, the code's."
  (interactive)
  (require 'agent-shell)
  (let ((chat (agent-shell--read-shell-buffer :prompt "Switch to chat: ")))
    (+ai--select-window (or (get-buffer-window chat t)
                            (display-buffer chat agent-shell-display-action)))
    (+ai--chat-at-prompt)))

(defun +ai--chat-frame (chat)
  "The frame of its own CHAT has, from \\[+ai/chat-frame], or nil."
  (seq-find (lambda (frame) (eq (frame-parameter frame '+ai-chat) chat))
            (frame-list)))

(defun +ai--chat-frame-close (chat)
  "Close the frame of its own CHAT has, while another frame is on show."
  (when-let* ((frame (+ai--chat-frame chat))
              ((seq-some (lambda (other)
                           (not (or (eq other frame) (frame-parent other)
                                    (frame-initial-p other))))
                         (visible-frame-list))))
    (delete-frame frame)))

(defun +ai--chat-frame-close-h ()
  "Close this chat's frame of its own as the chat ends: left open, it
would show whatever buffer came next, under the chat's name."
  (+ai--chat-frame-close (current-buffer)))

;;;###autoload
(defun +ai/chat-hide ()
  "Hide this project's chat; it keeps running.  A frame of its own closes."
  (interactive)
  (let ((chat (+ai--chat-buffer-or-error)))
    (+ai--chat-frame-close chat)
    (dolist (window (get-buffer-window-list chat nil t))
      (quit-window nil window))))

;;;###autoload
(defun +ai/chat-window ()
  "Show this project's chat full size, in the editor window, as VS Code's
Open in New Tab.  \\[+ai/chat-hide] brings the code back."
  (interactive)
  (let ((chat (+ai--chat-buffer-or-error)))
    ;; From a frame of its own, it moves back to the editor's frame.
    (+ai--chat-frame-close chat)
    (let ((window (or (+ai--editor-window) (user-error "No editor window"))))
      (dolist (side (get-buffer-window-list chat nil t))
        (when (window-parameter side 'window-side)
          (delete-window side)))
      (select-window window)
      (switch-to-buffer chat nil t)
      (+ai--chat-at-prompt))))

;;;###autoload
(defun +ai/chat-frame ()
  "Show this project's chat in a frame of its own, as VS Code's Open in
New Window.  When it has one already, go there.  The windows that
showed it give it up: its side window closes, the editor window shows
its code again.  Hiding or ending the chat closes the frame."
  (interactive)
  (let* ((chat (+ai--chat-buffer-or-error))
         (frame (+ai--chat-frame chat)))
    (unless frame
      (dolist (window (get-buffer-window-list chat nil t))
        (if (window-parameter window 'window-side)
            (delete-window window)
          (switch-to-prev-buffer window)))
      (setq frame (make-frame `((name . "AI chat") (+ai-chat . ,chat))))
      (with-current-buffer chat
        (add-hook 'kill-buffer-hook #'+ai--chat-frame-close-h nil t)))
    (select-frame-set-input-focus frame)
    (if-let* ((window (get-buffer-window chat frame)))
        (select-window window)
      (switch-to-buffer chat nil t)
      (delete-other-windows))
    (+ai--chat-at-prompt)))

(defvar-local +ai--chat-focus nil
  "Non-nil while this chat folds its tool calls, as VS Code's Focus view.")

;;;###autoload
(defun +ai/chat-focus ()
  "Fold the tool calls of this project's chat, or unfold them again.
While folded, a new turn's calls start folded too."
  (interactive)
  (with-current-buffer (+ai--chat-buffer-or-error)
    (setq +ai--chat-focus (not +ai--chat-focus))
    (if +ai--chat-focus
        (setq-local agent-shell-activity-group-expand-by-default nil)
      (kill-local-variable 'agent-shell-activity-group-expand-by-default))
    ;; The fold-all command goes the other way from its last state, so it
    ;; is told the opposite of the one wanted.
    (setq-local agent-shell-ui--fold-toggle-state
                (if +ai--chat-focus 'expanded 'collapsed))
    (agent-shell-ui-toggle-all-fragments)
    (message "Tool calls %s" (if +ai--chat-focus "folded" "shown"))))

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
  (let* ((chat (+ai--chat-buffer-or-error))
         (client (or (map-elt (buffer-local-value 'agent-shell--state chat) :client)
                     (user-error "%s has no agent yet" (buffer-name chat)))))
    (unless acp-logging-enabled
      (setq acp-logging-enabled t)
      (message "ACP logging is on; traffic from before now was not kept"))
    ;; Not agent-shell-view-traffic: it refuses an empty buffer, which
    ;; this one is right after logging goes on. It fills as traffic comes.
    (pop-to-buffer (acp-traffic-buffer :client client))))

(defun +ai--chat-file-mention (path)
  "PATH as an @-mention; quoted when it holds a space, as agent-shell does."
  (if (string-match-p "[[:space:]]" path)
      (format "@\"%s\"" path)
    (concat "@" path)))

;;;###autoload
(defun +ai/chat-mention ()
  "Put this file, or its selected lines, into the project's chat.
With no region, an @-mention of the file, which goes whole.  With one,
only those lines, under the file's name and their numbers: agent-shell
reads no line suffix in a mention.  Focus stays here."
  (interactive)
  (unless buffer-file-name
    (user-error "Not a file buffer"))
  (let* ((region (use-region-p))
         (beg (if region (region-beginning) (pos-bol)))
         ;; A region ending at a line's start leaves that line out.
         (end (if (and region (> (region-end) (region-beginning))
                       (save-excursion (goto-char (region-end)) (bolp)))
                  (1- (region-end))
                (if region (region-end) (pos-eol))))
         (first (line-number-at-pos beg))
         (last (line-number-at-pos end))
         (lines (if (= first last)
                    (format "line %d" first)
                  (format "lines %d-%d" first last)))
         (text (and region (buffer-substring-no-properties beg end)))
         (language (+core-language major-mode))
         (file buffer-file-name)
         (chat (or (+ai--chat-buffer) (+ai--chat-start-quietly)))
         (path (file-relative-name file (with-current-buffer chat (agent-shell-cwd)))))
    (deactivate-mark)
    (agent-shell-insert :text (if region
                                  (format "%s, %s:\n%s" path lines (+ai--fenced text language))
                                (format "%s (%s) " (+ai--chat-file-mention path) lines))
                        :no-focus t :shell-buffer chat)))

;;;###autoload
(defun +ai--fenced (text &optional language)
  "TEXT in a code fence longer than any run of backticks in it."
  (let ((fence "```"))
    (while (string-match-p (regexp-quote fence) text)
      (setq fence (concat fence "`")))
    (format "%s%s\n%s\n%s\n" fence (or language "") (string-trim-right text "\n+") fence)))

(defun +ai--output-buffer-p (buffer)
  "Non-nil when BUFFER is a terminal or a build whose output can be sent."
  (with-current-buffer buffer
    (and (derived-mode-p 'vterm-mode 'eshell-mode 'shell-mode 'term-mode
                         'compilation-mode 'comint-mode)
         (not (derived-mode-p 'agent-shell-mode)))))

;;;###autoload
(defun +ai/chat-send-output (buffer)
  "Put the last output of BUFFER, a terminal or a build, into the chat.
The last `+ai-chat-output-lines' lines go, fenced, under the buffer's
name; focus stays here.  As VS Code's @terminal."
  (interactive
   (let* ((buffers (seq-filter #'+ai--output-buffer-p (buffer-list)))
          (default (cond ((+ai--output-buffer-p (current-buffer)) (current-buffer))
                         ((when-let* ((build (+core-last-compilation-buffer)))
                            (and (buffer-live-p build) build)))
                         (t (car buffers)))))
     (unless buffers
       (user-error "No terminal or build to take output from"))
     (list (get-buffer (completing-read "Output of: " (mapcar #'buffer-name buffers)
                                        nil t nil nil (and default (buffer-name default)))))))
  (let* ((text (with-current-buffer buffer
                 (save-excursion
                   (goto-char (point-max))
                   (skip-chars-backward " \t\n")
                   (let ((end (point)))
                     (forward-line (- 1 +ai-chat-output-lines))
                     (buffer-substring-no-properties (pos-bol) end)))))
         (chat (or (+ai--chat-buffer) (+ai--chat-start-quietly))))
    (agent-shell-insert :text (format "Output of %s, its last lines:\n%s"
                                      (buffer-name buffer) (+ai--fenced text))
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

(defvar-local +ai--chat-tools-trusted nil
  "Non-nil when this chat's emacs-tools server is ours alone, so its read
tools may run unasked.")

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
        (if-let* ((taken (+ai--tools-name-taken dir)))
            (message "%s, so the Emacs tools ask first" taken)
          (setq +ai--chat-tools-trusted t))
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
  "Reload the buffers of the files a finished edit of the chat wrote,
then tell `+ai-edit-functions'. EVENT is agent-shell's
tool-call-update.  A buffer you modified is left alone."
  (let ((tool-call (map-nested-elt event '(:data :tool-call)))
        paths)
    (when (and (equal (map-elt tool-call :kind) "edit")
               (equal (map-elt tool-call :status) "completed"))
      (seq-doseq (location (map-elt tool-call :locations))
        (when-let* ((path (map-elt location 'path)))
          (push path paths)
          (when-let* ((buffer (find-buffer-visiting path)))
            (with-current-buffer buffer
              (unless (or (buffer-modified-p)
                          (verify-visited-file-modtime buffer))
                (revert-buffer :ignore-auto :noconfirm :preserve-modes))))))
      (when paths
        (let ((dir (file-name-directory (car paths))))
          (run-hook-with-args '+ai-edit-functions
                              (or (+ai--turn-root dir) dir)
                              (nreverse paths)))))))

;;;###autoload
(defun +ai--chat-reload-h ()
  "Reload a file's buffer as soon as one of this chat's edits lands."
  (agent-shell-subscribe-to
   :shell-buffer (current-buffer)
   :event 'tool-call-update
   :on-event #'+ai--chat-edit-landed))

(defun +ai--chat-turn-started (_event)
  "Snapshot this chat's project: a turn begins."
  (+ai--turn-snapshot default-directory))

;;;###autoload
(defun +ai--chat-turn-h ()
  "Snapshot the project each time a prompt of this chat is sent."
  (let ((chat (current-buffer)))
    (agent-shell-subscribe-to
     :shell-buffer chat
     :event 'input-submitted
     :on-event (lambda (event)
                 (when (buffer-live-p chat)
                   (with-current-buffer chat
                     (+ai--chat-turn-started event)))))))

;;;###autoload
(defun +ai--chat-permission-responder (request)
  "Allow an Emacs read tool at once; leave every other tool to the buttons.
REQUEST is agent-shell's permission alist.  The tool is judged by the
name in the ACP request, mcp__SERVER__TOOL for an MCP tool, never by the
title: the model writes a shell command's title itself.  A request with
no name, from an agent that sends none, or from a chat whose server
name another server shares, shows its buttons."
  (when-let* (((buffer-live-p +ai--chat-permission-buffer))
              ((buffer-local-value '+ai--chat-tools-trusted +ai--chat-permission-buffer))
              (name (map-nested-elt +ai--chat-permission-request
                                    '(params toolCall name)))
              ((member name (mapcar (lambda (tool) (concat "mcp__emacs-tools__" tool))
                                    +ai-auto-allowed-tools)))
              (option (seq-find (lambda (option)
                                  (equal (map-elt option :kind) "allow_once"))
                                (map-elt request :options))))
    (funcall (map-elt request :respond) (map-elt option :option-id))
    t))
