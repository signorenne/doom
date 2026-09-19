;;; private/rust/autoload/rust.el -*- lexical-binding: t; -*-
;;
;; What a cargo build depends on, and the commands built from it. The
;; shape follows the cpp module: a few settings kept in .dir-locals.el,
;; every command built from them, so SPC k b and the panel and the run
;; all mean the same thing.

(declare-function +core-project-root "lib")
(declare-function +core-dir-locals-set "lib")
(declare-function +core-compile "lib")

(defvar +rust-cargo-timeout 10
  "Seconds to wait on `cargo metadata' before giving up on it.")


;;
;;; The settings

;; Each is a directory local variable: set once for the project, read by
;; every command. Safe as a local variable because a string or a symbol
;; from this list is all any of them can be.

;;;###autoload
(defvar-local +rust-profile nil
  "The cargo profile to build with: nil or \"dev\", \"release\", or the
name of a profile the project defines.  Kept in .dir-locals.el.")
;;;###autoload
(put '+rust-profile 'safe-local-variable #'stringp)

;;;###autoload
(defvar-local +rust-features nil
  "The features to build with: a comma separated string, the symbol
`all', the symbol `none', or nil for the defaults.")
;;;###autoload
(put '+rust-features 'safe-local-variable
     (lambda (v) (or (stringp v) (memq v '(all none)))))

;;;###autoload
(defvar-local +rust-member nil
  "The workspace member to build, or nil for the whole workspace.")
;;;###autoload
(put '+rust-member 'safe-local-variable #'stringp)

;;;###autoload
(defvar-local +rust-target nil
  "The target triple to build for, or nil for this machine.")
;;;###autoload
(put '+rust-target 'safe-local-variable #'stringp)

;;;###autoload
(defvar-local +rust-run-args nil
  "Arguments passed to the program after `--', as one string.")
;;;###autoload
(put '+rust-run-args 'safe-local-variable #'stringp)


;;
;;; The project

;;;###autoload
(defun +rust-project-p (&optional dir)
  "Non-nil when DIR, or the current project, is a cargo project."
  (let ((root (or dir (+core-project-root 'noerror))))
    (and root (file-exists-p (expand-file-name "Cargo.toml" root)))))

;;;###autoload
(defun +rust-root ()
  "The cargo project's root, or an error."
  (let ((root (+core-project-root 'noerror)))
    (unless (+rust-project-p root)
      (user-error "No Cargo.toml here: this is not a cargo project"))
    (file-name-as-directory (expand-file-name root))))

(defun +rust--cargo-toml ()
  "The text of the project's Cargo.toml."
  (let ((file (expand-file-name "Cargo.toml" (+rust-root))))
    (when (file-readable-p file)
      (with-temp-buffer (insert-file-contents file) (buffer-string)))))

(defun +rust--metadata ()
  "What `cargo metadata' says about the project, as an alist, or nil.
Asked of cargo rather than read out of Cargo.toml: a workspace member
can be a glob, and a feature can come from a dependency."
  (when (executable-find "cargo")
    (let ((default-directory (+rust-root)))
      (with-temp-buffer
        (when (zerop (or (ignore-errors
                           (call-process "cargo" nil t nil "metadata"
                                         "--no-deps" "--format-version" "1"))
                         1))
          (goto-char (point-min))
          (ignore-errors (json-parse-buffer :object-type 'alist
                                            :array-type 'list)))))))


;;
;;; The flags every command carries

;;;###autoload
(defun +rust-flags ()
  "The cargo flags this project is set to, as a list of strings."
  (append
   (pcase +rust-profile
     ((or 'nil "dev" "") nil)
     ("release" '("--release"))
     (profile (list "--profile" profile)))
   (pcase +rust-features
     ('all '("--all-features"))
     ('none '("--no-default-features"))
     ((and (pred stringp) (pred (lambda (s) (not (string-empty-p s)))) features)
      (list "--features" features))
     (_ nil))
   (when +rust-member (list "-p" +rust-member))
   (when +rust-target (list "--target" +rust-target))))

(defun +rust--command (subcommand &rest extra)
  "The cargo command line for SUBCOMMAND with the project's flags."
  (string-join (append (list "cargo" subcommand) (+rust-flags)
                       (delq nil extra))
               " "))

;;;###autoload
(defun +rust-build-command ()
  "What `SPC k b' runs in a cargo project."
  (+rust--command "build"))

;;;###autoload
(defun +rust-test-command ()
  "What `SPC k t' runs in a cargo project."
  (+rust--command "test"))

;;;###autoload
(defun +rust-install-command ()
  "What `SPC k i' runs in a cargo project."
  (+rust--command "install" "--path" "."))

;;;###autoload
(defun +rust-run-command ()
  "What `SPC k r' runs in a cargo project, arguments and all."
  (+rust--command "run"
                  (when (and +rust-run-args (not (string-empty-p +rust-run-args)))
                    (concat "-- " +rust-run-args))))


;;
;;; The commands

(defun +rust--compile (name command)
  "Run COMMAND in a compilation buffer called NAME, from the root."
  (+core-compile name command (+rust-root)))

;;;###autoload
(defun +rust/build ()
  "Build the project with the flags it is set to."
  (interactive)
  (+rust--compile "build" (+rust-build-command)))

;;;###autoload
(defun +rust/run ()
  "Run what the project builds, with the arguments it is set to."
  (interactive)
  (+rust--compile "run rust" (+rust-run-command)))

;;;###autoload
(defun +rust/run-with-args (args)
  "Run the project once with ARGS, without writing them down."
  (interactive (list (read-string "Arguments: " +rust-run-args)))
  (+rust--compile "run rust"
                  (+rust--command "run" (unless (string-empty-p args)
                                          (concat "-- " args)))))

;;;###autoload
(defun +rust/test ()
  "Run the project's tests with the flags it is set to."
  (interactive)
  (+rust--compile "test" (+rust-test-command)))

;;;###autoload
(defun +rust/check ()
  "Check the project without building it, which is the fast one."
  (interactive)
  (+rust--compile "check" (+rust--command "check" "--all-targets")))

;;;###autoload
(defun +rust/clippy ()
  "Run clippy over the project."
  (interactive)
  (unless (executable-find "cargo-clippy")
    (user-error "clippy is not installed: rustup component add clippy"))
  (+rust--compile "clippy" (+rust--command "clippy" "--all-targets")))

;;;###autoload
(defun +rust/clippy-fix ()
  "Run clippy and apply the fixes it is sure of."
  (interactive)
  (+rust--compile "clippy" (+rust--command "clippy" "--all-targets" "--fix"
                                           "--allow-dirty" "--allow-staged")))

;;;###autoload
(defun +rust/test-at-point ()
  "Run the test the cursor is in, and no other."
  (interactive)
  (let ((name (+rust--test-at-point)))
    (unless name (user-error "No test here"))
    (+rust--compile "test" (+rust--command "test" name "--" "--exact" "--nocapture"))))

(defun +rust--test-at-point ()
  "The path of the test the cursor is in, module and all, or nil."
  (save-excursion
    (let ((case-fold-search nil)
          (name (when (re-search-backward
                       "^[[:space:]]*\\(?:pub[[:space:]]+\\)?\\(?:async[[:space:]]+\\)?fn[[:space:]]+\\([a-zA-Z0-9_]+\\)"
                       nil t)
                  (match-string-no-properties 1)))
          (modules nil))
      (when name
        ;; Every `mod' the function sits inside, outermost last: cargo
        ;; wants the path, not the bare name.
        (while (re-search-backward "^[[:space:]]*\\(?:pub[[:space:]]+\\)?mod[[:space:]]+\\([a-zA-Z0-9_]+\\)"
                                   nil t)
          (push (match-string-no-properties 1) modules))
        (string-join (append modules (list name)) "::")))))

;;;###autoload
(defun +rust/doc ()
  "Build the project's documentation and open it."
  (interactive)
  (+rust--compile "doc" (+rust--command "doc" "--open" "--no-deps")))

;;;###autoload
(defun +rust/bench ()
  "Run the project's benchmarks."
  (interactive)
  (+rust--compile "bench" (+rust--command "bench")))

;;;###autoload
(defun +rust/clean ()
  "Remove what the build made."
  (interactive)
  (+rust--compile "clean" (+rust--command "clean")))

;;;###autoload
(defun +rust/update ()
  "Update the locked dependencies."
  (interactive)
  (+rust--compile "update" "cargo update"))

;;;###autoload
(defun +rust/open-cargo-toml ()
  "Open the project's Cargo.toml."
  (interactive)
  (find-file (expand-file-name "Cargo.toml" (+rust-root))))

;;;###autoload
(defun +rust/expand ()
  "Show the file with its macros expanded, if cargo-expand is installed."
  (interactive)
  (unless (executable-find "cargo-expand")
    (user-error "cargo-expand is not installed: cargo install cargo-expand"))
  (+rust--compile "expand" (+rust--command "expand")))


;;;###autoload
(defun +rust--debug-program ()
  "The binary to debug: what cargo would run, built first.
cargo puts it under target/<profile>/, named after the package, so the
answer is asked of cargo rather than guessed."
  (let* ((default-directory (+rust-root))
         (profile (pcase +rust-profile
                    ((or 'nil "dev" "") "debug")
                    ("release" "release")
                    (other other)))
         (dir (file-name-concat (+rust-root) "target" profile))
         (names (when-let* ((metadata (+rust--metadata)))
                  (mapcan (lambda (package)
                            (mapcar (lambda (target)
                                      (alist-get 'name target))
                                    (seq-filter
                                     (lambda (target)
                                       (member "bin" (alist-get 'kind target)))
                                     (alist-get 'targets package))))
                          (alist-get 'packages metadata))))
         (candidates (seq-filter #'file-executable-p
                                 (mapcar (lambda (n) (expand-file-name n dir))
                                         names))))
    (pcase (length candidates)
      (0 (user-error "Nothing built under %s yet: F7 first"
                     (abbreviate-file-name dir)))
      (1 (car candidates))
      (_ (completing-read "Debug which: " candidates nil t)))))

;;;###autoload
(defun +rust/debug ()
  "Debug what this project builds, with codelldb."
  (interactive)
  (unless (fboundp 'dape)
    (user-error "dape is not here to debug with"))
  (let ((program (+rust--debug-program)))
    (funcall #'dape (list 'codelldb-rust :program program
                          :cwd (+rust-root)))))


;;
;;; Setting what a build depends on

(defun +rust--profiles ()
  "The profiles the project defines, plus cargo's own two."
  (let ((named (when-let* ((toml (+rust--cargo-toml)))
                 (let ((start 0) (out nil))
                   (while (string-match "^\\[profile\\.\\([^]]+\\)\\]" toml start)
                     (push (match-string 1 toml) out)
                     (setq start (match-end 0)))
                   (nreverse out)))))
    (delete-dups (append '("dev" "release") named))))

;;;###autoload
(defun +rust/set-profile (profile)
  "Build with PROFILE from now on, kept in .dir-locals.el."
  (interactive (list (completing-read "Profile: " (+rust--profiles) nil nil nil nil
                                      (or +rust-profile "dev"))))
  (let ((root (+rust-root)))
    (+core-dir-locals-set root '+rust-profile
                          (unless (equal profile "dev") profile))
    (setq-local +rust-profile (unless (equal profile "dev") profile))
    (message "Building with the %s profile" profile)))

;;;###autoload
(defun +rust/toggle-profile ()
  "Swap between dev and release, the two anyone switches between."
  (interactive)
  (+rust/set-profile (if (equal +rust-profile "release") "dev" "release")))

(defun +rust--features ()
  "The features the project defines."
  (let ((metadata (+rust--metadata)))
    (if metadata
        (delete-dups
         (mapcan (lambda (package)
                   (mapcar (lambda (pair) (symbol-name (car pair)))
                           (alist-get 'features package)))
                 (alist-get 'packages metadata)))
      ;; No cargo, or it failed: read the section by hand.
      (when-let* ((toml (+rust--cargo-toml))
                  ((string-match "^\\[features\\]$" toml)))
        (let ((rest (substring toml (match-end 0)))
              (out nil) (start 0))
          (when (string-match "^\\[" rest)
            (setq rest (substring rest 0 (match-beginning 0))))
          (while (string-match "^\\([a-zA-Z0-9_-]+\\)[[:space:]]*=" rest start)
            (push (match-string 1 rest) out)
            (setq start (match-end 0)))
          (nreverse out))))))

;;;###autoload
(defun +rust/set-features ()
  "Choose the features to build with, kept in .dir-locals.el.
Nothing chosen means the defaults; everything means --all-features."
  (interactive)
  (let* ((available (+rust--features))
         (chosen (completing-read-multiple
                  "Features (empty for the defaults): " available nil nil
                  (when (stringp +rust-features) +rust-features)))
         (value (cond ((null chosen) nil)
                      ((and available
                            (= (length chosen) (length available))) 'all)
                      (t (string-join chosen ",")))))
    (+core-dir-locals-set (+rust-root) '+rust-features value)
    (setq-local +rust-features value)
    (message "Features: %s"
             (pcase value
               ('nil "the defaults") ('all "all of them") ('none "none")
               (_ value)))))

;;;###autoload
(defun +rust/set-no-default-features ()
  "Build with no default features, or back to the defaults."
  (interactive)
  (let ((value (unless (eq +rust-features 'none) 'none)))
    (+core-dir-locals-set (+rust-root) '+rust-features value)
    (setq-local +rust-features value)
    (message "%s" (if value "No default features" "The default features"))))

(defun +rust--members ()
  "The workspace members, by name."
  (when-let* ((metadata (+rust--metadata)))
    (mapcar (lambda (package) (alist-get 'name package))
            (alist-get 'packages metadata))))

;;;###autoload
(defun +rust/set-member (member)
  "Build only workspace member MEMBER, or the whole workspace.
Empty means the whole workspace."
  (interactive
   (list (completing-read "Member (empty for the whole workspace): "
                          (or (+rust--members)
                              (user-error "cargo could not list the members"))
                          nil nil nil nil (or +rust-member ""))))
  (let ((value (unless (string-empty-p member) member)))
    (+core-dir-locals-set (+rust-root) '+rust-member value)
    (setq-local +rust-member value)
    (message "%s" (if value (format "Building %s alone" value)
                    "Building the whole workspace"))))

(defun +rust--targets ()
  "The target triples rustup has installed."
  (when (executable-find "rustup")
    (with-temp-buffer
      (when (zerop (or (ignore-errors
                         (call-process "rustup" nil t nil "target" "list"
                                       "--installed"))
                       1))
        (split-string (buffer-string) "\n" t)))))

;;;###autoload
(defun +rust/set-target (target)
  "Build for TARGET from now on.  Empty means this machine."
  (interactive
   (list (completing-read "Target (empty for this machine): "
                          (+rust--targets) nil nil nil nil (or +rust-target ""))))
  (let ((value (unless (string-empty-p target) target)))
    (+core-dir-locals-set (+rust-root) '+rust-target value)
    (setq-local +rust-target value)
    (message "%s" (if value (format "Building for %s" value)
                    "Building for this machine"))))

;;;###autoload
(defun +rust/set-run-args (args)
  "Keep ARGS for the program, so SPC k r passes them every time."
  (interactive (list (read-string "Arguments: " +rust-run-args)))
  (let ((value (unless (string-empty-p args) args)))
    (+core-dir-locals-set (+rust-root) '+rust-run-args value)
    (setq-local +rust-run-args value)
    (message "%s" (if value (format "Arguments: %s" value)
                    "No arguments"))))


;;
;;; What it all adds up to

;;;###autoload
(defun +rust-summary ()
  "One line saying what a build here depends on, for the panel."
  (if (not (+rust-project-p))
      "not a cargo project"
    (string-join
     (delq nil
           (list (format "profile %s" (or +rust-profile "dev"))
                 (pcase +rust-features
                   ('all "all features") ('none "no default features")
                   ((pred stringp) (format "features %s" +rust-features))
                   (_ nil))
                 (when +rust-member (format "member %s" +rust-member))
                 (when +rust-target (format "target %s" +rust-target))
                 (when +rust-run-args (format "args %s" +rust-run-args))))
     ", ")))

;;;###autoload
(defun +rust/project-status ()
  "Say what is set up here and what is missing."
  (interactive)
  (let ((lines nil))
    (push (format "cargo:         %s" (or (executable-find "cargo") "MISSING")) lines)
    (push (format "rust-analyzer: %s"
                  (or (executable-find "rust-analyzer")
                      "MISSING (rustup component add rust-analyzer)"))
          lines)
    (push (format "clippy:        %s"
                  (or (executable-find "cargo-clippy")
                      "MISSING (rustup component add clippy)"))
          lines)
    (push (format "rustfmt:       %s"
                  (or (executable-find "rustfmt")
                      "MISSING (rustup component add rustfmt)"))
          lines)
    (when (+rust-project-p)
      (push (format "this project:  %s" (+rust-summary)) lines))
    (message "%s" (string-join (nreverse lines) "\n"))))
