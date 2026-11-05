;;; private/ai/autoload/inline.el -*- lexical-binding: t; -*-
;;
;; Quick actions on the code: rewrite a region as a diff to accept or
;; reject, explain, ask, write a commit message. They run through gptel
;; once it has a usable backend, else through `claude -p' with the CLI's
;; own sign-in, so they work with no API key.

(defvar +ai-inline-backend)
(defvar +ai-inline-context-lines)
(defvar +ai-inline-model)
(defvar gptel-backend)
(defvar gptel-model)
(defvar gptel-tools)
(defvar gptel-use-tools)
(declare-function +ai--chat-buffer "chat")
(declare-function +ai--chat-start-quietly "chat")
(declare-function +ai--fenced "chat")
(declare-function +ai-answer-mode "config")
(declare-function +ai-rewrite-mode "config")
(declare-function agent-shell-insert "agent-shell")
(declare-function evil-normal-state "evil-states")
(declare-function evil-normal-state-p "evil-states")
(declare-function gptel-abort "gptel-request")
(declare-function gptel-backend-key "gptel-request")
(declare-function gptel-backend-name "gptel-request")
(declare-function gptel-magit-generate-message "gptel-magit")
(declare-function gptel-ollama-p "gptel-ollama")
(declare-function gptel-request "gptel-request")

;;
;;; Backends

(defun +ai--inline-gptel-ready-p ()
  "Non-nil when gptel can answer: a key that resolves, or a key-less
backend such as Ollama."
  (and (require 'gptel nil t)
       (bound-and-true-p gptel-backend)
       (or (and (fboundp 'gptel-ollama-p) (gptel-ollama-p gptel-backend))
           (let ((key (gptel-backend-key gptel-backend)))
             (when (functionp key)
               (setq key (condition-case nil (funcall key) (error nil))))
             (and (stringp key) (not (string-empty-p key)))))))

;;;###autoload
(defun +ai--inline-backend ()
  "The backend an inline request goes to now: gptel or claude-cli.
Asked at each request, so a key added later is used without a restart."
  (pcase +ai-inline-backend
    ('gptel 'gptel)
    ('claude-cli 'claude-cli)
    (_ (cond ((+ai--inline-gptel-ready-p) 'gptel)
             ((executable-find "claude") 'claude-cli)
             (t (user-error "No inline backend: give gptel a key, or install the claude CLI"))))))

;;;###autoload
(defun +ai--inline-backend-name (backend)
  "BACKEND and its model, as the menu and the answer buffer say it."
  (if (eq backend 'gptel)
      (format "gptel: %s %s" (gptel-backend-name gptel-backend) gptel-model)
    (format "claude CLI, %s" +ai-inline-model)))

(defun +ai--inline-cli (prompt system on-text on-done)
  "Send PROMPT with SYSTEM to `claude -p', with no tools, no MCP and no
session kept; return a function that cancels it.  ON-TEXT gets each
piece of the answer as it streams, ON-DONE the answer and an error
message or nil, once."
  (let* ((default-directory (or (+core-project-root-or-nil) default-directory))
         ;; No session of a project: the hook script stays quiet.
         (process-environment (cons "CLAUDE_EMACS_HOOK_SKIP=1" process-environment))
         (stderr (generate-new-buffer " *ai-inline-stderr*"))
         (pending "")
         (answer nil)
         (failed nil)
         (cancelled nil)
         (process
          (make-process
           :name "ai-inline"
           :buffer nil
           :stderr stderr
           :noquery t
           :coding 'utf-8
           :connection-type 'pipe
           :command (list "claude" "-p" "--model" +ai-inline-model
                          "--tools" "" "--strict-mcp-config"
                          "--no-session-persistence"
                          "--output-format" "stream-json"
                          "--include-partial-messages" "--verbose"
                          "--append-system-prompt" system)
           :filter
           (lambda (_process chunk)
             (setq pending (concat pending chunk))
             (while (string-match "\n" pending)
               (let ((line (substring pending 0 (match-beginning 0))))
                 (setq pending (substring pending (match-end 0)))
                 (when-let* ((event (ignore-errors
                                      (json-parse-string line :object-type 'alist
                                                         :null-object nil
                                                         :false-object nil))))
                   (pcase (alist-get 'type event)
                     ("stream_event"
                      (let-alist event
                        (when (and (equal .event.type "content_block_delta")
                                   (equal .event.delta.type "text_delta"))
                          (funcall on-text .event.delta.text))))
                     ("result"
                      (setq answer (alist-get 'result event)
                            failed (alist-get 'is_error event))))))))
           :sentinel
           (lambda (process _event)
             (unless (process-live-p process)
               ;; The error stream is a pipe of its own; let it finish.
               (when-let* (((buffer-live-p stderr))
                           (pipe (get-buffer-process stderr)))
                 (accept-process-output pipe 0.1 nil t))
               (let ((errors (when (buffer-live-p stderr)
                               (with-current-buffer stderr
                                 (string-trim (buffer-string))))))
                 (when (buffer-live-p stderr)
                   (when-let* ((pipe (get-buffer-process stderr)))
                     (delete-process pipe))
                   (kill-buffer stderr))
                 (unless cancelled
                   (funcall on-done answer
                            (cond ((not (zerop (process-exit-status process)))
                                   (if (string-empty-p (or errors ""))
                                       (format "claude exited with code %d"
                                               (process-exit-status process))
                                     ;; The last lines say what went wrong.
                                     (string-join (last (split-string errors "\n" t) 3)
                                                  "\n")))
                                  (failed (or answer "claude failed"))
                                  ((not answer) "claude gave no answer"))))))))))
    (process-send-string process prompt)
    (process-send-eof process)
    (lambda ()
      (setq cancelled t)
      (delete-process process))))

(defun +ai--inline-gptel (prompt system on-text on-done)
  "As `+ai--inline-cli', through gptel, with no tools either."
  (let ((buffer (generate-new-buffer " *ai-inline-gptel*"))
        (text ""))
    ;; gptel reads its tool settings from the request's buffer.
    (with-current-buffer buffer
      (setq-local gptel-use-tools nil
                  gptel-tools nil))
    (gptel-request prompt
      :buffer buffer :system system :stream t
      :callback
      (lambda (response info)
        (cond ((stringp response)
               (setq text (concat text response))
               (funcall on-text response)
               ;; gptel drops :stream when it does not stream; the whole
               ;; answer comes at once then, and no t follows.
               (unless (plist-get info :stream)
                 (funcall on-done text nil)
                 (kill-buffer buffer)))
              ((eq response t)
               (funcall on-done text nil)
               (kill-buffer buffer))
              ((null response)
               (funcall on-done nil (or (plist-get info :status) "gptel failed"))
               (kill-buffer buffer))
              ((eq response 'abort)
               (kill-buffer buffer)))))
    (lambda () (gptel-abort buffer))))


;;
;;; One request per buffer

(defvar-local +ai--inline-cancel nil
  "A function that cancels this buffer's running inline request.")

(defvar-local +ai--inline-overlay nil
  "The overlay that marks the region a running rewrite will replace.")

(defun +ai--inline-finish ()
  "Forget this buffer's request and take its overlay away."
  (setq +ai--inline-cancel nil)
  (when +ai--inline-overlay
    (delete-overlay +ai--inline-overlay)
    (setq +ai--inline-overlay nil)))

(defun +ai--inline-kill-h ()
  "Cancel this buffer's request as the buffer dies."
  (when +ai--inline-cancel
    (funcall +ai--inline-cancel)))

;;;###autoload
(defun +ai/inline-cancel ()
  "Stop the inline request running for this buffer."
  (interactive)
  (unless +ai--inline-cancel
    (user-error "No inline request runs here"))
  (funcall +ai--inline-cancel)
  (+ai--inline-finish)
  (message "Inline request cancelled"))

(defun +ai--inline-start (prompt system on-text on-done)
  "Send PROMPT with SYSTEM for this buffer, after asking to cancel the
request already running here.  ON-TEXT and ON-DONE run in this buffer."
  (let ((backend (+ai--inline-backend))
        (source (current-buffer)))
    (when +ai--inline-cancel
      (unless (y-or-n-p "An inline request runs here.  Cancel it? ")
        (user-error "The running request goes on"))
      (funcall +ai--inline-cancel)
      (+ai--inline-finish))
    (add-hook 'kill-buffer-hook #'+ai--inline-kill-h nil t)
    (setq +ai--inline-cancel
          (funcall (if (eq backend 'gptel) #'+ai--inline-gptel #'+ai--inline-cli)
                   prompt system
                   (lambda (text)
                     (when (buffer-live-p source)
                       (with-current-buffer source (funcall on-text text))))
                   (lambda (answer error)
                     (when (buffer-live-p source)
                       (with-current-buffer source
                         (+ai--inline-finish)
                         (funcall on-done answer error))))))
    backend))

(defun +ai--inline-unfence (text)
  "TEXT without the one code fence around all of it, if there is one."
  (if (string-match "\\`[ \t\n]*```[^\n]*\n\\(\\(?:.\\|\n\\)*?\\)\n?```[ \t\n]*\\'" text)
      (match-string 1 text)
    text))

(defun +ai--inline-target (what)
  "The region, or the defun at point in code, as (BEG . END); else a
user error naming WHAT."
  (cond ((use-region-p) (cons (region-beginning) (region-end)))
        ((and (derived-mode-p 'prog-mode) (bounds-of-thing-at-point 'defun)))
        (t (user-error "Select the text to %s" what))))

(defun +ai--inline-context (beg end)
  "The file, the mode and `+ai-inline-context-lines' around BEG..END."
  (let ((before (save-excursion
                  (goto-char beg)
                  (forward-line (- +ai-inline-context-lines))
                  (buffer-substring-no-properties (point) beg)))
        (after (save-excursion
                 (goto-char end)
                 (forward-line +ai-inline-context-lines)
                 (buffer-substring-no-properties end (point)))))
    (list :file (if buffer-file-name
                    (file-relative-name buffer-file-name
                                        (or (+core-project-root-or-nil)
                                            default-directory))
                  (buffer-name))
          :mode (symbol-name major-mode)
          :before before
          :after after)))


;;
;;; Rewrite

(defvar +ai--inline-rewrite-history nil
  "Instructions given to `+ai/inline-rewrite'.")

(defvar-local +ai--rewrite nil
  "In *ai-rewrite*: a plist of the source buffer, its markers, the
original text, the rewrite and the instruction.")

(defun +ai--rewrite-request (source beg end original instruction)
  "Ask for a rewrite of ORIGINAL, between markers BEG and END of SOURCE."
  (with-current-buffer source
    (let ((context (+ai--inline-context beg end)))
      (+ai--inline-start
       (concat (format "File: %s\nMode: %s\nInstruction: %s\n\n"
                       (plist-get context :file) (plist-get context :mode) instruction)
               "Context before the region, to read, not to repeat:\n"
               (plist-get context :before)
               "\n\nThe region to rewrite:\n" original
               "\n\nContext after the region, to read, not to repeat:\n"
               (plist-get context :after))
       (concat "You rewrite a region of a file as instructed. Reply with the "
               "replacement text only: no code fences, no commentary. Keep the "
               "language, the indentation and the style of the code around it.")
       #'ignore
       (lambda (answer error)
         (if error
             (message "%s" error)
           (+ai--rewrite-show source beg end original instruction answer))))
      ;; Made after the start, which may cancel a request and its overlay.
      (setq +ai--inline-overlay (make-overlay beg end nil nil t))
      (overlay-put +ai--inline-overlay 'face '+ai-inline-pending)
      (message "Rewriting the region..."))))

(defun +ai--rewrite-show (source beg end original instruction answer)
  "Show ANSWER against ORIGINAL as a diff to accept or reject."
  (let ((new (+ai--inline-unfence answer)))
    ;; The region's last newline, kept or left out as the original has it.
    (setq new (string-trim-right new "\n+"))
    (when (string-suffix-p "\n" original)
      (setq new (concat new "\n")))
    (if (equal new original)
        (message "No change")
      (let ((old-file (make-temp-file "ai-original"))
            (new-file (make-temp-file "ai-rewrite"))
            (buffer (get-buffer-create "*ai-rewrite*")))
        (unwind-protect
            (progn
              (with-temp-file old-file (insert original))
              (with-temp-file new-file (insert new))
              (with-current-buffer buffer
                (let ((inhibit-read-only t))
                  (erase-buffer)
                  ;; Labels, not the file's name, so no diff-mode key finds
                  ;; the file to patch.
                  (call-process "diff" nil t nil "-u"
                                "--label" "original" "--label" "rewrite"
                                old-file new-file))
                (diff-mode)
                (setq buffer-read-only t)
                (+ai-rewrite-mode +1)
                ;; y and n are normal-state keys.
                (when (and (bound-and-true-p evil-local-mode)
                           (not (evil-normal-state-p)))
                  (evil-normal-state))
                (setq +ai--rewrite (list :source source :beg beg :end end
                                         :original original :new new
                                         :instruction instruction))
                (goto-char (point-min))))
          (delete-file old-file)
          (delete-file new-file))
        ;; Shown, not selected: the answer comes while you type elsewhere,
        ;; where a y would have accepted it.
        (display-buffer buffer)
        (message "The rewrite is ready below%s"
                 (if (fboundp '+popup/other)
                     (substitute-command-keys ", \\[+popup/other] goes to it")
                   ""))))))

;;;###autoload
(defun +ai/inline-rewrite ()
  "Rewrite the region, or the defun at point, by an instruction.
The rewrite comes as a diff, shown below without taking the cursor:
there y accepts, n rejects, e opens ediff, r asks again with more to
the instruction."
  (interactive)
  (+ai--inline-backend)
  (let* ((bounds (+ai--inline-target "rewrite"))
         (beg (copy-marker (car bounds)))
         (end (copy-marker (cdr bounds)))
         (original (buffer-substring-no-properties beg end))
         (instruction (read-string "Rewrite: " nil '+ai--inline-rewrite-history)))
    (when (string-blank-p instruction)
      (user-error "No instruction"))
    (deactivate-mark)
    (+ai--rewrite-request (current-buffer) beg end original instruction)))

(defun +ai--rewrite-or-error ()
  "This *ai-rewrite* buffer's plist, or a user error in any other buffer."
  (or +ai--rewrite (user-error "Not in an *ai-rewrite* buffer")))

(defun +ai--rewrite-close ()
  "Close *ai-rewrite* and go back to its source; return the plist."
  (let ((rewrite (+ai--rewrite-or-error))
        (buffer (current-buffer)))
    (when-let* ((window (get-buffer-window buffer)))
      (quit-window nil window))
    (kill-buffer buffer)
    (when-let* ((window (get-buffer-window (plist-get rewrite :source))))
      (select-window window))
    rewrite))

;;;###autoload
(defun +ai/inline-rewrite-accept ()
  "Put the rewrite in place of the region, in one undo step."
  (interactive)
  (let* ((rewrite (+ai--rewrite-or-error))
         (source (plist-get rewrite :source))
         (beg (plist-get rewrite :beg))
         (end (plist-get rewrite :end)))
    (unless (buffer-live-p source)
      (user-error "The buffer of the region is gone"))
    (unless (equal (with-current-buffer source
                     (buffer-substring-no-properties beg end))
                   (plist-get rewrite :original))
      (user-error "The region changed; run it again"))
    (when (buffer-local-value 'buffer-read-only source)
      (user-error "%s is read-only" (buffer-name source)))
    ;; The diff closes once the edit is in, so a failed edit keeps it, and
    ;; the edit goes in whole or not at all.
    (with-current-buffer source
      (undo-boundary)
      (atomic-change-group
        (save-excursion
          (goto-char beg)
          (delete-region beg end)
          (insert (plist-get rewrite :new))))
      (undo-boundary))
    (+ai--rewrite-close)))

;;;###autoload
(defun +ai/inline-rewrite-reject ()
  "Leave the region as it is."
  (interactive)
  (+ai--rewrite-close)
  (message "Rewrite rejected"))

;;;###autoload
(defun +ai/inline-rewrite-ediff ()
  "Compare the region and the rewrite in ediff."
  (interactive)
  (let ((rewrite (+ai--rewrite-or-error))
        (old (get-buffer-create "*ai-original*"))
        (new (get-buffer-create "*ai-rewritten*")))
    (dolist (pair (list (cons old :original) (cons new :new)))
      (with-current-buffer (car pair)
        (erase-buffer)
        (insert (plist-get rewrite (cdr pair)))
        ;; The source's mode for its colours, without its hooks.
        (delay-mode-hooks
          (funcall (buffer-local-value 'major-mode (plist-get rewrite :source))))))
    (ediff-buffers old new)))

;;;###autoload
(defun +ai/inline-rewrite-retry ()
  "Ask again, with more added to the instruction."
  (interactive)
  (+ai--rewrite-or-error)
  (let* ((more (read-string "Add to the instruction: "))
         (rewrite (+ai--rewrite-close)))
    (+ai--rewrite-request (plist-get rewrite :source)
                          (plist-get rewrite :beg) (plist-get rewrite :end)
                          (plist-get rewrite :original)
                          (concat (plist-get rewrite :instruction) "\n" more))))


;;
;;; Explain and ask

(defvar +ai--inline-ask-history nil
  "Questions put to `+ai/inline-ask'.")

(defvar-local +ai--answer-question nil
  "In *ai-answer*: what was asked, for the chat to go on from.")

(defvar-local +ai--answer-owner nil
  "In *ai-answer*: (TOKEN SOURCE CANCEL) of the request it shows.
A request writes only while its TOKEN is the one here.")

(defun +ai--answer-header (name state)
  "The header line of *ai-answer*: NAME, the backend and model, and STATE."
  (setq header-line-format
        (format " %s: %s   C-c C-c continue in the chat" name state)))

(defun +ai--inline-answer (question prompt)
  "Stream the answer to PROMPT into *ai-answer*; QUESTION is kept for the chat."
  (let* ((buffer (get-buffer-create "*ai-answer*"))
         (dir default-directory)
         (source (current-buffer))
         (token (list 'answer))
         (owner (buffer-local-value '+ai--answer-owner buffer))
         (mine-p (lambda ()
                   (and (buffer-live-p buffer)
                        (eq (car (buffer-local-value '+ai--answer-owner buffer))
                            token))))
         backend
         name)
    ;; Set from the start's value; the callbacks below run later and keep
    ;; the backend's name as it was when the request went.
    (setq backend
          (+ai--inline-start
           prompt
           "Answer about code clearly and briefly, in Markdown."
           (lambda (text)
             (when (funcall mine-p)
               (with-current-buffer buffer
                 (let ((inhibit-read-only t))
                   (save-excursion
                     (goto-char (point-max))
                     (insert text))))))
           (lambda (answer error)
             (when (funcall mine-p)
               (with-current-buffer buffer
                 (let ((inhibit-read-only t))
                   ;; Nothing streamed: the answer comes whole at the end.
                   (when (and answer (= (point-min) (point-max)))
                     (insert answer)))
                 (+ai--answer-header name (if error "failed" "done"))))
             (when error
               (message "%s" error)))))
    (setq name (+ai--inline-backend-name backend))
    ;; Made ready right after the start, which may ask to cancel and stop
    ;; there, and before anything can wait for output.
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer))
      (unless (derived-mode-p 'markdown-mode)
        (if (fboundp 'gfm-mode) (gfm-mode) (markdown-mode)))
      (setq buffer-read-only t
            default-directory dir
            +ai--answer-question question
            +ai--answer-owner (list token source
                                     (buffer-local-value '+ai--inline-cancel source)))
      (+ai-answer-mode +1)
      (+ai--answer-header name "running"))
    ;; Only now does an answer still coming for another buffer give the
    ;; window up: killing its process runs the sentinels of every process
    ;; that ended, this one's too, which must find the window theirs. One
    ;; for this buffer was the start's to ask about.
    (pcase-let ((`(,_ ,old-source ,old-cancel) owner))
      (when (and (buffer-live-p old-source)
                 (not (eq old-source source))
                 old-cancel
                 (eq (buffer-local-value '+ai--inline-cancel old-source) old-cancel))
        (with-current-buffer old-source
          (funcall old-cancel)
          (+ai--inline-finish))))
    (display-buffer buffer)))

(defun +ai--inline-code (beg end)
  "The code between BEG and END, fenced, with the file it is from."
  (let ((context (+ai--inline-context beg end)))
    (format "From %s (%s):\n%s"
            (plist-get context :file) (plist-get context :mode)
            (+ai--fenced (buffer-substring-no-properties beg end)
                         (+core-language major-mode)))))

;;;###autoload
(defun +ai/inline-explain ()
  "Explain the region, else the defun at point, else the symbol at point."
  (interactive)
  (+ai--inline-backend)
  (let* ((bounds (cond ((use-region-p) (cons (region-beginning) (region-end)))
                       ((and (derived-mode-p 'prog-mode) (bounds-of-thing-at-point 'defun)))
                       ((bounds-of-thing-at-point 'symbol))
                       (t (user-error "Nothing here to explain"))))
         (code (+ai--inline-code (car bounds) (cdr bounds))))
    (deactivate-mark)
    (+ai--inline-answer (concat "Explain this code.\n\n" code)
                        (concat "Explain this code.\n\n" code))))

;;;###autoload
(defun +ai/inline-ask (question)
  "Ask QUESTION, with the region as its context when one is active."
  (interactive (list (progn (+ai--inline-backend)
                            (read-string "Ask: " nil '+ai--inline-ask-history))))
  (when (string-empty-p (string-trim question))
    (user-error "No question"))
  (let ((prompt (if (use-region-p)
                    (concat question "\n\n"
                            (+ai--inline-code (region-beginning) (region-end)))
                  question)))
    (deactivate-mark)
    (+ai--inline-answer prompt prompt)))

;;;###autoload
(defun +ai/inline-answer-to-chat ()
  "Put the question and this answer into the project's chat prompt."
  (interactive)
  (unless (bound-and-true-p +ai-answer-mode)
    (user-error "Not in an *ai-answer* buffer"))
  (let ((text (format "%s\n\nAn answer I got:\n\n%s"
                      +ai--answer-question
                      (string-trim (buffer-substring-no-properties
                                    (point-min) (point-max)))))
        (chat (or (+ai--chat-buffer) (+ai--chat-start-quietly))))
    (agent-shell-insert :text text :shell-buffer chat)))


;;
;;; Commit message

(defun +ai--inline-git (&rest args)
  "The output of git ARGS here, or nil when it fails."
  (with-temp-buffer
    (when (zerop (apply #'call-process "git" nil t nil args))
      (buffer-string))))

(defun +ai--commit-message-end ()
  "The end of the message written so far: the first comment line."
  (save-excursion
    (goto-char (point-min))
    (if (re-search-forward (concat "^" (regexp-quote (string-trim (or comment-start "#"))))
                           nil t)
        (match-beginning 0)
      (point-max))))

(defun +ai--commit-message-put (message old)
  "Put MESSAGE above the first comment line, in place of OLD, the text
there when it was asked for, and return non-nil.  Text written since
stays and MESSAGE goes to the kill ring: the answer comes while you may
be typing, where a question would take your next key."
  (let ((end (+ai--commit-message-end))
        (text (string-trim (+ai--inline-unfence message))))
    (if (not (equal (buffer-substring-no-properties (point-min) end) old))
        (progn (kill-new text) nil)
      (save-excursion
        (delete-region (point-min) end)
        (goto-char (point-min))
        (insert text "\n\n"))
      t)))

;;;###autoload
(defun +ai/inline-commit-message ()
  "Write a commit message for the staged changes, in this commit buffer."
  (interactive)
  (let ((backend (+ai--inline-backend)))
    (if (and (eq backend 'gptel) (fboundp 'gptel-magit-generate-message))
        (call-interactively #'gptel-magit-generate-message)
      (let ((diff (+ai--inline-git "diff" "--cached"))
            (subjects (+ai--inline-git "log" "-15" "--format=%s"))
            (old (buffer-substring-no-properties (point-min) (+ai--commit-message-end))))
        (when (string-empty-p (string-trim (or diff "")))
          (user-error "Nothing staged"))
        ;; Asked now, as you press the key, never when the answer comes.
        (unless (or (string-empty-p (string-trim old))
                    (y-or-n-p "Replace the message written here? "))
          (user-error "The message stays"))
        (message "Writing a commit message...")
        (+ai--inline-start
         (concat "Write a commit message for this staged diff. Follow the style "
                 "of these recent subjects:\n" (or subjects "") "\n\nThe diff:\n"
                 (substring diff 0 (min (length diff) 60000)))
         "You write git commit messages. Reply with the message only: no fences, no commentary."
         #'ignore
         (lambda (answer error)
           (cond (error (message "%s" error))
                 ((+ai--commit-message-put answer old)
                  (message "Commit message written"))
                 (t (message "You wrote here meanwhile; the message written is in the kill ring")))))))))
