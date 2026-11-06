;;; private/docs/autoload/keys.el -*- lexical-binding: t; -*-
;;
;; Do the menus and the documented keys hold up? A transient refuses a
;; key bound twice or a suffix it cannot find only when asked, and it
;; moves a suffix off q and Q on its own, since core binds q to quit.
;; So every private menu is set up under conflict detection, its layout
;; read for what transient would silently move, and each suffix's key
;; looked up in the map the menu is built with, where q as the last of
;; two keys quits too. Every SPC key the docs mention is looked up, so
;; a changed key cannot stay in the docs, a README row that names its
;; command must run it where the row says, and the leader is read for
;; one of our commands on two keys and for a Doom key rebound by
;; mistake. `+docs/check-keys' runs it all from a session.

(require 'transient)

(defvar transient-detect-key-conflicts)
(defvar transient--layout)
(defvar transient--transient-map)
(defvar transient--suffixes)
(defvar transient-sticky-map)
(defvar recentf-list)
(defvar save-place-alist)
(defvar image-mode-map)
(declare-function recentf-expand-file-name "recentf")
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

(defun +docs--menu-key-runs (map key)
  "The command KEY, a key description, runs in a menu whose keymap is
MAP, nil when none.  Once the first of several keys is pressed,
transient lays `transient-sticky-map' over MAP for the rest, and that
map ends the sequence on q and C-g: a suffix on \"a q\" never runs."
  (let* ((events (kbd key))
         (sticky (and (> (length events) 1)
                      (lookup-key transient-sticky-map
                                  (vector (aref events (1- (length events)))))))
         (def (if (and sticky (not (numberp sticky)))
                  sticky
                (lookup-key map events))))
    (and def (not (numberp def)) def)))

(defun +docs--menu-unreachable (prefix suffixes map present)
  "The suffixes of PREFIX that their own key does not reach, as
sentences.  SUFFIXES is the layout's (KEY . COMMAND) list, MAP the
keymap transient set the menu up with and PRESENT the suffixes it put
in it, the same way.  A suffix this context leaves out, by a group's
:if, is judged only by what no context changes, `transient-sticky-map'.
A key two suffixes share, each for a context of its own, may run either."
  (let (problems)
    (pcase-dolist (`(,key . ,command) suffixes)
      (unless (member key +docs--owned-keys)
        (let* ((here (seq-some (lambda (suffix)
                                 (and (eq (cdr suffix) command)
                                      (equal (kbd (car suffix)) (kbd key))))
                               present))
               (runs (+docs--menu-key-runs (if here map (make-sparse-keymap)) key)))
          (unless (or (and (not here) (null runs))
                      (seq-some (lambda (suffix)
                                  (and (eq (cdr suffix) runs)
                                       (equal (kbd (car suffix)) (kbd key))))
                                suffixes))
            (push (format "%s: %s runs %s, not %s" prefix key (+docs--command-name runs) command)
                  problems)))))
    (nreverse problems)))

(defun +docs--command-name (def)
  "DEF, what a key runs, in a word for a report: a command's name,
\"nothing\", or what kind of thing it is."
  (cond ((null def) "nothing")
        ((symbolp def) (symbol-name def))
        ((keymapp def) "a prefix")
        (t "an anonymous command")))

;; Autoloaded: bin/check-config.el calls it.
;;;###autoload
(defun +docs-menu-problems ()
  "Every private menu that does not hold up, as a list of sentences:
one that fails to set up under conflict detection (a key bound twice,
a suffix neither defined nor autoloaded), a suffix on a key transient
owns, a suffix whose key runs another command in the menu as transient
builds it (\"a q\" quits), a command on two keys.  Nil when all is
well.  Needs a frame to show the menu in, so not doom doctor."
  (let (problems)
    (dolist (prefix (+docs--prefixes))
      (when (autoloadp (symbol-function prefix))
        (autoload-do-load (symbol-function prefix) prefix))
      (let ((transient-detect-key-conflicts t) map present)
        (condition-case err
            (progn (transient-setup prefix)
                   ;; Read before the quit, which clears them.
                   (setq map transient--transient-map
                         present (mapcar (lambda (obj)
                                           (cons (oref obj key) (oref obj command)))
                                         transient--suffixes))
                   (transient-quit-all))
          (error (ignore-errors (transient-quit-all))
                 (setq map nil)
                 (push (format "%s does not set up: %s" prefix (error-message-string err))
                       problems)))
        (when map
          (dolist (problem (+docs--menu-unreachable
                            prefix (+docs--layout-suffixes (get prefix 'transient--layout))
                            map present))
            (push problem problems))))
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

;; Autoloaded: bin/check-config.el calls it.
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

;; Autoloaded: bin/check-config.el calls it.
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
no unmeant shadow, every documented key is bound, the leader's and the
rest, and runs the command its README row names; see
`+docs-menu-problems', `+docs-leader-problems', `+docs-key-problems',
`+docs-binding-problems' and `+docs-row-problems'."
  (interactive)
  (let ((problems (append (+docs-menu-problems) (+docs-leader-problems)
                          (+docs-key-problems) (+docs-binding-problems)
                          (+docs-row-problems)))
        (unplaced (length (+docs-row-unplaced))))
    (if (null problems)
        (message "Every menu sets up clean and every documented key is bound%s"
                 (if (zerop unplaced)
                     ""
                   (format "; %d README row(s) name no mode, (+docs-row-unplaced) lists them"
                           unplaced)))
      (message "%d problem(s):\n%s" (length problems)
               (mapconcat (lambda (p) (concat "  " p)) problems "\n")))))


;;
;;; The keys that are not the leader's

;; The rest of the sheet's keys are ordinary ones, where the quiet
;; mistakes live: a key that means one thing in a C++ buffer and another
;; in an Org document, a key Doom renamed, a key that only works in a
;; mode nobody is in. Each is looked up where its section says it
;; belongs.

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
    ;; plain lookup does not follow, so they cannot be checked.
    ("Completion" . skip)
    ("minibuffer" . minibuffer)
    ("\\`Dired" . dired)
    ("\\`Org\\|\\`Notes\\|In a document" . org)
    ("\\`Side bar, Source Control" . sidebar-scm)
    ("\\`Side bar" . sidebar-explorer)  ; the Explorer, and what every view has
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
              ;; Case counts: RET and TAB are keys.
              (let ((case-fold-search nil))
                (string-match-p "\\`[a-z]\\{3,\\}\\'" key))) ; doxy, qobj, tc
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

(defun +docs--in-dired (fn)
  "Call FN in a listing in normal state and return what it returns, nil
when dired cannot list.  A directory of its own: dired hands back the
buffer already listing a directory, and killing it would close the
user's.  Doom counts a directory listed among the recent files and
save-place keeps the cursor's place in it, and a check run from the
session would leave both behind for the next one: they are taken out."
  (let* ((dir (make-temp-file "docs-keys" t))
         (name (file-name-as-directory dir))
         (buffer (ignore-errors (dired-noselect dir))))
    (unwind-protect
        (and buffer (with-current-buffer buffer
                      (when (fboundp 'evil-normal-state) (evil-normal-state))
                      (funcall fn)))
      (when (buffer-live-p buffer) (kill-buffer buffer))
      (when (boundp 'recentf-list)
        (setq recentf-list (delete (if (fboundp 'recentf-expand-file-name)
                                       (recentf-expand-file-name name)
                                     name)
                                   recentf-list)))
      (when (boundp 'save-place-alist)
        (setq save-place-alist (assoc-delete-all name save-place-alist)))
      (delete-directory dir))))

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
      ('dired (+docs--in-dired #'in-buffer))
      ('org (with-temp-buffer (org-mode)
                              (when (fboundp 'evil-normal-state) (evil-normal-state))
                              (in-buffer)))
      ;; A view's mode in a buffer of its own, not the side bar's, which
      ;; the check must not open or redraw.
      ((or 'sidebar-explorer 'sidebar-scm)
       (let ((mode (if (eq context 'sidebar-scm) '+sidebar-scm-mode '+sidebar-explorer-mode)))
         (if (not (fboundp mode))
             t
           (with-temp-buffer (funcall mode)
                             (when (fboundp 'evil-normal-state) (evil-normal-state))
                             (in-buffer)))))
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


;;
;;; The keys a README names the command of

;; A README's key table has a Command column: the row says what the key
;; runs, not only that it is bound, and a key that runs something else
;; in its mode is the quiet mistake, evil-snipe's s over a viewer's own
;; s, evil-collection's RET over the image viewer's. Each such row is
;; looked up in a buffer of the mode the docs give it, in normal state
;; unless they name another. A row says its mode after its key, "f
;; (image)"; else its description starts "in the file manager:"; else
;; the line above its table reads "In the player:". A leader key that
;; says none is the leader's anywhere; any other key that says none is
;; not judged, and is listed as such, since guessing its mode would
;; judge it against a mode the docs never meant.

(defconst +docs-row-modes
  '(("\\`\\(?:dired\\|the file manager\\)\\'" . dired)
    ("\\`magit\\'" . (magit-status-mode))
    ("\\`the commit buffer\\'" . (text-mode git-commit-mode))
    ("\\`image\\'" . (+docs--image-mode))
    ("\\`SVG\\'" . (nxml-mode))
    ("\\`view\\'" . (special-mode +core-view-panel-mode +core-view-image-mode))
    ("\\`\\(?:the \\)?sheet\\'" . (org-mode read-only-mode +docs-cheatsheet-mode))
    ("\\`anywhere\\'" . (fundamental-mode))
    ("\\`corfu\\'" . (:map corfu-map)))
  "The modes a README row can name, by the words it uses, and how a
buffer of each is made: `dired' a listing of an empty directory, a list
of modes turned on in order in a buffer of its own, or (:map MAP) for a
popup no buffer shows, its keys looked up in MAP.")

(defun +docs--image-mode ()
  "Make this buffer an image viewer's as far as its keys go.  The check
runs in a daemon without a frame, where `image-mode' refuses to start,
so its map and hooks are set up the way it sets them up, without a
picture to show."
  (require 'image-mode)
  (kill-all-local-variables)
  (setq major-mode 'image-mode mode-name "Image")
  (use-local-map image-mode-map)
  (run-mode-hooks 'image-mode-hook))

(defun +docs--marked (text)
  "The ~marked~ or =marked= parts of TEXT, in order."
  (let ((start 0) out)
    (while (string-match "[~=]\\([^~=]+\\)[~=]" text start)
      (push (match-string 1 text) out)
      (setq start (match-end 0)))
    (nreverse out)))

(defun +docs--row-state (text)
  "The evil state TEXT names, \"insert state\", or nil."
  (and text
       (string-match "\\b\\(normal\\|insert\\|visual\\|motion\\|emacs\\) state\\b" text)
       (intern (match-string 1 text))))

(defun +docs--row-pairs (keys commands)
  "(KEY . COMMAND) for a row whose key cell names KEYS, a list of
alternatives each a list of keys, and whose command cell names
COMMANDS.  As many commands as keys go in order, zM and zR to
close-all and open-all; one command goes to each alternative's first
key, both s and ? in \"s or ?\", but only n in \"n p\", the p beside it
being the other way the description names.  Nil when they cannot be
paired."
  (let ((flat (apply #'append keys)))
    (cond ((and (cdr commands) (= (length commands) (length flat)))
           (cl-mapcar #'cons flat commands))
          ((null (cdr commands))
           (mapcar (lambda (alternative) (cons (car alternative) (car commands)))
                   keys)))))

(defun +docs--command-rows ()
  "Every row of a key table with a Command column in the sheet, above
its generated part, and the private READMEs, as plists: :file, :line,
:key, :command, :mode the words naming its mode or nil, :state."
  (let ((files (cons +docs-cheatsheet-file
                     (directory-files-recursively
                      (file-name-concat doom-user-dir "modules/private") "README\\.org\\'")))
        rows)
    (dolist (file files)
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (let (column intro (prev ""))
          (while (not (eobp))
            (let ((line (buffer-substring-no-properties (line-beginning-position)
                                                        (line-end-position))))
              (cond
               ((string-prefix-p "* Reference" line) (goto-char (point-max)))
               ((string-prefix-p "|" line)
                (let ((cells (mapcar #'string-trim
                                     (split-string (string-trim line "|" "|[ \t]*") "|"))))
                  (cond
                   ;; A table's first line, its header: is there a
                   ;; Command column beside the Key one?
                   ((not (string-prefix-p "|" prev))
                    (setq column (and (equal (car cells) "Key")
                                      (seq-position cells "Command"))))
                   ((string-prefix-p "|-" line))
                   ((and column (nth column cells))
                    (dolist (row (+docs--command-row cells column intro))
                      (push (append (list :file (file-relative-name file doom-user-dir)
                                          :line (line-number-at-pos))
                                    row)
                            rows))))))
               ((not (string-blank-p line)) (setq intro line column nil)))
              (setq prev line))
            (forward-line 1)))))
    (nreverse rows)))

(defun +docs--command-row (cells column intro)
  "The keys one table row names with their commands, as plists: CELLS
the row's cells, COLUMN where its command is, INTRO the line above the
table.  None for a range, \"1 .. 5\", or a command cell that is not all
commands, \"quick access\" or a pattern such as casual-*-tmenu."
  (let* ((cell (car cells))
         (command-cell (nth column cells))
         (description (nth (1+ column) cells))
         (mark (and (string-match "(\\([^()]+\\))[ \t]*\\'" cell)
                    (match-string 1 cell)))
         ;; "(dired, insert state)": the mode is dired.
         (mark-mode (and mark (replace-regexp-in-string
                               ",? *\\b[a-z]+ state\\b" "" mark)))
         (said (and description
                    (string-match "\\`in \\([^:,;]+\\)[:,]" description)
                    (match-string 1 description)))
         (heard (and intro (string-match "\\`In \\([^:,]+\\).*:\\'" intro)
                     (match-string 1 intro)))
         (keys (and (not (string-match-p "\\.\\." cell))
                    (delq nil (mapcar #'+docs--marked (split-string cell " or " t)))))
         (commands (+docs--marked command-cell)))
    (when (and keys commands
               (not (string-search "*" command-cell))
               (string-blank-p (replace-regexp-in-string "[~=][^~=]+[~=]" "" command-cell)))
      (mapcar (pcase-lambda (`(,key . ,command))
                (list :key key :command (intern command)
                      :mode (or (and mark-mode (not (string-blank-p mark-mode)) mark-mode)
                                said heard)
                      :state (or (+docs--row-state mark) (+docs--row-state description)
                                 (+docs--row-state intro) 'normal)))
              (+docs--row-pairs keys commands)))))

(defun +docs--row-context (row)
  "Where ROW's key is looked up, a context of `+docs-row-modes', or a
sentence saying why that cannot be told."
  (let ((mode (plist-get row :mode)) (key (plist-get row :key)))
    (cond
     (mode (or (cdr (seq-find (lambda (rule) (string-match-p (car rule) mode))
                              +docs-row-modes))
               (format "names a mode the check does not know, %S" mode)))
     ((string-match-p "\\`SPC m\\( \\|\\'\\)" key) "the localleader, in no mode the row names")
     ((string-match-p "\\`SPC k\\( \\|\\'\\)" key) "SPC k, for no kind of project the row names")
     ((string-prefix-p "SPC " key) (cdr (assoc "\\`anywhere\\'" +docs-row-modes)))
     (t "names no mode"))))

(defun +docs--key-runs-here (sequence)
  "The command a press of SEQUENCE runs in this buffer, nil when none.
A window system sends RET as <return> and TAB as <tab>, which Emacs
reads as RET and TAB only when nothing binds them as they come, so a
map that binds <return> wins over one that binds RET.  The maps a menu
set up earlier leaves over the keyboard are put aside."
  (let* ((overriding-terminal-local-map nil)
         (overriding-local-map nil)
         (sent (vconcat (mapcar (lambda (event)
                                  (pcase event
                                    (?\r 'return) (?\t 'tab) (?\e 'escape)
                                    (?\d 'backspace) ('S-tab 'backtab) (_ event)))
                                sequence)))
         (def (and (not (equal sent sequence)) (key-binding sent))))
    (when (or (null def) (numberp def))
      (setq def (key-binding sequence)))
    (and def (not (numberp def)) def)))

(defun +docs--rows-in (context state rows)
  "What each of ROWS runs in a buffer of CONTEXT in evil STATE, as a list
of (ROW . COMMAND), or a message when no such buffer can be made."
  (cl-flet ((runs ()
              (when (fboundp 'evil-change-state) (evil-change-state state))
              (mapcar (lambda (row)
                        (cons row (+docs--key-runs-here
                                   (+docs--key-sequence (plist-get row :key)))))
                      rows)))
    (condition-case err
        (pcase context
          ('dired (+docs--in-dired #'runs))
          (`(:map ,map)
           (unless (boundp map) (error "%s is not loaded" map))
           (mapcar (lambda (row)
                     (cons row (let ((def (lookup-key (symbol-value map)
                                                      (+docs--key-sequence
                                                       (plist-get row :key)))))
                                 (and (not (numberp def)) def))))
                   rows))
          (_ (with-temp-buffer
               (dolist (mode context) (funcall mode))
               (runs))))
      (error (error-message-string err)))))

(defun +docs--placed-rows ()
  "The README rows that name their command, split by where they are
looked up: (PLACED . UNPLACED), PLACED an alist from (CONTEXT . STATE)
to its rows, UNPLACED a list of (ROW . WHY)."
  (let (placed unplaced)
    (dolist (row (+docs--command-rows))
      (let ((context (+docs--row-context row)))
        (cond ((stringp context) (push (cons row context) unplaced))
              ((null (+docs--key-sequence (plist-get row :key))))
              (t (push row (alist-get (cons context (plist-get row :state)) placed
                                      nil nil #'equal))))))
    (cons (nreverse placed) (nreverse unplaced))))

;; Autoloaded: bin/check-config.el calls it.
;;;###autoload
(defun +docs-row-problems ()
  "Every README row that names a command its key does not run, looked
up in a buffer of the row's mode, as a list of sentences with the file
and line.  Nil when all is well.  A row whose mode the docs do not say
is not judged; `+docs-row-unplaced' lists those."
  (+docs--warm-keymaps)
  (let (problems)
    (pcase-dolist (`((,context . ,state) . ,rows) (car (+docs--placed-rows)))
      (let ((runs (+docs--rows-in context state (reverse rows))))
        (if (stringp runs)
            (dolist (row rows)
              (push (cons row (format "no buffer of %S: %s" context runs)) problems))
          (pcase-dolist (`(,row . ,command) runs)
            (unless (eq command (plist-get row :command))
              (push (cons row (format "runs %s, not %s, in %s, %s state"
                                      (+docs--command-name command) (plist-get row :command)
                                      (or (plist-get row :mode) "any buffer")
                                      (plist-get row :state)))
                    problems))))))
    ;; In the order of the docs, which the grouping by mode has mixed.
    (mapcar (pcase-lambda (`(,row . ,what))
              (format "%s:%d: %s %s" (plist-get row :file) (plist-get row :line)
                      (plist-get row :key) what))
            (sort problems
                  (lambda (a b)
                    (let ((a (car a)) (b (car b)))
                      (if (equal (plist-get a :file) (plist-get b :file))
                          (< (plist-get a :line) (plist-get b :line))
                        (string< (plist-get a :file) (plist-get b :file)))))))))

;; Autoloaded: bin/check-config.el calls it.
;;;###autoload
(defun +docs-row-unplaced ()
  "Every README row that names a command but not the mode its key runs
it in, as a list of sentences with the file and line: what
`+docs-row-problems' cannot judge until the row says, (dired) after
the key or \"in magit:\" before the description."
  (mapcar (pcase-lambda (`(,row . ,why))
            (format "%s:%d: %s: %s" (plist-get row :file) (plist-get row :line)
                    (plist-get row :key) why))
          (cdr (+docs--placed-rows))))
