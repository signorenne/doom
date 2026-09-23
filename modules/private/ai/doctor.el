;; -*- lexical-binding: t; no-byte-compile: t; -*-
;;; private/ai/doctor.el

(assert! (modulep! :tools llm)
         "This module needs (:tools llm) for gptel")
(assert! (modulep! :term vterm)
         "claude-code-ide runs in vterm: enable (:term vterm)")

(if-let* ((claude (executable-find "claude")))
    (let ((version
           (with-temp-buffer
             ;; Under timeout, with no stdin: a doctor must never block.
             (ignore-errors
               (call-process "timeout" nil t nil "20" claude "--version"))
             (string-trim (buffer-string)))))
      (unless (string-match-p "[0-9]+\\.[0-9]+" version)
        (warn! "claude is on PATH but `claude --version' failed: %s" version)))
  (error! "claude CLI not found on PATH")
  (explain! "Install it with: curl -fsSL https://claude.ai/install.sh | bash"))

(unless (executable-find "claude-agent-acp")
  (warn! "claude-agent-acp not found, so agent-shell cannot start Claude")
  (explain! "Install it with: npm install -g --prefix ~/.local "
            "@agentclientprotocol/claude-agent-acp"))

(unless (executable-find "node")
  (warn! "node not found; the ACP adapter and MCP servers need it"))

;; Never read ~/.authinfo.gpg here: decrypting it would ask for a passphrase
;; and hang doom doctor. Seeing the file is enough.
(unless (or (getenv "ANTHROPIC_API_KEY")
            (file-exists-p (expand-file-name "~/.authinfo.gpg"))
            (and (file-exists-p (expand-file-name "~/.authinfo"))
                 (with-temp-buffer
                   (insert-file-contents (expand-file-name "~/.authinfo"))
                   (search-forward "api.anthropic.com" nil t))))
  ;; Said, not warned about. gptel is the only thing here that wants a
  ;; key and Claude Code signs in on its own, so an absent key describes
  ;; how this machine is set up rather than something that is wrong.
  (print! "No Anthropic API key: gptel cannot reach the API, Claude Code is unaffected")
  (print! "  Set ANTHROPIC_API_KEY, or put a line like this in ~/.authinfo.gpg:")
  (print! "  machine api.anthropic.com login apikey password KEY"))

(let ((script (file-name-concat doom-user-dir "bin/claude-emacs-hook")))
  (unless (file-executable-p script)
    (warn! "%s is not executable, so +ai/install-claude-hooks will fail"
           script)))
