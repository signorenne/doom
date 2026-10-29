;;; init.el -*- lexical-binding: t; -*-
;;
;; The modules Doom loads. After editing this file run `doom sync', which is
;; SPC h r s, and restart.
;;
;; Two notes: a language module needs its own +tree-sitter flag, and the
;; :private block at the end holds this config's own modules.

;; Where the notes live. Set before any module or the doctor reads them;
;; a missing folder is made on first use. Unset, both are ~/org: the
;; documents and library (`org-directory') and the knowledge graph
;; (`org-roam-directory') share one root.
(setq +core-notes-dir "~/projects/personal/knowledge_base/"
      +notes-knowledge-dir "~/projects/personal/knowledge/")

;; With the login daemon running, a GUI Emacs opens its files there.
(load (file-name-concat doom-user-dir "modules/private/core/+hand-off") nil 'nomessage)

(doom!
 ;; Input methods and keyboard layouts
 :input
 ;;bidi              ; bidirectional text support
 ;;layout            ; alternative keyboard layouts

 ;; Completion
 :completion
 (corfu +orderless +icons +dabbrev) ; completion popup as you type, C-SPC on demand
 (vertico +icons)  ; the minibuffer UI for M-x, find-file and the rest

 ;; Appearance
 :ui
 doom              ; Doom Emacs visuals
 dashboard         ; startup dashboard
 ;;doom-quit         ; custom quit prompt/message
 ;;(emoji +unicode)  ; Emacs 31 already inserts emoji with C-x 8 e
 hl-todo           ; highlight TODO/FIXME/NOTE/...
 indent-guides     ; indent-bars, SPC t i
 ;;ligatures       ; off on purpose: -> and |= stay as typed
 (modeline +light) ; light status line, not doom-modeline
 nav-flash         ; flash the line you jumped to
 ;;neotree           ; simple file tree
 ophints           ; highlight region affected by operations
 (popup +defaults) ; sane defaults for pop-up windows
 smooth-scroll     ; pixel scrolling
 ;;tabs            ; off: a tab per open file said nothing the buffer list does not
 treemacs          ; project drawer, SPC o p
 ;;unicode           ; slow first run; :private ui sets the fontsets
 (vc-gutter +pretty) ; git diffs in the fringe; diff-hl is the only backend in Doom 3
 vi-tilde-fringe   ; tildes beyond end-of-buffer
 (window-select +numbers) ; numbered windows, SPC w 1 to 9
 workspaces        ; separate workspaces/layouts
 zen               ; distraction-free editing

 ;; Editing
 :editor
 (evil +everywhere); Vim keybindings everywhere
 file-templates    ; auto-insert templates for new files
 fold              ; code folding
 (format +onsave)  ; format on save, per language
 ;;god               ; modifier-less command mode
 ;;lispy             ; structural editing for Lisp
 multiple-cursors  ; edit multiple regions at once
 ;;objed             ; structural editing
 ;;parinfer          ; indentation-based Lisp editing
 rotate-text       ; cycle values at point (true/false, etc.)
 snippets          ; yasnippet, plus $DOOMDIR/snippets
 (whitespace +trim +guess) ; trim edited lines, guess the indent style
 ;;word-wrap         ; smarter soft wrapping

 ;; Core Emacs behaviour
 :emacs
 (dired +icons)    ; file browser (+dirvish would take SPC o p from treemacs)
 electric          ; smarter auto-indentation
 (ibuffer +icons)  ; buffer list
 tramp             ; remote files and containers, connections shared
 undo              ; undo-fu and vundo, persistent across sessions
 vc                ; version control integration

 ;; Terminals
 :term
 eshell            ; Emacs shell
 ;;shell             ; system shell
 ;;term              ; basic terminal emulator
 vterm             ; fast terminal, also used by Claude Code

 ;; Linting, spelling and grammar
 :checkers
 (syntax +childframe +flymake) ; errors as you type: flymake, eglot's own, a popup and the line's end
 (spell +aspell)   ; spell checking
 grammar           ; LanguageTool, English and Italian

 ;; Tools
 :tools
 ;;ansible
 biblio            ; citar, for a .bib library
 ;;collab
 debugger          ; dape, which talks to gdb
 direnv            ; a project's .envrc, for its shells, builds and servers
 ;;docker
 editorconfig      ; respect .editorconfig
 ;;ein
 (eval +overlay)   ; inline evaluation of code
 llm               ; gptel, configured for Claude in :private ai
 (lookup +docsets) ; jump to definitions and documentation
 (lsp +eglot)      ; language server support using Eglot
 magit             ; git porcelain
 make              ; makefile-executor
 ;;pass
 pdf               ; pdf-tools; epdfinfo builds against libpoppler-glib-devel
 ;;prodigy
 ;;rgb
 ;;terraform
 ;;tmux
 tree-sitter       ; built-in treesit integration
 ;;upload

 ;; OS integration
 :os
 (:if (featurep :system 'macos) macos)
 ;;tty

 ;; Languages
 :lang
 (cc +lsp +tree-sitter)   ; C, C++, CMake, GLSL; see :private cpp
 emacs-lisp               ; Emacs Lisp
 data                     ; XML, plist, CSV and the rest
 graphviz                 ; dot files, used by the mind maps
 (json +lsp +tree-sitter)
 markdown
 (python +lsp +tree-sitter) ; pyright, basedpyright or pylsp when installed
 (rust +lsp +tree-sitter) ; rust-analyzer when installed; cargo through SPC k
 (org +dragndrop +present +pretty +roam +pandoc +noter) ; pomodoro: :private notes
 plantuml                 ; UML diagrams
 (qt +lsp +tree-sitter)   ; QML and qmake files, qmlls when installed
 (sh +lsp)                ; shell scripts, bash-ts-mode set up in :private core
 (web +lsp +tree-sitter)  ; HTML, CSS; typescript-language-server when installed
 (javascript +lsp +tree-sitter) ; JS, TS
 (yaml +lsp +tree-sitter)

 ;; Email
 :email
 ;;(mu4e +org +gmail)

 ;; "Apps" inside Emacs
 :app
 ;;calendar
 ;;(rss +org)

 ;; Doom configuration system
 :config
 ;;literate
 (default +bindings +smartparens +gnupg)

 ;; This config's own modules, in modules/private/
 :private
 core              ; environment, defaults, maintenance
 container         ; the containers a toolchain lives in
 qtcreator         ; Qt Creator's kits and project settings, read
 device            ; a machine that is not this one, over ssh
 ui                ; glyphs, dashboard, visual aids
 cpp               ; C/C++: CMake, PlatformIO, Qt, clangd, dape
 rust              ; cargo on the same keys, rust-analyzer, codelldb
 pascal            ; Free Pascal and Lazarus; Delphi sources read
 web               ; Svelte, TypeScript, Tailwind, node and Electron
 uml               ; PlantUML: completion, live preview, templates
 git               ; magit tuned, the history and branch menus
 media             ; a player on mpv, in a buffer of its own
 notes             ; documents, capture, agenda, roam
 ai                ; Claude Code, agent shells, gptel
 docs              ; the cheat sheet
 butler)           ; Hudson, SPC h j
