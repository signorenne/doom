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

(defun +ui--defun-around (top)
  "(START . END) of the function holding TOP, or nil.  From the syntax
tree where the buffer has one, in as many steps as it is deep: moving to
the start and end of a defun walks every sibling on the way, and in a
large object literal or array that was most of a scroll step's time."
  (if (and (fboundp 'treesit-defun-at-point)
           (bound-and-true-p treesit-defun-type-regexp)
           (treesit-parser-list))
      (when-let* ((node (save-excursion (goto-char top) (treesit-defun-at-point))))
        (cons (treesit-node-start node) (treesit-node-end node)))
    (save-excursion
      (goto-char top)
      (when-let* ((start (and (ignore-errors (beginning-of-defun) t) (point)))
                  (end (progn (ignore-errors (end-of-defun)) (point))))
        (cons start end)))))

(defun +ui--scrolled-defun ()
  "The first line of the function that holds the window's first line,
when that first line is scrolled off; nil at the top of a function or
between two.  Kept while the window's top stays inside that function."
  (let ((top (window-start)))
    (when (> top (point-min))
      (pcase-let ((`(,from ,to ,tick . ,line) +ui--defun-cache))
        (if (and from (<= from top) (< top to) (eq tick (buffer-chars-modified-tick)))
            line
          (let* ((range (+ui--defun-around top))
                 (inside (and range (< (car range) top) (> (cdr range) top)))
                 (text (and inside
                            (save-excursion
                              (goto-char (car range))
                              (font-lock-ensure (car range) (pos-eol))
                              (string-trim-right (buffer-substring (car range) (pos-eol)))))))
            (setq +ui--defun-cache
                  (cons (if inside (car range) top)
                        (cons (if inside (cdr range) (1+ top))
                              (cons (buffer-chars-modified-tick) text))))
            text))))))

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

;; flymake rewrites the text at the end of every line with a diagnostic
;; at each report: 1 607 lines of it in a file a server found 2 896
;; problems in, which doubled the cost of a key. Past a few hundred the
;; ends of the lines are a wall no one reads; the underline, the fringe
;; and the popup still say it all, and the text comes back when the
;; count comes down.
(defvar +ui-flymake-eol-max 300
  "Past this many diagnostics in a report, none is written at a line's end.")

(defvar-local +ui--flymake-eol-held nil
  "Non-nil while this buffer has too many diagnostics for line ends.")

(defun +ui--flymake-eol-within-reason-a (fn backend token report-action &rest args)
  "Hold the end-of-line text back while a report is too long for it."
  (when (and (listp report-action) (default-value 'flymake-show-diagnostics-at-end-of-line))
    (if (> (length report-action) +ui-flymake-eol-max)
        (unless +ui--flymake-eol-held
          (setq +ui--flymake-eol-held t)
          (setq-local flymake-show-diagnostics-at-end-of-line nil)
          (save-restriction
            (widen)
            (dolist (o (overlays-in (point-min) (point-max)))
              (when (overlay-get o 'flymake--eol-overlay) (delete-overlay o)))))
      (when +ui--flymake-eol-held
        (setq +ui--flymake-eol-held nil)
        (kill-local-variable 'flymake-show-diagnostics-at-end-of-line))))
  (apply fn backend token report-action args))

(after! flymake
  (advice-add 'flymake--handle-report :around #'+ui--flymake-eol-within-reason-a))

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

;; The indent guides would cost four milliseconds a scroll step on a big
;; frame, but switching them off while the wheel turns refontifies the
;; buffer, which costs more; so they are off unless asked for, SPC t i.
(defun +ui--no-guides-by-default-h ()
  "Keep Doom's indent guides off until asked for."
  t)
(add-hook '+indent-guides-inhibit-functions #'+ui--no-guides-by-default-h)

;;
;;; Where you are in the buffer

;; In the modeline, where the eye already goes for a buffer's facts: the
;; line out of how many the buffer has, the column out of how many the
;; line has, and how far through the buffer point is as a percentage,
;; 228/1009:7/42  23%. They take no column from the text and no pixel
;; from the fringe, which carries the git gutter and the diagnostics.
(defun +ui--position ()
  "How far through the buffer point is, for the modeline."
  ;; %%%% here is %% after `format', which the modeline then shows as
  ;; one %: a lone % would be read as one of its codes.
  (format "%3d%%%%" (round (* 100 (/ (float (- (point) (point-min)))
                                     (max 1 (- (point-max) (point-min))))))))

;; Counting the lines reads the whole text, so the count is kept and done
;; again only when the buffer has changed, and in a buffer of megabytes
;; only once the typing stops.
(defvar +ui-line-count-idle-size (* 2 1024 1024)
  "Past this many characters, the line count waits for a pause to be redone.")

(defvar-local +ui--line-count nil
  "(TICK START END . LINES): the buffer's lines when they were last counted.")

(defvar-local +ui--line-count-timer nil
  "The pending recount of a large buffer.")

(defun +ui--count-lines ()
  "Count the lines of the accessible part of the buffer, and keep it."
  (let ((lines (line-number-at-pos (point-max))))
    (setq +ui--line-count (cons (buffer-chars-modified-tick)
                                (cons (point-min) (cons (point-max) lines))))
    lines))

(defun +ui--line-total ()
  "How many lines the buffer has, for the modeline."
  (pcase-let ((`(,tick ,start ,end . ,lines) +ui--line-count))
    (number-to-string
     (cond ((and lines (eq tick (buffer-chars-modified-tick))
                 (eq start (point-min)) (eq end (point-max)))
            lines)
           ((or (null lines) (< (buffer-size) +ui-line-count-idle-size))
            (+ui--count-lines))
           (t
            (unless (timerp +ui--line-count-timer)
              (let ((buffer (current-buffer)))
                (setq +ui--line-count-timer
                      (run-with-idle-timer
                       0.5 nil
                       (lambda ()
                         (when (buffer-live-p buffer)
                           (with-current-buffer buffer
                             (setq +ui--line-count-timer nil)
                             (+ui--count-lines)
                             (force-mode-line-update))))))))
            lines)))))

;; The line's width is measured again only when point is on another line
;; or the text changed, so moving along a line costs a comparison; and
;; past `+ui-line-width-max' characters it is the count of characters,
;; since measuring a line of a minified file reads all of it at each key.
;; Past the end of the line, in insert state, the column is one more than
;; the width: 43/42.
(defvar +ui-line-width-max 4000
  "Past this many characters a line's width is its count of characters.")

(defvar-local +ui--line-width nil
  "(TICK BOL . WIDTH): the width of the line point was on, when measured.")

(defun +ui--line-width ()
  "How many columns the current line has, for the modeline."
  (let ((tick (buffer-chars-modified-tick))
        (bol (pos-bol)))
    (unless (and (eq tick (car +ui--line-width))
                 (eq bol (cadr +ui--line-width)))
      (let ((eol (pos-eol)))
        (setq +ui--line-width
              (cons tick (cons bol (if (> (- eol bol) +ui-line-width-max)
                                       (- eol bol)
                                     (save-excursion (goto-char eol) (current-column))))))))
    (number-to-string (cddr +ui--line-width))))

;; Doom's light modeline says "30:12 Bot"; this keeps the line and
;; column, adds how many lines and columns there are, and puts the
;; percentage where the word was.
(setq-default +modeline-position
              '("  %l/" (:eval (+ui--line-total)) ":%C/" (:eval (+ui--line-width)) "  "
                (:eval (+ui--position)) "  "))


;;
;;; Redrawing only what changed

;; Emacs redraws a window by laying out every line of it again, unless it
;; can tell that only the cursor moved or only a line changed; on a full
;; frame of C++ that layout is most of what a key costs. Two things kept
;; it from telling.

;; The theme draws the current line's number unlike the others, bright on
;; hl-line's band. Emacs sees two faces that differ and gives up every
;; shortcut: each redraw laid out the whole window, even one after a
;; timer or a server message that changed nothing, 2.8 ms instead of 0.6,
;; and a key cost 6 ms instead of 4. So where Emacs looks the two faces
;; are the same, and the theme's look comes back through a remap in the
;; buffers where hl-line is on. There a change of line always moves
;; hl-line's overlay, which redraws the whole window anyway, so the
;; bright number is never left on the line the cursor left.
(defface +ui-current-line-number '((t))
  "The current line's number as the theme draws it, kept by
`+ui--line-number-faces-h'."
  :group 'display-line-numbers)

(defun +ui--line-number-faces-h (&optional frame)
  "Keep the theme's current line number in `+ui-current-line-number', and
make `line-number-current-line' the same as `line-number', on FRAME or
on every frame."
  (dolist (f (if (framep frame) (list frame) (frame-list)))
    (unless (internal-lisp-face-equal-p 'line-number 'line-number-current-line f)
      (copy-face 'line-number-current-line '+ui-current-line-number f)
      (copy-face 'line-number 'line-number-current-line f))))

(add-hook 'doom-load-theme-hook #'+ui--line-number-faces-h)
(add-hook 'after-make-frame-functions #'+ui--line-number-faces-h)

(defvar-local +ui--current-line-number nil
  "The remap that draws this buffer's current line number the theme's way.")

(defun +ui--current-line-number-h ()
  "Draw the current line's number the theme's way while hl-line is on."
  (cond ((and hl-line-mode (null +ui--current-line-number))
         (setq +ui--current-line-number
               (face-remap-add-relative 'line-number-current-line
                                        '+ui-current-line-number)))
        ((and (not hl-line-mode) +ui--current-line-number)
         (face-remap-remove-relative +ui--current-line-number)
         (setq +ui--current-line-number nil))))

(add-hook 'hl-line-mode-hook #'+ui--current-line-number-h)

;; solaire gives the line numbers of its buffers a face of their own; the
;; current one gets the same, or the two would differ again in there.
(after! solaire-mode
  (add-to-list 'solaire-mode-remap-alist
               '(line-number-current-line . solaire-line-number-face)))

;; And hl-line puts its overlay on the current line after every command,
;; even when the overlay is there already, and an overlay moved, even in
;; place, changes the whole window as far as redisplay knows. It moves
;; now only when the line did: moving along a line and typing on it no
;; longer lay out the window.
(defadvice! +ui--hl-line-stay-a (fn overlay)
  "Leave OVERLAY where it is when it already covers the current line."
  :around #'hl-line-move
  (unless (and (null hl-line-range-function)
               (eq (overlay-buffer overlay) (current-buffer))
               (eql (overlay-start overlay) (line-beginning-position))
               (eql (overlay-end overlay) (line-beginning-position 2)))
    (funcall fn overlay)))

;; The modeline is formatted again at every key. Doom's light one formats
;; its right half twice for it, the first time only to measure it for the
;; space that pushes it to the edge; and eglot's piece of it is a cl-loop
;; quoted into `mode-line-misc-info', a macro the interpreter expands
;; afresh each time. Formatted once, with eglot's loop expanded once, the
;; modeline takes 70 microseconds instead of 200 and half the garbage.
(defun +ui--modeline-right ()
  "The right half of the modeline, pushed against the window's edge."
  (let ((right (format-mode-line '("" +modeline-format-right))))
    (concat (propertize " " 'display
                        `((space :align-to (- (+ right right-fringe right-margin)
                                              ,(string-width right)))))
            ;; What this returns is read as a modeline construct again: a
            ;; % in it, a server's 45%, would start a code there.
            (string-replace "%" "%%" right))))

(add-hook! '+modeline-mode-hook
  (defun +ui--modeline-right-once-h ()
    (when +modeline-mode
      (setq mode-line-format
            '("" +modeline-bar +modeline-format-left (:eval (+ui--modeline-right)))))))

(after! eglot
  (setq mode-line-misc-info
        (mapcar (lambda (entry)
                  (pcase entry
                    ;; Only eglot's own loop: after a reload the entry is
                    ;; this one already, and would come to call itself.
                    (`(eglot--managed-mode (,open (:eval ,(and form `(cl-loop . ,_))) ,close))
                     (defalias '+ui--eglot-mode-line
                       (eval `(lambda () ,(macroexpand-all form)) t)
                       "eglot's piece of the modeline: its own code, expanded once.")
                     `(eglot--managed-mode (,open (:eval (+ui--eglot-mode-line)) ,close)))
                    (_ entry)))
                mode-line-misc-info)))


;;
;;; Minimap

;; SPC t m: the buffer in a tiny font on the right, the part on screen
;; marked; autoload/minimap.el. A copy of the text, taken again once the
;; typing pauses, so moving and typing cost it nothing.

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
       :desc "Where you are, in the header" "h" #'+ui-where-mode
       :desc "Minimap"                  "m" #'+ui/minimap)
      (:prefix "c"
       :desc "Docs at point (popup)" "H" #'eldoc-box-help-at-point)
      (:prefix ("e" . "explorer")
       ;; The same command Doom's own SPC o p runs, so the two keys do
       ;; not part ways: the package's `treemacs' opens where it last
       ;; was, the toggle opens on the project and closes again.
       :desc "Toggle Treemacs"       "t" #'+treemacs/toggle))
