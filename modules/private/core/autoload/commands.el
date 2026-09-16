;;; private/core/autoload/commands.el -*- lexical-binding: t; -*-

(declare-function consult-fd "consult")
(declare-function consult-ripgrep "consult")
(declare-function doom/restart-and-restore "sessions")
(defvar consult-fd-args)
(defvar +core-compile-name)             ; lib.el

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
    (unless (executable-find "xdg-open")
      (user-error "xdg-open not found on PATH"))
    (call-process "xdg-open" nil 0 nil (expand-file-name target))
    (message "Opened %s externally" (abbreviate-file-name target))))

;;;###autoload
(defun +core/project-todos ()
  "Search the project for TODO, FIXME, HACK, NOTE, REVIEW, BUG and XXX."
  (interactive)
  (consult-ripgrep (+core-project-root 'noerror) (+core-todo-regexp)))

;;;###autoload
(defun +core/find-any-file ()
  "Find a file anywhere under the project, ignored ones included: build
output, generated files, untracked assets."
  (interactive)
  (require 'consult)
  (let ((consult-fd-args (append consult-fd-args '("--no-ignore"))))
    (consult-fd (+core-project-root 'noerror))))
