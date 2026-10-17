;; -*- lexical-binding: t; no-byte-compile: t; -*-
;;; private/rust/doctor.el

(assert! (modulep! :lang rust)
         "This module builds on Doom's rust module: enable (:lang rust +lsp +tree-sitter)")
(assert! (modulep! :private core)
         "This module uses core's compile runner and project root: enable (:private core)")

(unless (executable-find "cargo")
  (error! "No cargo: %s, then rustup default stable"
          (if (featurep :system 'macos)
              "brew install rustup with $(brew --prefix rustup)/bin on PATH"
            "zypper in rustup")))

(unless (executable-find "rustc")
  (error! "No rustc, although cargo is here: rustup default stable"))

;; rust-analyzer is not packaged for Tumbleweed; rustup carries it.
(unless (executable-find "rust-analyzer")
  (warn! "No rust-analyzer, so no completion or go-to-definition: rustup component add rust-analyzer"))

(unless (executable-find "cargo-clippy")
  (warn! "No clippy, so SPC k m l does nothing: rustup component add clippy"))

(unless (executable-find "rustfmt")
  (warn! "No rustfmt, so a Rust buffer is not formatted on save: rustup component add rustfmt"))

;; The sources let rust-analyzer show the standard library's definitions.
(unless (and (executable-find "rustc")
             (let ((dir (string-trim
                         (shell-command-to-string "rustc --print sysroot 2>/dev/null"))))
               (and (not (string-empty-p dir))
                    (file-directory-p
                     (expand-file-name "lib/rustlib/src/rust" dir)))))
  (warn! "No rust-src: go-to-definition stops at the standard library. rustup component add rust-src"))

(unless (file-executable-p
         (expand-file-name "debug-adapters/codelldb/extension/adapter/codelldb"
                           doom-user-dir))
  (warn! "No codelldb, so SPC k d cannot debug Rust: M-x +cpp/install-codelldb"))
