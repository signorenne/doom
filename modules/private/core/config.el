;;; private/core/config.el -*- lexical-binding: t; -*-
;;
;; Global settings that don't belong to a bigger topic: environment, a few
;; editing defaults, and contextual menus. Doom already tunes GC, scrolling and
;; IPC in lisp/doom-start.el, so only the differences live here. The file
;; manager and the image viewer are topics of their own, beside this file.

;;
;;; Environment

;; The two directories the other modules build on: the notes, and where
;; projects live. Set here, before the org module reads them.
(defvar +core-notes-dir "~/org/"
  "Where the notes live; the org module sets `org-directory' from it.")
(defvar +core-projects-dir "~/projects/"
  "Where projects live: quick access in the file manager, new scaffolds.")

(defvar +core-docs
  '(:groups (("core" "Core" (dired dirvish image-mode)
              dired-mode-map dirvish-mode-map image-mode-map))
    :sections ((dired-mode . "Dired, the file manager")
               (image-mode . "Looking at a picture")))
  "How the cheat sheet documents this module; see `+docs--module-docs'.")

;; Install tree-sitter grammars on first use instead of asking.
(setq treesit-auto-install-grammar 'always)

;; Nothing deleted from Emacs is gone: dired's D and x, SPC f D, and every
;; delete-file behind them move the file to the desktop's trash, the one
;; Dolphin shows, and SPC f t opens it here. Put a file back from the
;; trash listing with SPC m t.
(setq delete-by-moving-to-trash t)

(map! :leader
      :desc "The trash" "f t" #'+core/trash)
(map! :after dired
      :map dired-mode-map
      :localleader
      :desc "Put back from the trash" "t" #'+core/restore-from-trash)

;; Keep ~/.local/bin (claude, pio, node) reachable when Emacs starts from the
;; desktop with a stale `doom env' file.
(let ((bin (expand-file-name "~/.local/bin")))
  (add-to-list 'exec-path bin)
  (unless (string-match-p (concat "\\(^\\|:\\)" (regexp-quote bin) "\\(:\\|$\\)")
                          (or (getenv "PATH") ""))
    (setenv "PATH" (concat bin path-separator (getenv "PATH")))))

;; Every compilation notes when it started, so the newest can be found:
;; `+core-last-compilation-buffer', which the AI's build tool reports.
(add-hook 'compilation-start-hook #'+core--note-compile-start-h)
;; A program that ran and exited leaves a window with nothing in it.
(add-hook 'compilation-finish-functions #'+core--run-window-h)
;; And the keys that read a buffer, once nothing is listening.
(add-hook 'compilation-finish-functions #'+core--run-finished-h)

;; The Emacs server lets emacsclient reach this session (Claude Code hooks,
;; org-protocol, $EDITOR). Daemons already run one.
(add-hook! 'doom-after-init-hook
  (defun +core--start-server-h ()
    "Start the Emacs server unless one is already running."
    (require 'server)
    (unless (or (daemonp) (server-running-p))
      (server-start))))

;; gcmh drops the GC threshold to 800 KB while Emacs is idle, but an agent
;; streaming into vterm happens while idle: on a 350 MB heap that was a
;; 100 ms freeze every 800 KB of output. 16 MB is Doom's own value for a
;; setup without gcmh.
(setq gcmh-low-cons-threshold (* 16 1024 1024))

;; And it collects once Emacs has rested ten times as long as the last
;; collection took, Doom's setting: here that came to under half a
;; second, so a pause to read a line ended in a collection of 40 to 150
;; ms, and the key that ended the pause waited for it. Four seconds is a
;; rest, not a glance.
(setq gcmh-idle-delay 4)


;; A 47 MB log opens in a fifth of a second here, in fundamental mode as
;; Doom arranges for big files, so the "really open?" question can wait
;; for files that are big even for that.
(setq large-file-warning-threshold (* 64 1024 1024))

;; Opening the first file of a project starts its language server; Doom
;; waits a second for it before giving the buffer back, and a server that
;; starts inside a container takes longer than that every time. Give the
;; buffer back at once; the server attaches when it is ready.
(after! eglot
  (setq eglot-sync-connect nil
        ;; The server's "a fix is available here" is a mark in the margin,
        ;; as in every other IDE, not a line of text in the echo area: with
        ;; that hint on, moving through a file with n made the echo area
        ;; grow to three lines at every hit and read like a prompt.
        eglot-code-action-indications '(margin)))

;; eglot answers imenu from the server: every symbol of the file, asked
;; for again after each edit by the header line's breadcrumbs, and an
;; eleven thousand line JSON file froze five seconds at every pause.
;; The mode's own index, tree-sitter's, is local and instant.
(after! eglot
  (add-to-list 'eglot-stay-out-of 'imenu))

;; A server that formats as you type is asked, and waited for, at each
;; newline: clangd did it on every RET, a round trip a busy server makes
;; long. The mode indents the new line already, and the file is
;; formatted when it is saved.
(after! eglot
  (add-to-list 'eglot-ignored-server-capabilities :documentOnTypeFormattingProvider))

;; eglot finds each position a server sends by counting lines from the
;; top of the buffer, so a list of them, diagnostics or symbols, costs
;; the square of the file's length. Counted from the last one found, a
;; list in file order costs its length.
(defvar-local +core--lsp-line nil
  "(TICK LINE . POS): where the last position a server sent was found.")

(after! eglot
  (defadvice! +core--lsp-position-from-last-a (pos-plist &optional marker)
    "The point of POS-PLIST, an LSP position, counted from the last found."
    :override #'eglot--lsp-position-to-point
    (save-excursion
      (save-restriction
        (widen)
        (let* ((line (min most-positive-fixnum (plist-get pos-plist :line)))
               (tick (buffer-chars-modified-tick))
               (from (if (eq (car +core--lsp-line) tick)
                         (cdr +core--lsp-line)
                       (cons 0 (point-min)))))
          (goto-char (cdr from))
          (when (and (zerop (forward-line (- line (car from)))) (bolp))
            (setq +core--lsp-line (cons tick (cons line (point)))))
          ;; A line past the end leaves point at the end, as eglot does.
          (unless (eobp)
            (let ((col (plist-get pos-plist :character)))
              (unless (wholenump col)
                (eglot--warn "Caution: LSP server sent invalid character position %s. Using 0 instead." col)
                (setq col 0))
              (funcall eglot-move-to-linepos-function col)))
          (if marker (copy-marker (point-marker)) (point)))))))

;; Its "a fix is available" mark asks the server about the expression
;; around point, and tree-sitter finds that expression by walking its
;; siblings: most of a pause's time in a large array or object literal.
;; The symbol at point is what the server needs.
(after! eglot
  (defadvice! +core--lsp-code-action-bounds-a ()
    "The region, else the diagnostics at point, else the symbol at point."
    :override #'eglot--code-action-bounds
    (let (diags bounds)
      (cond ((use-region-p) (list (region-beginning) (region-end)))
            ((setq diags (eglot--flymake-diagnostics (point)))
             (list (apply #'min (mapcar #'flymake-diagnostic-beg diags))
                   (apply #'max (mapcar #'flymake-diagnostic-end diags))))
            ((setq bounds (bounds-of-thing-at-point 'symbol))
             (list (car bounds) (cdr bounds)))
            (t (list (point) (point)))))))

;; The echo area takes up to three lines for what is under the cursor.
;; One line cut every diagnostic that did not fit, which is most of the
;; ones worth reading; three holds nearly all of them and still does not
;; grow into a page. K or SPC c H open the whole text when even that is
;; not enough.
(setq eldoc-echo-area-use-multiline-p 3)

;; Questions are answered on the keyboard, in the minibuffer. Emacs asks
;; through a GTK dialog when the question was started by the mouse, and
;; closing the frame with the window button is one of those: the dialog
;; wants a click on Yes, and typing y into it does nothing.
(setq use-dialog-box nil)

;;
;;; Editing

;; One `u' undoes one edit, not a whole insert session.
(setq evil-want-fine-undo t)

;; :lang sh has no +tree-sitter flag, so map the mode here.
(when (modulep! :tools tree-sitter)
  (set-tree-sitter! 'sh-mode 'bash-ts-mode
    '((bash :url "https://github.com/tree-sitter/tree-sitter-bash"))))

;; Completion as you type, the way VS Code and Zed do it: the popup
;; comes after two characters and a short pause with the first
;; candidate already chosen, RET takes it, TAB completes what the
;; candidates share, C-n C-p and the arrows move, ESC closes, C-SPC
;; opens it without waiting.  SPC t a makes it manual again.
(after! corfu
  (setq corfu-auto t
        corfu-auto-delay 0.15
        corfu-auto-prefix 2
        corfu-preselect 'first
        ;; TAB indents; Doom makes it complete as well, which with the
        ;; popup coming by itself is one popup too many.
        tab-always-indent t))

;; Doom makes backspace reset the popup whenever a candidate is chosen,
;; to take back the preview it puts in the buffer; with the first
;; chosen from the start that was every backspace, and the typo stayed.
;; Backspace deletes; it resets only over a preview, which the first
;; candidate never is.
(let ((reset `(menu-item "Reset completion" corfu-reset
               :filter ,(lambda (cmd) (when (corfu--preview-current-p) cmd)))))
  (map! :after corfu
        :map corfu-map
        [backspace] reset
        "DEL" reset))

;; What the candidate under the cursor means, beside the list. Doom turns
;; the popup on and binds nothing for it, so it could only be waited for:
;; M-d asks for it at once, and M-n and M-p read a long one.
(map! :after corfu-popupinfo
      :map corfu-map
      "M-d" #'corfu-popupinfo-toggle
      "M-n" #'corfu-popupinfo-scroll-up
      "M-p" #'corfu-popupinfo-scroll-down)


;; zM and zR close and open every fold, which is what they do in Vim and
;; what the sheet has always said. Doom puts those commands on zm and zr
;; and leaves the capitals unbound in a code buffer; org-mode binds its
;; own, and a mode map wins, so this only fills the gap.
(map! :n "zM" #'+fold/close-all
      :n "zR" #'+fold/open-all)


;;
;;; Projects

;; Doom keeps projectile's file list in a cache that survives restarts, so
;; a file added outside Emacs, an image dropped in by hand or a source
;; written by Qt Creator, is not found until SPC p i. fd lists a project
;; in milliseconds; ask it every time.
(after! projectile
  (setq projectile-enable-caching nil))

(map! :leader
      :desc "Find any file in project" "s F" #'+core/find-any-file)

;; SPC s f and SPC f l are Doom's `locate', which shells out to locate(1):
;; not installed here, and an index a cron job has to keep fresh is a
;; poor way to find a file on a machine that has fd. consult-fd searches
;; names live under the directory you are in, C-u for another one, and
;; there is nothing to keep up to date.
(map! :leader
      :desc "Find a file by name, here and below" "s f" #'consult-fd
      :desc "Find a file by name, here and below" "f l" #'consult-fd)

;; SPC s SPC: the search menu, laid out like the others. The flags
;; ripgrep takes are set in it rather than typed after a lone -- in the
;; prompt, which works but has to be remembered.
(map! :leader
      :desc "Search and replace menu" "s SPC" #'+core/search-menu
      :desc "Replace in the project"  "s R"   #'+core/replace-in-project)


;;
;;; The bigger topics

(load! "+dired")                        ; the file manager
(load! "+images")                       ; the image viewer
(load! "+data")                         ; JSON, YAML, TOML, XML and friends


;;
;;; Formatting

;; Two things want the buffer when it is saved. ws-butler trims the lines
;; it touched, apheleia runs the formatter, and the formatter is not
;; instant: ws-butler's hook changes the buffer while apheleia is still
;; working, apheleia sees a buffer that moved under it and throws its own
;; result away, so the file is never formatted. A buffer with a formatter
;; does not need the trimming, since the formatter does that and more, so
;; ws-butler stands down in those and keeps every other buffer.
(declare-function apheleia--get-formatters "apheleia")
(declare-function ws-butler-mode "ws-butler")

(defun +core--ws-butler-yields-to-format-h ()
  "Turn ws-butler off in a buffer a formatter is going to format."
  (when (and (bound-and-true-p apheleia-mode)
             (bound-and-true-p ws-butler-mode)
             (ignore-errors (apheleia--get-formatters)))
    (ws-butler-mode -1)))

;; On saving rather than on entering the mode: ws-butler is turned on
;; later than apheleia, so at that point there is nothing yet to stand
;; down.
(add-hook 'before-save-hook #'+core--ws-butler-yields-to-format-h)



;;
;;; Leaving

;; The window's close button asks whether to save what is open, and by
;; then the compositor has taken the keyboard away: the question is on
;; screen and nothing can answer it. Take the focus back before asking,
;; and raise the frame, since it may be behind something too.
(defun +core--focus-to-ask (&rest _)
  "Bring the frame forward and give it the keyboard, before a question.
It advises commands that take an argument, SPC q q's prefix among them,
so it takes whatever they are given."
  (when (display-graphic-p)
    (let ((frame (selected-frame)))
      (when (frame-live-p frame)
        (ignore-errors (raise-frame frame))
        (ignore-errors (select-frame-set-input-focus frame))))))

(advice-add 'save-buffers-kill-emacs :before #'+core--focus-to-ask)
(advice-add 'save-buffers-kill-terminal :before #'+core--focus-to-ask)
(with-eval-after-load 'doom-ui
  (when (fboundp 'doom/delete-frame-with-prompt)
    (advice-add 'doom/delete-frame-with-prompt :before #'+core--focus-to-ask)))


;;
;;; Contextual menus

;; q closes a menu, the way it closes any read-only buffer. This is
;; transient's own switch; a menu that used q for a command gets that
;; command on Q instead, which transient also does itself.
(after! transient
  (transient-bind-q-to-quit)
  ;; Doom binds this in the magit module, so it is only there once magit
  ;; has loaded. Our menus open before that. Same key, same command.
  (define-key transient-map [escape] #'transient-quit-one))

;; SPC m SPC opens a transient menu listing what the current mode can
;; do, the way SPC k SPC, SPC g SPC and the others open a module's; C-o
;; stays evil's jump back. calc and isearch have no evil state, so the
;; menu sits on C-o there. dired's is bound with its localleader above.
(use-package! casual
  :defer t
  :init
  (map! (:after ibuffer    :map ibuffer-mode-map        :localleader "SPC" #'casual-ibuffer-tmenu)
        (:after info       :map Info-mode-map           :localleader "SPC" #'casual-info-tmenu)
        (:after bookmark   :map bookmark-bmenu-mode-map :localleader "SPC" #'casual-bookmarks-tmenu)
        (:after org-agenda :map org-agenda-mode-map     :localleader "SPC" #'casual-agenda-tmenu)
        (:after re-builder :map reb-mode-map            :localleader "SPC" #'casual-re-builder-tmenu)
        (:after calc       :map calc-mode-map               "C-o" #'casual-calc-tmenu)
        (:after isearch    :map isearch-mode-map            "C-o" #'casual-isearch-tmenu)))


;;
;;; Keybindings

(map! :leader
      (:prefix "t"
       :desc "Corfu auto-complete" "a" #'+corfu/toggle-auto-complete
       :desc "Subword (camelCase)" "S" #'subword-mode
       :desc "Transparency"        "T" #'+core/toggle-transparency)

      (:prefix "f"
       :desc "Open externally"     "x" #'+core/open-externally
       ;; Doom's y is the path, Y the path inside the project; these are
       ;; the other forms you end up wanting in a terminal or a chat.
       :desc "Copy file name"      "n" #'+core/yank-file-name
       :desc "Copy directory"      "N" #'+core/yank-file-directory
       :desc "Copy absolute path"  "a" #'+core/yank-file-path
       :desc "Copy path:line"      "L" #'+core/yank-file-line
       :desc "Copy menu"           "k" #'+core/copy-menu)

      (:prefix "p"
       :desc "Project TODOs"       "t" #'+core/project-todos))

;; Next to Doom's own reload keys (SPC h r ...).
(map! :map help-map
      :desc "Doom sync"    "rs" #'+core/doom-sync
      :desc "Doom doctor"  "rd" #'+core/doom-doctor
      :desc "Doom upgrade" "ru" #'+core/doom-upgrade)
