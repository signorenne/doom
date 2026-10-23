;;; private/docs/config.el -*- lexical-binding: t; -*-
;;
;; docs/cheatsheet.org: written notes plus key and command tables generated
;; from the running config. Each module also has its own README.org.

(defvar +docs-cheatsheet-file
  (file-name-concat doom-user-dir "docs/cheatsheet.org")
  "The file `+docs/cheatsheet' opens.")

(defvar +docs-docs
  '(:groups (("docs" "Docs" () +docs-cheatsheet-mode)))
  "How the cheat sheet documents this module; see `+docs--module-docs'.")

(defvar +docs-leader-features '(winum eglot)
  "Features loaded before the leader keys are read for the sheet: what
Doom binds under the leader only once the package has loaded, and it
loads on a hook.  winum takes SPC w 0 to 9 on the first window switch;
a session that never switched would write evil's defaults instead.  The
cpp module binds SPC c h and SPC c T once eglot has loaded.")

;; Each private module says how the sheet documents it, in its own
;; `+NAME-docs'. This holds only the modes no private module owns.
(defvar +docs-cheatsheet-sections nil
  "Cheat sheet heading per mode, for the modes no private module owns.
A mode is a major mode, or a minor mode that is on in the buffer.")

(define-minor-mode +docs-cheatsheet-mode
  "Keys for the cheat sheet buffer: s search, q close, gr regenerate."
  :lighter " Cheat"
  ;; The mode's keys are evil normal-state bindings, with no map of its
  ;; own. evil gathers them only on a state change, and the sheet buffer
  ;; is already in normal state, so evil is told as the mode turns on.
  (when (fboundp 'evil-normalize-keymaps)
    (evil-normalize-keymaps)))

;; Opens on the right and closes with q.
(set-popup-rule! "^cheatsheet\\.org$"
  :side 'right :size 0.5 :select t :quit t :ttl nil :modeline t)

;; The README and the check sit under SPC h d, Doom's help about itself.
;; SPC h is also Emacs's help map, so on SPC h M and SPC h C they would
;; take C-h M and C-h C as well.
(map! :leader
      (:prefix "h"
       :desc "Cheat sheet"           "/" #'+docs/cheatsheet
       :desc "Private module README" "d M" #'+docs/module-readme
       :desc "Check the config's commands" "d C" #'+docs/check-autoloads))

;; Its own form: inside the :leader block above this would bind SPC <f12>.
(map! :g "<f12>" #'+docs/cheatsheet)

;; evil's own API for a minor mode's keys: they rank above the auxiliary
;; maps of other minor modes, evil-snipe's s among them, which a map! on
;; the mode map would lose to.
(after! evil
  (evil-define-minor-mode-key 'normal '+docs-cheatsheet-mode
    (kbd "s")  #'+docs/cheatsheet-search
    (kbd "?")  #'+docs/cheatsheet-search
    (kbd "S")  #'+docs/cheatsheet-find
    (kbd "gr") #'+docs/cheatsheet-regenerate
    (kbd "q")  #'+popup/close))
