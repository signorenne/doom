;;; private/ai/autoload/chat.el -*- lexical-binding: t; -*-
;;
;; agent-shell chats: the Emacs tools they reach, the permissions they ask
;; for, and the window the editor works in.

(defvar +ai--chat-permission-request)
(defvar +ai-auto-allowed-tools)
(defvar agent-shell-mcp-servers)
(declare-function agent-shell-cwd "agent-shell-project")
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
project, whatever buffer is current when the call arrives."
  (let ((dir (file-name-as-directory (expand-file-name (agent-shell-cwd)))))
    (if (or +ai--chat-session-id
            (member dir (list (expand-file-name "~/") "/"))
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
