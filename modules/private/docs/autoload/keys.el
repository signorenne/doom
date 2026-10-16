;;; private/docs/autoload/keys.el -*- lexical-binding: t; -*-
;;
;; Do the menus and the documented keys hold up? A transient refuses a
;; key bound twice or a suffix it cannot find, but only when asked, and
;; it moves a suffix off q and Q on its own, since core binds q to quit;
;; so every private menu is set up here under conflict detection and
;; its layout read for what transient would silently move. Then every
;; SPC key the sheet and the READMEs mention is looked up, so a key
;; that changed in the config cannot stay in the docs; and the leader
;; is read for one of our commands on two keys and for a Doom key
;; rebound without meaning to. bin/check-config runs all of it;
;; `+docs/check-keys' does from a session.

(require 'transient)

(defvar transient-detect-key-conflicts)
(defvar transient--layout)
(declare-function transient-setup "transient")
(declare-function transient-quit-all "transient")

(defconst +docs--owned-keys '("q" "Q" "?" "M-q" "C-g" "C-h")
  "Keys transient keeps for itself in this config: q quits and ? explains,
and a suffix on q or Q is moved to Q or M-q without a word.")


;;
;;; The menus

(defun +docs--prefixes ()
  "Every transient prefix the private modules define, by name."
  (let ((root (file-name-concat doom-user-dir "modules/private")) names)
    (dolist (file (directory-files-recursively root "\\.el\\'"))
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (while (re-search-forward "^(transient-define-prefix \\(\\+[^ \t\n()]+\\)" nil t)
          (push (intern (match-string 1)) names))))
    (nreverse names)))

(defun +docs--layout-suffixes (layout)
  "(KEY . COMMAND) for every suffix in LAYOUT, groups walked, keyless
entries, the :info lines, left out."
  (let (out)
    (cl-labels ((walk (node)
                  (cond ((vectorp node) (mapc #'walk (aref node 2)))
                        ((and (listp node) (symbolp (car node)) (keywordp (cadr node)))
                         (when-let* ((key (plist-get (cdr node) :key)))
                           (push (cons key (plist-get (cdr node) :command)) out)))
                        ((listp node) (mapc #'walk node)))))
      (mapc #'walk layout))
    (nreverse out)))

(defun +docs--menu-keys (prefix)
  "The keys PREFIX's layout binds, loaded if need be."
  (when (autoloadp (symbol-function prefix))
    (autoload-do-load (symbol-function prefix) prefix))
  (mapcar #'car (+docs--layout-suffixes (get prefix 'transient--layout))))

;; Autoloaded: bin/check-config.el calls it in the throwaway daemon.
;;;###autoload
(defun +docs-menu-problems ()
  "Every private menu that does not hold up, as a list of sentences:
one that fails to set up under conflict detection (a key bound twice,
a suffix neither defined nor autoloaded), a suffix on a key transient
owns, a command on two keys.  Nil when all is well.  Needs a frame to
show the menu in, so not doom doctor."
  (let (problems)
    (dolist (prefix (+docs--prefixes))
      (when (autoloadp (symbol-function prefix))
        (autoload-do-load (symbol-function prefix) prefix))
      (let ((transient-detect-key-conflicts t))
        (condition-case err
            (progn (transient-setup prefix) (transient-quit-all))
          (error (ignore-errors (transient-quit-all))
                 (push (format "%s does not set up: %s" prefix (error-message-string err))
                       problems))))
      (let ((suffixes (+docs--layout-suffixes (get prefix 'transient--layout)))
            (by-command (make-hash-table)))
        (pcase-dolist (`(,key . ,command) suffixes)
          (when (member key +docs--owned-keys)
            (push (format "%s binds %s, which transient owns here, to %s" prefix key command)
                  problems))
          (when (symbolp command)
            (push key (gethash command by-command))))
        (maphash (lambda (command keys)
                   (when (cdr keys)
                     (push (format "%s binds %s on %s" prefix command
                                   (mapconcat #'identity (reverse keys) " and "))
                           problems)))
                 by-command)))
    (nreverse problems)))


;;
;;; The leader

(defconst +docs-doom-keys-taken '("SPC o -" "SPC f d" "SPC p >")
  "Doom leader keys a private module rebinds on purpose: the two dired
keys and the one for another project, which open dirvish with the
preview pane where Doom would have asked for a file.  Any other key that
carries Doom's description and ours is a shadow nobody meant.")

(defun +docs--private-prefixes ()
  "The prefixes this config's commands carry, +core/ and the rest, read
from the definitions in the private modules; Doom's own +default/ and
+lookup/ are not among them."
  (let ((root (file-name-concat doom-user-dir "modules/private")) prefixes)
    (dolist (file (directory-files-recursively root "\\.el\\'"))
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (while (re-search-forward "^(\\(?:defun\\|transient-define-prefix\\) \\(\\+[a-z]+/\\)" nil t)
          (cl-pushnew (match-string 1) prefixes :test #'equal))))
    prefixes))

(defun +docs--private-command-p (command prefixes)
  "Non-nil when COMMAND, a symbol, is one of this config's, by PREFIXES."
  (and (symbolp command)
       (seq-some (lambda (prefix) (string-prefix-p prefix (symbol-name command)))
                 prefixes)))

(defun +docs--kit-maps ()
  "Every keymap SPC k can open, one for each kind of project; nil before
core has made them."
  (and (fboundp '+core-kit-maps) (mapcar #'cdr (+core-kit-maps))))

(defun +docs--leader-bindings ()
  "(KEYS . COMMAND) for every command under the leader, KEYS after SPC,
those of every SPC k keymap among them."
  (let (out)
    (cl-labels ((walk (map prefix)
                  (map-keymap (lambda (event def)
                                (let ((keys (concat prefix (if prefix " " "")
                                                    (key-description (vector event))))
                                      ;; A kit map keeps its descriptions
                                      ;; in the map: ("Build" . command).
                                      (def (if (and (consp def) (stringp (car def)))
                                               (cdr def)
                                             def)))
                                  (cond ((keymapp def) (walk def keys))
                                        ((and def (symbolp def) (not (numberp def)))
                                         (push (cons keys def) out)))))
                              map)))
      (walk doom-leader-map nil)
      (dolist (map (+docs--kit-maps))
        (walk map "k")))
    out))

;; Autoloaded: bin/check-config.el calls it in the throwaway daemon.
;;;###autoload
(defun +docs-leader-problems ()
  "Every leader key that does not hold up, as a list of sentences: one
of this config's commands on two keys, or a Doom key rebound that
`+docs-doom-keys-taken' does not name, seen as a key described twice
in which-key, Doom's word and ours.  Nil when all is well."
  (require 'which-key)
  (let ((by-command (make-hash-table)) (by-key (make-hash-table :test #'equal))
        (prefixes (+docs--private-prefixes)) problems)
    (pcase-dolist (`(,keys . ,command) (+docs--leader-bindings))
      ;; One key in several kit maps, SPC k n in all of them, is one key.
      (when (+docs--private-command-p command prefixes)
        (cl-pushnew keys (gethash command by-command) :test #'equal)))
    (maphash (lambda (command keys)
               (when (cdr keys)
                 (push (format "%s is on SPC %s" command
                               (mapconcat #'identity (sort keys #'string<) " and SPC "))
                       problems)))
             by-command)
    (dolist (entry which-key-replacement-alist)
      ;; An entry can hold a function in place of (KEY . DESCRIPTION):
      ;; Doom's, which trims its prefixes from every command's name.
      (let ((key-regexp (car-safe (car entry))) (description (cdr-safe (cdr entry))))
        (when (and (stringp key-regexp) (string-prefix-p "\\`SPC " key-regexp)
                   (stringp description))
          (cl-pushnew description (gethash (substring key-regexp 2 -2) by-key) :test #'equal))))
    ;; Doom describes a few of its own keys twice, so only a key that
    ;; now holds one of our commands, or a prefix of ours, counts.
    (maphash (lambda (key descriptions)
               (let ((binding (ignore-errors (lookup-key doom-leader-map (kbd (substring key 4))))))
                 (when (and (cdr descriptions)
                            (not (member key +docs-doom-keys-taken))
                            (or (keymapp binding)
                                (+docs--private-command-p binding prefixes)))
                   (push (format "%s is a Doom key, rebound: %s" key
                                 (mapconcat (lambda (d) (format "%S" d)) (reverse descriptions) " and "))
                         problems))))
             by-key)
    (nreverse problems)))


;;
;;; The documented keys

(defconst +docs--key-mention-regexp "[~=]SPC \\([^~=\n]+\\)[~=]"
  "A leader key in the sheet or a README, the keys after SPC in group 1.")

(defun +docs--documented-keys ()
  "Every leader key the sheet, above its generated part, and the private
READMEs mention, as (FILE LINE KEYS): notation with a range or brackets
skipped, a mention that lists several keys split at the commas."
  (let ((files (cons (file-name-concat doom-user-dir "docs/cheatsheet.org")
                     (directory-files-recursively
                      (file-name-concat doom-user-dir "modules/private") "README\\.org\\'")))
        out)
    (dolist (file files)
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (let ((limit (or (save-excursion (re-search-forward "^\\* Reference: " nil t))
                         (point-max))))
          (while (re-search-forward +docs--key-mention-regexp limit t)
            (let ((line (line-number-at-pos))
                  (mention (replace-regexp-in-string "\\s-+" " " (string-trim (match-string 1)))))
              (dolist (keys (split-string mention " *, *" t))
                (unless (string-match-p "\\.\\.\\|[][]" keys)
                  (push (list (file-relative-name file doom-user-dir) line keys) out))))))))
    (nreverse out)))

(defun +docs--key-problem (keys)
  "Why KEYS, the keys after SPC, is not a binding: a sentence, or nil.
The leader map is followed key by key; a command reached with keys
left over is a menu key when the command is a private menu, checked
against its layout, and accepted otherwise, a capture template's key
or an argument.  The localleader is not followed.  SPC k opens the
keymap of the project's kind, so a key under it is bound when one of
those maps binds all of it."
  (let ((parts (split-string keys " " t)))
    (cond
     ((equal (car parts) "m") nil)
     ((and (equal (car parts) "k") (+docs--kit-maps))
      (let ((problems (mapcar (lambda (map)
                                (+docs--key-problem-1
                                 parts (lambda (seq)
                                         (if (equal seq "k")
                                             map
                                           (ignore-errors
                                             (lookup-key map (kbd (substring seq 2))))))))
                              (+docs--kit-maps))))
        (unless (memq nil problems) (car problems))))
     (t (+docs--key-problem-1
         parts (lambda (seq) (ignore-errors (lookup-key doom-leader-map (kbd seq)))))))))

(defun +docs--key-problem-1 (parts lookup)
  "Why the key PARTS is not a binding, following it with LOOKUP, which
takes the keys so far as a string and returns their binding."
  (let ((n (length parts)) (i 0) problem)
    (catch 'done
      (while (< i n)
        (let* ((seq (mapconcat #'identity (seq-take parts (1+ i)) " "))
               (binding (funcall lookup seq)))
          (cond
           ((keymapp binding))
           ((or (null binding) (numberp binding))
            (setq problem (format "SPC %s is not bound" seq))
            (throw 'done nil))
           ((= (1+ i) n) (throw 'done nil))
           ((and (symbolp binding) (get binding 'transient--layout))
            (let ((rest (mapconcat #'identity (seq-drop parts (1+ i)) " "))
                  (menu-keys (+docs--menu-keys binding)))
              (unless (or (member rest menu-keys)
                          (seq-some (lambda (k) (string-prefix-p (concat rest " ") k)) menu-keys))
                (setq problem (format "SPC %s: %s has no key %s" seq binding rest))))
            (throw 'done nil))
           (t (throw 'done nil))))
        (setq i (1+ i))))
    problem))

;; Autoloaded: bin/check-config.el calls it in the throwaway daemon.
;;;###autoload
(defun +docs-key-problems ()
  "Every leader key the docs mention that the config does not bind, as
a list of sentences with the file and line.  Nil when all is well."
  (let (problems)
    (pcase-dolist (`(,file ,line ,keys) (+docs--documented-keys))
      (when-let* ((problem (+docs--key-problem keys)))
        (push (format "%s:%d: %s" file line problem) problems)))
    (nreverse problems)))

;;;###autoload
(defun +docs/check-keys ()
  "Check that every private menu holds up, the leader has no double and
no unmeant shadow, and every documented key is bound, the leader's and
the rest; see `+docs-menu-problems', `+docs-leader-problems',
`+docs-key-problems' and `+docs-binding-problems'."
  (interactive)
  (let ((problems (append (+docs-menu-problems) (+docs-leader-problems)
                          (+docs-key-problems) (+docs-binding-problems))))
    (if (null problems)
        (message "Every menu sets up clean and every documented key is bound")
      (message "%d problem(s):\n%s" (length problems)
               (mapconcat (lambda (p) (concat "  " p)) problems "\n")))))


;;
;;; The keys that are not the leader's

;; The leader is followed key by key above. The rest of the sheet's keys
;; are ordinary ones, and they are where the quiet mistakes live: a key
;; that means one thing in a C++ buffer and another in an Org document,
;; a key Doom renamed, a key that only ever worked in a mode nobody is
;; in. Each is looked up in the place its section says it belongs to.

(defconst +docs-key-contexts
  '(("\\`Git" . skip)                   ; magit's transient suffixes
    ("\\`AI" . skip)                    ; Claude's own keys, inside its terminal
    ("Text objects\\|Surround\\|Operators\\|Visual mode\\|registers" . skip)
    ("Snippets\\|Templates\\|scaffold\\|New files" . skip) ; abbreviations, not keys
    ("Renaming in place" . skip)        ; wdired, only once it is on
    ("Export and babel" . skip)         ; org-tempo's <s, typed not pressed
    ("The CMake panel\\|CMake panel" . skip) ; transient suffixes
    ("Function keys" . dape)
    ;; The popup's keys are bound per evil state, in an auxiliary map a
    ;; plain lookup does not follow; there is nothing to check here.
    ("Completion" . skip)
    ("minibuffer" . minibuffer)
    ("\\`Dired" . dired)
    ("\\`Org\\|\\`Notes\\|In a document" . org)
    ("" . code))
  "Where each part of the sheet's keys are looked up, by the first
section or subsection name that matches: `skip' for the keys of a
transient menu or of another program altogether, which are not Emacs
bindings, and a context otherwise.")

(defconst +docs--key-notations
  '(("\\`\\(S-\\)?F\\([0-9]+\\)\\'" . "<\\1f\\2>"))
  "How the sheet writes a key against how `kbd' wants it: F2 is <f2>.")

(defun +docs--key-context (section subsection)
  "Where the keys under SECTION and SUBSECTION are looked up."
  (let ((where (concat section ", " subsection)))
    (cdr (seq-find (lambda (rule) (string-match-p (car rule) where))
                   +docs-key-contexts))))

(defun +docs--key-sequence (key)
  "KEY as `kbd' wants it, or nil when it is not a key at all: an ex
command, a register, a snippet's abbreviation or prose."
  (unless (or (string-match-p "\\`[:\"]" key)
              (string-match-p "\\.\\.\\." key)
              (string-match-p "\\`[a-z]\\{3,\\}\\'" key)) ; doxy, qobj, tc
    (let ((key (seq-reduce (lambda (k rule)
                             (if (string-match-p (car rule) k)
                                 ;; Fixed case: the replacement's <f2> would
                                 ;; otherwise be capitalised to match F2.
                                 (replace-regexp-in-string (car rule) (cdr rule) k t)
                               k))
                           +docs--key-notations key)))
      (ignore-errors (kbd key)))))

(defun +docs--bound-in (sequence context)
  "Non-nil when SEQUENCE is bound in CONTEXT.

A transient set up earlier in the same session, as the menu check sets
up every one of them, leaves its own map over the keyboard; a lookup
would then answer for the menu rather than for the buffer, and every
key of evil's would look unbound.  Those maps are put aside here."
  (let ((overriding-terminal-local-map nil)
        (overriding-local-map nil))
    (+docs--bound-in-1 sequence context)))

(defun +docs--bound-in-1 (sequence context)
  "Non-nil when SEQUENCE is bound in CONTEXT, the maps already put aside."
  (cl-flet ((in-map (map) (when (keymapp map)
                            (let ((binding (lookup-key map sequence)))
                              (and binding (not (numberp binding))))))
            (in-buffer () (let ((binding (key-binding sequence)))
                            (and binding (not (numberp binding))))))
    (pcase context
      ;; A map this session has not got is a key that cannot be checked,
      ;; not a key that is missing: say nothing rather than cry wolf.
      ('minibuffer (if (boundp 'vertico-map) (in-map vertico-map) t))
      ;; The function keys are global but for the four that belong to a
      ;; running debug session, whose map exists only while one runs: a
      ;; key of that table is checked against the buffer, and excused
      ;; when there is no map to check the rest against.
      ('dape (or (in-buffer)
                 (if (boundp 'dape-active-mode-map) (in-map dape-active-mode-map) t)))
      ;; A directory of its own: dired hands back the buffer already
      ;; listing a directory, and killing that closed the user's.
      ('dired (let* ((dir (make-temp-file "docs-keys" t))
                     (buffer (ignore-errors (dired-noselect dir))))
                (unwind-protect
                    (and buffer (with-current-buffer buffer
                                  (when (fboundp 'evil-normal-state) (evil-normal-state))
                                  (in-buffer)))
                  (when (buffer-live-p buffer) (kill-buffer buffer))
                  (delete-directory dir))))
      ('org (with-temp-buffer (org-mode)
                              (when (fboundp 'evil-normal-state) (evil-normal-state))
                              (in-buffer)))
      (_ (with-temp-buffer (c++-ts-mode)
                           (when (fboundp 'evil-normal-state) (evil-normal-state))
                           ;; C-i and C-m reach their own event through
                           ;; `input-decode-map', which a lookup cannot see.
                           (or (in-buffer)
                               (and (equal sequence (kbd "C-i")) (in-buffer))
                               (in-map (current-global-map))))))))

(defun +docs--warm-keymaps ()
  "Load what the sheet's keys are bound by.  Doom loads a package when
it is first wanted, and a key of a package nothing has wanted yet looks
unbound; the check would then report whatever this session happens not
to have touched."
  (dolist (feature '(evil evil-collection vertico corfu dired org dape
                     avy evil-easymotion evil-snipe))
    (ignore-errors (require feature nil t)))
  (when (and (fboundp 'evil-mode) (not (bound-and-true-p evil-mode)))
    (ignore-errors (evil-mode 1))))

(defun +docs--sheet-keys ()
  "Every key row of the sheet that is not the leader's, as
(LINE SECTION SUBSECTION KEY), a cell naming two keys read as two."
  (let ((file +docs-cheatsheet-file)
        (section "") (subsection "") rows)
    (when (file-readable-p file)
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (while (not (eobp))
          (let ((line (buffer-substring-no-properties
                       (line-beginning-position) (line-end-position))))
            (cond
             ((string-prefix-p "* Reference" line) (goto-char (point-max)))
             ((string-match "\\`\\* \\(.+\\)" line)
              (setq section (match-string 1 line) subsection ""))
             ((string-match "\\`\\*\\* \\(.+\\)" line)
              (setq subsection (match-string 1 line)))
             ((string-match "\\`| ~\\([^|]+?\\)~ +|" line)
              ;; "~/~ ~C-s~" names two keys, each marked up on its own.
              (let ((cell (string-trim
                           (replace-regexp-in-string "~ +~" " " (match-string 1 line)))))
                (unless (string-prefix-p "SPC" cell)
                  (push (list (line-number-at-pos) section subsection cell) rows))))))
          (forward-line 1))))
    (nreverse rows)))

(defun +docs--cell-bound-p (cell context)
  "Non-nil when CELL, one key column of the sheet, is bound in CONTEXT.
A cell is one key sequence, =C-c C-o=, or several keys named together,
=zM zR=, and the sheet writes both the same way: it counts as bound if
the whole of it is a binding, or if each of its parts is."
  (let* ((whole (+docs--key-sequence cell))
         (parts (and (string-match-p " " cell) (split-string cell " " t)))
         (head (and parts (+docs--key-sequence (car parts)))))
    (or (and whole (+docs--bound-in whole context))
        (and parts
             (seq-every-p (lambda (part)
                            (let ((sequence (+docs--key-sequence part)))
                              (or (null sequence)
                                  (+docs--bound-in sequence context))))
                          parts))
        ;; A key and what it goes on to read: "s ab", "f x", "m a". The
        ;; letters after it are the argument, not keys of their own.
        (and head
             (+docs--bound-in head context)
             (seq-every-p (lambda (part) (string-match-p "\\`[a-z]\\{1,2\\}\\'" part))
                          (cdr parts))))))

;;;###autoload
(defun +docs-module-problems ()
  "Every private module the cheat sheet\='s list of READMEs leaves out.
The list is written by hand and a module added later has been missed
twice; nothing else notices, since a missing link breaks nothing. Only
the list counts: the sheet links some READMEs further down as well, and
those links hid four modules the list had left out."
  (let* ((dir (expand-file-name "modules/private" doom-user-dir))
         (modules (when (file-directory-p dir)
                    (seq-filter
                     (lambda (name)
                       (file-exists-p (file-name-concat dir name "README.org")))
                     (directory-files dir nil "\\`[^.]"))))
         (paragraph (with-temp-buffer
                      (insert-file-contents +docs-cheatsheet-file)
                      (goto-char (point-min))
                      (when (search-forward "Each module keeps its own notes" nil t)
                        (buffer-substring-no-properties
                         (point) (if (re-search-forward "^[ \t]*$" nil t)
                                     (point)
                                   (point-max)))))))
    (if (not paragraph)
        (list "the sheet has lost its list of the modules' READMEs")
      (delq nil
            (mapcar (lambda (name)
                      (unless (string-match-p
                               (regexp-quote
                                (format "modules/private/%s/README.org" name))
                               paragraph)
                        (format "the sheet's list of READMEs leaves out the %s module"
                                name)))
                    modules)))))

(defun +docs-binding-problems ()
  "Every key the sheet names outside the leader that is not bound where
its section says it belongs, as a list of sentences with the line.
Nil when all is well.

What cannot be told apart from a session that has not loaded something
is let through: the keys of a debug session while none runs, and the
completion popup's, which are bound per evil state in a map no plain
lookup follows."
  (+docs--warm-keymaps)
  (let (problems)
    (pcase-dolist (`(,line ,section ,subsection ,cell) (+docs--sheet-keys))
      (let ((context (+docs--key-context section subsection)))
        (when (and (not (eq context 'skip))
                   (+docs--key-sequence cell)
                   (not (+docs--cell-bound-p cell context)))
          (push (format "docs/cheatsheet.org:%d: %s is not bound in %s (%s)"
                        line cell context
                        (string-trim (concat section ", " subsection) nil ", "))
                problems))))
    (nreverse problems)))
