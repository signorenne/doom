;;; private/core/config.el -*- lexical-binding: t; -*-
;;
;; Global settings that don't belong to a bigger topic: environment, a few
;; editing defaults, and contextual menus. Doom already tunes GC, scrolling and
;; IPC in lisp/doom-start.el, so only the differences live here. The file
;; manager and the image viewer are topics of their own, beside this file.

;;
;;; Environment

;; The two directories the other modules build on: the notes, and where
;; projects live. Set here, before the org module reads them; init.el
;; sets the notes for this machine.
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

;; A file over a megabyte is large here: the header's function line, in
;; the ui module, stands down in it when it has no syntax tree to ask.
;; Doom kept that mark once, and now tells a large file by its lines, for
;; so-long alone, so the mark is made here, in the file's own buffer, as
;; it opens.
(defvar +core-large-file-size (* 1024 1024)
  "Past this size, in bytes, a file opened is large: `+core-large-file-p'.")

(defvar +core-large-file-excluded-modes
  '(so-long-mode special-mode archive-mode tar-mode jka-compr
    git-commit-mode image-mode doc-view-mode doc-view-mode-maybe
    ebrowse-tree-mode pdf-view-mode tags-table-mode)
  "Modes a file keeps at any size: a picture's, a PDF's, an archive's,
which show something other than the text.")

(defvar-local +core-large-file-p nil
  "The size of this buffer's file when it is large, else nil.")

(add-hook! 'find-file-hook :depth -95
  (defun +core--mark-large-file-h ()
    "Mark the file just opened as large when it is."
    (when-let* ((file buffer-file-name)
                ((not (file-remote-p file)))
                (size (file-attribute-size (file-attributes file))))
      (when (> size +core-large-file-size)
        (setq-local +core-large-file-p size)))))

;; Tree-sitter reparses what an edit touched, and the node that holds it
;; with all its children: in most files a function among a few thousand,
;; a reparse of 2 ms in a megabyte of C++. But in a file that is one
;; declaration, an image as a C array, that node is a list of 170 000
;; values, and every key rebuilt it: 340 to 410 ms a key, 11 to 14 in
;; c-mode. A file the grammar cannot read at all, nlohmann's json.hpp, is
;; one error node, and nothing of it is reused. A file with a node that
;; crowded, and a quarter of a megabyte that failed to parse, open in the
;; mode Emacs had before tree-sitter. Size alone is no reason: that
;; megabyte of C++ costs 11 ms a key in c++-ts-mode and 128 to 163 in
;; c++-mode. A key here is a character typed, the reparse and the
;; colouring of 6 KB around it, timed on the Mac the README names.
(defvar +core-treesit-unparsed-max (* 256 1024)
  "Past this size a file tree-sitter could not parse opens without it.")

;; And a file the grammar reads with many errors reparses slowly at every
;; key wherever it is edited: a generated 1.5 MB C file with 2 579 error
;; nodes, 90 ms a reparse and 190 ms a key, 18 to 34 in c-mode; a 1 MB
;; register header with 930, 20 ms and 42 a key, which stays, cc-mode
;; spending half a second at a key in places there. Ordinary C++ of the
;; same size reparses in under a millisecond. Past the size above, one
;; reparse is timed as the file opens.
(defvar +core-treesit-reparse-max 0.04
  "Past `+core-treesit-unparsed-max', a file whose syntax tree takes longer
than this, in seconds, to reparse after a one character edit opens without
tree-sitter.")

(defun +core--treesit-slow-reparse-p ()
  "Non-nil when a one character edit in the middle of the buffer takes
tree-sitter longer than `+core-treesit-reparse-max' to reparse.  The edit
is made and taken back unseen: no undo, no change hooks, the text and the
modified flag as they were."
  (save-excursion
    (let ((inhibit-read-only t)
          elapsed)
      (with-silent-modifications
        (goto-char (/ (+ (point-min) (point-max)) 2))
        (treesit-buffer-root-node)
        (insert " ")
        (unwind-protect
            (let ((start (float-time)))
              (treesit-buffer-root-node)
              (setq elapsed (- (float-time) start)))
          (delete-char -1)))
      (> elapsed +core-treesit-reparse-max))))

(defvar +core-treesit-children-max 20000
  "Past this many children under one node, a file opens without tree-sitter:
JSON's array of 9 000 objects, a megabyte, costs 13 ms a key, and of
18 000, two, 37.")

(defun +core--treesit-crowded-p ()
  "Non-nil when a node around the middle of the buffer has more than
`+core-treesit-children-max' children: tree-sitter rebuilds it at every
key.  A node that holds most of the file holds the middle too."
  (let ((node (treesit-node-at (/ (+ (point-min) (point-max)) 2)))
        crowded)
    (while (and node (not crowded))
      (setq crowded (> (treesit-node-child-count node t) +core-treesit-children-max)
            node (treesit-node-parent node)))
    crowded))

(defun +core--classic-mode (mode)
  "The mode that tree-sitter MODE stands in for, or nil."
  (car (or (rassq mode major-mode-remap-alist)
           (rassq mode (bound-and-true-p major-mode-remap-defaults)))))

(add-hook! 'find-file-hook :depth -90
  (defun +core--without-treesit-h ()
    "Open a file tree-sitter would make slow in the mode before it."
    (when-let* (((treesit-parser-list))
                (classic (+core--classic-mode major-mode))
                ((fboundp classic))
                ((or (and (> (buffer-size) +core-treesit-unparsed-max)
                          (equal (treesit-node-type (treesit-buffer-root-node)) "ERROR"))
                     (+core--treesit-crowded-p)
                     (and (> (buffer-size) +core-treesit-unparsed-max)
                          (+core--treesit-slow-reparse-p)))))
      (funcall classic)
      (message "%s opens in %s: tree-sitter would slow it down" (buffer-name) classic))))

;; Whether a grammar is there is looked up on disk at every asking, 3 ms
;; even with the library loaded, and markdown asks twice for each code
;; block it colours: every block of a README, and each documentation
;; popup's signature, 5.5 ms a block. A grammar found stays usable for
;; the session; one not found is looked for again, so a grammar
;; installed meanwhile is found.
(defvar +core--treesit-available (make-hash-table :test #'eq)
  "The languages whose grammar was found, as t.")

(defadvice! +core--treesit-available-once-a (fn language &optional detail)
  "Ask FN about LANGUAGE once it has been found; DETAIL is always asked."
  :around #'treesit-language-available-p
  (cond (detail (funcall fn language detail))
        ((gethash language +core--treesit-available))
        ((funcall fn language)
         (puthash language t +core--treesit-available))))

;; Doom installs a grammar it finds missing when it picks a tree-sitter
;; mode, cloning and compiling it while Emacs waits, and takes it to be
;; missing whenever `treesit-ready-p' says no, which it also says of a
;; buffer past `treesit-max-buffer-size', 40 MB. Each C++ file that big
;; cloned and built the C++ grammar again, two seconds, over the library
;; the session had loaded. And a file only previewed, the cursor passing
;; over it in SPC . or a search, built its language's grammar there and
;; then: 1.8 s frozen for CSS, longer for TypeScript, on a machine new to
;; them. Both get the older mode instead, with nothing installed; the
;; grammar comes with the first file of its language opened for real.
(defvar treesit-auto-install-grammar)

(defvar +core--previewing nil
  "Non-nil while a file is opened only to preview it, by consult or by
dirvish beside a prompt.")

(advice-add 'major-mode-remap :around
            (defun +core--treesit-no-install-a (fn mode)
              "Install no grammar for a buffer too big for tree-sitter, nor
for a file previewed."
              ;; Loaded first: bound before treesit.el had defined it,
              ;; the binding was lexical, and the first file of a session
              ;; failed to open with treesit loading inside it.
              (require 'treesit)
              ;; Bound only to say never: bound to its own value, Doom's
              ;; making it buffer-local once a grammar is in was warned of.
              (if (or +core--previewing
                      (> (buffer-size) (or (bound-and-true-p treesit-max-buffer-size)
                                           most-positive-fixnum)))
                  (let ((treesit-auto-install-grammar 'never))
                    (funcall fn mode))
                (funcall fn mode)))
            '((depth . -90)))

;; Past two megabytes a file is made by a program: an image as a C array,
;; a Qt resource, compile_commands.json, a log. Reading one is quick, 50
;; MB in a fifth of a second; its mode is slow, going over all of it
;; before the first screen: 2.4 s for 8 MB of C++, 2.3 s for 2.5 MB of
;; Org, and in a 50 MB resource array cc-mode spent minutes on one key.
;; Such a file opens whole but as plain text, at once, and
;; `+core/file-own-mode' gives it its mode. Reading the rest in pieces
;; behind the first screen was tried and is worse: each piece sends the
;; mode over the file again, 8.8 s in all for that C++ and 40 s for an 8
;; MB JSON that opens in 0.4.
(defvar +core-plain-file-size (* 2 1024 1024)
  "Past this size a file opens as plain text, without its major mode.")

(defvar +core-plain-file-keep-modes '(org-mode)
  "Modes a file keeps at any size, besides `+core-large-file-excluded-modes':
org's agenda and refile refuse a file that is not in org-mode, and the
agenda reads every file of the notes.")

(defvar-local +core-plain-mode nil
  "The mode a file opened as plain text would have had, or t once it has
it, which a revert keeps.")
(put '+core-plain-mode 'permanent-local t)

;; A file previewed in a prompt is a glance: plain text, whatever it is and
;; whatever its size, its mode never set up, so nothing a mode runs can
;; hold the cursor up. Colouring a 900 KB header took a third of a second
;; at each step through the list, and C headers and other files held SPC
;; . up while their modes started. A binary shows nothing. Read whole up
;; to 8 MB, where consult showed the first 10 KB of anything past a
;; megabyte, so a search's match beyond them was not on screen. The file
;; picked is opened afresh, in its own mode.
(defun +core--previewing-a (fn &rest args)
  "Call FN with ARGS as a preview, `+core--previewing' set.
No grammar is built for it, whoever asks: Doom's choice of mode, above,
or one of Emacs 31's tree-sitter modes, which installs its own as it
starts, TOML's taking 1.4 s, Go's, Lua's or a Dockerfile's the same."
  (require 'treesit)
  (let ((+core--previewing t)
        (treesit-auto-install-grammar 'never))
    (apply fn args)))

(after! consult
  (setq consult-preview-partial-size (* 8 1024 1024))
  (advice-add 'consult--find-file-temporarily :around #'+core--previewing-a))

;; dirvish's beside a prompt, SPC . among them, and in its own pane: the
;; text of a file, its first 64 KB, or the file opened.
(after! dirvish
  (advice-add 'dirvish--preview-file-maybe-truncate :around #'+core--previewing-a)
  (advice-add 'dirvish--find-file-temporarily :around #'+core--previewing-a))

(defadvice! +core--plain-big-file-a (fn mode &rest args)
  "Set a file past `+core-plain-file-size' up in `fundamental-mode', not
MODE, and a file previewed at any size.  Opened, the modes a large file
keeps, a picture's, a PDF's, an archive's, `+core-large-file-excluded-modes',
are left alone, and so are `+core-plain-file-keep-modes'."
  :around #'set-auto-mode-0
  (if (and mode
           buffer-file-name
           (not (eq +core-plain-mode t))
           (or +core--previewing
               (and (> (buffer-size) +core-plain-file-size)
                    (not (memq mode +core-large-file-excluded-modes))
                    (not (memq mode +core-plain-file-keep-modes)))))
      (progn (setq +core-plain-mode mode)
             (apply fn #'fundamental-mode args))
    ;; Back under the limit, a revert after the file shrank: not plain.
    (unless (eq +core-plain-mode t)
      (setq +core-plain-mode nil))
    (apply fn mode args)))

(add-hook! 'find-file-hook :depth 90
  (defun +core--plain-file-say-h ()
    "Say that the file was opened as plain text, and how to change that."
    (when (and +core-plain-mode (not (eq +core-plain-mode t)))
      (message "%s is %s: plain text; M-x +core/file-own-mode for %s"
               (buffer-name) (file-size-human-readable (buffer-size))
               +core-plain-mode))))

;; Nothing deleted from Emacs is gone: dired's D and x, SPC f D, and every
;; delete-file behind them move the file to the system's trash, the one
;; Finder or Dolphin shows, and SPC f t opens it here. Put a file back
;; from the trash listing with SPC m t; on macOS Emacs notes where each
;; file it deletes came from, since only Finder knows otherwise.
(setq delete-by-moving-to-trash t)
(when (featurep :system 'macos)
  (advice-add 'move-file-to-trash :around #'+core--trash-note-origin-a))

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

;; On a Mac the left Option is Meta, as Alt is elsewhere, and the right
;; one stays Option, so a U.S. layout still types its accents: right
;; Option and ` then e is è. Command is Super, on which Doom puts the
;; Mac's own keys, s-c, s-v, s-s, s-z.
(when (featurep :system 'macos)
  (setq ns-command-modifier 'super
        ns-option-modifier 'meta
        ns-right-option-modifier 'none))

;; vterm's module is native code built on this machine: on a new machine,
;; or once the packages were rebuilt for a new Emacs, vterm asked whether
;; to build it, and a daemon, with no one to answer, waited for good. It
;; is built without asking; it needs cmake, and libvterm or the network.
(setq vterm-always-compile-module t)

;; Every compilation notes when it started, so the newest can be found:
;; `+core-last-compilation-buffer', which the AI's build tool reports.
(add-hook 'compilation-start-hook #'+core--note-compile-start-h)
;; A program that ran and exited leaves a window with nothing in it.
(add-hook 'compilation-finish-functions #'+core--run-window-h)
;; And the keys that read a buffer, once nothing is listening.
(add-hook 'compilation-finish-functions #'+core--run-finished-h)

;; Builds start below the editor. At load 30 on twelve cores Emacs had
;; under half a core, and every key waited its turn behind the compilers.
;; A compilation starts under nice unless it runs a program or a
;; benchmark, whose speed is the point, or takes input; a search is not
;; a compilation here and keeps its pace. The command reads as it did.
(defvar +core-build-niceness 10
  "The nice value builds start at, so typing goes first when the cores
are short.  nil starts them at the editor's own priority.")

(defvar +core--compiling)
(defvar +core--compile-type nil
  "The type of the projection command starting: `build', `run' and so on.")
(defvar +core--recompiling nil)
(defvar-local +core--compile-run nil
  "Non-nil in a compilation buffer whose command runs a program, so a
re-run starts it at the editor's priority again.")
(put '+core--compile-run 'permanent-local t)

(defadvice! +core--projection-type-a (fn project command type &rest args)
  :around #'projection-commands--run-command-for-type
  (let ((+core--compile-type type))
    (apply fn project command type args)))

(defadvice! +core--recompiling-a (fn &rest args)
  :around #'recompile
  (let ((+core--recompiling t))
    (apply fn args)))

(defadvice! +core--nice-build-a (fn name buffer command)
  :around #'start-file-process-shell-command
  (let ((buf (and buffer (get-buffer buffer))))
    (if (not (and buf (eq (buffer-local-value 'major-mode buf) 'compilation-mode)))
        (funcall fn name buffer command)
      (let* ((started (bound-and-true-p +core--compiling))
             (run (cond (started (string-match-p "\\`\\(run\\|bench\\)" started))
                        (+core--compile-type (eq +core--compile-type 'run))
                        (+core--recompiling (buffer-local-value '+core--compile-run buf))))
             (nice (and +core-build-niceness (not run)
                        (not (file-remote-p default-directory))
                        (executable-find "nice"))))
        (with-current-buffer buf
          (setq +core--compile-run (and run t)))
        (if nice
            (start-file-process name buffer nice "-n" (number-to-string +core-build-niceness)
                                shell-file-name shell-command-switch command)
          (funcall fn name buffer command))))))

;; A program's output was a plain window beside the source, not one of
;; Doom's popups like the build's: the cursor stayed in the source and ESC
;; left it standing. It opens as a popup on the right now, the cursor in
;; it, and ESC or q closes it, from it or from the source. The buffer is
;; kept, and what still runs in it, a dev server, goes on running.
(set-popup-rule! "^\\*run[ :]" :side 'right :size 0.45 :select t :quit t :ttl nil)

;; And a build, a test or a check this config starts is named for what it
;; is, *build* or *clippy*, which none of Doom's popup rules knows: it
;; stood as a plain window that ESC left, where *compilation* goes. It
;; goes the same way now, at the bottom, the cursor left where it was.
(set-popup-rule! #'+core--compile-popup-p :vslot -2 :size 0.3 :select nil :quit t :ttl nil)

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
;; 100 ms freeze every 800 KB of output. It waits for 64 MB: with memory
;; to spare a pause comes half as often as at 16 MB and lasts as long,
;; 181 ms where it took 176 on a 178 MB heap; at 256 MB, a quarter as
;; often again, 219 ms. Working, Doom's 64 MB is 256 here, below, and
;; 512 once a language server runs, which Doom doubles it for.
(setq gcmh-low-cons-threshold (* 64 1024 1024))

;; And it collects once Emacs has rested ten times as long as the last
;; collection took, Doom's setting: here that came to under half a
;; second, so a pause to read a line ended in a collection of 40 to 150
;; ms, and the key that ended the pause waited for it. Four seconds is a
;; rest, not a glance. Doom sets its own as gcmh loads, with the first
;; buffer, after this file: set before, the four seconds never held.
(after! gcmh
  (setq gcmh-idle-delay 4
        gcmh-high-cons-threshold (* 256 1024 1024)))

;; Doom compiles a few functions it calls often once Emacs is idle, and
;; natively where it can: `native-compile' runs a batch Emacs for each
;; one and waits for it, a third of a second frozen, and a key pressed
;; then waits too. Byte code is made in place in a few milliseconds and
;; is most of the gain over the interpreter.
(defadvice! +core--byte-compile-functions-a (&rest fns)
  "Byte-compile FNS the next time Emacs is idle."
  :override #'doom-compile-functions
  (run-with-idle-timer
   1.5 nil (lambda ()
             (dolist (fn fns)
               (when (interpreted-function-p (indirect-function fn))
                 (let ((byte-compile-warnings nil))
                   (ignore-errors (byte-compile fn))))))))

;; The first file of a session costs close to a second that the next one
;; does not: eglot and what it needs load, version control and the diff
;; gutter, the mode's own library, its tree-sitter queries are compiled
;; and its snippets read, and the modules load their files. The first
;; key costs a fifth of a second too, which-key mostly. Emacs does it
;; while it waits after starting instead, one step at a time; a key
;; pressed during a step stops it at once, and it is taken up again at
;; the next pause. The modes set up ahead are those of the latest files,
;; three at most: with only the latest one's, the first file of the
;; second language of the day still paid for its mode, its library and
;; its snippets as it opened, a third to half a second.
(defvar +core-warm-up-features
  '(which-key vertico corfu
    ert eldoc xref jsonrpc external-completion flymake eglot yasnippet
    vc-git vc-dir diff-hl diff-hl-flydiff so-long saveplace whitespace disp-table)
  "Libraries the first file of a session loads, loaded ahead while Emacs
waits after starting.")

(defvar +core-warm-up-functions '(+core--warm-up-mode)
  "Called one at a time, each at a pause, once `+core-warm-up-features'
are loaded: each with every mode of `+core--recent-file-modes' in turn.")

(defvar +core-warm-up-modes 3
  "How many modes of the latest files are set up ahead.")

(defvar +core--warm-up-queue nil
  "(MODE . STEPS): the warm-up steps left, and the mode they are for,
`unknown' until the first function step asks.")

(defun +core--recent-file-modes ()
  "The modes of the latest recent files, `+core-warm-up-modes' at most:
the one most of them open in first, the latest first among equals."
  (require 'recentf)
  (unless recentf-list (recentf-load-list))
  (let (modes)
    (dolist (file (seq-take recentf-list 10))
      ;; Remote names are passed over by their shape: asking Emacs
      ;; whether one is remote loads TRAMP.
      (unless (string-match-p "\\`/[^/:]+:" file)
        (when-let* ((mode (assoc-default file auto-mode-alist #'string-match))
                    (mode (major-mode-remap (if (consp mode) (car mode) mode)))
                    ((symbolp mode))
                    ;; A picture's or an archive's mode is nothing without
                    ;; the file to show.
                    ((not (memq mode (cons 'fundamental-mode +core-large-file-excluded-modes)))))
          (push mode modes))))
    (setq modes (nreverse modes))
    (seq-take (sort (seq-uniq modes)
                    :key (lambda (mode) (- (seq-count (lambda (m) (eq m mode)) modes)))
                    :lessp #'<)
              +core-warm-up-modes)))

(defun +core--warm-up-mode (mode)
  "Set MODE up once in a buffer no one sees: its library loads, its
tree-sitter queries are compiled into the cache every buffer shares,
and its snippets are read."
  (when (and mode (fboundp mode))
    ;; A warning, a grammar gone missing, is logged but not shown: no
    ;; window should open while you are not looking.
    (let ((warning-minimum-level :emergency))
      (with-temp-buffer
        (delay-mode-hooks (funcall mode))
        (when (fboundp 'yas--load-pending-jits)
          (yas--load-pending-jits))))))

(defun +core-load-autoloads (&rest fns)
  "Load the file each of FNS, an autoloaded function, lives in, unless
it is loaded already."
  (dolist (fn fns)
    (let ((def (symbol-function fn)))
      (when (autoloadp def)
        (autoload-do-load def fn)))))

(defun +core--warm-up ()
  "Take the next warm-up step, unless a key comes first, then wait for a
pause again for the one after."
  (pcase-let ((`(,mode . ,steps) +core--warm-up-queue))
    (when steps
      (pcase-let ((`(,how . ,what) (car steps)))
        (unless (eq t (while-no-input
                        (let ((inhibit-message t))
                          (with-demoted-errors "Warm-up: %S"
                            (pcase how
                              ('require (require what nil t))
                              ;; A function step becomes one step a mode.
                              ('call
                               (when (eq mode 'unknown)
                                 (setq mode (ignore-errors (+core--recent-file-modes))))
                               ;; Itself made a step that does nothing, so
                               ;; a key in between cannot expand it twice.
                               (setq steps (append (list '(done))
                                                   (mapcar (lambda (m) (cons 'warm (cons what m))) mode)
                                                   (cdr steps))))
                              ('warm (funcall (car what) (cdr what)))
                              ('done nil))))
                        nil))
          (setq steps (cdr steps))))
      (setq +core--warm-up-queue (cons mode steps))
      (when steps
        ;; A second step in the same pause needs a time past the pause's
        ;; length so far, or it waits for the next pause.
        (run-with-idle-timer (time-add (or (current-idle-time) 0) 0.1)
                             nil #'+core--warm-up)))))

(defun +core--warm-up-start-h ()
  "Queue the warm-up, to start at the first pause after starting."
  (setq +core--warm-up-queue
        (cons 'unknown
              (append (mapcar (lambda (f) (cons 'require f)) +core-warm-up-features)
                      (mapcar (lambda (f) (cons 'call f)) +core-warm-up-functions))))
  (run-with-idle-timer 1 nil #'+core--warm-up))

(add-hook 'doom-after-init-hook #'+core--warm-up-start-h 90)


;; A 47 MB log opens in a fifth of a second here, in fundamental mode as
;; Doom arranges for big files, so the "really open?" question can wait
;; for files that are big even for that.
(setq large-file-warning-threshold (* 64 1024 1024))

;; Opening the first file of a project starts its language server; Doom
;; waits a second for it before giving the buffer back, and a server that
;; starts inside a container takes longer than that every time. Give the
;; buffer back at once; the server attaches when it is ready.
(after! eglot
  ;; What was typed goes to the server after a quarter second at rest,
  ;; not half, so its diagnostics follow sooner; sending is a few ms here.
  (setq eglot-send-changes-idle-time 0.25)
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
;; formatted when it is saved. Tried again on the Mac, a RET costs 8.5 ms
;; without it, and with it clangd's edit lands inside the same insertion:
;; Doom's comment continuation then finds no newline before point and
;; RET signals an error.
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

;; Inlay hints, the parameter names before each argument, were asked for
;; a screen at a time, as each part of the file was first drawn: every
;; new screen scrolled to sent a request, and the text moved as the names
;; came back. They are asked for the whole file when the hints come on,
;; with the file or after SPC k l i; after an edit for what is on screen,
;; as eglot does; and not for scrolling alone. The whole file goes in
;; blocks, the one on screen first: painted at once, eleven thousand
;; hints held Emacs a quarter of a second. Not again at each save: that
;; many hints made again are garbage enough for a collection each time.
(declare-function eglot--update-hints-1 "eglot")
(declare-function eglot-current-server "eglot")
(declare-function jsonrpc-connection-ready-p "jsonrpc")
(defvar eglot-inlay-hints-mode)

(defvar +core-inlay-block-lines 300
  "How many lines of inlay hints are asked for at a time for a whole file.")

(defvar-local +core--inlay-tick nil
  "The buffer's modification tick when its inlay hints were last asked for.")

(defvar-local +core--inlay-round 0
  "Counts the whole-file requests, so a newer one stops an older's blocks.")

(defvar +core--inlay-all nil
  "Non-nil while a block of a whole-file request is asked for.")

(defun +core--inlay-send (buffer round lines)
  "Ask for BUFFER's inlay hints block by block, from the first line of
each in LINES, while ROUND is the latest whole-file request. A block
waits while the server has edits to receive."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (when (and lines (= round +core--inlay-round)
                 (bound-and-true-p eglot-inlay-hints-mode))
        (let ((server (eglot-current-server)))
          (cond
           ((null server))
           ((not (jsonrpc-connection-ready-p server 'eglot--update-hints-1))
            (run-at-time 0.2 nil #'+core--inlay-send buffer round lines))
           (t
            (save-excursion
              (save-restriction
                (widen)
                (goto-char (point-min))
                (forward-line (car lines))
                (let ((from (point)))
                  (forward-line +core-inlay-block-lines)
                  (let ((+core--inlay-all t))
                    (eglot--update-hints-1 from (point))))))
            (run-at-time 0.03 nil #'+core--inlay-send buffer round (cdr lines)))))))))

(defun +core--inlay-hints-all ()
  "Ask for the inlay hints of the whole buffer, the block on screen first,
then outward; after this command, since eglot turns the hints on before
it tells the server the file is open."
  (let* ((round (setq +core--inlay-round (1+ +core--inlay-round)))
         (total (count-lines (point-min) (point-max)))
         (here (/ (1- (line-number-at-pos
                       (if-let* ((window (get-buffer-window)))
                           (window-start window)
                         (point))))
                  +core-inlay-block-lines))
         (blocks (number-sequence 0 (/ total +core-inlay-block-lines))))
    (run-at-time 0 nil #'+core--inlay-send (current-buffer) round
                 (mapcar (lambda (block) (* block +core-inlay-block-lines))
                         (sort blocks :key (lambda (block) (abs (- block here))))))))

;; Asked for once, the hints of text changed off screen were lost with it
;; and never asked for again: a format on save, a rename, a revert after
;; git, and that part of the file had no hints until it was edited. The
;; changed text is kept between two markers, and once the keys rest its
;; blocks are asked for, on screen or not.
(defvar-local +core--inlay-dirty nil
  "(BEG . END), markers round the text changed since its hints were
asked for, or nil.")

(defvar-local +core--inlay-dirty-timer nil
  "The one-shot that asks for the changed text's hints.")

(defun +core--inlay-dirty-clear ()
  "Forget the changed text."
  (when +core--inlay-dirty
    (set-marker (car +core--inlay-dirty) nil)
    (set-marker (cdr +core--inlay-dirty) nil)
    (setq +core--inlay-dirty nil)))

(defun +core--inlay-dirty-h (beg end _length)
  "Count BEG to END among the text whose hints are to be asked for."
  (when (bound-and-true-p eglot-inlay-hints-mode)
    (if +core--inlay-dirty
        (progn (when (< beg (car +core--inlay-dirty))
                 (set-marker (car +core--inlay-dirty) beg))
               (when (> end (cdr +core--inlay-dirty))
                 (set-marker (cdr +core--inlay-dirty) end)))
      (setq +core--inlay-dirty (cons (copy-marker beg) (copy-marker end t))))
    (unless (timerp +core--inlay-dirty-timer)
      (setq +core--inlay-dirty-timer
            ;; At rest already, a revert or a formatter's answer: an idle
            ;; timer would wait for the next rest.
            (if (current-idle-time)
                (run-at-time 0.6 nil #'+core--inlay-refresh-dirty (current-buffer))
              (run-with-idle-timer 0.6 nil #'+core--inlay-refresh-dirty (current-buffer)))))))

(defun +core--inlay-refresh-dirty (buffer)
  "Ask for the hints of BUFFER's changed text, the blocks that hold it."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (setq +core--inlay-dirty-timer nil)
      (when-let* ((dirty +core--inlay-dirty))
        (let ((first (/ (1- (line-number-at-pos (car dirty) t)) +core-inlay-block-lines))
              (last (/ (1- (line-number-at-pos (cdr dirty) t)) +core-inlay-block-lines)))
          (+core--inlay-dirty-clear)
          (+core--inlay-send buffer +core--inlay-round
                             (mapcar (lambda (block) (* block +core-inlay-block-lines))
                                     (number-sequence first last))))))))

(after! eglot
  (defadvice! +core--inlay-hints-on-edit-a (fn from to)
    "Ask for the hints of FROM to TO when the buffer changed since they
were last asked for, or for a block of the whole buffer; scrolling finds
them there. After an edit the whole screen is asked for: eglot's region
starts after the line just typed, drawn already, and scrolling no longer
asks again for it."
    :around #'eglot--update-hints-1
    (cond
     (+core--inlay-all
      (setq +core--inlay-tick (buffer-chars-modified-tick))
      (funcall fn from to))
     ((not (eql +core--inlay-tick (buffer-chars-modified-tick)))
      (setq +core--inlay-tick (buffer-chars-modified-tick))
      (let* ((window (get-buffer-window))
             (from (if window (min from (window-start window)) from))
             (to (if window (max to (window-end window t)) to)))
        ;; Changed on screen only: this request covers it.
        (when (and +core--inlay-dirty
                   (<= from (car +core--inlay-dirty))
                   (<= (cdr +core--inlay-dirty) to))
          (+core--inlay-dirty-clear))
        (funcall fn from to)))))

  (add-hook! 'eglot-inlay-hints-mode-hook
    (defun +core--inlay-hints-whole-h ()
      "Ask for the whole buffer's hints as they come on."
      (if eglot-inlay-hints-mode
          (progn (add-hook 'after-change-functions #'+core--inlay-dirty-h nil t)
                 (+core--inlay-hints-all))
        (remove-hook 'after-change-functions #'+core--inlay-dirty-h t)))))


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
            ((setq diags (eglot--flymake-sniff-diagnostics (point)))
             (list (apply #'min (mapcar #'flymake-diagnostic-beg diags))
                   (apply #'max (mapcar #'flymake-diagnostic-end diags))))
            ((setq bounds (bounds-of-thing-at-point 'symbol))
             (list (car bounds) (cdr bounds)))
            (t (list (point) (point)))))))

;; With the buffer given back before the server answers (above), a second
;; file of the project opened while its server is still starting, a
;; header straight after its source, started a second server: eglot
;; knows of a server only once it has answered. One of the two then died,
;; and said so as an error. A start on its way is waited for now; when
;; its server answers it takes every open file of the project, this one
;; too. A start asked for by hand always goes ahead.
(defvar +core--lsp-starting nil
  "((ROOT . MODES) . TIME) for each server started and not answering yet.")

(defvar-local +core--lsp-ensuring nil
  "Set by `eglot-ensure': the next start in this buffer is not by hand.")

(defun +core--lsp-started-h (server)
  "Forget that SERVER was on its way: it answered, or it died."
  (setq +core--lsp-starting
        (assoc-delete-all (cons (project-root (eglot--project server))
                                (eglot--major-modes server))
                          +core--lsp-starting)))

(after! eglot
  (defadvice! +core--lsp-ensuring-a (&rest _)
    "Mark the start `eglot-ensure' will make as automatic."
    :before #'eglot-ensure
    (setq +core--lsp-ensuring t))

  (defadvice! +core--lsp-one-start-a (fn managed-modes project &rest args)
    "Start a server, unless an automatic start finds one for PROJECT and
MANAGED-MODES on its way already."
    :around #'eglot--connect
    (let ((automatic (prog1 +core--lsp-ensuring (setq +core--lsp-ensuring nil)))
          (key (cons (project-root project) managed-modes))
          (patience (if (numberp eglot-connect-timeout) eglot-connect-timeout 30)))
      ;; A start that never answered is let go once eglot gives up on it.
      (setq +core--lsp-starting
            (seq-filter (lambda (entry) (< (- (float-time) (cdr entry)) patience))
                        +core--lsp-starting))
      (unless (and automatic (assoc key +core--lsp-starting))
        (push (cons key (float-time)) +core--lsp-starting)
        (apply fn managed-modes project args))))

  (add-hook 'eglot-connect-hook #'+core--lsp-started-h)
  (advice-add 'eglot--on-shutdown :after #'+core--lsp-started-h))

;; The echo area takes up to three lines for what is under the cursor.
;; One line cut every diagnostic that did not fit, which is most of the
;; ones worth reading; three holds nearly all of them and still does not
;; grow into a page. K or SPC c H open the whole text when even that is
;; not enough.
(setq eldoc-echo-area-use-multiline-p 3)

;; What is under the cursor shows after a quarter second at rest, not
;; half. In C++ with clangd that rest asks for the signature, the hover
;; and the highlights, 37 to 46 ms of work in all, the longest piece 19
;; ms: a key pressed meanwhile waits no more than that (2026-10-23).
(setq eldoc-idle-delay 0.25)

;; eldoc, which eglot brings from ELPA and which loads with the first
;; file, primes its list of motion commands by running thirty prefixes
;; one by one through every symbol there is: 76 000 of them in a session
;; here, 235 ms, and 581 while the minibuffer folds case. One regexp for
;; all thirty, matched in C in a single pass, finds the same 152 commands
;; in 30 ms.
(defadvice! +core--eldoc-command-completions-a (&rest names)
  "Add every command whose name starts with one of NAMES, in one pass."
  :override #'eldoc-add-command-completions
  (let ((completion-regexp-list (list (concat "\\`" (regexp-opt names))))
        (completion-ignore-case nil))
    (apply #'eldoc-add-command (all-completions "" obarray #'commandp))))

;; Questions are answered on the keyboard, in the minibuffer. Emacs asks
;; through a GTK dialog when the question was started by the mouse, and
;; closing the frame with the window button is one of those: the dialog
;; wants a click on Yes, and typing y into it does nothing.
(setq use-dialog-box nil)

;;
;;; Editing

;; :lang sh has no +tree-sitter flag, so map the mode here.
(when (modulep! :tools tree-sitter)
  (set-tree-sitter! 'sh-mode 'bash-ts-mode
    '((bash :url "https://github.com/tree-sitter/tree-sitter-bash"))))

;; yasnippet reads a mode's snippets the first time the mode is used, a
;; file at a time: for each, Emacs asked editorconfig the file's coding,
;; and editorconfig looked for .editorconfig files up every directory,
;; and yasnippet looked up the tree for a .yas-make-groups. Two thirds of
;; it went there, half the cost of the first Elisp file of a session. The
;; snippets are UTF-8, and a directory's groups file is looked for once.
(defvar +core--yas-groups nil
  "While snippets load, (DIRECTORY . NAME) to where NAME was found above.")

(after! yasnippet
  (defadvice! +core--yas-load-quickly-a (fn directory mode)
    :around #'yas--load-directory-2
    (if +core--yas-groups
        (funcall fn directory mode)
      (let ((+core--yas-groups (make-hash-table :test #'equal))
            (coding-system-for-read 'utf-8)
            (find (symbol-function 'locate-dominating-file)))
        (cl-letf (((symbol-function 'locate-dominating-file)
                   (lambda (file name)
                     (let* ((key (cons (file-name-directory (expand-file-name file)) name))
                            (hit (gethash key +core--yas-groups 'none)))
                       (if (eq hit 'none)
                           (puthash key (funcall find file name) +core--yas-groups)
                         hit)))))
          (funcall fn directory mode))))))

;; yasnippet-capf looks for a snippet key by scanning the buffer from its
;; first character to point each time completion is tried, unless told
;; how far to look: most of the typing cost in a long org file. A key is
;; a word, and eighty characters either side is plenty.
(after! yasnippet-capf
  (setq yasnippet-capf-max-search-distance 80))

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
;; M-d asks for it at once, and M-n and M-p read a long one. By itself it
;; comes 0.3 s after the list does, and follows the selection in 0.15:
;; Doom waited half a second and then a whole one at each move.
(after! corfu-popupinfo
  (setq corfu-popupinfo-delay '(0.3 . 0.15)))
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

;; A project whose directory was deleted or moved stayed in SPC p p for
;; good, and picking it failed. The list is checked each time it is
;; asked for now: a root that is gone leaves it and projects.eld. So
;; does one on a disk that is not mounted; a remote one is kept.
(after! projectile
  (setq projectile-auto-cleanup-known-projects t))

;; SPC k was the C++ keys wherever you were: in a Pascal project most of
;; them meant nothing, and outside a project nothing at all. It opens
;; the keys of the module that owns the project now, C++, Pascal, Rust
;; or the web; in a project none of them knows, what projection can do
;; with it; outside one, starting a project and going to one. Each
;; module registers its map with `+core-register-builder'.
(defvar +core-kit-map
  (+core-kit-keymap
   '(("n" "New project"            #'+core/new-project)
     ("p" "Open a project"         #'projectile-switch-project)
     ("f" "A file in any project"  #'projectile-find-file-in-known-projects)
     ("o" "The projects folder"    #'+core/open-projects-dir)
     ("g" "Clone a repository"     #'magit-clone)
     ("D" "Forget a project"       #'projectile-remove-known-project)))
  "SPC k outside a project: starting one, and going to one.")

(defvar +core-kit-project-map
  (let ((map (+core-kit-keymap
              '(("b" "Build"             #'projection-commands-build-project)
                ("B" "Build a target"    #'projection-multi-compile)
                ("c" "Configure"         #'projection-commands-configure-project)
                ("t" "Test"              #'projection-commands-test-project)
                ("r" "Run"               #'projection-commands-run-project)
                ("i" "Install"           #'projection-commands-install-project)
                ("P" "Package"           #'projection-commands-package-project)))))
    (set-keymap-parent map +core-kit-map)
    map)
  "SPC k in a project no module here knows: what projection can do with
its sixty kinds, and the keys from outside a project.")

(define-key doom-leader-map "k" '(menu-item "project" nil :filter +core--kit-map))
(after! which-key
  (which-key-add-key-based-replacements
    (concat doom-leader-key " k") "project"
    (concat doom-leader-alt-key " k") "project"))

;; SPC SPC lists the project's files by how recently they were opened,
;; so the first, the one it opens on and previews, was the file already
;; on screen: its preview showed what was there and looked like none.
;; That file goes to the end, and the list opens on the one before it.
(declare-function projectile-project-root "projectile")
(defun +core--current-file-last (candidates)
  "CANDIDATES sorted as usual, with the file shown in the window the
prompt was opened from moved to the end; from core's view, the file of
the window the view stands beside."
  (let ((sorted (funcall (default-value 'vertico-sort-function) candidates))
        (current (when-let* ((window (let ((from (minibuffer-selected-window)))
                                       (if (and from (window-parameter from '+core-view))
                                           (get-mru-window nil nil t)
                                         from)))
                             (buffer (window-buffer window))
                             (file (buffer-file-name buffer))
                             (root (with-current-buffer buffer
                                     (ignore-errors (projectile-project-root)))))
                   (file-relative-name file root))))
    (if (and current (member current sorted))
        (nconc (delete current sorted) (list current))
      sorted)))

(after! vertico-multiform
  (add-to-list 'vertico-multiform-categories
               '(project-file (vertico-sort-function . +core--current-file-last))))

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

;; SPC s s lists every line of the buffer before its prompt opens: 1.9 s
;; in a 50 MB log, and each key then sifted 430 000 lines. Past
;; `+core-search-buffer-max' it asks ripgrep about the file instead,
;; which answers as you type and moves the view as the line search does.
;; Changes not saved, or a selection over several lines, keep the line
;; search: ripgrep reads the file on disk.
(defvar +core-search-buffer-max (* 2 1024 1024)
  "Past this size SPC s s searches the buffer's file with ripgrep.")

(declare-function consult-ripgrep "consult")
(defvar consult-async-split-style)
(defvar consult-async-split-styles-alist)
(declare-function consult--split-perl "consult")

(defadvice! +core--search-big-buffer-a (fn)
  "Search a file past `+core-search-buffer-max' with ripgrep."
  :around #'+default/search-buffer
  (let ((text (and (region-active-p)
                   (buffer-substring-no-properties (region-beginning) (region-end)))))
    (if (and buffer-file-name
             (> (buffer-size) +core-search-buffer-max)
             (not (buffer-modified-p))
             (not (file-remote-p buffer-file-name))
             (not (and text (string-search "\n" text)))
             (executable-find "rg")
             (require 'consult nil t))
        (let ((query (and text (regexp-quote text)))
              (consult-async-split-style consult-async-split-style)
              (consult-async-split-styles-alist consult-async-split-styles-alist))
          (when text (deactivate-mark))
          ;; An Emacs regexp, which consult turns into ripgrep's, quoted
          ;; as Doom's file search quotes; and, as there, another
          ;; separator than # when the text has one, which would split it.
          (when (and query (eq consult-async-split-style 'perl)
                     (string-search "#" query))
            (setf (alist-get 'perlalt consult-async-split-styles-alist)
                  (list :initial (or (seq-find (lambda (c) (not (string-search (string c) query)))
                                               '(?% ?@ ?! ?& ?/ ?\;))
                                     ?%)
                        :function #'consult--split-perl)
                  consult-async-split-style 'perlalt))
          (consult-ripgrep (list buffer-file-name) query))
      (funcall fn))))


;;
;;; The bigger topics

(load! "+dired")                        ; the file manager
(load! "+images")                       ; the image viewer
(load! "+data")                         ; JSON, YAML, TOML, XML and friends
(load! "+undo")                         ; undo as a graph, U


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

;; The window's close button asks whether to save what is open, whether
;; to stop what still runs, whether to quit, in the minibuffer. KDE takes
;; that click without giving the window the keyboard, and Wayland lets no
;; program take it: the frame is raised and given the focus here, which
;; works under X and nowhere else. The click that then brings Emacs
;; forward lands in a window and puts the cursor there, out of the
;; minibuffer, so y or n went to the buffer and the question stayed.
;; While quitting, a question reads the next key wherever the cursor is.
(defun +core--answer-anywhere-a (fn &rest args)
  "Call FN with ARGS, the questions it asks answered by the next key.
It advises the commands that quit, SPC q q's among them."
  (when (display-graphic-p)
    (let ((frame (selected-frame)))
      (when (frame-live-p frame)
        (ignore-errors (raise-frame frame))
        (ignore-errors (select-frame-set-input-focus frame)))))
  (let ((y-or-n-p-use-read-key t))
    (apply fn args)))

(advice-add 'save-buffers-kill-emacs :around #'+core--answer-anywhere-a)
(advice-add 'save-buffers-kill-terminal :around #'+core--answer-anywhere-a)
(with-eval-after-load 'doom-ui
  (when (fboundp 'doom/delete-frame-with-prompt)
    (advice-add 'doom/delete-frame-with-prompt :around #'+core--answer-anywhere-a)))


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
       :desc "Transparency"        "T" #'+core/toggle-transparency
       :desc "Watch for pauses"    "W" #'+core-latency-watch-mode)

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
       :desc "Project TODOs"       "t" #'+core/project-todos)

      (:prefix "h"
       :desc "Delays: what paused" "D" #'+core/latency-show))

;; Next to Doom's own reload keys (SPC h r ...).
(map! :map help-map
      :desc "Doom sync"    "rs" #'+core/doom-sync
      :desc "Doom doctor"  "rd" #'+core/doom-doctor
      :desc "Doom upgrade" "ru" #'+core/doom-upgrade)
