;;; private/core/autoload/commands.el -*- lexical-binding: t; -*-

(declare-function consult-fd "consult")
(declare-function consult-ripgrep "consult")
(declare-function doom/restart-and-restore "sessions")
(defvar consult-fd-args)
(defvar +core-compile-name)
(defvar +core-plain-mode)
(defvar +core-todo-markers)

(defvar +core-transparency-alpha 85
  "Opacity (0-100) `+core/toggle-transparency' switches to.")


;;
;;; Doom maintenance

(defun +core--doom-cli (name &rest args)
  "Run bin/doom with ARGS in a compilation buffer named *doom NAME*."
  (let ((compilation-scroll-output t))
    (+core-compile (format "doom %s" name)
                   (mapconcat #'shell-quote-argument
                              (cons (expand-file-name "bin/doom" doom-emacs-dir) args)
                              " ")
                   doom-emacs-dir)))

(defun +core--doom-sync-finished-h (buffer status)
  "Offer a restart when the `+core/doom-sync' BUFFER ends with STATUS."
  (when (equal (buffer-local-value '+core-compile-name buffer) "doom sync")
    (remove-hook 'compilation-finish-functions #'+core--doom-sync-finished-h)
    (if (string-prefix-p "finished" status)
        (when (y-or-n-p "Sync finished.  Restart Emacs and restore session? ")
          (doom/restart-and-restore))
      (message "doom sync failed (%s); see the %s buffer"
               (string-trim status) (buffer-name buffer)))))

;;;###autoload
(defun +core/doom-sync (&optional rebuild)
  "Run `doom sync --aot' in a compilation buffer, then offer to restart.
With prefix argument REBUILD, rebuild every package too (slow; do this
after upgrading Emacs itself)."
  (interactive "P")
  (add-hook 'compilation-finish-functions #'+core--doom-sync-finished-h)
  ;; --force: compilation buffers have no TTY, so answer the CLI's prompts.
  (apply #'+core--doom-cli "sync"
         (append '("sync" "--aot" "--force") (when rebuild '("--rebuild")))))

(defvar +core--reloaded-at nil
  "When `+core/reload' last read the config, as a float time.")

(defun +core--mtime (file)
  "FILE's modification time as a float time."
  (float-time (file-attribute-modification-time (file-attributes file))))

(defun +core--sync-needed ()
  "The config's files changed since the last doom sync that need one:
init.el, a packages.el, an autoload file."
  (let* ((profile (doom-profile-init-file doom-profile))
         (synced (and (file-exists-p profile) (+core--mtime profile))))
    (seq-filter
     (lambda (file) (or (null synced) (> (+core--mtime file) synced)))
     (append
      (seq-filter #'file-exists-p
                  (list (expand-file-name "init.el" doom-user-dir)
                        (expand-file-name "packages.el" doom-user-dir)))
      (seq-filter
       (lambda (file)
         (or (member (file-name-nondirectory file) '("packages.el" "autoload.el"))
             (string-match-p "/autoload/" file)))
       (directory-files-recursively
        (expand-file-name "modules/" doom-user-dir) "\\.el\\'"))))))

(defun +core--reload-in-place (&optional note)
  "Read the config again in this Emacs, as `doom/reload' does after its
sync, then the private autoload files already loaded that changed since
the last reload: those load on first use, not with the config. NOTE,
when given, ends the message."
  (let ((start (float-time))
        (since (or +core--reloaded-at (float-time before-init-time)))
        (private (expand-file-name "modules/" doom-user-dir)))
    (condition-case err
        ;; In *scratch*, as Doom does: a setq of a buffer-local variable
        ;; would otherwise land in whatever file is current.
        (with-current-buffer (get-scratch-buffer-create)
          (with-doom-context 'reload
            (doom-run-hooks 'doom-before-reload-hook)
            (general-auto-unbind-keys)
            (unwind-protect
                (startup--load-user-init-file nil)
              (general-auto-unbind-keys t))
            (doom-run-hooks 'doom-after-reload-hook))
          (let ((files (delete-dups
                        (delq nil
                              (mapcar
                               (lambda (entry)
                                 (when-let* ((loaded (car entry))
                                             ((stringp loaded))
                                             ((string-prefix-p private loaded))
                                             (file (concat (file-name-sans-extension loaded) ".el"))
                                             ((string-match-p "/autoload\\(?:/\\|\\.el\\'\\)" file))
                                             ((file-exists-p file))
                                             ((> (+core--mtime file) since)))
                                   file))
                               load-history)))))
            (dolist (file files)
              (load file nil 'nomessage 'nosuffix))
            (setq +core--reloaded-at start)
            (message "Config reloaded in %.1f s%s%s"
                     (- (float-time) start)
                     (if files (format ", with %d autoload file%s" (length files)
                                       (if (cdr files) "s" ""))
                       "")
                     (or note ""))))
      (error (message "Reload stopped: %s" (error-message-string err))))))

;;;###autoload
(defun +core/reload ()
  "Reload the config in this Emacs, keeping its frames and buffers.
When init.el, a packages.el or an autoload file changed since the last
doom sync, the sync runs first, in the background and without the
envvar file `doom/reload' writes; a failed sync leaves the config as it
was and shows why. What an old version added and the new one dropped,
a hook or an advice, stays until a restart."
  (interactive)
  (if-let* ((changed (+core--sync-needed)))
      (let ((buffer (get-buffer-create " *doom sync for reload*"))
            (default-directory doom-emacs-dir)
            (packages (seq-find (lambda (file)
                                  (member (file-name-nondirectory file) '("init.el" "packages.el")))
                                changed)))
        (with-current-buffer buffer (erase-buffer))
        (message "Syncing first: %s changed..." (file-relative-name (car changed) doom-user-dir))
        ;; --force: no terminal to answer the CLI's prompts. And stdin
        ;; closed at once: the CLI reads a pipe to its end, and waits.
        (process-send-eof
         (make-process
          :name "doom-sync-reload" :buffer buffer :noquery t :connection-type 'pipe
          :command (list (expand-file-name "bin/doom" doom-emacs-dir)
                         "sync" "-B" "--aot" "--force")
          :sentinel (lambda (process _event)
                      (unless (process-live-p process)
                        (if (zerop (process-exit-status process))
                            (+core--reload-in-place
                             (and packages "; a new package may need SPC q r"))
                          (pop-to-buffer buffer)
                          (message "doom sync failed; the config was not reloaded")))))))
    (+core--reload-in-place)))

;;;###autoload
(defun +core/doom-doctor ()
  "Run `doom doctor' in a compilation buffer."
  (interactive)
  (+core--doom-cli "doctor" "doctor"))

;;;###autoload
(defun +core/doom-upgrade ()
  "Update Doom and its packages, then rebuild them.
The private packages keep their pins; `doom/bump-package-at-point' moves one."
  (interactive)
  (when (y-or-n-p "Upgrade Doom and its packages? ")
    (+core--doom-cli "upgrade" "upgrade" "--aot" "--force")))


;;
;;; Toggles

;;;###autoload
(defun +core/toggle-transparency (&optional alpha)
  "Toggle background transparency of this frame.
With numeric prefix ALPHA (0-100), use that opacity."
  (interactive "P")
  (let* ((current (or (frame-parameter nil 'alpha-background) 100))
         (target (cond ((numberp alpha) (max 0 (min 100 alpha)))
                       ((= current 100) +core-transparency-alpha)
                       (t 100))))
    (set-frame-parameter nil 'alpha-background target)
    (message "Frame opacity %d%% (C-u N SPC t T sets it)" target)))


;;
;;; Files & projects

;;;###autoload
(defun +core/open-externally (&optional file)
  "Open FILE with the desktop's default application.
FILE defaults to the file at point in dired, this buffer's file, or
`default-directory'."
  (interactive)
  (let ((target (or file
                    (ignore-errors (+core-file-at-point))
                    default-directory)))
    (+core-os-open (expand-file-name target))
    (message "Opened %s externally" (abbreviate-file-name target))))

;;;###autoload
(defun +core/file-own-mode ()
  "Give a file opened as plain text the major mode it would have had.
A file past `+core-plain-file-size' opens in `fundamental-mode'; this
sets it up as opening it would have, and a revert keeps that."
  (interactive)
  (unless (and +core-plain-mode (not (eq +core-plain-mode t)))
    (user-error "%s was not opened as plain text" (buffer-name)))
  (setq +core-plain-mode t)
  (after-find-file nil nil t))

;;;###autoload
(defun +core/project-todos ()
  "Search the project for TODO, FIXME, HACK, NOTE, REVIEW, BUG and XXX."
  (interactive)
  ;; An Emacs regexp, since consult turns it into ripgrep's; a ripgrep
  ;; pattern such as `+core-todo-regexp' would be searched as literal text.
  (consult-ripgrep (+core-project-root 'noerror) (regexp-opt +core-todo-markers 'words)))

;;;###autoload
(defun +core/find-any-file ()
  "Find a file anywhere under the project, ignored ones included: build
output, generated files, untracked assets."
  (interactive)
  (require 'consult)
  (let ((consult-fd-args (append consult-fd-args '("--no-ignore"))))
    (consult-fd (+core-project-root 'noerror))))
