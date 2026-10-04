;;; private/docs/autoload/cheatsheet.el -*- lexical-binding: t; -*-

(defvar +docs-cheatsheet-file)
(declare-function +docs-cheatsheet-mode "../config")
(declare-function consult-org-heading "consult-org")
(declare-function consult-line "consult")
(declare-function org-fold-show-all "org-fold")
(declare-function which-key--get-bindings "which-key")
(declare-function evil-get-auxiliary-keymap "evil-core")

(defvar +docs-cheatsheet-sections)
(defvar +docs-leader-features)
(defvar evil-minor-mode-keymaps-alist)
(declare-function doom-module-list "doom-lib")

;;;###autoload
(defun +docs/cheatsheet (&optional search)
  "Open the cheat sheet beside the current buffer, or close it again.
It opens at the section for the current major mode.  With one prefix
argument SEARCH, pick a heading instead; with two, search its text."
  (interactive "P")
  (let* ((buffer (find-file-noselect +docs-cheatsheet-file))
         (window (get-buffer-window buffer))
         (section (+docs-cheatsheet-section-for)))
    (with-current-buffer buffer
      (read-only-mode +1)
      (+docs-cheatsheet-mode +1))
    (cond ((equal search '(16))
           (pop-to-buffer buffer)
           (+docs/cheatsheet-find))
          (search
           (pop-to-buffer buffer)
           (+docs/cheatsheet-search))
          (window
           ;; F12 again closes it. A window that is the only one in its
           ;; frame cannot be deleted, so the buffer is buried instead
           ;; and the frame keeps something to show.
           (if (one-window-p t (window-frame window))
               (with-selected-window window (quit-window))
             (delete-window window)))
          (t
           (pop-to-buffer buffer)
           (+docs--goto-section section)))))

(defun +docs--goto-section (&optional heading)
  "Fold the sheet and show HEADING, or its start."
  (when (derived-mode-p 'org-mode)
    (org-overview)
    (goto-char (point-min))
    (when (and heading
               (re-search-forward (format "^\\*+ %s" (regexp-quote heading))
                                  nil t))
      (beginning-of-line)
      (org-fold-show-entry)
      (org-fold-show-children)
      (recenter 0))))

;;;###autoload
(defun +docs/cheatsheet-search ()
  "Jump to a cheat sheet heading."
  (interactive)
  (unless (equal (buffer-file-name) +docs-cheatsheet-file)
    (pop-to-buffer (find-file-noselect +docs-cheatsheet-file)))
  (if (fboundp 'consult-org-heading)
      (consult-org-heading)
    (call-interactively #'imenu))
  (when (derived-mode-p 'org-mode)
    (org-fold-show-entry)
    (org-fold-show-children)))

;;;###autoload
(defun +docs/cheatsheet-find ()
  "Search the sheet's text and land on the line: words in any order,
the matches shown as you type.  The sheet unfolds for it, since a
folded line cannot be shown."
  (interactive)
  (unless (equal (buffer-file-name) +docs-cheatsheet-file)
    (pop-to-buffer (find-file-noselect +docs-cheatsheet-file)))
  (when (derived-mode-p 'org-mode)
    (org-fold-show-all))
  (if (fboundp 'consult-line)
      (consult-line)
    (call-interactively #'isearch-forward)))

;;;###autoload
(defun +docs/module-readme (module)
  "Open the README of the private MODULE."
  (interactive
   (let ((dir (file-name-concat doom-user-dir "modules/private")))
     (list (completing-read
            "Module: "
            (mapcar #'file-name-nondirectory
                    (directory-files dir t "^[^.]"))))))
  (find-file
   (file-name-concat doom-user-dir "modules/private" module "README.org")))


;;
;;; The tips: the key rows of the hand written sheet

(defvar +docs--tips nil
  "Cons of (FILE-TIME . TIPS), the cheat sheet read into (SECTION . TIP).")

(defun +docs--strip-markup (text)
  "TEXT without the org markers around keys and code."
  (replace-regexp-in-string "[~=]\\([^~=]+\\)[~=]" "\\1" text))

(defun +docs--global-key-p (key)
  "Non-nil when KEY works on its own, not only inside some menu."
  (string-match-p (concat "\\`\\(SPC\\|M-\\|C-\\|S-\\|F[0-9]\\|<\\|g\\|z\\|Z"
                          "\\|\\]\\|\\[\\|RET\\|TAB\\|ESC\\)")
                  key))

(defun +docs--tip (key description subsection)
  "One tip: KEY and DESCRIPTION, naming the SUBSECTION for a menu key."
  (format "%s%s: %s"
          key
          (if (or (+docs--global-key-p key) (null subsection))
              ""
            (format " (%s)" (replace-regexp-in-string ": " ", " subsection)))
          description))

(defun +docs--read-tips ()
  "Every key row of the hand written cheat sheet, as (SECTION . TIP)."
  (let ((tips nil) (section nil) (subsection nil))
    (with-temp-buffer
      (insert-file-contents +docs-cheatsheet-file)
      (goto-char (point-min))
      (while (not (eobp))
        (let ((line (buffer-substring-no-properties
                     (line-beginning-position) (line-end-position))))
          (cond
           ;; The generated references repeat what the sections say.
           ((string-prefix-p "* Reference" line)
            (goto-char (point-max)))
           ((string-match "\\`\\* \\(.+\\)" line)
            (setq section (match-string 1 line)
                  subsection nil))
           ((string-match "\\`\\*\\* \\(.+\\)" line)
            (setq subsection (match-string 1 line)))
           ((and section
                 (string-match "\\`| ~\\([^|]+?\\)~ +| \\([^|]+?\\) +|" line))
            ;; Two keys in one cell, ~B b~ ~B g~, read as one: B b, B g.
            (push (cons section
                        (+docs--tip (replace-regexp-in-string
                                     "~ +~" ", " (match-string 1 line))
                                      (+docs--strip-markup
                                       (match-string 2 line))
                                      subsection))
                  tips))))
        (forward-line 1)))
    (nreverse tips)))


;;
;;; Searching the docs by words

(defconst +docs--stop-words
  '("a" "an" "the" "to" "of" "in" "on" "at" "for" "and" "or" "is" "it"
    "its" "do" "does" "i" "me" "my" "we" "you" "how" "what" "where"
    "which" "can" "with" "from" "into" "this" "that" "be" "up" "off"
    "one" "some" "any" "there" "here" "then" "when" "please"
    "am" "are" "was" "were" "been" "have" "has" "had" "will" "shall"
    "would" "could" "should" "must" "may" "might" "get" "got" "use"
    "using" "want" "need" "tell" "again" "way" "thing" "things" "stuff"
    "just" "also" "too" "very" "really" "about" "but" "not" "as" "by"
    "all" "every" "each" "another" "same" "than" "so" "if" "sir")
  "Words a question is made of that say nothing about the answer.")

(defvar +docs-synonyms
  '(("folder" "directory" "dired")
    ("folders" "directory" "dired")
    ("dir" "directory" "dired")
    ("explorer" "dired" "dirvish")
    ("tree" "dired" "dirvish")
    ("files" "file" "dired" "find")
    ("terminal" "vterm" "shell")
    ("console" "vterm" "shell")
    ("autocomplete" "completion" "corfu")
    ("autocompletion" "completion" "corfu")
    ("complete" "completion" "corfu")
    ("suggestions" "completion" "corfu")
    ("popup" "completion" "popup")
    ("intellisense" "completion" "eglot" "lsp")
    ("lsp" "eglot" "clangd" "server")
    ("language" "eglot" "clangd" "server")
    ("compile" "build" "compile")
    ("compiling" "build" "compile")
    ("make" "build" "cmake")
    ("cmake" "cmake" "configure" "kit")
    ("toolchain" "kit" "toolchain" "container")
    ("sdk" "kit" "sysroot" "container")
    ("docker" "container" "distrobox")
    ("podman" "container" "distrobox")
    ("target" "target" "device" "deploy")
    ("board" "device" "deploy")
    ("remote" "device" "ssh" "remote")
    ("flash" "deploy" "upload")
    ("run" "run" "execute")
    ("execute" "run")
    ("launch" "run" "start")
    ("debugger" "debug" "dape")
    ("gdb" "debug" "dape")
    ("breakpoints" "breakpoint")
    ("error" "problem" "diagnostic" "flymake")
    ("errors" "problem" "diagnostic" "flymake")
    ("warning" "problem" "diagnostic" "flymake")
    ("warnings" "problem" "diagnostic" "flymake")
    ("lint" "clang-tidy" "diagnostic" "flymake")
    ("diagnostic" "problem" "diagnostic" "error")
    ("diagnostics" "problem" "diagnostic" "error")
    ("fix" "quickfix" "fix" "problem")
    ("formatting" "format" "clang-format")
    ("indentation" "indent" "clang-format")
    ("goto" "go" "jump" "definition")
    ("declaration" "definition" "header")
    ("implementation" "definition" "source")
    ("usages" "references")
    ("callers" "references" "call")
    ("refactor" "rename" "quickfix")
    ("header" "header" "sibling" "source")
    ("docs" "documentation" "help" "sheet" "readme")
    ("documentation" "documentation" "help" "sheet")
    ("manual" "help" "info" "documentation")
    ("cheatsheet" "sheet" "cheat")
    ("keybinding" "key" "keys" "binding")
    ("keybindings" "key" "keys" "binding")
    ("shortcut" "key" "keys" "binding")
    ("shortcuts" "key" "keys" "binding")
    ("hotkey" "key" "keys" "binding")
    ("git" "git" "magit" "commit")
    ("version" "git" "magit" "version")
    ("history" "log" "history" "time")
    ("changes" "diff" "changes" "status")
    ("revert" "revert" "discard" "undo")
    ("discard" "revert" "discard" "checkout")
    ("checkout" "switch" "checkout" "branch")
    ("branches" "branch")
    ("commits" "commit")
    ("amend" "amend" "commit" "history")
    ("squash" "rebase" "squash" "history")
    ("cherry" "cherry" "rebase")
    ("conflict" "merge" "conflict" "smerge")
    ("conflicts" "merge" "conflict" "smerge")
    ("upload" "push" "deploy")
    ("download" "pull" "fetch" "clone")
    ("sync" "pull" "push" "fetch" "sync")
    ("github" "forge" "remote" "browse")
    ("gitlab" "forge" "remote" "browse")
    ("pr" "forge" "pull request")
    ("who" "blame" "author")
    ("author" "blame" "author")
    ("when" "blame" "date" "time")
    ("notes" "note" "roam" "org")
    ("todo" "todo" "task" "agenda")
    ("todos" "todo" "task" "agenda")
    ("task" "todo" "task" "agenda")
    ("tasks" "todo" "task" "agenda")
    ("reminder" "agenda" "schedule" "deadline")
    ("schedule" "agenda" "schedule")
    ("diary" "journal" "daily")
    ("today" "daily" "journal" "today")
    ("wiki" "roam" "note" "link")
    ("zettelkasten" "roam" "note")
    ("bookmarks" "bookmark")
    ("favorite" "bookmark")
    ("favourite" "bookmark")
    ("copy" "copy" "kill" "yank" "clipboard")
    ("paste" "yank" "paste" "clipboard")
    ("cut" "kill" "cut")
    ("clipboard" "clipboard" "kill ring" "yank")
    ("select" "select" "region" "mark")
    ("selection" "select" "region" "mark")
    ("highlight" "highlight" "select" "region")
    ("find" "search" "find")
    ("look" "search" "find")
    ("locate" "search" "find" "jump")
    ("grep" "search" "grep" "ripgrep")
    ("ripgrep" "search" "grep")
    ("regex" "regexp" "search" "replace")
    ("substitute" "replace")
    ("rename" "rename" "replace")
    ("multiple" "multiple" "cursors" "iedit")
    ("cursors" "multiple" "cursors" "iedit")
    ("comment" "comment")
    ("uncomment" "comment")
    ("collapse" "fold")
    ("expand" "fold" "expand" "snippet")
    ("folding" "fold")
    ("outline" "outline" "imenu" "fold")
    ("structure" "outline" "imenu" "breadcrumb")
    ("functions" "imenu" "outline" "symbol")
    ("function" "imenu" "definition" "symbol")
    ("symbols" "symbol" "imenu")
    ("class" "symbol" "definition" "outline")
    ("navigate" "jump" "go" "move")
    ("navigation" "jump" "go" "move")
    ("move" "move" "jump" "go")
    ("scroll" "scroll" "move")
    ("back" "back" "return" "previous")
    ("previous" "previous" "back" "last")
    ("next" "next" "forward")
    ("undo" "undo" "redo")
    ("redo" "undo" "redo")
    ("save" "save" "write")
    ("saving" "save" "write")
    ("reload" "revert" "reload" "sync")
    ("refresh" "revert" "reload" "sync")
    ("restart" "restart" "reload" "sync")
    ("update" "sync" "update" "upgrade")
    ("upgrade" "sync" "update" "upgrade")
    ("install" "install" "package" "sync")
    ("plugin" "package" "module")
    ("plugins" "package" "module")
    ("extension" "package" "module")
    ("config" "config" "configuration" "module")
    ("settings" "config" "configuration" "setting")
    ("preferences" "config" "configuration" "setting")
    ("options" "config" "configuration" "setting")
    ("customize" "config" "configuration")
    ("variable" "variable" "setting" "config")
    ("theme" "theme" "colour" "color")
    ("colors" "theme" "colour" "color")
    ("colours" "theme" "colour" "color")
    ("dark" "theme")
    ("light" "theme")
    ("fonts" "font")
    ("zoom" "font" "size" "scale" "big")
    ("increase" "big" "font" "scale")
    ("decrease" "small" "font" "scale")
    ("larger" "big" "font" "scale")
    ("enlarge" "big" "font" "scale")
    ("shrink" "small" "font" "scale")
    ("hide" "toggle" "hide" "off")
    ("show" "show" "list" "display")
    ("display" "show" "display")
    ("enable" "toggle" "enable" "on")
    ("disable" "toggle" "disable" "off")
    ("turn" "toggle")
    ("bigger" "font" "size" "scale" "big")
    ("smaller" "font" "size" "scale")
    ("size" "size" "font" "scale")
    ("fullscreen" "frame" "maximize" "fullscreen")
    ("maximize" "frame" "maximize" "fullscreen")
    ("split" "split" "window")
    ("pane" "window" "split")
    ("panes" "window" "split")
    ("tabs" "tab" "workspace")
    ("workspaces" "workspace" "tab")
    ("session" "workspace" "session" "restore")
    ("layout" "window" "workspace" "layout")
    ("sidebar" "outline" "minimap" "dired" "side")
    ("map" "minimap")
    ("guides" "guide" "indent")
    ("numbers" "number" "line")
    ("wrap" "wrap" "fill")
    ("close" "close" "quit" "kill")
    ("emacs" "emacs" "doom" "frame")
    ("exit" "quit" "close" "exit")
    ("leave" "quit" "close" "exit")
    ("escape" "quit" "close" "esc")
    ("cancel" "quit" "cancel" "abort")
    ("stop" "quit" "stop" "kill" "cancel")
    ("kill" "kill" "close" "stop")
    ("delete" "delete" "kill" "remove")
    ("remove" "delete" "remove" "kill")
    ("trash" "delete" "trash")
    ("new" "new" "create" "capture")
    ("create" "new" "create" "capture")
    ("open" "open" "find" "visit")
    ("visit" "open" "find" "visit")
    ("recent" "recent" "history")
    ("switch" "switch" "buffer" "other")
    ("buffers" "buffer")
    ("windows" "window")
    ("ai" "claude" "gptel" "agent" "llm")
    ("llm" "claude" "gptel" "agent" "llm")
    ("chat" "gptel" "claude" "chat")
    ("gpt" "gptel" "claude")
    ("assistant" "claude" "agent" "butler")
    ("copilot" "claude" "agent" "completion")
    ("explain" "explain" "gptel")
    ("summarize" "explain" "gptel" "rewrite")
    ("translate" "rewrite" "gptel")
    ("spelling" "spell")
    ("spellcheck" "spell")
    ("typo" "spell")
    ("dictionary" "spell" "dictionary")
    ("hudson" "butler")
    ("him" "butler")
    ("mascot" "butler")
    ("greeting" "greeting" "dashboard" "butler")
    ("home" "dashboard" "home")
    ("start" "dashboard" "start" "run")
    ("startup" "dashboard" "startup" "start")
    ("slow" "performance" "slow" "lag")
    ("lag" "performance" "slow" "lag")
    ("performance" "performance" "slow" "lag")
    ("freeze" "performance" "slow" "hang")
    ("crash" "doctor" "error" "log")
    ("broken" "doctor" "check" "error")
    ("check" "check" "doctor")
    ("health" "doctor" "check")
    ("test" "test" "ctest")
    ("tests" "test" "ctest")
    ("unit" "test" "ctest")
    ("benchmark" "test" "run")
    ("profile" "profiler" "performance")
    ("macro" "macro" "register")
    ("record" "macro" "register")
    ("repeat" "repeat" "macro" "again")
    ("again" "repeat" "again" "recompile")
    ("recompile" "recompile" "build")
    ("rebuild" "build" "recompile" "clean")
    ("clean" "clean" "build" "reset")
    ("reset" "reset" "clean" "forget")
    ("cache" "cache" "reset" "forget")
    ("forget" "forget" "reset" "cache")
    ("pick" "pick" "choose" "set" "select")
    ("choose" "pick" "choose" "set" "select")
    ("change" "set" "change" "switch")
    ("set" "set" "change")
    ("edit" "edit" "open" "change")
    ("write" "write" "edit" "save")
    ("type" "type" "insert" "kind")
    ("insert" "insert" "type" "snippet")
    ("snippets" "snippet" "template")
    ("boilerplate" "snippet" "template")
    ("scaffold" "template" "new" "project")
    ("generate" "template" "new" "write")
    ("export" "export" "write" "presets")
    ("presets" "preset" "presets" "export")
    ("qtcreator" "qt" "creator" "kit")
    ("qt" "qt" "creator" "kit")
    ("hpkg" "package" "hpkg")
    ("release" "build" "type" "release")
    ("optimize" "build" "type" "release")
    ("flags" "args" "arguments" "variable" "flags")
    ("arguments" "args" "arguments")
    ("args" "args" "arguments")
    ("environment" "env" "environment")
    ("env" "env" "environment")
    ("path" "path" "directory" "prefix")
    ("ssh" "ssh" "device" "remote" "tramp")
    ("connect" "ssh" "device" "connect" "remote")
    ("password" "gpg" "authinfo" "password")
    ("token" "gpg" "authinfo" "token" "key")
    ("api" "api" "key" "gptel")
    ("email" "mail" "email")
    ("mail" "mail" "email")
    ("web" "browser" "browse" "eww")
    ("browse" "browser" "browse")
    ("url" "link" "browse" "url")
    ("links" "link")
    ("image" "image" "picture")
    ("picture" "image" "picture")
    ("screenshot" "image" "screenshot")
    ("pdf" "pdf")
    ("markdown" "markdown" "org")
    ("table" "table" "org")
    ("spreadsheet" "table" "calc")
    ("calculator" "calc")
    ("math" "calc")
    ("date" "date" "time" "calendar")
    ("time" "time" "date" "clock")
    ("clock" "clock" "time")
    ("timer" "timer" "clock" "pomodoro")
    ("word" "word" "spell" "count")
    ("count" "count" "word")
    ("encoding" "encoding" "utf" "coding")
    ("unicode" "unicode" "char" "emoji")
    ("emoji" "emoji" "unicode" "char")
    ("character" "char" "unicode")
    ("whitespace" "whitespace" "trailing" "space")
    ("spaces" "whitespace" "tab" "indent")
    ("eol" "eol" "line" "ending")
    ("shell" "shell" "vterm" "eshell" "script")
    ("script" "script" "shell" "run")
    ("command" "command" "run" "M-x")
    ("commands" "command" "M-x")
    ("m-x" "command" "M-x")
    ("leader" "leader" "SPC" "prefix")
    ("prefix" "prefix" "leader" "C-u")
    ("evil" "evil" "vim" "normal" "insert")
    ("vim" "evil" "vim" "normal" "insert")
    ("mode" "mode" "state" "major")
    ("modes" "mode" "state" "major")
    ("normal" "normal" "evil" "state")
    ("visual" "visual" "select" "region")
    ("emacs" "emacs" "doom")
    ("doom" "doom" "emacs")
    ("modules" "module")
    ("readme" "readme" "documentation"))
  "What a question may call things and what the docs call them: each
entry is a word of a question and the words to look for in its place.
The docs are written once, in their own words; a question comes in
anyone's.")

(defun +docs--synonyms (word)
  "The words the docs use for WORD: its own entry, or WORD alone."
  (or (cdr (assoc word +docs-synonyms))
      (list word)))

(defun +docs--question-words (question)
  "The words of QUESTION that carry it, lowercased, the stop words and
the one-letter ones dropped; a key sequence typed with SPC stays one
word, spc, so it can be looked for."
  (seq-uniq
   (seq-filter (lambda (word)
                 (and (> (length word) 1)
                      (not (member word +docs--stop-words))))
               (split-string (downcase question) "[^a-z0-9_.+-]+" t))))

(defun +docs--search-files ()
  "The files a question is answered from: the sheet and the READMEs."
  (cons +docs-cheatsheet-file
        (directory-files-recursively
         (file-name-concat doom-user-dir "modules/private") "README\\.org\\'")))

(defun +docs--word-weight (word)
  "How much WORD counts: a long word says more about the answer than a
short one, \"definition\" more than \"jump\", so it weighs a little more."
  (+ 1.0 (* 0.05 (max 0 (- (length word) 4)))))

(defun +docs--word-forms (word)
  "WORD and the other forms of it the docs may be written in: the
plural read as the singular and the other way about, so \"commits\"
finds \"commit\" and \"branches\" finds \"branch\".  Matching counts a
prefix, so only the shorter forms need making."
  (delete-dups
   (cons word
         (cond ((string-suffix-p "ies" word)
                (list (concat (substring word 0 -3) "y")))
               ((string-suffix-p "es" word)
                (list (substring word 0 -2) (substring word 0 -1)))
               ((and (string-suffix-p "s" word) (> (length word) 3))
                (list (substring word 0 -1)))
               (t nil)))))

(defun +docs--holds-p (text word)
  "Non-nil when TEXT holds WORD at the start of a word, a prefix counting."
  (string-match-p (concat "\\(?:\\`\\|[^a-z0-9]\\)" (regexp-quote word)) text))

(defun +docs--holds-any-p (text words)
  "Non-nil when TEXT holds any of WORDS."
  (seq-some (lambda (w) (+docs--holds-p text w)) words))

(defun +docs--word-at (text word)
  "Where TEXT first holds WORD in any of its forms, or nil."
  (seq-some (lambda (w)
              (and (string-match (concat "\\(?:\\`\\|[^a-z0-9]\\)" (regexp-quote w)) text)
                   (match-beginning 0)))
            (+docs--word-forms word)))

(defun +docs--together-p (text words)
  "Non-nil when two of WORDS stand close together in TEXT, within a
handful of characters: words that keep company in a question keep it in
the answer, \"jump to definition\" over a line that only says jump."
  (let ((spots (delq nil (mapcar (lambda (word) (+docs--word-at text word)) words))))
    (and (cdr spots)
         (let ((sorted (sort spots #'<)))
           (cl-loop for (a b) on sorted
                    thereis (and b (< (- b a) 28)))))))

(defun +docs--line-score (line words &optional section)
  "How much LINE answers a question made of WORDS, SECTION being where
it stands.  A word counts by its weight, a word the docs use in its
place three quarters of that; holding all the words counts for more
than holding one of them twice over, so a line that answers the whole
question wins; a key row counts half more, since a key is what a
question about keys wants, a heading the question names a quarter,
and two words standing together half again.  Returns (SCORE . COVERED),
COVERED the share of the question the line holds, which says how much
of an answer it is."
  (let* ((down (downcase line))
         (where (and section (downcase section)))
         (total (length words))
         (matched 0)
         (base (cl-loop for word in words
                        for forms = (+docs--word-forms word)
                        for weight = (+docs--word-weight word)
                        ;; A word the docs use in this word's place, unless
                        ;; the question already asks for it in its own right:
                        ;; a question naming two things must not have one of
                        ;; them counted twice over.
                        for stands-in = (mapcan #'+docs--word-forms
                                                (seq-remove (lambda (w) (member w words))
                                                            (+docs--synonyms word)))
                        sum (cond ((+docs--holds-any-p down forms)
                                   (cl-incf matched) weight)
                                  ((+docs--holds-any-p down stands-in)
                                   (cl-incf matched) (* 0.75 weight))
                                  ;; The heading over a line answers for it:
                                  ;; the row that reloads the config says
                                  ;; nothing of Doom, the section it stands
                                  ;; under says it for every row there.
                                  ((and where (+docs--holds-any-p where forms))
                                   (cl-incf matched) (* 0.5 weight))
                                  ((and where (+docs--holds-any-p where stands-in))
                                   (cl-incf matched) (* 0.4 weight))
                                  (t 0)))))
    (cons
     (+ base
        ;; Every word of the question answered is worth more than any
        ;; one of the bonuses below, so nothing outbids a fuller answer.
        (if (> total 0) (* 0.75 (/ (float matched) total)) 0)
        (if (string-prefix-p "| ~" line) 0.5 0)
        ;; Standing under a heading the question names is worth a
        ;; little, whether or not the line needed the heading to
        ;; answer: it is what the lines under it are all about.
        (if (and where
                 (+docs--holds-any-p
                  where (mapcan (lambda (word)
                                  (mapcan #'+docs--word-forms
                                          (cons word (+docs--synonyms word))))
                                words)))
            0.25 0)
        (if (+docs--together-p down words) 0.5 0))
     (if (> total 0) (/ (float matched) total) 0))))

(defun +docs--line-text (line)
  "LINE as it would be said aloud: a key row as \"KEY: what it does\",
any other row of a table as its cells, the pipes that draw it gone."
  (cond ((string-match "\\`| ~\\([^|]+?\\)~ +| \\([^|]+?\\) +|" line)
         (format "%s: %s" (match-string 1 line) (match-string 2 line)))
        ((string-prefix-p "|" line)
         (let ((cells (seq-remove #'string-empty-p
                                  (mapcar #'string-trim (split-string line "|" t)))))
           (pcase cells
             (`(,one) one)
             (`(,one ,two) (format "%s: %s" one two))
             (_ (string-join cells ", ")))))
        (t (string-trim line))))

(defun +docs--distinct (hits)
  "HITS with the repeats dropped: the same line is written in the sheet
and again in a README, and one of them is enough of an answer."
  (let (seen kept)
    (dolist (hit hits (nreverse kept))
      (let ((text (downcase (string-trim (plist-get hit :text)))))
        (unless (member text seen)
          (push text seen)
          (push hit kept))))))

;; Autoloaded: the butler answers questions with it.
;;;###autoload
(defun +docs-search (question &optional limit)
  "The lines of the sheet and the READMEs that answer QUESTION best, at
most LIMIT of them (eight), best first, as plists: :file, :line, :section
(\"Git, Committing\"), :text with the org markup dropped, :key when
the line is a key row, :score how much of an answer it is and
:coverage the share of QUESTION's words it holds.  The
generated references of the sheet, which repeat the sections, are not
read."
  (let ((words (+docs--question-words question)) hits)
    (when words
      (dolist (file (+docs--search-files))
        (when (file-readable-p file)
          (with-temp-buffer
            (insert-file-contents file)
            (goto-char (point-min))
            (let ((readme (and (not (equal file +docs-cheatsheet-file))
                               (format "the %s README"
                                       (file-name-nondirectory (directory-file-name (file-name-directory file))))))
                  (section nil) (subsection nil) (n 0))
              (while (not (eobp))
                (setq n (1+ n))
                (let ((line (buffer-substring-no-properties (line-beginning-position) (line-end-position))))
                  (cond
                   ((string-prefix-p "* Reference" line) (goto-char (point-max)))
                   ((string-match "\\`\\* \\(.+\\)" line)
                    (setq section (match-string 1 line) subsection nil))
                   ((string-match "\\`\\*\\* \\(.+\\)" line)
                    (setq subsection (match-string 1 line)))
                   ((or (string-prefix-p "|-" line) (string-prefix-p "#+" line)
                        (string-prefix-p "| Key" line) (string-blank-p line)))
                   (t (pcase-let* ((`(,score . ,covered)
                                    (+docs--line-score
                                     line words
                                     (string-join (delq nil (list section subsection)) ", ")))
                                   ;; The sheet is written to be answered
                                   ;; from; a README explains a module to
                                   ;; whoever works on it, so it yields.
                                   (score (if readme score (+ score 0.5))))
                        (when (>= score 1)
                          (push (list :file file :line n
                                      :section (string-join (delq nil (list readme section subsection)) ", ")
                                      :text (+docs--strip-markup (+docs--line-text line))
                                      :key (and (string-match "\\`| ~\\([^|]+?\\)~" line)
                                                (match-string 1 line))
                                      :score score :coverage covered)
                                hits))))))
                (forward-line 1)))))))
    (seq-take (+docs--distinct
               (seq-sort-by (lambda (hit) (plist-get hit :score)) #'> (nreverse hits)))
              (or limit 8))))

;; Autoloaded: the butler asks for his hints.
;;;###autoload
(defun +docs-cheatsheet-tips ()
  "Every key row of the hand written cheat sheet, as (SECTION . TIP), read
again when the sheet has changed."
  (unless (file-readable-p +docs-cheatsheet-file)
    (user-error "The cheat sheet is missing: %s" +docs-cheatsheet-file))
  (let ((stamp (file-attribute-modification-time
                (file-attributes +docs-cheatsheet-file))))
    (unless (equal stamp (car +docs--tips))
      (setq +docs--tips (cons stamp (+docs--read-tips))))
    (cdr +docs--tips)))

;;
;;; What each module says about itself

(defun +docs--module-docs ()
  "What every enabled private module says for the sheet, in load
order, as (NAME . PLIST).  PLIST is the module's own `+NAME-docs' when
it defines one: :groups, a list of (PREFIX HEADING FEATURES MAPS...),
the prefix its commands share, the heading they are listed under, the
features to load before their keys are read and the mode maps, or the
minor modes, those keys may live in besides the leader; and :sections,
(MODE . HEADING) pairs saying which section of the sheet a buffer in
MODE, major or minor, opens at.  A module without the variable gets one
group under its own name and no section; a new module needs nothing
here."
  (cl-loop for (group . name) in (doom-module-list)
           when (eq group :private)
           collect (cons name (let ((docs (intern (format "+%s-docs" name))))
                                (and (boundp docs) (symbol-value docs))))))

(defun +docs--command-groups ()
  "Every module's command groups, see `+docs--module-docs'."
  (cl-loop for (name . docs) in (+docs--module-docs)
           append (or (plist-get docs :groups)
                      (list (list (symbol-name name)
                                  (capitalize (symbol-name name))
                                  nil)))))

(defun +docs--sections ()
  "Every module's sections, then `+docs-cheatsheet-sections'."
  (append (cl-loop for (_name . docs) in (+docs--module-docs)
                   append (plist-get docs :sections))
          +docs-cheatsheet-sections))

;; Autoloaded: the butler asks for his hints.
;;;###autoload
(defun +docs-cheatsheet-section-for (&optional buffer)
  "The cheat sheet section that fits BUFFER, the current one by
default: its major mode's, else that of a minor mode on in it, from
what the modules say and `+docs-cheatsheet-sections'; nil when none fits."
  (let ((sections (+docs--sections)))
    (with-current-buffer (or buffer (current-buffer))
      (or (alist-get major-mode sections)
          (cdr (seq-find (lambda (entry)
                           (and (boundp (car entry)) (symbol-value (car entry))))
                         sections))))))

;;
;;; Generated tables

(defvar +docs--descriptions nil
  "Cached (KEY-REGEXP . DESCRIPTION) pairs from which-key.")

(defun +docs--descriptions ()
  "Doom's `:desc' strings, keyed by key sequence regexp."
  (or +docs--descriptions
      (setq +docs--descriptions
            (cl-loop for entry in which-key-replacement-alist
                     when (and (consp (car entry)) (stringp (caar entry))
                               (consp (cdr entry)) (stringp (cddr entry)))
                     collect (cons (caar entry) (cddr entry))))))

(defun +docs--describe-key (key)
  "Description of leader KEY, for example \"k b\", or nil."
  (let ((case-fold-search nil)   ; "SPC l c" must not match "SPC l C"
        (candidates
         (list (concat doom-leader-key " " key)
               ;; SPC h is `help-map', whose keys are recorded on their
               ;; own; only sequences, since a single key such as s is
               ;; also described by other maps (dired's "symlinks").
               (and (string-prefix-p "h " key)
                    (string-match-p " " (substring key 2))
                    (substring key 2)))))
    (cl-loop for full in (delq nil candidates)
             thereis (cdr (seq-find (lambda (d) (string-match-p (car d) full))
                                    (+docs--descriptions))))))

(defun +docs--leader-descriptions ()
  "Alist of (KEY . DESCRIPTION) for everything under the leader, once
`+docs-leader-features' are loaded, so the table does not depend on
what the session has done."
  (require 'which-key)
  (dolist (feature +docs-leader-features)
    (require feature nil t))
  (setq +docs--descriptions nil)
  ;; Entries are (KEY . DESC) in which-key 3 and (KEY SEP DESC) in the
  ;; version bundled with Emacs 30 and later.
  (mapcar (lambda (cell)
            (let* ((key (substring-no-properties (car cell)))
                   (command (substring-no-properties
                             (if (consp (cdr cell)) (car (last cell)) (cdr cell))))
                   (desc (+docs--describe-key key)))
              ;; The description alone keeps the rows narrow; `SPC h k' on
              ;; the key says which command it runs.
              (cons key (or desc command))))
          (let ((which-key-max-description-length 120)) ; don't truncate
            (which-key--get-bindings nil doom-leader-map nil t))))

(defun +docs--org-escape (s)
  "Make S safe inside an org table cell."
  (thread-last (string-trim s)
               (replace-regexp-in-string "|" "/")
               ;; Docstrings come back with curly quotes; keep the sheet ASCII.
               (replace-regexp-in-string "[\u2018\u2019]" "'")
               (replace-regexp-in-string "[\u201C\u201D]" "\"")))

(defun +docs--leader-tables ()
  "One org table of leader bindings per prefix."
  (let ((groups nil) (top nil))
    (dolist (binding (+docs--leader-descriptions))
      (let* ((keys (split-string (car binding) " " t))
             (prefix (car keys)))
        (if (cdr keys)
            (push (cons (string-join (cdr keys) " ") (cdr binding))
                  (alist-get prefix groups nil nil #'equal))
          (push binding top))))
    (with-temp-buffer
      (insert "** Top level (SPC)\n| Key | What it does |\n|-----+--------------|\n")
      (dolist (binding (sort top :key #'car :lessp #'string<))
        (unless (string-prefix-p "+prefix" (cdr binding))
          (insert (format "| ~SPC %s~ | %s |\n"
                          (+docs--org-escape (car binding))
                          (+docs--org-escape (cdr binding))))))
      (dolist (group (sort groups :key #'car :lessp #'string<))
        (let ((prefix (car group)))
          (insert (format "\n** SPC %s: %s\n| Key | What it does |\n|-----+--------------|\n"
                          prefix (or (+docs--describe-key prefix) prefix)))
          (dolist (binding (sort (cdr group) :key #'car :lessp #'string<))
            (insert (format "| ~SPC %s %s~ | %s |\n" prefix
                            (+docs--org-escape (car binding))
                            (+docs--org-escape (cdr binding)))))))
      ;; Aligned here, so what goes into the file is what a reader sees
      ;; and a regeneration compares like with like.
      (let ((org-inhibit-startup t) (org-mode-hook nil))
        (delay-mode-hooks (org-mode)))
      (org-table-map-tables #'org-table-align t)
      (buffer-string))))

(defun +docs--this-config-p (command)
  "Non-nil when COMMAND is defined in this config, not in Doom or a package.
A prefix alone does not say: Doom's :lang org defines +org/ commands,
and a package could define anything."
  (when-let* ((file (symbol-file command 'defun)))
    (file-in-directory-p file doom-user-dir)))

(defun +docs--keymaps (maps)
  "The keymaps MAPS name.  A bound keymap symbol comes with the evil maps
that sit on top of it, since a :n binding lives in an auxiliary map,
not in the mode map itself; a minor mode symbol brings the state maps
`evil-define-minor-mode-key' keeps for it, apart from any keymap."
  (cl-loop for symbol in maps
           when (and (boundp symbol) (keymapp (symbol-value symbol)))
           collect (symbol-value symbol)
           and append (when (fboundp 'evil-get-auxiliary-keymap)
                        (delq nil (mapcar (lambda (state)
                                            (evil-get-auxiliary-keymap (symbol-value symbol) state))
                                          '(normal motion visual))))
           append (cl-loop for (_state . modes) in (bound-and-true-p evil-minor-mode-keymaps-alist)
                           for map = (cdr (assq symbol modes))
                           when map collect map)))

(defun +docs--command-key (command maps)
  "The key to show for COMMAND: under the leader when it has one there,
else in one of MAPS (symbols of keymaps, unbound ones skipped), else
wherever `where-is-internal' finds it in the global maps.  Looked up in
the maps themselves, not in the buffer the sheet is regenerated from,
so dired's and C++'s keys are found from anywhere."
  (cl-flet ((describe (key)
              ;; A localleader key is bound under M-SPC as well; the sheet
              ;; shows the SPC form, the one the leader tables use.
              (thread-last (key-description key)
                           (replace-regexp-in-string "<[a-z-]+-state> " "")
                           (replace-regexp-in-string "\\`M-SPC " "SPC "))))
    (or (when-let* ((key (where-is-internal command (list doom-leader-map) t)))
          (concat doom-leader-key " " (describe key)))
        ;; One map at a time, not the whole list at once. Given a list,
        ;; `where-is-internal' drops a key that an earlier map in it binds
        ;; to something else, so dired's j and k hid the image viewer's
        ;; pan keys and the sheet printed those commands with no key at
        ;; all. Worse, it depended on whether dirvish had loaded yet.
        ;;
        ;; Asking each map separately gives several answers where the one
        ;; list gave none, so they are ranked: the localleader form first,
        ;; since that is the one a reader can find from the mode they are
        ;; in, then the shortest, which is how TAB wins over <tab>.
        (when-let* ((keys (delq nil
                                (cl-loop for map in (+docs--keymaps maps)
                                         collect (where-is-internal
                                                  command (list map) t))))
                    (best (car (sort (mapcar #'describe keys)
                                     (lambda (a b)
                                       (let ((la (string-prefix-p "SPC " a))
                                             (lb (string-prefix-p "SPC " b)))
                                         (cond ((and la (not lb)) t)
                                               ((and lb (not la)) nil)
                                               (t (< (length a) (length b))))))))))
          best)
        (when-let* ((key (where-is-internal command nil t)))
          (describe key)))))

(defun +docs--fill (text)
  "TEXT wrapped at 76 columns, continuation lines indented by two."
  (with-temp-buffer
    (insert text)
    (let ((fill-column 76)
          (fill-prefix "  "))
      (fill-region (point-min) (point-max)))
    (buffer-string)))

(defun +docs--command-entry (command maps)
  "One description list item for COMMAND, from its docstring and its key,
looked up in the leader, then MAPS, then the global maps."
  ;; A transient menu keeps its docstring in a property set when its file
  ;; loads, so an autoload stub knows nothing about it.
  (when (autoloadp (symbol-function command))
    (ignore-errors (autoload-do-load (symbol-function command) command)))
  (let* ((doc (or (ignore-errors (documentation command)) ""))
         ;; The first sentence, even when it wraps onto a second line.
         (paragraph (string-join (split-string (car (split-string doc "\n\n")) "\n" t)
                                 " "))
         (summary (if (string-match "\\`\\(.*?[.!?]\\)\\(?:[ \t]\\|\\'\\)" paragraph)
                      (match-string 1 paragraph)
                    paragraph))
         (key (+docs--command-key command maps)))
    (+docs--fill (format "- ~%s~%s :: %s\n"
                         command
                         (if key (format " (~%s~)" (+docs--org-escape key)) "")
                         (+docs--org-escape summary)))))

(defun +docs--commands-list ()
  "A description list of every command this config adds, per module,
the groups from `+docs--command-groups'.  The features are loaded
before the keys are read, and the maps are read directly, so the tables
come out the same whatever buffer this runs in and whatever the session
has loaded so far."
  (with-temp-buffer
    (pcase-dolist (`(,prefix ,heading ,features . ,maps) (+docs--command-groups))
      (dolist (feature features) (require feature nil t))
      (when-let* ((commands (sort (seq-filter #'+docs--this-config-p
                                              (apropos-internal (format "^\\+%s/" prefix)
                                                                #'commandp))
                                  #'string<)))
        (insert (format "\n** %s\n" heading))
        (mapc (lambda (command) (insert (+docs--command-entry command maps)))
              commands)))
    (buffer-string)))

(defun +docs--replace-generated (marker content)
  "Replace what is between the BEGIN and END MARKER lines with CONTENT.
Returns non-nil when the text changed."
  (goto-char (point-min))
  (let ((begin (format "^# BEGIN %s$" marker))
        (end (format "^# END %s$" marker)))
    (unless (re-search-forward begin nil t)
      (user-error "No %s markers in the cheat sheet" marker))
    (let ((start (1+ (line-end-position))))
      (unless (re-search-forward end nil t)
        (user-error "No %s markers in the cheat sheet" marker))
      (let ((old (buffer-substring-no-properties start (line-beginning-position))))
        (unless (equal old content)
          (delete-region start (line-beginning-position))
          (goto-char start)
          (insert content)
          t)))))

;; Autoloaded: bin/check-config asks whether the sheet has drifted.
;;;###autoload
(defun +docs-sheet-stale-p ()
  "Non-nil when the sheet's generated tables no longer match the config.
Rebuilt in a temporary buffer, so asking the question does not answer it
by writing the file: a key added to the config and never regenerated is
a finding, not something to fix behind the user's back."
  (let ((keys (+docs--leader-tables))
        (commands (+docs--commands-list))
        (changed nil))
    (with-temp-buffer
      (insert-file-contents +docs-cheatsheet-file)
      (when (+docs--replace-generated "GENERATED-KEYS" keys) (setq changed t))
      (when (+docs--replace-generated "GENERATED-COMMANDS" commands) (setq changed t)))
    changed))

;;;###autoload
(defun +docs/cheatsheet-regenerate ()
  "Rebuild the key and command tables in the cheat sheet.
The timestamp moves only when a table changed, so a regeneration that
found nothing new leaves the file as it was."
  (interactive)
  (let ((buffer (find-file-noselect +docs-cheatsheet-file))
        (keys (+docs--leader-tables))
        (commands (+docs--commands-list))
        changed)
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (save-excursion
          (when (+docs--replace-generated "GENERATED-KEYS" keys)
            (setq changed t))
          (when (+docs--replace-generated "GENERATED-COMMANDS" commands)
            (setq changed t))
          (when changed
            (goto-char (point-min))
            (when (re-search-forward "^#\\+generated: .*$" nil t)
              (replace-match (format "#+generated: %s"
                                     (format-time-string "%Y-%m-%d %H:%M"))
                             t t))))
        (when changed (save-buffer))))
    (message "Cheat sheet %s: %d leader bindings"
             (if changed "updated" "unchanged")
             (length (+docs--leader-descriptions)))))
