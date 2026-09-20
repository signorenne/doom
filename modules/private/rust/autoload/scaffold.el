;;; private/rust/autoload/scaffold.el -*- lexical-binding: t; -*-
;;
;; A new cargo project. cargo makes the skeleton, since it is the one
;; that knows what a crate looks like this year; the house files go on
;; top, the way the cpp templates do it.

(declare-function +core-copy-template "scaffold")
(declare-function +core-read-new-project "scaffold")
(declare-function +core-leave-dirvish "dired")
(defvar +rust-templates-dir)

(defun +rust--cargo (dir &rest args)
  "Run cargo with ARGS in DIR, or raise what cargo said.
cargo's own message is the useful one, a missing toolchain or a name it
will not take, so it is carried out rather than left in *Messages*."
  (let ((default-directory (file-name-as-directory dir)))
    (with-temp-buffer
      (unless (zerop (apply #'call-process "cargo" nil t nil args))
        (user-error "cargo: %s"
                    (string-trim
                     (replace-regexp-in-string "[ \t\n]+" " " (buffer-string)))))
      t)))

(defun +rust--overlay (kind dir name)
  "Put the house files for KIND over the project in DIR, called NAME."
  (dolist (part (list "_base" kind))
    (let ((src (file-name-concat +rust-templates-dir part)))
      (when (file-directory-p src)
        (+core-copy-template src dir name)))))

(defun +rust--lints ()
  "The lint table every scaffolded crate carries.
Written into Cargo.toml rather than left to a flag, so `cargo clippy'
and the editor and CI all see the same rules."
  (concat "\n[lints.rust]\n"
          "unsafe_code = \"warn\"\n"
          "missing_docs = \"warn\"\n"
          "\n[lints.clippy]\n"
          "all = { level = \"warn\", priority = -1 }\n"
          "pedantic = { level = \"warn\", priority = -1 }\n"
          "unwrap_used = \"warn\"\n"
          "expect_used = \"warn\"\n"))

(defun +rust--add-lints (file)
  "Append the lint table to the Cargo.toml at FILE, once."
  (when (and (file-exists-p file)
             (with-temp-buffer
               (insert-file-contents file)
               (not (string-match-p "^\\[lints" (buffer-string)))))
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-max))
      (unless (bolp) (insert "\n"))
      (insert (+rust--lints))
      (write-region (point-min) (point-max) file nil 'quiet))))

(defun +rust--crate-doc (dir name)
  "Give the crate root in DIR a //! line, so NAME starts without a warning.
The lint table asks for documentation, and cargo\='s own main.rs carries
none: a project made here would greet you with a warning about itself."
  (dolist (file (list (expand-file-name "src/main.rs" dir)
                      (expand-file-name "src/lib.rs" dir)))
    (when (and (file-exists-p file)
               (with-temp-buffer
                 (insert-file-contents file)
                 (not (string-prefix-p "//!" (buffer-string)))))
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (insert (format "//! `%s`.\n//!\n//! Say here what this crate is for.\n\n"
                        name))
        (write-region (point-min) (point-max) file nil 'quiet)))))

(defun +rust--workspace (dir name)
  "Write the workspace Cargo.toml in DIR and its two first members."
  (make-directory (file-name-concat dir "crates") t)
  (with-temp-file (expand-file-name "Cargo.toml" dir)
    (insert "[workspace]\n"
            "resolver = \"2\"\n"
            "members = [\"crates/*\"]\n"
            "\n[workspace.package]\n"
            "edition = \"2021\"\n"
            (format "repository = \"https://github.com/%s/%s\"\n"
                    (bound-and-true-p +core-github-user) name)
            (+rust--lints)))
  (let ((core (file-name-concat dir "crates" (concat name "_core")))
        (app (file-name-concat dir "crates" name)))
    (+rust--cargo dir "new" "--lib" (file-relative-name core dir))
    (+rust--cargo dir "new" "--bin" (file-relative-name app dir))
    (+rust--crate-doc core (concat name "_core"))
    (+rust--crate-doc app name)
    ;; The binary uses the library, which is the point of a workspace.
    (let ((manifest (expand-file-name "Cargo.toml" app)))
      (when (file-exists-p manifest)
        (with-temp-buffer
          (insert-file-contents manifest)
          (goto-char (point-max))
          (unless (bolp) (insert "\n"))
          (insert (format "\n[dependencies]\n%s_core = { path = \"../%s_core\" }\n"
                          name name))
          (write-region (point-min) (point-max) manifest nil 'quiet))))
    app))

;;;###autoload
(defun +rust-project-kinds ()
  "The kinds of cargo project this module can start."
  '("bin" "lib" "workspace"))

;;;###autoload
(defun +rust/new-project (kind dir name)
  "Start cargo project NAME of KIND in DIR, and open it.
KIND is \"bin\" for a program, \"lib\" for a library, \"workspace\" for
several crates together."
  (interactive
   (cons (completing-read "Kind: " (+rust-project-kinds) nil t nil nil "bin")
         (+core-read-new-project)))
  (unless (executable-find "cargo")
    (user-error "cargo is not installed: zypper in rustup, then rustup default stable"))
  (when (and (file-exists-p dir) (directory-files dir nil "^[^.]"))
    (unless (y-or-n-p (format "%s is not empty.  Continue? " dir))
      (user-error "Aborted")))
  (make-directory dir t)
  (let ((entry
         (if (equal kind "workspace")
             (+rust--workspace dir name)
           ;; `init' rather than `new': the directory is already there,
           ;; made above, and cargo refuses to create one that exists.
           (+rust--cargo dir "init" (if (equal kind "lib") "--lib" "--bin")
                         "--name" name)
           (+rust--add-lints (expand-file-name "Cargo.toml" dir))
           (+rust--crate-doc dir name)
           dir)))
    (+rust--overlay kind dir name)
    ;; Made from a listing, the dirvish panes would stay standing round it.
    (+core-leave-dirvish)
    (find-file (or (seq-find #'file-exists-p
                             (list (expand-file-name "src/main.rs" entry)
                                   (expand-file-name "src/lib.rs" entry)
                                   (expand-file-name "Cargo.toml" entry)))
                   dir))
    (message "%s created: F7 builds it, F6 runs it, SPC k m is the panel" name)))
