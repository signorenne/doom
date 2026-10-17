;; -*- lexical-binding: t; no-byte-compile: t; -*-
;;; private/cpp/doctor.el
;; Only `executable-find' and `modulep!' checks here: requiring a package
;; from a doctor file trips an eager macro-expansion cycle on Emacs 31.

(assert! (modulep! :lang cc +lsp)
         "This module needs (:lang cc +lsp)")
(assert! (modulep! :tools lsp +eglot)
         "This module is written for eglot: enable (:tools lsp +eglot)")
(assert! (modulep! :tools debugger)
         "Debugging needs :tools debugger (dape)")

(dolist (tool `(("clangd" . "the default language server")
                ("ccls" . "the other language server, SPC k l s")
                ("cmake" . "needed by CMake projects")
                ("ninja" . "the generator the scaffold presets use")
                ;; gdb does not run on Apple silicon; a Mac has lldb-dap.
                ,@(unless (featurep :system 'macos)
                    '(("gdb" . "needed to debug, version 14.1 or newer")))
                ("clang-format" . "formats C and C++, SPC k f")
                ("run-clang-tidy" . "lints the whole project, SPC k g p")
                ("pio" . "PlatformIO, the SPC k p commands")))
  (unless (executable-find (car tool))
    (warn! "Couldn't find %s: %s" (car tool) (cdr tool))))

(when (and (featurep :system 'macos)
           (not (executable-find "gdb"))
           (not (seq-some #'file-executable-p
                          '("/Library/Developer/CommandLineTools/usr/bin/lldb-dap"
                            "/Applications/Xcode.app/Contents/Developer/usr/bin/lldb-dap")))
           (not (executable-find "lldb-dap")))
  (warn! "No lldb-dap, so SPC k d cannot debug C or C++")
  (explain! "xcode-select --install, or brew install llvm"))

(when-let* ((gdb (executable-find "gdb")))
  (let ((version (with-temp-buffer
                   (call-process gdb nil t nil "--version")
                   (goto-char (point-min))
                   (when (re-search-forward "GDB[^0-9]*\\([0-9]+\\.[0-9]+\\)"
                                            nil t)
                     (match-string 1)))))
    (when (and version (version< version "14.1"))
      (warn! "gdb %s is too old for DAP; dape needs gdb >= 14.1" version))))

(unless (seq-some #'executable-find
                  '("qmlls" "qmlls6" "/usr/lib64/qt6/bin/qmlls"))
  (warn! "No qmlls, so QML files get no language server")
  (explain! "openSUSE: zypper in qt6-declarative-tools"))

(unless (seq-some #'executable-find '("cmake-language-server" "neocmakelsp"))
  (warn! "No CMake language server, so CMakeLists.txt gets no completion")
  (explain! "pipx install cmake-language-server, or zypper in neocmakelsp"))

;; Other languages: the kit menu, SPC k SPC, works for any project type
;; projection knows, but a language gets completion, jumps and fixes only
;; with its server on PATH. Each line says how to get one.
;; The languages this config is set up for. Go, Java, Kotlin and Zig
;; were dropped from init.el because nothing here is written in them,
;; so their servers are no longer asked after either.
(dolist (server
         '(("rust-analyzer"
            . "Rust: zypper in rust-analyzer, or rustup component add rust-analyzer")
           ("typescript-language-server"
            . "JS and TS: npm install -g typescript-language-server typescript")))
  (unless (executable-find (car server))
    (warn! "No %s. %s" (car server) (cdr server))))
(unless (seq-some #'executable-find '("basedpyright-langserver" "pyright-langserver" "pylsp"))
  (warn! "No Python server. pipx install basedpyright, or pip install python-lsp-server"))
(unless (executable-find "cargo")
  (warn! "No cargo: Rust projects cannot build. zypper in cargo, or rustup"))
(unless (or (file-executable-p
             (expand-file-name "debug-adapters/codelldb/extension/adapter/codelldb"
                               doom-user-dir))
            (executable-find "lldb-dap"))
  (warn! "No codelldb, so Rust cannot be debugged; C and C++ use gdb, or lldb-dap on a Mac")
  (explain! "+cpp/install-codelldb downloads it into debug-adapters/"))

(assert! (modulep! :private container)
         "A kit whose toolchain lives in a container needs it: enable :private container")

(assert! (modulep! :private qtcreator)
         "The kits come from Qt Creator's settings: enable :private qtcreator")

(assert! (modulep! :private device)
         "Deploying to a board and running it there needs it: enable :private device")
