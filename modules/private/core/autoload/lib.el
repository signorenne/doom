;;; private/core/autoload/lib.el -*- lexical-binding: t; -*-
;;
;; Helpers the other private modules call: the project root, the file at
;; point, a compile runner, a vterm runner, git in a directory. core loads
;; first in the :private block and each of these is autoloaded, so a module
;; can call them without a declare-function.

(declare-function dired-get-filename "dired")
(declare-function dired-get-marked-files "dired")
(declare-function vterm "vterm")
(declare-function vterm-send-string "vterm")
(declare-function vterm-send-return "vterm")
(defvar compilation-shell-minor-mode)

(defvar dirvish--props)
(defvar +core--peek-root)
(defvar projectile-known-projects)

;;
;;; Projects and files

(defvar +core-project-root-memo-seconds 2
  "How long an answer of `+core-project-root' holds for a directory.
The lookup walks up the tree for every marker projectile knows, about
2 ms in a tree without a repository, and a menu asks a dozen times per
redraw.  Two seconds outlasts a redraw and not the time it takes to
create a repository and ask again.")

(defvar +core--roots (make-hash-table :test #'equal)
  "Directory to (TIME . ROOT) as last answered, ROOT nil for none.")

;;;###autoload
(defun +core-project-root-or-nil ()
  "The project root of `default-directory', projectile's answer, else
project.el's, else nil, remembered for `+core-project-root-memo-seconds'.
`+core-project-root' without its fallback, for a caller that must know
there is no project."
  (let* ((dir (expand-file-name default-directory))
         (hit (gethash dir +core--roots))
         (now (float-time)))
    (if (and hit (< (- now (car hit)) +core-project-root-memo-seconds))
        (cdr hit)
      (let ((root (or (doom-project-root)
                      (when-let* ((project (project-current nil)))
                        (project-root project)))))
        ;; A session visits many directories; the table need not keep
        ;; them all.
        (when (> (hash-table-count +core--roots) 500)
          (clrhash +core--roots))
        (puthash dir (cons now root) +core--roots)
        root))))

;;;###autoload
(defun +core-project-root (&optional noerror)
  "Root of the current project.
The version control root when there is one, else the topmost CMake or
PlatformIO directory (projectile and project.el both know those, see
the cpp module), else `default-directory' with NOERROR, else an error.
The answer is remembered a moment, see `+core-project-root-memo-seconds'."
  (or (+core-project-root-or-nil)
      (if noerror
          default-directory
        (user-error "Not inside a project"))))

;;;###autoload
(defun +core-file-at-point (&optional marked)
  "The file this buffer is about: at point in dired, else the visited file.
With MARKED, a list instead: the marked files in dired, else the file at
point, else the visited file.  Signals a `user-error' when there is none."
  (if marked
      (or (and (derived-mode-p 'dired-mode)
               (dired-get-marked-files nil nil nil nil t))
          (and buffer-file-name (list buffer-file-name))
          (user-error "No file here"))
    (or (and (derived-mode-p 'dired-mode) (dired-get-filename nil t))
        buffer-file-name
        (user-error "This buffer is not visiting a file"))))


;;
;;; Runners

(defvar-local +core-compile-name nil
  "The NAME `+core-compile' gave this compilation buffer, so a finish hook
can tell the buffers it started from grep, rmsbolt and the rest.")
(put '+core-compile-name 'permanent-local t) ; a re-run keeps it

;;;###autoload
(defun +core-compile (name command &optional dir comint)
  "Run shell COMMAND in a compilation buffer named *NAME* from DIR.
DIR defaults to the project root.  With COMINT the buffer takes input.
Returns the buffer, which carries NAME in `+core-compile-name'."
  (let* ((default-directory (file-name-as-directory
                             (expand-file-name (or dir (+core-project-root 'noerror)))))
         (compilation-buffer-name-function
          (lambda (_mode) (format "*%s*" name)))
         (buffer (compile command comint)))
    (with-current-buffer buffer
      (setq +core-compile-name name))
    ;; A program that takes input is no use without the cursor in it:
    ;; `compile' shows the buffer and leaves you where you were, so what
    ;; you type goes into the source. A build has nothing to be told and
    ;; keeps out of the way.
    (when (and comint (string-prefix-p "run" name))
      (with-current-buffer buffer
        ;; Output, once nothing is listening: q closes it the way it
        ;; closes every other window of the kind, and so does ESC, the
        ;; other key a window one has finished reading is dismissed with.
        ;; While the program runs the buffer is in insert state, where q
        ;; is a letter it is told and ESC steps out of typing first.
        (when (fboundp 'evil-local-set-key)
          (evil-local-set-key 'normal "q" #'quit-window)
          (evil-local-set-key 'normal [escape] #'quit-window)))
      (when-let* ((window (get-buffer-window buffer)))
        (select-window window)
        (goto-char (point-max))))
    buffer))

(defvar +core-run-window-closes t
  "Close the window of a program that ran, finished cleanly and said
nothing.  A window holding only compile's own header and closing line
has nothing in it to read; a program that printed something, or failed,
keeps its window.  The buffer is kept either way.")

;; Autoloaded: on `compilation-finish-functions', added in config.el.
;;;###autoload
(defun +core--run-window-h (buffer status)
  "Close BUFFER's windows when a program ran to a clean end.
STATUS is what compile says of it: \"finished\" and nothing else counts
as clean, so a program that failed keeps its window and its output."
  (when (and +core-run-window-closes
             (buffer-live-p buffer)
             (equal status "finished\n")
             (with-current-buffer buffer
               (string-prefix-p "run" (or +core-compile-name "")))
             ;; A program that printed something left it to be read.
             (+core--said-nothing-p buffer))
    (dolist (window (get-buffer-window-list buffer nil t))
      (when (and (window-live-p window) (not (one-window-p t (window-frame window))))
        (ignore-errors (delete-window window))))))

;; Autoloaded: on `compilation-finish-functions', added in config.el.
;;;###autoload
(defun +core--run-finished-h (buffer _status)
  "Leave insert state in BUFFER when the program it ran has ended.
Nothing is listening any more, so the keys that read a buffer are the
ones wanted: q closes it, and the rest move about rather than type."
  (when (and (buffer-live-p buffer)
             (with-current-buffer buffer
               (string-prefix-p "run" (or +core-compile-name ""))))
    (with-current-buffer buffer
      (when (and (fboundp 'evil-normal-state)
                 (eq (bound-and-true-p evil-state) 'insert))
        (evil-normal-state)))))

(defvar-local +core-compile-output-start nil
  "Marker where the program's own output begins in a compilation buffer.
Compile's header is before it; the closing line comes after.")
(put '+core-compile-output-start 'permanent-local t)

(defvar-local +core-compile-started nil
  "When this compilation buffer last started, as `float-time'.
Set in every compilation buffer, whoever started it, so the newest one
can be told from the rest.")
(put '+core-compile-started 'permanent-local t)

;; Autoloaded: on `compilation-start-hook', added in config.el.
;;;###autoload
(defun +core--note-compile-start-h (process)
  "Note the time and where the output begins, for PROCESS's buffer."
  (when-let* ((buffer (process-buffer process)))
    (with-current-buffer buffer
      (setq +core-compile-started (float-time))
      ;; Everything before this is compile's own: the mode line, when it
      ;; started, the command. What the program says starts here.
      (setq +core-compile-output-start (copy-marker (point-max))))))

(defun +core--said-nothing-p (buffer)
  "Non-nil when the program in BUFFER printed nothing of its own.
Compile writes a header and a closing line whatever happens; between
them is the program, and a program that said nothing there has left
nothing to read."
  (with-current-buffer buffer
    (save-excursion
      (goto-char (point-max))
      (let ((end (if (re-search-backward
                      "^\\(?:Comint\\|Compilation\\) \\(?:finished\\|exited\\|interrupt\\)"
                      nil t)
                     (point)
                   (point-max)))
            (start (or (and (markerp +core-compile-output-start)
                            (marker-position +core-compile-output-start))
                       (point-min))))
        (string-blank-p (buffer-substring-no-properties (min start end) end))))))

;;;###autoload
(defun +core-last-compilation-buffer ()
  "The build, test or run buffer that started last, or nil.
Compilation buffers proper and the comint ones a run uses; grep and its
kind, which share the mode's ancestry, are not builds."
  (car (seq-sort-by (lambda (buffer)
                      (buffer-local-value '+core-compile-started buffer))
                    #'>
                    (seq-filter (lambda (buffer)
                                  (and (buffer-local-value '+core-compile-started buffer)
                                       (or (eq (buffer-local-value 'major-mode buffer)
                                               'compilation-mode)
                                           (buffer-local-value 'compilation-shell-minor-mode
                                                               buffer))))
                                (buffer-list)))))

;;;###autoload
(defun +core-run-in-vterm (name command &optional dir)
  "Run shell COMMAND in a new vterm buffer called NAME, in DIR.
DIR defaults to the project root.  Returns the buffer."
  (require 'vterm)
  (let* ((default-directory (file-name-as-directory
                             (expand-file-name (or dir (+core-project-root 'noerror)))))
         (buffer (vterm (generate-new-buffer-name name))))
    (with-current-buffer buffer
      (vterm-send-string command)
      (vterm-send-return))
    buffer))



;;
;;; Settings kept in .dir-locals.el

(defvar +core--dir-locals-cache (make-hash-table :test #'equal)
  "Project root to (MTIME . CONTENTS) of its .dir-locals.el: read once
per change, since every setting is asked for on every menu redraw.")

;;;###autoload
(defun +core-dir-locals-read (root)
  "Contents of ROOT's .dir-locals.el, or nil."
  (let* ((root (file-name-as-directory (expand-file-name root)))
         (file (expand-file-name ".dir-locals.el" root))
         (mtime (file-attribute-modification-time (file-attributes file)))
         (hit (gethash root +core--dir-locals-cache)))
    (cond ((null mtime) nil)
          ((and hit (equal (car hit) mtime)) (cdr hit))
          (t (let ((contents (with-temp-buffer
                               (insert-file-contents file)
                               (condition-case nil (read (current-buffer)) (error nil)))))
               (puthash root (cons mtime contents) +core--dir-locals-cache)
               contents)))))

;;;###autoload
(defun +core-dir-locals-set (root variable value &optional mode)
  "Set VARIABLE to VALUE in ROOT's .dir-locals.el, for MODE or all modes.
A nil VALUE removes the entry, since every variable written here reads
nil as \"not set\".  Only the alist is rewritten: comments and other
forms around it stay, and a file that does not read back as an alist is
left alone rather than replaced."
  (let ((file (expand-file-name ".dir-locals.el" root)))
    (with-temp-buffer
      (when (file-exists-p file)
        (insert-file-contents file))
      (goto-char (point-min))
      (with-syntax-table emacs-lisp-mode-syntax-table
        (forward-comment (buffer-size)))
      (let* ((start (point))
             (alist (if (eobp)
                        nil
                      (condition-case nil
                          (read (current-buffer))
                        (error (user-error "%s does not read back, edit it by hand"
                                           (abbreviate-file-name file))))))
             (end (point))
             (entry (assq mode alist)))
        (unless (listp alist)
          (user-error "%s does not hold an alist, edit it by hand"
                      (abbreviate-file-name file)))
        (cond ((and entry value)
               (setf (alist-get variable (cdr entry)) value))
              (entry
               (setf (alist-get variable (cdr entry) nil 'remove) nil)
               (unless (cdr entry)
                 (setq alist (delq entry alist))))
              (value
               (push (cons mode (list (cons variable value))) alist)))
        (delete-region start end)
        (goto-char start)
        (when (= start (point-min))
          (insert ";;; Directory Local Variables -*- no-byte-compile: t -*-\n"
                  ";;; See (info \"(emacs) Directory Variables\")\n\n"))
        (let ((print-length nil) (print-level nil))
          (pp alist (current-buffer)))
        (unless (eobp) (delete-blank-lines))
        (write-region (point-min) (point-max) file nil 'quiet)))
    ;; Pick the new values up on the next visit, and on the next question.
    (dir-locals-read-from-dir root)
    (remhash (file-name-as-directory (expand-file-name root)) +core--dir-locals-cache)
    file))

;;
;;; Git

;;;###autoload
(defun +core-git (dir &rest args)
  "Run git with ARGS inside DIR, returning (CODE . OUTPUT), output trimmed."
  (with-temp-buffer
    (let* ((default-directory (file-name-as-directory (expand-file-name dir)))
           (code (apply #'call-process "git" nil t nil args)))
      (cons code (string-trim (buffer-string))))))

;;;###autoload
(defun +core-git-state (dir)
  "What git says about DIR: `no-repo', `stopped', `dirty' or `clean'.
`stopped' is a rebase, merge or cherry-pick waiting for a hand: a commit
made then would record conflict markers."
  (let ((git-dir (+core-git dir "rev-parse" "--git-dir")))
    (if (not (zerop (car git-dir)))
        'no-repo
      (let ((git-dir (expand-file-name (cdr git-dir) dir))
            (status (cdr (+core-git dir "status" "--porcelain"))))
        (cond
         ((or (seq-some (lambda (state)
                          (file-exists-p (expand-file-name state git-dir)))
                        '("rebase-merge" "rebase-apply" "MERGE_HEAD"
                          "CHERRY_PICK_HEAD"))
              ;; Unmerged paths show as U on either side, or as AA and DD.
              (string-match-p "^\\(?:U.\\|.U\\|AA\\|DD\\) " status))
          'stopped)
         ((string-empty-p status) 'clean)
         (t 'dirty))))))


;;
;;; Languages

(defvar +core-languages
  '((c++-mode "cpp" "cpp")
    (c-mode "c" "C")
    (emacs-lisp-mode "elisp" "emacs-lisp")
    (lisp-interaction-mode "elisp" "emacs-lisp")
    (sh-mode "bash" "sh")
    (cmake-mode "cmake" "cmake")
    (qml-mode "qml" "qml")
    (python-mode "python" "python")
    (js-mode "js" "js")
    (json-mode "json" "json")
    (yaml-mode "yaml" "yaml")
    (org-mode "org" "org")
    (markdown-mode "markdown" "markdown")
    (plantuml-mode "plantuml" "plantuml")
    (graphviz-dot-mode "dot" "dot"))
  "Major mode to the name of its language in a fenced code block and in
an org source block, in that order.  A tree-sitter mode is looked up
as its plain mode; a mode not listed is named after itself.")

;;;###autoload
(defun +core-language (mode &optional kind)
  "The language name of MODE for a fenced block, or an org source
block with KIND `babel'.  From `+core-languages', else the mode's own
name without its -mode or -ts-mode suffix."
  (let* ((plain (intern (replace-regexp-in-string "-ts-mode\\'" "-mode"
                                                  (symbol-name mode))))
         (entry (alist-get plain +core-languages)))
    (or (and entry (if (eq kind 'babel) (nth 1 entry) (nth 0 entry)))
        (thread-last (symbol-name plain)
                     (string-remove-suffix "-mode")))))


;;
;;; Markers

;; Autoloaded as a value: the ai module reads it when it registers its
;; tools, before anything here has loaded.
;;;###autoload
(defconst +core-todo-markers '("TODO" "FIXME" "HACK" "NOTE" "REVIEW" "BUG" "XXX")
  "The words a code comment uses to flag work.")

;;;###autoload
(defun +core-todo-regexp ()
  "A ripgrep pattern matching one of `+core-todo-markers' as a word."
  (format "\\b(%s)\\b" (string-join +core-todo-markers "|")))

;;
;;; The preview beside the minibuffer

;;;###autoload
(defun +core--peek-root-for ()
  "Where the candidate the preview is about is relative to.
`SPC SPC' pressed outside a project asks which project first, and the
candidates are then relative to the one chosen, which is not the
directory the prompt was opened from and is written down nowhere a
preview can read.  So the candidate is tried under each place it could
be until one of them holds it, and that one is kept for the rest of the
prompt."
  (let ((candidate (ignore-errors
                     (funcall (cdr (assq :peek-fetcher dirvish--props))))))
    (if (or (null candidate) (file-name-absolute-p candidate)
            (and +core--peek-root
                 (file-exists-p (expand-file-name candidate +core--peek-root))))
        (or +core--peek-root default-directory)
      (or (when-let* ((found (seq-find
                              (lambda (root)
                                (file-exists-p (expand-file-name candidate root)))
                              (delete-dups
                               (delq nil
                                     (append (list default-directory)
                                             (mapcar #'expand-file-name
                                                     (bound-and-true-p
                                                      projectile-known-projects))))))))
            (setq +core--peek-root found))
          +core--peek-root
          default-directory))))
