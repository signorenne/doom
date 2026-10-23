;;; private/cpp/autoload/pio.el -*- lexical-binding: t; -*-
;;
;; Every command runs from the nearest directory holding a platformio.ini,
;; for the environment in `+pio-env' or the project's default.

(declare-function gdb "gdb-mi")
(defvar +core-projects-dir)
(defvar +core-compile-name)

(defvar +pio-env)                       ; config.el, with its safe-local put

(defvar +pio--boards-cache nil
  "Cached output of `pio boards --json-output'.")


;;
;;; Helpers

;;;###autoload
(defun +pio--root (&optional noerror)
  "Directory of the nearest platformio.ini.
Signals an error unless NOERROR."
  (or (locate-dominating-file default-directory "platformio.ini")
      (unless noerror
        (user-error "No platformio.ini above %s"
                    (abbreviate-file-name default-directory)))))

(defun +pio--envs (&optional root)
  "Environments declared in ROOT's platformio.ini."
  (let ((root (or root (+pio--root))))
    (with-temp-buffer
      (insert-file-contents (expand-file-name "platformio.ini" root))
      (let (envs)
        (while (re-search-forward "^\\[env:\\([^]]+\\)\\]" nil t)
          (push (match-string 1) envs))
        (nreverse envs)))))

(defun +pio--command (&rest args)
  "The pio command line for ARGS, with the selected environment."
  (mapconcat #'shell-quote-argument
             (append (list "pio") args
                     (when +pio-env (list "-e" +pio-env)))
             " "))

(defun +pio--compile (&rest args)
  "Run pio ARGS in a compilation buffer."
  (+core-compile "pio" (apply #'+pio--command args) (+pio--root)))

(defun +pio--vterm (name &rest args)
  "Run pio ARGS in a vterm buffer called NAME, so it takes input."
  (+core-run-in-vterm name (apply #'+pio--command args) (+pio--root)))

;; What the projection project type runs.
;;;###autoload
(defun +pio--configure-command () (+pio--command "run" "-t" "compiledb"))
;;;###autoload
(defun +pio--build-command () (+pio--command "run"))
;;;###autoload
(defun +pio--upload-command () (+pio--command "run" "-t" "upload"))
;;;###autoload
(defun +pio--test-command () (+pio--command "test"))

;;;###autoload
(defun +pio-targets ()
  "Build targets offered for a PlatformIO project, per environment."
  (let ((root (+pio--root 'noerror)))
    (when root
      (append
       `(("pio:build"     . ,(+pio--command "run"))
         ("pio:upload"    . ,(+pio--command "run" "-t" "upload"))
         ("pio:clean"     . ,(+pio--command "run" "-t" "clean"))
         ("pio:test"      . ,(+pio--command "test"))
         ("pio:compiledb" . ,(+pio--command "run" "-t" "compiledb"))
         ("pio:check"     . ,(+pio--command "check")))
       (cl-loop for env in (+pio--envs root)
                collect (cons (format "pio:%s:build" env)
                              (format "pio run -e %s" env))
                collect (cons (format "pio:%s:upload" env)
                              (format "pio run -e %s -t upload" env)))))))


;;
;;; Commands

;;;###autoload
(defun +pio/set-env (env &optional persist)
  "Build for environment ENV, or the project default when it is empty.
With prefix argument PERSIST, write it to .dir-locals.el."
  (interactive
   (let* ((envs (+pio--envs))
          (choice (completing-read "Environment (empty for the default): "
                                   (cons "" envs) nil t nil nil
                                   (or +pio-env ""))))
     (list (unless (string-empty-p choice) choice) current-prefix-arg)))
  (setq-default +pio-env env)
  (setq +pio-env env)
  ;; And the project's other buffers, which may hold their own value
  ;; from .dir-locals.el.
  (when-let* ((root (+pio--root 'noerror)))
    (dolist (buffer (buffer-list))
      (with-current-buffer buffer
        (when (and buffer-file-name (local-variable-p '+pio-env)
                   (file-in-directory-p buffer-file-name root))
          (setq +pio-env env)))))
  (when persist
    (+core-dir-locals-set (+pio--root) '+pio-env env))
  (message "PlatformIO environment: %s" (or env "project default")))

;;;###autoload
(defun +pio/build ()
  "Build the firmware."
  (interactive) (+pio--compile "run"))

;;;###autoload
(defun +pio/upload ()
  "Build the firmware and flash it to the board."
  (interactive) (+pio--compile "run" "-t" "upload"))

;;;###autoload
(defun +pio/clean ()
  "Delete the build output."
  (interactive) (+pio--compile "run" "-t" "clean"))

;;;###autoload
(defun +pio/test ()
  "Run the project's tests on the board."
  (interactive) (+pio--compile "test"))

;;;###autoload
(defun +pio/compiledb ()
  "Write compile_commands.json so the language server sees the flags."
  (interactive) (+pio--compile "run" "-t" "compiledb"))

;;;###autoload
(defun +pio/update ()
  "Update this project's platforms, tools and libraries."
  (interactive) (+pio--compile "pkg" "update"))

;;;###autoload
(defun +pio/device-list ()
  "List the serial devices that are plugged in."
  (interactive)
  ;; It takes no environment: -e is an error there.
  (let ((+pio-env nil))
    (+pio--compile "device" "list")))

;;;###autoload
(defun +pio/lib-install (spec)
  "Install library SPEC into the project.
SPEC is a name, owner/name@version, or a URL."
  (interactive (list (read-string "Library: ")))
  (+pio--compile "pkg" "install" "-l" spec))

;;;###autoload
(defun +pio/monitor ()
  "Open the serial monitor.  C-c exits it."
  (interactive)
  (+pio--vterm "*pio monitor*" "device" "monitor"))

;;;###autoload
(defun +pio/home ()
  "Start PlatformIO Home and open it in the browser."
  (interactive)
  (let ((default-directory (or (+pio--root 'noerror) default-directory)))
    (start-process "pio-home" "*pio home*" "pio" "home")
    (message "PlatformIO Home is starting, kill *pio home* to stop it")))

;;;###autoload
(defun +pio/debug ()
  "Debug the firmware with gdb, through PlatformIO.
Needs a board or probe that supports debugging."
  (interactive)
  (require 'gdb-mi)
  (let ((default-directory (+pio--root)))
    ;; pio options first, then the arguments forwarded to gdb.
    (gdb (mapconcat #'shell-quote-argument
                    (append (list "pio" "debug")
                            (when +pio-env (list "-e" +pio-env))
                            (list "--interface=gdb" "-x" ".pioinit" "-i=mi"))
                    " "))))

(defun +pio--boards ()
  "Every board PlatformIO knows, fetched once."
  (or +pio--boards-cache
      (setq +pio--boards-cache
            (with-temp-buffer
              (unless (zerop (call-process "pio" nil t nil
                                          "boards" "--json-output"))
                (user-error "pio boards failed: %s" (buffer-string)))
              (goto-char (point-min))
              (json-parse-buffer :object-type 'alist :array-type 'list)))))

;; Autoloaded: scaffold.el asks for the board before it starts.
;;;###autoload
(defun +pio--read-board ()
  "Ask which board, and return its id."
  (let* ((boards (+pio--boards))
         (table (mapcar (lambda (b)
                          (cons (format "%-32s %s (%s, %s)"
                                        (alist-get 'id b)
                                        (alist-get 'name b)
                                        (alist-get 'platform b)
                                        (alist-get 'mcu b))
                                (alist-get 'id b)))
                        boards))
         (choice (completing-read "Board: " table nil t)))
    (cdr (assoc choice table))))

;;;###autoload
(defun +pio/boards (board)
  "Look up a BOARD and insert or copy its id."
  (interactive (list (+pio--read-board)))
  (pcase (read-char-choice
          (format "%s: [i]nsert, [c]opy, [q]uit? " board)
          '(?i ?c ?q))
    (?i (insert (format "board = %s" board)))
    (?c (kill-new board) (message "Copied %s" board))
    (_ nil)))

;;;###autoload
(defun +pio--read-framework ()
  "Ask which framework, or nothing for the board's own default."
  (let ((fw (completing-read
             "Framework (empty for the board default): "
             '("" "arduino" "espidf" "stm32cube" "zephyr" "mbed" "freertos")
             nil nil)))
    (unless (string-empty-p fw) fw)))

;;;###autoload
(defun +pio/new-project (dir board &optional framework)
  "Start a PlatformIO project in DIR for BOARD, using FRAMEWORK.
Opens platformio.ini when it is ready."
  (interactive
   (list (read-directory-name "Project directory: " +core-projects-dir)
         (+pio--read-board)
         (+pio--read-framework)))
  (make-directory dir t)
  (+core-compile "pio"
                 (mapconcat
                  #'shell-quote-argument
                  (append (list "pio" "project" "init" "--board" board)
                          (when framework
                            (list "--project-option"
                                  (concat "framework=" framework))))
                  " ")
                 dir)
  (letrec ((open-ini
            (lambda (buf status)
              (when (equal (buffer-local-value '+core-compile-name buf) "pio")
                (remove-hook 'compilation-finish-functions open-ini)
                (when (string-prefix-p "finished" status)
                  (find-file (expand-file-name "platformio.ini" dir)))))))
    (add-hook 'compilation-finish-functions open-ini)))

;;
;;; The compilation database, without being asked for it

(defvar +pio--compiledb-done nil
  "Projects this session has already written a compilation database for.")

(defun +pio--compiledb-stale (root db)
  "Why DB, ROOT's compile_commands.json, no longer answers for it, or nil.
Written for another directory, the project moved since: every relative
path in it, the include directories, the sources, the specs file the
cross compiler is asked about, pointed into a directory that was gone,
and clangd found no header at all. Or older than platformio.ini, whose
flags it carries."
  (cond
   ((file-newer-than-file-p (expand-file-name "platformio.ini" root) db)
    "platformio.ini is newer")
   ((with-temp-buffer
      ;; The first entry says it, so only the start of the file is read:
      ;; the file can be very large, and the entry's long command comes
      ;; before its directory.
      (insert-file-contents db nil 0 (* 1024 1024))
      (and (re-search-forward "\"directory\": *\"\\([^\"]+\\)\"" nil t)
           (not (file-equal-p (match-string 1) root))
           (format "it was written in %s" (match-string 1)))))))

;;;###autoload
(defun +pio--clangd-db (root)
  "Where ROOT's compilation database for clangd is: what pio writes, made
readable to clang by bin/clangd-db, in .pio, which git leaves alone."
  (expand-file-name ".pio/clangd/compile_commands.json" root))

(defun +pio--python ()
  "PlatformIO's own Python, which every pio comes with, else python3."
  (or (when-let* ((pio (executable-find "pio"))
                  (python (expand-file-name "python" (file-name-directory (file-truename pio))))
                  ((file-executable-p python)))
        python)
      (executable-find "python3")))

(defvar +pio--clangd-db-tried (make-hash-table :test #'equal)
  "ROOT to the time of the database the clangd copy was last tried from,
so a copy that cannot be written is not tried at every file.")

(defun +pio--write-clangd-db (root)
  "Write ROOT's database for clangd from pio's, then start its servers
again on it.  A second's work, in the background."
  (let ((db (expand-file-name "compile_commands.json" root))
        (script (expand-file-name "bin/clangd-db" doom-user-dir))
        (python (+pio--python)))
    (puthash root (file-attribute-modification-time (file-attributes db))
             +pio--clangd-db-tried)
    (when python
      (make-process
       :name "pio-clangd-db"
       :buffer (generate-new-buffer " *pio clangd db*")
       :noquery t
       :command (list python script db (+pio--clangd-db root))
       :sentinel
       (lambda (process _event)
         (unless (process-live-p process)
           (let ((ok (eq (process-exit-status process) 0))
                 (said (with-current-buffer (process-buffer process)
                         (string-trim (buffer-string)))))
             (kill-buffer (process-buffer process))
             ;; A server started before the copy was there, as the file
             ;; opened, kept its errors: it starts again on the copy.
             (when ok (+pio--reconnect-servers root))
             (message "pio: %s" (if ok
                                    (concat "clangd has the flags, " said)
                                  (concat "the database for clangd failed: " said))))))))))

;;;###autoload
(defun +pio--compiledb-h ()
  "Give clangd a PlatformIO project's flags, with nothing to set up.
pio writes compile_commands.json when the project has none, or one that
is stale, see `+pio--compiledb-stale'; and from it the copy clangd starts
on, `+pio--clangd-db', whenever that is missing or older, so a database
pio wrote from a terminal is taken up as well.
A firmware's flags are nothing a language server can guess: the cross
compiler, the framework's headers, the board's defines. pio knows them
and writes them out in a minute for a project that has been built, so
the first C or C++ file opened in one asks for them.

Only for a project with a .pio/build: without one the answer means
fetching a toolchain, which is minutes and not a thing to start behind
someone's back. SPC k p i asks for it then."
  (when-let* (((derived-mode-p 'c-mode 'c++-mode 'c-ts-mode 'c++-ts-mode))
              (root (ignore-errors (+pio--root 'noerror)))
              (root (expand-file-name root))
              ((file-directory-p (expand-file-name ".pio/build" root))))
    (let* ((db (expand-file-name "compile_commands.json" root))
           (copy (+pio--clangd-db root))
           (why (if (file-exists-p db)
                    (+pio--compiledb-stale root db)
                  "there is none")))
      (cond
       ((and why (not (member root +pio--compiledb-done)) (executable-find "pio"))
        (push root +pio--compiledb-done)
        (let ((default-directory root))
          (message "pio: writing the compilation database for %s, %s..."
                   (file-name-nondirectory (directory-file-name root)) why)
          (make-process
           :name "pio-compiledb"
           :buffer (generate-new-buffer " *pio compiledb*")
           :noquery t
           :command (list (executable-find "pio") "run" "-t" "compiledb")
           :sentinel
           (lambda (process _event)
             (unless (process-live-p process)
               (let ((ok (eq (process-exit-status process) 0)))
                 (when (buffer-live-p (process-buffer process))
                   (kill-buffer (process-buffer process)))
                 (if ok
                     (+pio--write-clangd-db root)
                   (message "pio: could not write the compilation database; SPC k p i says why"))))))))
       ((and (not why)
             (or (not (file-exists-p copy)) (file-newer-than-file-p db copy))
             (not (equal (gethash root +pio--clangd-db-tried)
                         (file-attribute-modification-time (file-attributes db)))))
        (+pio--write-clangd-db root))))))

(declare-function eglot-current-server "eglot")
(declare-function eglot-reconnect "eglot")

(defun +pio--reconnect-servers (root)
  "Start again every language server running for a file under ROOT."
  (let (servers)
    (dolist (buffer (buffer-list))
      (when-let* ((file (buffer-file-name buffer))
                  ((file-in-directory-p file root))
                  (server (and (fboundp 'eglot-current-server)
                               (with-current-buffer buffer (eglot-current-server)))))
        (cl-pushnew server servers)))
    (dolist (server servers)
      (eglot-reconnect server))))
