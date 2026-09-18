;;; private/ui/config.el -*- lexical-binding: t; -*-
;;
;; Glyph fallbacks, dashboard entry points and small visual aids. The fonts
;; themselves are set in $DOOMDIR/config.el.

;;
;;; Glyphs

(defvar +ui-symbol-fallback-font "Noto Sans Symbols 2"
  "Font tried for symbols the Nerd Font doesn't cover.")

(defvar +ui-docs '(:groups (("ui" "Interface" ())))
  "How the cheat sheet documents this module; see `+docs--module-docs'.")

;; Doom maps the Nerd Font ranges and the symbol, math and emoji scripts from
;; `doom-symbol-font' and `doom-emoji-font'. This adds one more fallback for
;; arrows, technical and dingbat blocks. Re-runs on SPC h r f.
(add-hook! 'after-setting-font-hook
  (defun +ui--extra-fontsets-h ()
    "Append `+ui-symbol-fallback-font' to the symbol blocks."
    (when (and (display-graphic-p)
               (find-font (font-spec :family +ui-symbol-fallback-font)))
      (dolist (range '((#x2190 . #x21FF)    ; arrows
                       (#x2300 . #x23FF)    ; misc technical
                       (#x25A0 . #x25FF)    ; geometric shapes
                       (#x2600 . #x26FF)    ; misc symbols
                       (#x2700 . #x27BF)    ; dingbats
                       (#x2900 . #x297F)    ; supplemental arrows B
                       (#x2B00 . #x2BFF)))  ; misc symbols and arrows
        (set-fontset-font t range +ui-symbol-fallback-font nil 'append)))))


;;
;;; Zen

;; Zen keeps the one font. Doom turns mixed-pitch on there for org,
;; markdown and the rest, which sets the body in a proportional face:
;; easier on the eye in a letter, harder in a file where the tables,
;; the source blocks and the indentation are all laid out by column.
(setq +zen-mixed-pitch-modes nil)


;;
;;; Dashboard

;; Doom traps point in the menu after every command, so a dashboard taller
;; than its window can never show its top: the view snaps back to a button.
;; Scrolling commands are let through; the next j or k lands on a button.
;; Guarded: defadvice! on a renamed Doom function installs silently.
(if (fboundp '+doom-dashboard-reposition-point-h)
    (defadvice! +ui--dashboard-let-scroll-a (fn &rest args)
      :around #'+doom-dashboard-reposition-point-h
      (unless (and (symbolp this-command)
                   (string-match-p "scroll" (symbol-name this-command)))
        (apply fn args)))
  (warn "+doom-dashboard-reposition-point-h is gone; the dashboard cannot scroll"))

;; Doom pads the dashboard down the window to centre it, and measures the
;; window with `get-buffer-window', which answers for the selected frame.
;; A child frame, the butler's bubble or a completion popup, is the
;; selected frame while the window hooks run for it, and the dashboard is
;; then padded for a seven row window: the centring is lost and, nothing
;; else resizing the real window, it never comes back. A child frame
;; changing size says nothing about the dashboard, so it is left alone.
;; Guarded: defadvice! on a renamed Doom function installs silently.
(if (fboundp '+doom-dashboard-resize-h)
    (defadvice! +ui--dashboard-keep-centred-a (fn &rest args)
      :around #'+doom-dashboard-resize-h
      (unless (frame-parent (selected-frame))
        (apply fn args)))
  (warn "+doom-dashboard-resize-h is gone; the dashboard may lose its centring"))

;; The animation stops when the dashboard leaves the screen and starts
;; again when it comes back; a tick is a redisplay, and ten a second for
;; a buffer nobody sees cost a fifth of a core.
(add-hook 'window-buffer-change-functions #'+ui--dashboard-shown-h)

;; Nothing on the dashboard gets selected or lit up: no cursor, since there
;; is nothing to type into; no highlight when the mouse passes over a menu
;; entry; no region from a drag. Clicks and RET still open the entries.
;; evil sets the cursor from its state's spec on every change, so that spec
;; is the one to blank; a bar of zero width is the shape it accepts.
(add-hook! '+doom-dashboard-mode-hook
  (defun +ui--dashboard-quiet-h ()
    ;; mouse-highlight as a buffer local holds in the selected window
    ;; only, which the dashboard is whenever it is shown.
    (setq-local evil-normal-state-cursor '(bar . 0)
                mouse-highlight nil)
    (when (fboundp 'evil-refresh-cursor) (evil-refresh-cursor))))

;; evil binds the drag itself in its normal state, above the mode map, so
;; the quiet has to be told to that state. The map exists by now: Doom
;; loads its own modules before this one, and doom-dashboard is not a
;; feature one could wait for.
(map! :map +doom-dashboard-mode-map
      :nm [down-mouse-1] #'ignore
      :nm [drag-mouse-1] #'ignore
      :nm [down-mouse-3] #'ignore
      :nm [drag-mouse-3] #'ignore)

;; What another module may add to the dashboard, without the dashboard
;; knowing it: a greeting above the date, and a step at every tick of
;; the animation. The butler uses both.
(defvar +ui-dashboard-greeting-function nil
  "Function that inserts a greeting above the date, given the width of
the dashboard to centre in, its words in the face `+ui-greeting'; nil
shows the date alone.")

(defvar +ui-dashboard-tick-hook nil
  "Run in the dashboard buffer at every tick of the animation, with the
ticks elapsed as the one argument, one per step.  Whatever a module
draws on the dashboard moves on from here, inside
`with-silent-modifications'.")

(defvar +ui-banner-name (user-login-name)
  "The name the dashboard banner spells out.  Its letters are drawn from
`+ui-banner-font' when the dashboard is built, so another name is a
`setq' and nothing has to be redrawn by hand.")

;; The name as an ASCII banner, the greeting, then a short menu of entry
;; points, each showing its current key. Doom skips entries whose
;; command isn't defined. Our banner stands in for Doom's widget, the
;; way its README says to, so a terminal frame and the GUI draw the
;; same thing; a picture would want `doom-dashboard-widget-banner' back
;; and `fancy-splash-image' pointed at it.
(when (modulep! :ui doom-dashboard)
  (setq +doom-dashboard-functions '(+ui-dashboard-banner
                                    +ui-dashboard-greeting ; a module's, else the date
                                    doom-dashboard-widget-shortmenu)
        +doom-dashboard-menu-sections
        '(("Recently opened files"
           :icon (nerd-icons-faicon "nf-fa-file_text" :face 'doom-dashboard-menu-title)
           :action recentf-open-files)
          ("Open project"
           :icon (nerd-icons-octicon "nf-oct-briefcase" :face 'doom-dashboard-menu-title)
           :action projectile-switch-project)
          ("Agenda dashboard"
           :icon (nerd-icons-octicon "nf-oct-calendar" :face 'doom-dashboard-menu-title)
           :action +notes/dashboard)
          ("Org documents"
           :icon (nerd-icons-octicon "nf-oct-book" :face 'doom-dashboard-menu-title)
           :action +notes/open-document)
          ("AI hub"
           :icon (nerd-icons-mdicon "nf-md-robot" :face 'doom-dashboard-menu-title)
           :action +ai/menu)
          ("Build kit"
           :icon (nerd-icons-octicon "nf-oct-tools" :face 'doom-dashboard-menu-title)
           :action +cpp/menu)
          ("Cheat sheet"
           :icon (nerd-icons-octicon "nf-oct-question" :face 'doom-dashboard-menu-title)
           :action +docs/cheatsheet)
          ("Open private config"
           :icon (nerd-icons-octicon "nf-oct-gear" :face 'doom-dashboard-menu-title)
           :action doom/open-private-config))))


;;
;;; Visual aids

;; Where you are, in the header line: the project path and the symbol
;; path (file > class > function) from breadcrumb, replaced by the
;; first line of the enclosing function while that line is scrolled off
;; the top, the way VS Code and Zed pin it.  In code buffers.
(defvar-local +ui--defun-cache nil
  "(START END TICK . LINE) of the function last found under the window's
top: reused while the top stays inside it and the buffer unchanged,
since the header line is asked on every redisplay, dozens a second
while the wheel turns.")

(defun +ui--scrolled-defun ()
  "The first line of the function that holds the window's first line,
when that first line is scrolled off; nil at the top of a function or
between two.  The answer holds for a range of window tops, the
function's own or the gap up to the next one, and is kept for it."
  (let ((top (window-start)))
    (when (> top (point-min))
      (pcase-let ((`(,from ,to ,tick . ,line) +ui--defun-cache))
        (if (and from (<= from top) (< top to) (eq tick (buffer-chars-modified-tick)))
            line
          (save-excursion
            (goto-char top)
            (let* ((found (and (ignore-errors (beginning-of-defun) t) (point)))
                   (end (and found (progn (ignore-errors (end-of-defun)) (point))))
                   (inside (and found (< found top) (> end top)))
                   (text (and inside
                              (progn (goto-char found)
                                     (font-lock-ensure found (pos-eol))
                                     (string-trim-right (buffer-substring found (pos-eol))))))
                   ;; Inside: good until the function ends.  Between two,
                   ;; or at one's first line: good until the next begins.
                   (from (if inside found (max (or end (point-min)) (point-min))))
                   (to (if inside end
                         (save-excursion
                           (goto-char top)
                           (if (and (ignore-errors (end-of-defun) t) (> (point) top))
                               (progn (ignore-errors (beginning-of-defun)) (max (point) (1+ top)))
                             (point-max))))))
              (setq +ui--defun-cache (cons from (cons (max to (1+ from)) (cons (buffer-chars-modified-tick) text))))
              text)))))))

(defvar-local +ui--crumbs-cache nil
  "(LINE-START TICK . CRUMBS): the breadcrumbs of the line point is on,
reused until point leaves the line or the buffer changes.")

(defun +ui--crumbs ()
  "The breadcrumbs of point: the project path, then the symbol path."
  (let ((here (line-beginning-position)))
    (pcase-let ((`(,line ,tick . ,crumbs) +ui--crumbs-cache))
      (if (and line (eq line here) (eq tick (buffer-chars-modified-tick)))
          crumbs
        (let ((text (string-join (seq-remove #'string-empty-p
                                             (list (or (ignore-errors (breadcrumb-project-crumbs)) "")
                                                   (or (ignore-errors (breadcrumb-imenu-crumbs)) "")))
                                 (propertize "  >  " 'face 'shadow))))
          (setq +ui--crumbs-cache (cons here (cons (buffer-chars-modified-tick) text)))
          text)))))

(defun +ui--where-line ()
  "The header line: the enclosing function's first line while it is
scrolled off, else the breadcrumbs."
  (concat " " (or (+ui--scrolled-defun) (+ui--crumbs))))

(define-minor-mode +ui-where-mode
  "A header line saying where you are: the project and symbol paths,
or the enclosing function's first line while it is scrolled off the top."
  :lighter nil
  (if +ui-where-mode
      (setq-local header-line-format '(:eval (+ui--where-line)))
    (kill-local-variable 'header-line-format)))

(use-package! breadcrumb
  :commands (breadcrumb-project-crumbs breadcrumb-imenu-crumbs)
  :init (add-hook 'prog-mode-hook #'+ui-where-mode))

;; The symbol outline at the side, VS Code's Outline: SPC t o opens
;; and closes it; it follows point.
(use-package! imenu-list
  :defer t
  :config
  (setq imenu-list-position 'right
        imenu-list-size 32
        imenu-list-focus-after-activation nil
        imenu-list-auto-resize nil))

;; Diagnostics at the end of the line as well as in the popup, the
;; most severe one; flymake is the checker (init.el, +flymake), eglot
;; reports into it directly.
(after! flymake
  (setq flymake-show-diagnostics-at-end-of-line 'short))

;; ]e and [e are `next-error', which walks whatever buffer last reported
;; errors: with flymake doing the checking that is some compilation log
;; from an hour ago, and the key leaves the file to ask where vertico's
;; sources are. Flymake says in its own manual that it does not take
;; `next-error' over and that one should say so oneself, so here it is:
;; in a buffer flymake is checking, ]e is that buffer's diagnostics.
(defun +ui--flymake-next-error (n reset)
  "A `next-error-function' that walks this buffer's flymake diagnostics."
  (when reset (goto-char (point-min)))
  (flymake-goto-next-error n nil t))

(add-hook 'flymake-mode-hook
          (defun +ui--flymake-next-error-h ()
            (if flymake-mode
                (setq-local next-error-function #'+ui--flymake-next-error)
              (kill-local-variable 'next-error-function))))

;; While the wheel turns, ultra-scroll switches off what costs a
;; redisplay per step, hl-line and jit-lock among them, and back on when
;; it stops.  The minimap joins: its marks follow the window on every
;; step, each move a redraw of its whole window, so they hold still
;; while the wheel turns and catch up once after.  The indent guides
;; would be the next to hide, four milliseconds a step on a big frame,
;; but switching them off refontifies the buffer, which costs more; so
;; they are off unless asked for, SPC t i.
(defvar +ui--scrolling nil
  "Non-nil while the wheel turns.")

(defun +ui--scroll-hide (arg)
  "Called by ultra-scroll with ARG -1 as a scroll starts and 1 as it
ends: hold the minimap still meanwhile, then let it catch up."
  (if (< arg 0)
      (setq +ui--scrolling t)
    (setq +ui--scrolling nil)
    (when (fboundp 'demap-buffer-minimap)
      (dolist (buffer (buffer-list))
        (when-let* ((minimap (and (buffer-local-value 'demap-visible-region-mode buffer)
                                  (with-current-buffer buffer (demap-buffer-minimap)))))
          (ignore-errors (demap--visible-region-mode-update-if minimap))
          (ignore-errors (demap-current-line-mode-update minimap)))))))

(after! ultra-scroll
  (add-hook 'ultra-scroll-hide-functions #'+ui--scroll-hide))

(defun +ui--no-guides-by-default-h ()
  "Keep Doom's indent guides off until asked for."
  t)
(add-hook '+indent-guides-inhibit-functions #'+ui--no-guides-by-default-h)

(after! demap
  ;; Its marks follow the window on every scroll step; not while the
  ;; wheel turns, once when it stops.
  (advice-add 'demap--visible-region-mode-update-if :before-while
              (lambda (&rest _) (not +ui--scrolling)))
  (advice-add 'demap-current-line-mode-update :before-while
              (lambda (&rest _) (not +ui--scrolling))))

;;
;;; Where you are in the buffer

;; The modeline says a percentage and the file's size, two numbers to
;; read. A thumb in the right fringe says the same at a glance: as long
;; a part of the window's edge as the window is of the buffer, sitting
;; where you are in it. Emacs draws it, in the theme's own colours, so
;; none of the desktop's widgets come in; it takes no column from the
;; text, and a buffer that fits its window has no thumb at all, there
;; being nowhere in it to be. It counts the buffer's lines as it draws,
;; a fifth of a millisecond over fifty thousand of them.
(declare-function yascroll:compute-thumb-size "yascroll")
(declare-function yascroll:safe-show-scroll-bar "yascroll")

(defvar +ui--thumb-timer nil
  "The one-shot that draws the thumb once an edit has settled.")

(defun +ui--thumb-now (buffer)
  "Draw BUFFER's thumb, wherever the timer happens to leave us."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (when (bound-and-true-p yascroll-bar-mode)
        (yascroll:safe-show-scroll-bar)))))

(use-package! yascroll
  :hook (doom-first-buffer . global-yascroll-bar-mode)
  :config
  ;; It is there to be glanced at, so it does not fade.
  (setq yascroll:delay-to-hide nil
        ;; The right fringe: the left carries the git gutter and the
        ;; diagnostics, and the text area is for text.
        yascroll:scroll-bar '(right-fringe))

  ;; Furniture rather than text: the dashboard is a page and treemacs is
  ;; a map of somewhere else. Images are yascroll's own exception, having
  ;; no lines to count. Added one by one, so a reload does not lengthen
  ;; the list.
  (dolist (mode '(+doom-dashboard-mode treemacs-mode))
    (cl-pushnew mode yascroll:disabled-modes))

  ;; The minimap is a map of the buffer already. Its own buffer has no
  ;; major mode to speak of, so the list above cannot name it.
  (defadvice! +ui--no-thumb-in-minimap-a (fn buffer)
    "Leave the minimap's own buffer without a thumb."
    :around #'yascroll:enabled-buffer-p
    (and (not (and (fboundp 'demap-buffer-minimap)
                   (demap-buffer-minimap buffer)))
         (funcall fn buffer)))

  ;; Not fading means yascroll redraws the thumb on every change to the
  ;; buffer, which is every keystroke: a fifth of a millisecond each,
  ;; measured, in a config that keeps the indent guides off for four.
  ;; Nothing typed inside a line moves the thumb anyway, so the redraw
  ;; waits for a pause; scrolling and resizing still draw it at once,
  ;; through yascroll's own hooks.
  (defadvice! +ui--thumb-after-a-pause-a (&rest _)
    "Draw the thumb when the typing stops, not on every change."
    :override #'yascroll:after-change
    (when (timerp +ui--thumb-timer) (cancel-timer +ui--thumb-timer))
    (setq +ui--thumb-timer
          (run-with-idle-timer 0.2 nil #'+ui--thumb-now (current-buffer))))

  ;; True to proportion, a window of forty lines on a file of fifty
  ;; thousand earns a thumb one line tall: a dot, and a dot in a fringe
  ;; is something to hunt for. Two lines is still small and can be seen.
  (defadvice! +ui--thumb-worth-seeing-a (fn &rest args)
    "Never draw the thumb shorter than two lines."
    :around #'yascroll:compute-thumb-size
    (max 2 (apply fn args)))

  (custom-set-faces!
    `(yascroll:thumb-fringe :foreground ,(doom-color 'base6)
                            :background ,(doom-color 'base6))))


;;
;;; Minimap

;; The minimap, Doom's :ui minimap on demap, on the right, SPC t m: its
;; window lays out the whole buffer in a tiny font on every redisplay
;; of the buffer it shows, eight milliseconds a frame for a thousand
;; lines of C++ on a big frame, twice the cost of the code window
;; itself; so it opens when asked, not by itself.
(after! demap
  (setq demap-minimap-window-side 'right
        demap-minimap-window-width 16))

;; A window can say it is not one to move to, and the minimap says it:
;; there is nothing to do in there and no way back but the way you came.
;; `other-window' listens, evil's window motions go through windmove,
;; which does not, so C-w l walked straight into it. They step over it
;; now, and a window given over to something else is left alone the same
;; way.
(defun +ui--keep-out-of-side-windows-a (fn &rest args)
  "Undo a move that landed on a window with `no-other-window'."
  (let ((origin (selected-window)))
    (apply fn args)
    (when (and (window-live-p origin)
               (not (eq (selected-window) origin))
               (window-parameter (selected-window) 'no-other-window))
      (select-window origin))))

;; Only the four directions: `evil-window-next' and its opposite go
;; through `other-window', which consults the parameter itself, and a
;; count given to them is a jump meant on purpose.
(dolist (command '(evil-window-left evil-window-right
                   evil-window-up evil-window-down))
  (advice-add command :around #'+ui--keep-out-of-side-windows-a))

(after! treemacs
  (setq treemacs-width 30
        treemacs-is-never-other-window t)
  (treemacs-follow-mode +1)         ; follow the current file
  (treemacs-filewatch-mode +1)      ; refresh when files change on disk
  (treemacs-git-mode 'deferred))    ; git status, without blocking

(use-package! eldoc-box
  :defer t
  :config
  (setq eldoc-box-max-pixel-width 600
        eldoc-box-max-pixel-height 500))


;;
;;; Keybindings

(map! :leader
      (:prefix "i"
       :desc "Nerd Font glyph"       "g" #'+ui/insert-glyph
       :desc "Glyph as elisp form"   "G" #'+ui/insert-glyph-form)
      (:prefix "t"
       :desc "Glyph test buffer"     "G" #'+ui/glyph-test
       :desc "The outline of this buffer" "o" #'imenu-list-smart-toggle
       :desc "Where you are, in the header" "h" #'+ui-where-mode)
      (:prefix "c"
       :desc "Docs at point (popup)" "H" #'eldoc-box-help-at-point)
      (:prefix ("e" . "explorer")
       ;; The same command Doom's own SPC o p runs, so the two keys do
       ;; not part ways: the package's `treemacs' opens where it last
       ;; was, the toggle opens on the project and closes again.
       :desc "Toggle Treemacs"       "t" #'+treemacs/toggle))
