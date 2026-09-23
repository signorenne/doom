;;; private/butler/autoload/menu.el -*- lexical-binding: t; -*-
;;
;; What the butler can be asked to do: say something, answer a
;; question, stand somewhere, step, go. SPC h j summons him and opens
;; this menu.

(require 'transient)

(defvar +butler-name)
(defvar +butler-positions)
(defvar +butler-nudge-step)
(defvar +butler-quips)
(defvar +butler-address)
(defvar +butler--said)                  ; config.el
(defvar +butler--section)
(declare-function +docs-cheatsheet-section-for "cheatsheet")
(defvar +butler--position)
(declare-function +butler--show "butler")
(declare-function +butler--hint "butler")
(declare-function +butler--withdraw "butler")
(declare-function +butler--stand "butler")
(declare-function +butler--nudge "butler")
(declare-function +butler--remember "butler")
(declare-function +butler--nearest-corner "butler")
(declare-function +butler--frame "butler")
(declare-function +butler--on-screen-p "butler")
(declare-function +butler--redisplay "butler")
(defvar +butler--question)
(defvar +butler--offered)
(defvar +butler--offered-hits)
(declare-function +butler--answer "ask")

;;
;;; Commands

(defun +butler--section-here ()
  "The cheat sheet section of this buffer, when the docs module is on."
  (and (fboundp '+docs-cheatsheet-section-for)
       (+docs-cheatsheet-section-for)))

;;;###autoload
(defun +butler/hint ()
  "A hint for the buffer you are in, from the cheat sheet."
  (interactive)
  (pcase-let ((`(,tip . ,section)
               (+butler--hint (or +butler--section (+butler--section-here)))))
    (+butler--show tip section)))

;;;###autoload
(defun +butler/tip ()
  "A hint from anywhere in the cheat sheet."
  (interactive)
  (pcase-let ((`(,tip . ,section) (+butler--hint nil)))
    (+butler--show tip section)))

;;;###autoload
(defun +butler/quip ()
  "A word of his own."
  (interactive)
  (+butler--show (+butler-quip)))

;;;###autoload
(defun +butler/greet ()
  "The greeting of the hour, the one the dashboard uses."
  (interactive)
  (+butler--show (+butler-greeting)))

;;;###autoload
(defun +butler/copy ()
  "Copy what he last said."
  (interactive)
  (kill-new +butler--said)
  (message "%s: noted, %s. It is on the kill ring." +butler-name +butler-address))

;;;###autoload
(defun +butler/read ()
  "Read the whole of what he last said, in a buffer that scrolls: the
bubble says his piece and stops, this holds all of it."
  (interactive)
  (when (or (null +butler--said) (string-empty-p +butler--said))
    (user-error "%s: I have said nothing yet, %s" +butler-name +butler-address))
  (let ((said +butler--said)
        (buffer (get-buffer-create "*butler says*")))
    (with-current-buffer buffer
      (unless (derived-mode-p 'special-mode) (special-mode))
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert said)
        (goto-char (point-min)))
      (visual-line-mode 1))
    (pop-to-buffer buffer)))

;;;###autoload
(defun +butler/dismiss ()
  "That will be all."
  (interactive)
  (+butler--withdraw))

;;;###autoload
(defun +butler/move ()
  "Stand at the next of `+butler-positions'."
  (interactive)
  (+butler--stand (or (cadr (memq +butler--position +butler-positions))
                      (car +butler-positions))))

;;;###autoload
(defun +butler/stand-top-left ()
  "Stand in the top left corner."
  (interactive)
  (+butler--stand 'top-left))

;;;###autoload
(defun +butler/stand-top-right ()
  "Stand in the top right corner."
  (interactive)
  (+butler--stand 'top-right))

;;;###autoload
(defun +butler/stand-bottom-left ()
  "Stand in the bottom left corner."
  (interactive)
  (+butler--stand 'bottom-left))

;;;###autoload
(defun +butler/stand-bottom-right ()
  "Stand in the bottom right corner."
  (interactive)
  (+butler--stand 'bottom-right))

;;;###autoload
(defun +butler/stand-centre ()
  "Stand in the middle of the frame."
  (interactive)
  (+butler--stand 'centre))

;;;###autoload
(defun +butler/stand-here ()
  "Stand just below the cursor."
  (interactive)
  (+butler--stand 'here))

;;;###autoload
(defun +butler/nudge-left ()
  "A step left."
  (interactive)
  (+butler--nudge (- +butler-nudge-step) 0))

;;;###autoload
(defun +butler/nudge-right ()
  "A step right."
  (interactive)
  (+butler--nudge +butler-nudge-step 0))

;;;###autoload
(defun +butler/nudge-up ()
  "A step up."
  (interactive)
  (+butler--nudge 0 (- +butler-nudge-step)))

;;;###autoload
(defun +butler/nudge-down ()
  "A step down."
  (interactive)
  (+butler--nudge 0 +butler-nudge-step))

;;;###autoload
(defun +butler/drag (event)
  "Move him with the mouse: press on him, drag, let go.
EVENT is the press.  Where he is let go is where he stands from then on.
Pressed anywhere but on him, this does nothing, so his menu's buttons
still take a click."
  (interactive "e")
  (let ((window (posn-window (event-start event)))
        (frame (+butler--frame)))
    (when (and frame (windowp window) (eq (window-frame window) frame))
      (let* ((from (mouse-absolute-pixel-position))
             (origin (frame-position frame))
             (spot origin)
             (track-mouse 'dragging)
             event)
        (catch 'released
          (while t
            (setq event (read-event))
            (cond
             ((mouse-movement-p event)
              (let ((now (mouse-absolute-pixel-position)))
                (setq spot (cons (+ (car origin) (- (car now) (car from)))
                                 (+ (cdr origin) (- (cdr now) (cdr from)))))
                (set-frame-position frame (car spot) (cdr spot))))
             ;; Frames and windows passing under the mouse are no concern.
             ((memq (car-safe event)
                    '(switch-frame select-window focus-in focus-out)))
             (t (throw 'released nil)))))
        ;; The release ends the drag; anything else was meant for Emacs.
        (unless (eq (event-basic-type event) 'mouse-1)
          (push event unread-command-events))
        ;; A press that did not move him is not a new spot: a named
        ;; corner stays a corner rather than becoming this monitor's
        ;; pixels.
        (unless (equal spot origin)
          ;; Let go of in a corner, he takes the corner and stays in it
          ;; whatever he says next; anywhere else he stands where he was
          ;; put, and keeps the edge he is nearest to.
          (setq +butler--position (or (+butler--nearest-corner) spot))
          (+butler--remember))))))

(defun +butler--choice-label (hit)
  "HIT as one line of his choice menu: what it says, and where from."
  (format "%-46s %s"
          (truncate-string-to-width (plist-get hit :text) 46 nil nil t)
          (truncate-string-to-width (plist-get hit :section) 30 nil nil t)))

;;;###autoload
(defun +butler/choose ()
  "Say the answer the number just pressed stands for."
  (interactive)
  (let ((hit (nth (- last-command-event ?1) +butler--offered)))
    (unless hit (user-error "%s: there is no such answer, %s" +butler-name +butler-address))
    (+butler--answer hit +butler--offered-hits)))

(defun +butler--choice-children (_)
  "The answers on offer, one suffix each, numbered from one."
  (transient-parse-suffixes
   '+butler/choices
   (or (cl-loop for hit in +butler--offered
                for i from 1
                collect (list (number-to-string i) (+butler--choice-label hit)
                              '+butler/choose))
       `(("1" ,(format "nothing to choose between, %s" +butler-address)
          +butler/choose)))))

;;;###autoload (autoload '+butler/choices "private/butler/autoload/menu" nil t)
(transient-define-prefix +butler/choices ()
  "The answers that fit the question, to choose between."
  [:description (lambda () (format "%s: I have said the first. Did you mean another, %s?"
                                   +butler-name +butler-address))
   :class transient-column
   :setup-children +butler--choice-children]
  [["Or"
    ("c" "None of these: ask Claude" +butler/ask-again)]])

;;;###autoload (autoload '+butler/menu "private/butler/autoload/menu" nil t)
(transient-define-prefix +butler/menu ()
  "What the butler can do while he is here.  Laid out and behaving as
the other menus: a command closes it, a step keeps it open."
  [:description (lambda () (format "%s, at your service" +butler-name))
   :pad-keys t
   ["Say"
    ("h" "A hint for this buffer" +butler/hint)
    ("n" "A hint from anywhere"   +butler/tip)
    ("a" "Answer a question"      +butler/ask)
    ("A" "Ask Claude outright"    +butler/ask-claude)
    ("r" "Not that: ask Claude"   +butler/ask-again
     :if (lambda () (bound-and-true-p +butler--question)))
    ("o" "Where the answer is"    +butler/show-source
     :if (lambda () (bound-and-true-p +butler--answer)))
    ("s" "A word of his own"      +butler/quip)
    ("g" "The greeting"           +butler/greet)
    ("c" "Copy what he said"      +butler/copy)
    ("R" "Read it in full"        +butler/read)]
   ["Stand"
    ("7" "Top left"      +butler/stand-top-left)
    ("9" "Top right"     +butler/stand-top-right)
    ("5" "In the middle" +butler/stand-centre)
    ("1" "Bottom left"   +butler/stand-bottom-left)
    ("3" "Bottom right"  +butler/stand-bottom-right)
    ("0" "By the cursor" +butler/stand-here)
    ("m" "Next spot"     +butler/move :transient t)]
   ["Step"
    ("<left>"  "Left"  +butler/nudge-left  :transient t)
    ("<right>" "Right" +butler/nudge-right :transient t)
    ("<up>"    "Up"    +butler/nudge-up    :transient t)
    ("<down>"  "Down"  +butler/nudge-down  :transient t)]
   ["Leave"
    ("x" "Dismiss him" +butler/dismiss)]]
  ;; Bound but not shown: a press on him starts a drag, and the key that
  ;; opened the menu closes it.
  [:hide always
   ("<down-mouse-1>" "drag" +butler/drag :transient t)
   ("SPC h j" "close the menu" transient-quit-one)])

;;;###autoload
(defun +butler/summon ()
  "Call the butler: he comes with a hint for this mode, and his menu opens.
q closes the menu and he stays where he is; x in the menu, or
`+butler/dismiss', and he goes.  While he is here this opens the menu
again."
  (interactive)
  (let ((new (not (+butler--on-screen-p))))
    (setq +butler--section (+butler--section-here))
    ;; The menu first, so he knows where it is and stands clear of it.
    (call-interactively #'+butler/menu)
    (if new (+butler/hint) (+butler--redisplay))))
