;;; private/butler/config.el -*- lexical-binding: t; -*-
;;
;; Hudson, the butler. SPC h j summons him: he appears in a bubble beside
;; your work with a hint for the mode you are in, taken from the cheat
;; sheet, or a word of his own, and stays until told otherwise.

(defvar +butler-name "Hudson"
  "The butler's name. Carson, Jeeves and Brabinger have all served.")

(defvar +butler-docs '(:groups (("butler" "Butler" () +butler-mode-map)))
  "How the cheat sheet documents this module; see `+docs--module-docs'.")

(defvar +butler-art
  '("  ,-----.  "
    " ( o   o ) "
    " |   .   | "
    " |  '-'  | "
    ".-'-----'-."
    "|  |>:<|  |"
    "|  |   |  |")
  "The butler, one string per line, all the same width.
Every part of him is centred on the same column: hair, eyes, nose, mouth,
shoulders, bow tie and coat.  No blank column is kept at the sides
beyond the one the turning head needs, so in a corner he stands against
the edge of it.")

(defvar +butler-head-rows 4
  "How many rows of `+butler-art', from the top, are the head.
They turn together; the rows below are the body and stay put.")

(defvar +butler-faces
  '((neutral)
    (blink   (1 . " ( -   - ) "))
    (wink    (1 . " ( o   - ) "))
    (happy   (1 . " ( ^   ^ ) ") (3 . " |  \\_/  | "))
    (wide    (1 . " ( O   O ) ") (3 . " |   o   | "))
    (sigh    (1 . " ( -   - ) ") (3 . " |  ___  | ")))
  "Faces: head rows of `+butler-art' swapped in, drawn with the head in
the middle. Whatever position the head is in, the face is turned with it.")

(defvar +butler-bodies
  '((neutral)
    (tie     (5 . "|  |>=<|  |"))
    (shrug   (5 . "/  |>:<|  \\")))
  "What the body does: rows of `+butler-art' swapped in, below the head.")

(defvar +butler-gestures
  '((blink 8        (face blink . 2))
    (blink2 3       (face blink . 2) (face neutral . 2) (face blink . 2))
    (wink 2         (face wink . 4))
    (happy 3        (face happy . 14) (face blink . 2))
    (wide 1         (face wide . 6) (face blink . 2))
    (sigh 1         (face sigh . 9) (face blink . 2))
    (tie 2          (body tie . 3) (body neutral . 3) (body tie . 3))
    (shrug 1        (body shrug . 8))
    (turn-left 3    (head left . 0) (face blink . 2))
    (turn-right 3   (head right . 0) (face blink . 2))
    (turn-middle 4  (head middle . 0) (face blink . 2))
    (look-about 2   (head right . 9) (head middle . 3) (head left . 9)
                    (head middle . 2) (face blink . 2)))
  "What he does between waits: a name, a weight, then steps.
A step is (TRACK VALUE . TICKS): the track is `face', `body' or `head',
the value a name from `+butler-faces', `+butler-bodies' or one of `left',
`middle', `right'; a tick is a tenth of a second, stretched a little at
random. When a gesture ends the face and the body go back to neutral; the
head stays where it was turned, so he can blink, smile or fix his tie
looking any way he likes.")

(defvar +butler-idle-ticks '(20 . 80)
  "The least and the most ticks he keeps still between two gestures.")

(defvar +butler-bubble-width 44
  "How many columns the speech bubble holds: a line wraps there, and
the bubble is always that wide and at least as tall as he is, so the
block keeps its shape whatever he says.  With the art beside it and
the one column between them the whole block is 58 columns at the widest;
a brief answer takes a smaller bubble and fewer of them.")

(defvar +butler-bubble-max-lines 12
  "How many lines the bubble says before it stops.  A butler says his
piece and stops; what is left is read in full with R in his menu and
copied whole with c, and a bubble taller than the frame could be
neither read nor scrolled.")

(defvar +butler-bubble-min-width 22
  "How narrow the bubble may be.  Below this a short word of his looks
less like a bubble and more like a crack in the wall.")

(defvar +butler-margin '(0 . 0)
  "Blank columns and lines kept round him and the bubble in his popup.
None on any side: in a corner he stands against the edge of it, which is
what a corner is for, and the drawing carries no blank column of its own
to hold him off.")

(defvar +butler-positions
  '(bottom-right bottom-left top-right top-left centre here)
  "Where he can stand, in the order m goes round them in his menu.
`here' is below the cursor.  Each has its own key in the menu as well, laid
out like a keypad: 7 9 for the top corners, 1 3 for the bottom ones, 5 for
the middle and 0 for here.")

(defvar +butler-nudge-step 60
  "Pixels one press of an arrow key moves him.")

(defvar +butler-claude-program "claude"
  "The Claude Code command line, how he reaches Claude when gptel has no
key of its own.  It is signed in already, so nothing else is needed.")

(defvar +butler-claude-seconds 120
  "How long he waits for the command line to answer before giving up.")

(defvar +butler-dashboard-say-ticks 250
  "Ticks of the dashboard animation between one thing he says there and
the next; a tick is a tenth of a second, so 250 is every twenty-five
seconds or so.  Nil, or zero, and he says the one thing all session.")

(defvar +butler-address "sir"
  "How he calls you: \"sir\", \"madam\", whatever you would like to be
called.  It goes into his greeting, his quips and every word he has for
you.  A butler does not use his employer's name, so it is a form of
address and not a name.")

(defvar +butler-greetings
  '((morning
     ("Good morning, %s. The house is awake, the kettle is on,"
      "and the day awaits your instructions.")
     ("A very good morning to you, %s. I have taken the liberty"
      "of leaving everything precisely where you left it.")
     ("Good morning, %s. The correspondence is on the tray;"
      "nothing in it need trouble you before breakfast.")
     ("Good morning, %s. I trust you slept soundly. There is a"
      "great deal to be done, and you are the one to do it.")
     ("Morning, %s. The weather is what it is; the work, I am"
      "pleased to say, is entirely within your power."))
    (afternoon
     ("Good afternoon, %s. The morning acquitted itself well;"
      "I see no reason the afternoon should not follow suit.")
     ("Good afternoon, %s. Tea will be at four,"
      "whether or not the compiler agrees.")
     ("A fine afternoon, %s. Nothing has caught fire in your absence,"
      "which I mention only because it so seldom needs mentioning.")
     ("Good afternoon, %s. If I may: the difficult task is best"
      "met now, while the light is still generous.")
     ("Afternoon, %s. The estate reports all quiet."
      "The build, I regret, reports nothing yet."))
    (evening
     ("Good evening, %s. The lamps are lit."
      "Shall we bring the day to a proper close?")
     ("Good evening, %s. One last matter before supper,"
      "and then I shall insist you leave the desk.")
     ("A pleasant evening, %s. Whatever remains undone will keep;"
      "the good ideas rarely do, so do write them down.")
     ("Good evening, %s. Splendid to have you back. The house"
      "has been quiet without you, and rather dull.")
     ("Good evening, %s. The day was well spent, by my reckoning,"
      "and my reckoning is seldom wrong."))
    (night
     ("Still at it, %s? Very well. I shall keep the lamp trimmed,"
      "but I do ask that you mind the hour.")
     ("The midnight oil, %s. A noble tradition, and one"
      "best honoured by saving your work first.")
     ("A late hour, %s. Genius keeps no schedule, but the body does,"
      "and it will present its bill.")
     ("Good night, %s. Or good morning; at this hour"
      "the distinction is largely academic.")
     ("The house sleeps, %s, and you do not."
      "I shall not judge, but I shall notice.")))
  "What the butler says, by the part of the day.
Each greeting is its lines; the first one takes `+butler-address'.")

(defvar +butler-quips
  '(;; On the craft
    "A tidy buffer is a tidy mind, %s. I say this without judgement."
    "The compiler is not angry with you, %s. It is merely precise."
    "One saves one's work the way one locks the front door: without thinking, and every time."
    "Tea solves a remarkable number of problems, and delays the rest agreeably."
    "The agenda is not a list of failures, %s. It is a list of intentions."
    "A note unlinked is a letter unsent."
    "Undo exists, %s. Boldness is therefore affordable."
    "The best time to write it down was when you thought of it. The second best time is now."
    "One cannot rush a good build, %s. One can, however, rush a bad one."
    "C-o returns you whence you came. It nearly always does."
    "I would not presume to read the diagnostics for you, %s, but they are on SPC c x."
    "A project with tests sleeps soundly. So, in consequence, does its author."
    "Marks are for places one intends to return to; bookmarks, for places one intends to remember."
    "The kettle is on, metaphorically. I regret that Emacs cannot boil water. Yet."
    "If I may, %s: the difficult task first, while the light is good."
    "Everything is where you left it. I have made quite sure of that."
    "A name that says what the thing is, %s, is half the documentation."
    "One does not argue with clangd. One provides it with a compilation database."
    "The house has seen worse merges, %s. Not many, but some."
    ;; On method and habit
    "A commit that says what it did, %s, is a kindness to the man you will be on Friday."
    "Small commits, %s, the way one eats an artichoke: a leaf at a time."
    "The branch is cheap, %s. Make one, and spare the main line your experiments."
    "Rebase in private, merge in public. The estate keeps its dignity either way."
    "A stash is a drawer, %s, not a wardrobe. Do empty it before it forgets what it holds."
    "One does not fear the force push, %s. One simply is quite certain first."
    "The blame, SPC t B, names the author, not the culprit. They are now and then the same man."
    "Read the error to its end, %s. The first line is the symptom; the cause is often further down."
    "When the build is strange, %s, clean it. A fresh start clears more than it costs."
    "A red test is a friend that tells you the truth before your users do."
    "Format on save, %s, and never again debate the placement of a brace."
    "The TODO you write today, %s, is a promise; SPC n t is where they are all kept."
    "Refactor while the tests are green, %s. Courage is cheaper with a net."
    "A long function, %s, is a paragraph that forgot to end. Do give it a full stop."
    "Name it well and you need not comment it, %s. Name it ill and no comment will save it."
    "The clipboard forgets, %s; the kill ring remembers. Prefer the one with the memory."
    "Two windows, %s, one truth: the header on the left, the source on the right, F4 between."
    "When lost in a file, %s, SPC s i shows its bones; the outline is the quickest map."
    "A regexp, %s, is a small sharp tool. Handle it with respect and a test buffer."
    "Macros, %s: do the tedious thing once with care, then let Emacs do it a hundred times without."
    ;; On patience, rest and proportion
    "The bug will keep until morning, %s. It has nowhere better to be."
    "Step away, %s. The answer often arrives while the kettle does."
    "A walk, %s, is a debugger for the mind. It clears the stack."
    "You have been at the desk some time, %s. The chair will hold your place."
    "Perfection is a fine direction, %s, and a poor destination."
    "Ship it, %s. A thing in use teaches more than a thing polished."
    "Rest is not idleness, %s. It is the part of the work that looks like nothing."
    "The deadline is a servant, %s, not a master. Do not let it into the drawing room."
    "One good hour, %s, outweighs three tired ones. I have kept the accounts."
    "Do not mistake motion for progress, %s. The dashboard is not the destination."
    ;; Courtesies and small manners
    "At your service, %s, as ever. The day is yours to command."
    "I took the liberty of tidying nothing, %s. Your arrangement, I assume, is deliberate."
    "Should you need me, %s, SPC h j. I am never far, and never in the way."
    "A pleasure, %s. The work suits you, and you it."
    "I shall be in the pantry, metaphorically, should the compiler require a witness."
    "Very good, %s. I shall say no more, unless a word of mine is wanted on s."
    "You rang, %s. Or you pressed a key, which in this house amounts to the same."
    "I remember where you last had me stand, %s. Savehist and I are of one mind."
    "The greeting on g changes with the hour, %s, as a proper household should."
    "If the words fail me, %s, I put your question to Claude and return with a sentence."
    ;; Gentle wit
    "I do not judge the late hour, %s. I merely note that I have seen it before."
    "The semicolon, %s: small, quiet, and sorely missed when absent."
    "Whitespace, %s, is invisible until it is wrong, at which point it is all one sees."
    "A merge conflict, %s, is two opinions meeting in a narrow corridor. Someone must step aside."
    "The cache lies, %s, but only about the past. SPC k reset restores its honesty."
    "One does not lose work in this house, %s. One merely misplaces a branch, briefly."
    "The docs are the truth, %s. I quote them precisely, that I may never invent a key."
    "I contain no wisdom of my own, %s, only the sheet, read aloud with better posture."
    "A good abstraction, %s, is a butler: it does the thing, and does not explain how."
    "The terminal is on SPC o t, %s, for the tasks that Emacs, in its modesty, leaves to the shell.")
  "What the butler says when asked for a word of his own.
Each takes `+butler-address' where it calls you by it.")

;; His state, here so it is there before either autoload file loads: what
;; he last said, the mode he was summoned from, and where he stands.
(defvar +butler--said ""
  "The last thing he said, for `+butler/copy'.")

(defvar +butler--section nil
  "The cheat sheet section of the buffer he was summoned from, or nil.")

(defvar +butler--question nil
  "The last question put to him, for `+butler/ask-again'.")

(defvar +butler--offered nil
  "The answers his choice menu is showing, best first.")

(defvar +butler--offered-hits nil
  "Every hit those answers came from, for the lines beside the one
chosen.")

(defvar +butler--position 'bottom-right
  "Where he stands: one of `+butler-positions', or (X . Y) in pixels of
the frame once the arrow keys or the mouse have put him somewhere of
their own.  Kept by savehist, so he is found where he was left.")

;; He stands on the dashboard through what ui offers: the greeting above
;; the date is his, and every tick of the animation moves him on. The
;; dashboard itself knows nothing of him.
(defvar +ui-dashboard-greeting-function)  ; ui/config.el
(defvar +ui-dashboard-tick-hook)
(setq +ui-dashboard-greeting-function #'+butler--dashboard-greeting)
(add-hook '+ui-dashboard-tick-hook #'+butler--dashboard-tick-h)

;; In a terminal he takes a window at the bottom; q closes it like any
;; popup. In the GUI he floats in a child frame instead, see the autoloads.
(set-popup-rule! "^\\*butler\\*" :side 'bottom :size 9 :select nil :quit t)
;; What he said in full, when the bubble could not hold it: an ordinary
;; buffer, which scrolls and searches like any other.
(set-popup-rule! "^\\*butler says\\*" :side 'bottom :size 0.4 :select t :quit t)

(map! :leader
      (:prefix "h"
       :desc "Summon the butler" "j" #'+butler/summon
       :desc "Dismiss the butler" "J" #'+butler/dismiss))

;; He stands clear of his menu while it is up and steps back into his
;; corner when it closes; when the frame changes size he is placed again.
(after! transient
  (add-hook 'transient-exit-hook #'+butler--menu-closed-h))
(add-hook 'window-size-change-functions
          (defun +butler--frame-changed-h (frame)
            (when (get-buffer "*butler*")
              (+butler--follow-frame-h frame))))

;; Where he last stood, a corner or a spot he was dragged to, is kept for
;; the next session.
(after! savehist
  (add-to-list 'savehist-additional-variables '+butler--position))

;; In his popup the keys are his menu's and the mouse drags him; evil has
;; no say there.
(after! evil
  (evil-set-initial-state '+butler-mode 'emacs))
