;; -*- lexical-binding: t; no-byte-compile: t; -*-
;;; private/web/doctor.el

;; Every server is looked for on PATH rather than at a fixed path, so
;; the module does not care where it is installed.

(assert! (modulep! :private core)
         "This module uses core's compile runner and project root: enable (:private core)")
(assert! (modulep! :lang javascript)
         "This module builds on Doom's javascript module: enable (:lang javascript +lsp +tree-sitter)")
(assert! (modulep! :lang web)
         "This module builds on Doom's web module: enable (:lang web +lsp +tree-sitter)")

(unless (executable-find "node")
  (error! "No node: %s, or install it with your version manager"
          (if (featurep :system 'macos) "brew install node" "zypper in nodejs22")))

(unless (seq-some #'executable-find '("yarn" "npm" "pnpm" "bun"))
  (error! "No package manager at all: %s"
          (if (featurep :system 'macos) "brew install yarn" "zypper in yarn")))

;; The command that installs any of these, wherever you keep them:
;;   npm i -g --prefix ~/.local <package>      (no root, ~/.local/bin is on PATH)
;;   sudo npm i -g <package>                   (system wide)
(dolist (pair '(("typescript-language-server" . "typescript typescript-language-server")
                ("svelteserver"               . "svelte-language-server")
                ("vscode-html-language-server" . "vscode-langservers-extracted")
                ("vscode-css-language-server" . "vscode-langservers-extracted")
                ("vscode-json-language-server" . "vscode-langservers-extracted")
                ("vscode-eslint-language-server" . "vscode-langservers-extracted")
                ("tailwindcss-language-server" . "@tailwindcss/language-server")
                ("prettier"                   . "prettier")))
  (unless (executable-find (car pair))
    (warn! "No %s: npm i -g --prefix ~/.local %s" (car pair) (cdr pair))))

;; Electron packaging for Windows from Linux or macOS goes through wine.
(when (and (executable-find "node") (not (executable-find "wine")))
  (warn! "No wine, so an Electron build for Windows cannot be made here: %s"
         (if (featurep :system 'macos) "brew install --cask wine-stable" "zypper in wine")))
