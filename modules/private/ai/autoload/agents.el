;;; private/ai/autoload/agents.el -*- lexical-binding: t; -*-
;;
;; Managing Claude Code from Emacs: CLAUDE.md, settings, slash commands,
;; hooks and session logs.

(defvar +ai-hook-script)
(declare-function +cpp-preset-names "kit")
(declare-function notifications-notify "notifications")
(declare-function org-capture "org-capture")

(defun +ai--claude-md-commands (root)
  "Build commands to suggest in a new CLAUDE.md for ROOT: PlatformIO's,
CMake's with the project's first preset when it has presets, else make."
  (cond ((file-exists-p (expand-file-name "platformio.ini" root))
         (concat "- Build: `pio run`, upload: `pio run -t upload`\n"
                 "- Tests: `pio test`\n"
                 "- Index for clangd: `pio run -t compiledb`\n"))
        ((file-exists-p (expand-file-name "CMakeLists.txt" root))
         (concat
          (if-let* ((preset (and (modulep! :private cpp)
                                 (fboundp '+cpp-preset-names)
                                 (car (+cpp-preset-names root)))))
              (format (concat "- Configure: `cmake --preset %s`\n"
                              "- Build: `cmake --build --preset %s`\n"
                              "- Tests: `ctest --preset %s`\n")
                      preset preset preset)
            (concat "- Configure: `cmake -S . -B build`\n"
                    "- Build: `cmake --build build`\n"
                    "- Tests: `ctest --test-dir build`\n"))
          "- The emacs_build_project tool builds from Emacs and "
          "returns the errors.\n"))
        (t "- Build: `make`\n")))

;;;###autoload
(defun +ai/open-claude-md ()
  "Open this project's CLAUDE.md, offering to create one."
  (interactive)
  (let* ((root (+core-project-root 'noerror))
         (file (expand-file-name "CLAUDE.md" root)))
    (unless (file-exists-p file)
      (when (y-or-n-p (format "No CLAUDE.md in %s.  Create one? "
                              (abbreviate-file-name root)))
        (with-temp-file file
          (insert "# " (file-name-nondirectory (directory-file-name root))
                  "\n\n## What this project is\n\n(one paragraph)\n"
                  "\n## Build, test, run\n\n"
                  (+ai--claude-md-commands root)
                  "\n## Conventions\n\n"
                  "- Code style: see .clang-format or .editorconfig\n"
                  "- Commit messages: conventional commits\n"
                  "\n## Gotchas\n\n- \n"))))
    (when (file-exists-p file) (find-file file))))

;;;###autoload
(defun +ai/open-claude-settings (&optional project)
  "Open ~/.claude/settings.json; with prefix PROJECT, the project's own file."
  (interactive "P")
  (find-file (if project
                 (expand-file-name ".claude/settings.json" (+core-project-root 'noerror))
               (expand-file-name "~/.claude/settings.json"))))

;;;###autoload
(defun +ai/new-slash-command (name description &optional global)
  "Create the slash command NAME (.claude/commands/NAME.md) with DESCRIPTION.
With prefix GLOBAL, create it in ~/.claude/commands instead of the project."
  (interactive (list (read-string "Command name (without /): ")
                     (read-string "Description: ")
                     current-prefix-arg))
  (let* ((dir (if global (expand-file-name "~/.claude/commands/")
                (expand-file-name ".claude/commands/" (+core-project-root 'noerror))))
         (file (expand-file-name (concat name ".md") dir)))
    (make-directory dir t)
    (when (or (not (file-exists-p file))
              (y-or-n-p "Command exists.  Overwrite? "))
      (with-temp-file file
        (insert "---\ndescription: " description "\n---\n\n"
                "<!-- $ARGUMENTS is replaced by what follows /" name " -->\n\n"
                "Do the following for: $ARGUMENTS\n\n1. \n2. \n")))
    (find-file file)
    (message "Use it inside Claude Code as /%s <arguments>" name)))


;;
;;; Letting Claude Code notify Emacs

(defvar +ai--hook-events
  '(("Stop" . "stop") ("Notification" . "notification"))
  "Hook events `+ai/install-claude-hooks' installs, and their arguments.")

(defun +ai--hook-entry (event-name)
  "A settings.json entry running the hook script for EVENT-NAME."
  `((hooks . [((type . "command")
               (command . ,(format "%s %s"
                                   (shell-quote-argument +ai-hook-script)
                                   event-name)))])))

;;;###autoload
(defun +ai/install-claude-hooks ()
  "Tell Claude Code to notify Emacs when it stops or needs input.
Writes to ~/.claude/settings.json, keeping a .bak copy.  Safe to re-run."
  (interactive)
  ;; Before the file is read: a hand-edited settings.json would
  ;; otherwise answer with a raw parse error where the missing hook
  ;; script has a sentence ready.
  (unless (file-executable-p +ai-hook-script)
    (user-error "Hook script %s is missing or not executable" +ai-hook-script))
  (let* ((file (expand-file-name "~/.claude/settings.json"))
         (settings (if (file-exists-p file)
                       (with-temp-buffer
                         (insert-file-contents file)
                         ;; Keep JSON false/null distinguishable from nil so the
                         ;; rest of the file round-trips unchanged.
                         (json-parse-buffer :object-type 'alist
                                            :array-type 'array
                                            :null-object :null
                                            :false-object :false))
                     nil))
         (hooks (alist-get 'hooks settings))
         (changed nil))
    (dolist (event +ai--hook-events)
      (let* ((key (intern (car event)))
             (existing (alist-get key hooks))
             (already
              (seq-some
               (lambda (entry)
                 (seq-some (lambda (h)
                             (string-match-p (regexp-quote +ai-hook-script)
                                             (or (alist-get 'command h) "")))
                           (alist-get 'hooks entry)))
               (append existing nil))))
        (unless already
          (setf (alist-get key hooks)
                (vconcat (append existing nil)
                         (list (+ai--hook-entry (cdr event)))))
          (setq changed t))))
    (if (not changed)
        (message "Hooks already installed in %s"
                 (abbreviate-file-name file))
      (when (y-or-n-p (format "Write hooks into %s (a .bak is kept)? "
                              (abbreviate-file-name file)))
        (setf (alist-get 'hooks settings) hooks)
        (when (file-exists-p file) (copy-file file (concat file ".bak") t))
        (make-directory (file-name-directory file) t)
        (with-temp-file file
          (insert (json-serialize settings
                                  :null-object :null :false-object :false))
          (json-pretty-print-buffer))
        (message "Hooks installed in %s, backup in settings.json.bak"
                 (abbreviate-file-name file))))))

;;;###autoload
(defun +ai--claude-event (event dir)
  "Handle hook EVENT for project DIR.  Called by emacsclient."
  (let ((name (file-name-nondirectory (directory-file-name dir))))
    (pcase event
      ("stop"
       ;; Pick up edits Claude made on disk in buffers that are not modified.
       (let ((reverted 0))
         (dolist (buf (buffer-list))
           (with-current-buffer buf
             (when (and buffer-file-name
                        (file-in-directory-p buffer-file-name dir)
                        (not (buffer-modified-p))
                        (not (verify-visited-file-modtime buf))
                        (file-exists-p buffer-file-name))
               (revert-buffer :ignore-auto :noconfirm :preserve-modes)
               (cl-incf reverted))))
         (+ai--notify "Claude Code"
                      (if (> reverted 0)
                          (format "Finished in %s, %d buffer(s) reloaded"
                                  name reverted)
                        (format "Finished in %s" name)))))
      ("notification"
       (+ai--notify "Claude Code" (format "%s is waiting for you" name)))
      (_ (+ai--notify "Claude Code" (format "%s: %s" name event))))
    t))

(defun +ai--notify (title body)
  "Show a desktop notification, or a message if that fails."
  (condition-case nil
      (progn (require 'notifications)
             (notifications-notify :title title :body body
                                   :app-name "Emacs" :timeout 6000))
    (error (message "%s: %s" title body))))


;;
;;; Logging

;;;###autoload
(defun +ai/log-session ()
  "Write a session note into the owning project's Progress, or the inbox."
  (interactive)
  (require 'org-capture)
  (org-capture nil "a"))
