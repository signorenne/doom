;;; private/cpp/autoload/lsp.el -*- lexical-binding: t; -*-

(declare-function +container-path "container")
;;
;; The language server: started where the kit runs and pointed at its
;; compilation database, restarted afresh, switched between clangd and
;; ccls; the .clangd writer and the root link for other tools; the
;; diagnostics and their fixes.

(defvar +cpp-ccls-init-options)
(defvar +cpp-clangd-args)
(defvar +cpp-container)
(declare-function +cpp-kit-container "kit")
(declare-function +cpp--set-setting "project")
(declare-function +cpp-kit-make "kit")
(declare-function +cpp-kit-name "kit")
(defvar +cpp-lsp-server)
(defvar +cpp-modes)
(declare-function eglot-current-server "eglot")
(declare-function eglot-ensure "eglot")
(declare-function eglot-shutdown "eglot")
(declare-function flycheck-has-current-errors-p "flycheck")
(defvar flycheck-navigation-minimum-level)
(declare-function flycheck-next-error "flycheck")
(declare-function flymake-goto-next-error "flymake")
(declare-function flymake-goto-prev-error "flymake")
(defvar +container-may-start)


;;
;;; Starting the server

;;;###autoload
(defun +cpp--eglot-server-program (&optional _interactive)
  "How eglot should start the server named by `+cpp-lsp-server'.
Evaluated when the server starts, so the compilation database it is
pointed at is the kit's at that moment.  When the kit runs in a
distrobox, so does the server; the home directory is shared, so every
path means the same thing there."
  (let* (;; This runs as a file is opened, so it asks only the
         ;; containers already up; SPC k b and the rest still start one.
         (+container-may-start nil)
         (argv (pcase +cpp-lsp-server
                 ('ccls (list "ccls"))
                 ;; clangd looks in the root and in build/ only; a kit's
                 ;; build/horizon-Debug has to be named.
                 (_ (append (cons "clangd" +cpp-clangd-args)
                            (when-let* ((db (+cpp--compile-commands-file)))
                              (list (concat "--compile-commands-dir="
                                            (file-name-directory db))))))))
         (kit (or (+cpp--kit) (+cpp-kit-make :name "host" :dir "build"))))
    (when-let* ((container (+cpp-kit-container kit)))
      (message "Kit %s runs in %s; so does the language server"
               (+cpp-kit-name kit) container))
    (append (+cpp--kit-process kit argv)
            (when (eq +cpp-lsp-server 'ccls)
              (list :initializationOptions +cpp-ccls-init-options)))))

;;;###autoload
(defun +cpp--container-path-a (path)
  "Advice on `eglot-uri-to-path': a PATH the server sent that is not on
the host is inside the kit's container, so reach it through TRAMP.
That is how a jump into an SDK header opens when the SDK lives only in
the distrobox.  Asked per buffer, so every buffer of the project sees
the container, not only the one that started the server."
  (if-let* (((stringp path))
            ((not (file-remote-p path)))
            ((not (file-exists-p path)))
            (kit (and (+core-project-root 'noerror) (+cpp--kit)))
            (container (+cpp-kit-container kit)))
      (+container-path container path)
    path))


;;
;;; Restarting and switching

;;;###autoload
(defun +cpp/restart-lsp ()
  "Restart this buffer's language server afresh, or start one.
Shuts the server down and starts a new one, so the command line is
computed again: a new kit, container, compilation database or server
choice reaches it. `eglot-reconnect' would reuse the old command line."
  (interactive)
  (when-let* ((server (and (fboundp 'eglot-current-server)
                           (eglot-current-server))))
    (eglot-shutdown server nil nil 'preserve-buffers))
  (eglot-ensure))

;; Autoloaded: called from the reindex hook in cmake.el.
;;;###autoload
(defun +cpp--restart-servers ()
  "Restart every C and C++ language server once, and put each of its
buffers back on the new one.  Grouped before anything is touched: once
a server is replaced, its old buffers already answer with the new one."
  (let (groups)
    (dolist (buffer (buffer-list))
      (with-current-buffer buffer
        (when-let* (((and buffer-file-name (apply #'derived-mode-p +cpp-modes)))
                    (server (and (fboundp 'eglot-current-server)
                                 (eglot-current-server))))
          (push buffer (alist-get server groups)))))
    (pcase-dolist (`(,server . ,buffers) groups)
      (eglot-shutdown server nil nil 'preserve-buffers)
      (dolist (buffer buffers)
        (with-current-buffer buffer (eglot-ensure))))
    (length groups)))

;;;###autoload
(defun +cpp/set-lsp-server (server &optional persist)
  "Switch this buffer to SERVER, clangd or ccls, and reconnect.
With prefix argument PERSIST, write the choice to .dir-locals.el so the
whole project uses it."
  (interactive
   (list (intern (completing-read "Language server: " '("clangd" "ccls")
                                  nil t nil nil
                                  (symbol-name +cpp-lsp-server)))
         current-prefix-arg))
  (let ((kit (+cpp--kit)))
    (unless (if-let* ((container (and kit (+cpp-kit-container kit))))
                (+container-has-p container (symbol-name server))
              (executable-find (symbol-name server)))
      (user-error "%s is not installed %s" server
                  (if kit (+cpp-kit-where kit) "on the host"))))
  (setq-default +cpp-lsp-server server)
  (setq +cpp-lsp-server server)
  (when persist
    (+core-dir-locals-set (+core-project-root) '+cpp-lsp-server server))
  (when (apply #'derived-mode-p +cpp-modes)
    (+cpp/restart-lsp))
  (message "Language server: %s%s" server
           (if persist ", saved to .dir-locals.el" "")))

;;;###autoload
(defun +cpp/set-container (name)
  "Run this project's kit inside the distrobox NAME, from now on.
Builds, tests, the debugger and the language server all move there.
An empty NAME goes back to reading the disk: the kit's compiler decides.
Written to .dir-locals.el, so it holds across sessions.  For the case
detection cannot settle, a compiler installed on the host and in the
container both."
  (interactive
   (list (completing-read "Distrobox (empty to detect): "
                          (+container-list) nil nil nil nil
                          (+cpp--setting '+cpp-container))))
  (let ((name (and (not (string-empty-p name)) name))
        (root (+core-project-root)))
    (when (and name (not (executable-find "distrobox")))
      (user-error "distrobox is not installed"))
    ;; The setter, so the project's open buffers take it too: the value
    ;; .dir-locals.el gave them as they opened won over the file.
    (+cpp--set-setting '+cpp-container name)
    (let ((kit (+cpp--kit root)))
      (when (apply #'derived-mode-p +cpp-modes)
        (+cpp/restart-lsp))
      (message "Kit %s now runs %s%s"
               (+cpp-kit-name kit) (+cpp-kit-where kit)
               (if name ", saved to .dir-locals.el" ", as the compiler says")))))

;; Autoloaded: called from the status buffer in cmake.el.
;;;###autoload
(defun +cpp--lsp-status ()
  "One line on the language server of the current buffer."
  (let ((where (if-let* ((container (+cpp-kit-container (+cpp--kit))))
                   (format " in %s" container)
                 "")))
    (if-let* ((server (and (fboundp 'eglot-current-server) (eglot-current-server))))
        (format "running (%s)%s"
                (or (seq-find (lambda (a) (member a '("clangd" "ccls")))
                              (process-command (+cpp--server-process server)))
                    "?")
                where)
      (format "not connected, would start %s%s"
              (bound-and-true-p +cpp-lsp-server) where))))


;;
;;; Jumps

;;;###autoload
(defun +cpp/find-declaration ()
  "Jump to the declaration of the symbol at point.
F2 goes to the definition, and from the definition back to the
declaration; this goes to the declaration from anywhere, the header line
rather than the body in the .cpp."
  (interactive)
  (unless (and (fboundp 'eglot-current-server) (eglot-current-server))
    (user-error "No language server here, SPC k l r starts one"))
  (call-interactively #'eglot-find-declaration))


(defvar qml-ts-mode-indent-offset)
(defvar qml--treesit-indent-rules)
(defvar treesit-simple-indent-rules)
(declare-function +cpp-kit-abs-dir "kit")
(declare-function +cpp--kit "kit")
;;
;;; clangd helpers

;; Autoloaded: scaffold.el writes them into a new project's .clangd.
;;;###autoload
(defun +cpp--qt-headers ()
  "Where Qt's headers are, or nil.
qmake knows wherever the distribution put them; openSUSE's own place is
the fallback."
  (or (when-let* ((qmake (or (executable-find "qmake6") (executable-find "qmake"))))
        (with-temp-buffer
          (when (zerop (call-process qmake nil t nil "-query" "QT_INSTALL_HEADERS"))
            (let ((dir (string-trim (buffer-string))))
              (and (file-directory-p dir) dir)))))
      (seq-find #'file-directory-p '("/usr/include/qt6" "/usr/include/qt5"))))

(defun +cpp--qt-include-flags ()
  "-I flags for Qt and each of its modules, so QString resolves without a
compilation database."
  (when-let* ((root (+cpp--qt-headers)))
    (cons (concat "-I" root)
          (mapcar (lambda (d) (concat "-I" d))
                  (directory-files root t "\\`Qt[A-Za-z0-9]+\\'")))))

;;;###autoload
(defun +cpp/write-clangd-config (db-dir)
  "Write a .clangd file that points clangd at DB-DIR.
DB-DIR holds compile_commands.json, relative to the project root.  Turns
on clang-tidy, inlay hints and include checks.  Qt's include paths go in
too when Qt is installed, and a language standard when there is no
database to say one, so a project without one still resolves QString."
  (interactive
   (let* ((root (+core-project-root))
          (candidates
           (delete-dups
            (delq nil
                  (cons (when-let* ((db (+cpp--compile-commands-file)))
                          (directory-file-name
                           (file-relative-name (file-name-directory db) root)))
                        (seq-filter
                         (lambda (d)
                           (file-exists-p (expand-file-name "compile_commands.json"
                                                            (expand-file-name d root))))
                         (cons "." (+cpp--configured-build-dirs))))))))
     (list (completing-read "Directory with compile_commands.json: "
                            (or candidates '("build")) nil nil
                            (or (car candidates) "build")))))
  (let* ((root (+core-project-root))
         (file (expand-file-name ".clangd" root)))
    (when (or (not (file-exists-p file))
              (y-or-n-p ".clangd exists. Overwrite? "))
      (with-temp-file file
        (insert "# See https://clangd.llvm.org/config\n"
                "CompileFlags:\n"
                (format "  CompilationDatabase: %s\n" db-dir)
                "  Remove: [-fmodules-ts, -fno-tree-loop-distribute-patterns]\n")
        (let ((flags (append (unless (file-exists-p
                                      (expand-file-name "compile_commands.json"
                                                        (expand-file-name db-dir root)))
                               ;; The templates' own: C++23, and include/
                               ;; seen from the root, src/ and one deeper.
                               '("-xc++" "-std=c++23" "-Iinclude"
                                 "-I../include" "-I../../include"))
                             (+cpp--qt-include-flags))))
          (when flags
            (insert "  # Flags for files no compilation database covers.\n"
                    "  Add:\n")
            (dolist (flag flags) (insert (format "    - %s\n" flag)))))
        (insert "Diagnostics:\n"
                "  ClangTidy:\n"
                "    Add: [bugprone-*, performance-*, modernize-*,\n"
                "          readability-*, cppcoreguidelines-*]\n"
                "    Remove: [modernize-use-trailing-return-type,\n"
                "             readability-magic-numbers,\n"
                "             readability-identifier-length,\n"
                "             cppcoreguidelines-avoid-magic-numbers]\n"
                "  UnusedIncludes: Strict\n"
                "  MissingIncludes: Strict\n"
                "InlayHints:\n"
                "  Enabled: Yes\n"
                "  ParameterNames: Yes\n"
                "  DeducedTypes: Yes\n"
                "  Designators: Yes\n"
                "Hover:\n"
                "  ShowAKA: Yes\n"))
      (message "Wrote %s" (abbreviate-file-name file))
      (when (y-or-n-p "Restart clangd now? ")
        (+cpp/restart-lsp)))))

;;;###autoload
(defun +cpp/link-compile-commands ()
  "Link the kit's compile_commands.json into the project root.
The language server is pointed at the kit's database by itself; the
link is for tools that look in the root only, clang-tidy run by hand or
another editor.  A link is replaced without asking, a real file only
after asking."
  (interactive)
  (let* ((root (+core-project-root))
         (src (or (+cpp--compile-commands-file)
                  (user-error "No compile_commands.json yet, configure first with SPC k c")))
         (dest (expand-file-name "compile_commands.json" root)))
    (cond ((string= src dest)
           (message "The database is in the root already"))
          ((and (file-symlink-p dest)
                (file-equal-p (file-truename dest) src))
           (message "%s already points at %s"
                    (abbreviate-file-name dest) (file-relative-name src root)))
          ((or (not (file-exists-p dest))
               (file-symlink-p dest)
               (y-or-n-p "A real compile_commands.json is in the root.  Replace? "))
           (when (file-exists-p dest) (delete-file dest))
           (make-symbolic-link (file-relative-name src root) dest t)
           (message "%s now points at %s"
                    (abbreviate-file-name dest) (file-relative-name src root))))))


;;
;;; Problems, and fixing them

(defun +cpp--problem (direction)
  "Go to the next (DIRECTION 1) or previous (-1) diagnostic and show it.
Wraps round at the end, and says so when there is none."
  (cond ((bound-and-true-p flycheck-mode)
         (unless (flycheck-has-current-errors-p)
           (user-error "No problems in this buffer"))
         (let ((flycheck-navigation-minimum-level nil))
           (condition-case nil
               (flycheck-next-error direction)
             (user-error
              (goto-char (if (> direction 0) (point-min) (point-max)))
              (flycheck-next-error direction)))))
        ((bound-and-true-p flymake-mode)
         (if (> direction 0)
             (flymake-goto-next-error 1 nil t)
           (flymake-goto-prev-error 1 nil t)))
        (t (next-error direction))))

;;;###autoload
(defun +cpp/next-problem ()
  "Go to the next problem in the buffer and show it; round at the end."
  (interactive)
  (+cpp--problem 1))

;;;###autoload
(defun +cpp/previous-problem ()
  "Go to the previous problem in the buffer and show it; round at the start."
  (interactive)
  (+cpp--problem -1))

;;;###autoload
(defun +cpp/quickfix ()
  "Apply the server's quick fix for the problem at point.
One fix is applied at once; several are offered; none says so.  The
region, when there is one, is what the fix is asked for."
  (interactive)
  (unless (and (fboundp 'eglot-current-server) (eglot-current-server))
    (user-error "No language server here, SPC k l r starts one"))
  (if (use-region-p)
      (eglot-code-action-quickfix (region-beginning) (region-end))
    (eglot-code-action-quickfix (point) (point))))

;;
;;; QML

;;;###autoload
(defun +cpp--qmlls-command (&optional _interactive _project)
  "qmlls, with the kit's build directory when there is one.
Without -b it resolves only what Qt ships: a type the project declares,
or a module it builds, is unknown, and completion offers nothing for
it."
  (when-let* ((program (seq-some (lambda (name)
                                   (and (executable-find name) name))
                                 '("qmlls" "qmlls6" "/usr/lib64/qt6/bin/qmlls"))))
    (let* ((dir (ignore-errors (+cpp-kit-abs-dir (+cpp--kit))))
           (modules (and dir (expand-file-name "qml" dir))))
      (append (list program)
              (when (and dir (file-directory-p dir)) (list "-b" dir))
              ;; Where `QT_QML_OUTPUT_DIRECTORY' puts the project's own
              ;; modules, named after their URI, which is the only shape
              ;; an import path can resolve.
              (when (and modules (file-directory-p modules))
                (list "-I" modules))))))

;;;###autoload
(defun +cpp--qml-guess-offset ()
  "The step this file is indented in, read off the file itself.
One project writes QML in twos and the next in fours, and a project
need not say which in a .editorconfig.  The smallest indent any line
has is one step of it."
  (save-excursion
    (goto-char (point-min))
    (let ((steps nil) (seen 0))
      (while (and (< seen 500) (not (eobp)))
        (let ((indent (current-indentation)))
          (unless (or (zerop indent) (looking-at-p "[ \t]*$"))
            (push indent steps)))
        (cl-incf seen)
        (forward-line 1))
      (when steps (apply #'min steps)))))

;;;###autoload
(defun +cpp--qml-indent-h ()
  "Build this buffer's indent rules for the step this file is written in.
`qml-ts-mode' writes `qml-ts-mode-indent-offset' into its rules when the
package loads, so the variable means nothing after that; every step in
the rules is the offset or zero, so the steps are replaced.  A
.editorconfig, or anything else that set the offset for this buffer
alone, is left as it is; otherwise the file itself is asked."
  (when (and (derived-mode-p 'qml-ts-mode)
             (boundp 'qml--treesit-indent-rules))
    (unless (local-variable-p 'qml-ts-mode-indent-offset)
      (when-let* ((guess (+cpp--qml-guess-offset)))
        (setq-local qml-ts-mode-indent-offset guess)))
    (let ((offset qml-ts-mode-indent-offset))
      (setq-local treesit-simple-indent-rules
                  (mapcar
                   (lambda (language)
                     (cons (car language)
                           (mapcar (lambda (rule)
                                     (mapcar (lambda (part)
                                               (if (and (integerp part) (/= part 0))
                                                   offset
                                                 part))
                                             rule))
                                   (cdr language))))
                   qml--treesit-indent-rules)))))

;;;###autoload
(defun +cpp--qml-server-h ()
  "Leave one entry for QML in `eglot-server-programs', ours.
Doom registers `qmlls' from the mode's own `:config', later than any
`after! eglot' in this config, so it would sit in front whatever we did
at load time; and `qmlls' is not the name openSUSE installs, so eglot
found nothing and no server started at all."
  (require 'eglot nil t)
  (when (boundp 'eglot-server-programs)
    (setq eglot-server-programs
          (cons (cons '(qml-mode qml-ts-mode) #'+cpp--qmlls-command)
                (seq-remove (lambda (entry)
                              (string-match-p "qml" (format "%S" (car entry))))
                            eglot-server-programs)))))
