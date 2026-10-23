;;; private/butler/autoload/ask.el -*- lexical-binding: t; -*-
;;
;; Ask him a question in your words. He looks it up in the cheat sheet
;; and the READMEs by the words, and answers with the line that fits
;; best, the key when it is one, and where it says so; when two
;; sections fit as well, he asks which you meant. When the words alone
;; do not settle it, or when asked with a prefix argument, he puts the
;; question to Claude with the lines he found, so the answer is a
;; sentence; the docs stay the source, so he cannot make a key up.

(defvar +butler-name)
(defvar +butler-address)
(defvar +butler-bubble-width)
(defvar +butler-claude-program)
(defvar +butler-claude-seconds)
(declare-function +butler--show "butler")
(declare-function +docs-search "cheatsheet")
(declare-function +docs/cheatsheet "cheatsheet")
(declare-function gptel-request "gptel-request")
(declare-function +butler/choices "menu")
(declare-function +butler--section-here "menu")
(declare-function +ai-anthropic-api-key "gptel")
(defvar +docs-cheatsheet-file)
(defvar +butler--question)
(defvar +butler--offered)
(defvar +butler--offered-hits)

(defvar +butler--answer nil
  "Where the last answer came from, (FILE . LINE), for `+butler/show-source'.")

(defvar +butler-ask-history nil
  "The questions asked so far, for the prompt's history.")

(defun +butler--clear-p (offers)
  "Non-nil when the best of OFFERS stands on its own: there is nothing
else to choose between, or it holds every word of the question and is
clearly ahead of the next thing the words could have meant."
  (let ((best (car offers))
        (next (cadr offers)))
    (or (null next)
        (and (>= (or (plist-get best :coverage) 0) 0.999)
             (> (plist-get best :score) (+ (plist-get next :score) 0.75))))))

(defun +butler--offer (hits)
  "The best of HITS under each section, best first, five at most: one
answer to choose between for each thing the question could have meant.
A key is an answer one can act on, so when two of the hits carry one
the lines of prose stand aside."
  (let* ((keyed (seq-filter (lambda (hit) (plist-get hit :key)) hits))
         (hits (if (cdr keyed) keyed hits))
         seen kept)
    (dolist (hit hits)
      (let ((section (plist-get hit :section)))
        (unless (member section seen)
          (push section seen)
          (push hit kept))))
    (seq-take (nreverse kept) 5)))

(defun +butler--beside (hit hits)
  "HIT and the lines beside it in HITS: under the same section and as
good an answer, three in all at most.  Two keys that do the one job,
split to the right and split below, are worth giving together."
  (let ((section (plist-get hit :section))
        (score (plist-get hit :score))
        (rows 0) (taken nil))
    (dolist (one (cons hit
                       (seq-filter (lambda (other)
                                     (and (not (eq other hit))
                                          (equal (plist-get other :section) section)
                                          (>= (plist-get other :score) (- score 0.01))))
                                   hits))
                 (nreverse taken))
      ;; Only as many as he can hold without growing: the bubble is
      ;; five lines tall before it passes his own height.
      (let ((needs (max 1 (ceiling (length (plist-get one :text))
                                   +butler-bubble-width))))
        (when (and (< (length taken) 3) (<= (+ rows needs) 5))
          (push one taken)
          (setq rows (+ rows needs)))))))

;; Autoloaded: called from menu.el.
;;;###autoload
(defun +butler--answer (hit &optional hits)
  "Say what HIT says, with the lines beside it in HITS when they answer
as well, and remember where it came from."
  (setq +butler--answer (cons (plist-get hit :file) (plist-get hit :line)))
  (+butler--show (mapconcat (lambda (one) (plist-get one :text))
                            (if hits (+butler--beside hit hits) (list hit))
                            "\n")
                 (plist-get hit :section)))

(defun +butler--claude-system ()
  "What Claude is told to be when he answers for the butler.  The docs
bind him only where the question is about this configuration: asked
about the world, he answers about the world, as the man would."
  (format "You are %s, the butler of this Emacs configuration: brief, courteous, precise. \
Answer in one to three sentences. No preamble, no markdown, no lists. \
Address the person as \"%s\", always, and never by any name: not the login name, not \
the full name, not the name on the commits or the electronic mail, whatever the \
question or the surroundings may tell you of it. A butler does not use his employer's \
name. \
When the question is about this Emacs configuration, answer from the lines of its \
documentation given below, naming keys exactly as written there (SPC k b, not Space-k-b), \
and never invent a key or a command that is not in them; say so plainly if they do not \
cover it. A key works where its section says it does and often nowhere else: prefer the \
lines whose section fits the buffer the question is asked from, and when you give a key \
from another section, say where it works, as in \"in an Org document\". Leave out the \
lines that have nothing to do with the question. When the question is about anything else, answer it from your own knowledge, \
as a well read butler would, and do not mention the documentation at all."
          +butler-name +butler-address))

(defun +butler--claude-prompt (question hits)
  "QUESTION and the lines HITS found, as Claude is given them, with the
part of the docs the buffer he was called from belongs to: a key means
one thing in a C++ buffer and another in an Org document."
  (concat "Question: " question "\n\n"
          (when-let* ((here (or +butler--section
                                (and (fboundp '+butler--section-here)
                                     (+butler--section-here)))))
            (format "Asked from a buffer the docs call: %s\n\n" here))
          (if hits
              (concat "What this configuration's docs say, in case the question is about it:\n"
                      (mapconcat (lambda (hit)
                                   (format "- [%s] %s" (plist-get hit :section) (plist-get hit :text)))
                                 hits "\n"))
            "This configuration's docs say nothing that touches the question.")))

(defun +butler--claude-cli (question hits)
  "Put QUESTION and HITS to the Claude Code command line, which is
signed in already, and say what comes back.  Run from the home
directory with no tools: he wants an answer, not an errand."
  (let* ((buffer (generate-new-buffer " *butler claude*"))
         ;; Its warnings go to the error stream; kept apart, they cannot
         ;; end up in the bubble as though he had said them.
         (errors (generate-new-buffer " *butler claude errors*"))
         (default-directory (expand-file-name "~/"))
         (process
          (make-process
           :name "butler-claude"
           :buffer buffer
           :stderr errors
           :noquery t
           :connection-type 'pipe
           :command (list +butler-claude-program
                          "--print" (+butler--claude-prompt question hits)
                          "--allowed-tools" ""
                          "--system-prompt" (+butler--claude-system))
           :sentinel
           (lambda (process _event)
             (unless (process-live-p process)
               (let ((said (with-current-buffer (process-buffer process)
                             (string-trim (buffer-string))))
                     (ok (eq (process-exit-status process) 0)))
                 (kill-buffer (process-buffer process))
                 (when (buffer-live-p errors) (kill-buffer errors))
                 (+butler--show (if (and ok (not (string-empty-p said)))
                                    said
                                  (format "I could not reach Claude, %s: %s"
                                          +butler-address
                                          (if (string-empty-p said) "no answer" said)))
                                "Claude")))))))
    ;; It reads the question from the command line, so nothing is coming
    ;; on its input; told so, it does not wait about for it.
    (process-send-eof process)
    ;; An answer that never comes must not leave him waiting for ever.
    (run-with-timer +butler-claude-seconds nil
                    (lambda ()
                      (when (process-live-p process)
                        (delete-process process))))
    process))

(defun +butler--ask-claude (question hits)
  "Put QUESTION to Claude with HITS as what the docs say, and let him
answer in his own words; the bubble waits meanwhile.  Through gptel
when it has a key of its own, else through the Claude Code command
line, which is signed in already."
  (setq +butler--answer (and hits (cons (plist-get (car hits) :file) (plist-get (car hits) :line))))
  (+butler--show (format "One moment, %s." +butler-address))
  (cond
   ((and (require 'gptel nil t)
         (fboundp 'gptel-request)
         (ignore-errors (+ai-anthropic-api-key)))
    (gptel-request (+butler--claude-prompt question hits)
      :system (+butler--claude-system)
      :callback (lambda (response info)
                  (cond ((stringp response)
                         (+butler--show (string-trim response) "Claude"))
                        ((eq response 'abort))
                        ;; Thinking, or a tool called on the way: the
                        ;; answer is still to come.
                        ((consp response))
                        (t (+butler--show (format "I could not reach Claude, %s: %s"
                                                  +butler-address
                                                  (or (plist-get info :status) "no answer"))))))))
   ((executable-find +butler-claude-program)
    (+butler--claude-cli question hits))
   (t (user-error "%s: I would ask Claude, %s, but neither a key for the API nor %s is here"
                  +butler-name +butler-address +butler-claude-program))))

;;;###autoload
(defun +butler/ask (question &optional claude)
  "Ask him QUESTION, in your words.  He answers from the cheat sheet
and the READMEs: the line that fits the words best, the key when it
is one, and where it says so.  When the words leave it open he offers
the answers that fit in a menu, to choose between, with Claude among
them.  With CLAUDE, a prefix argument, he puts it to Claude at once,
with what he found, and answers in a sentence."
  (interactive (list (read-string (format "%s, at your service. Ask: " +butler-name)
                                  nil '+butler-ask-history)
                     current-prefix-arg))
  (unless (fboundp '+docs-search)
    (user-error "%s: there is nothing to read, %s; the docs module is off"
                +butler-name +butler-address))
  (setq +butler--question question)
  (let ((hits (+docs-search question 12)))
    (cond
     (claude (+butler--ask-claude question hits))
     ((null hits)
      (if (and (require 'gptel nil t) (ignore-errors (+ai-anthropic-api-key)))
          (+butler--ask-claude question nil)
        (setq +butler--answer nil)
        (+butler--show (format "I have nothing on that, %s." +butler-address))))
     ;; The answer is the first offer, the line the clarity was judged
     ;; on, not the best hit: past two keyed hits, a line of prose that
     ;; scored best stands aside.
     ((+butler--clear-p (setq +butler--offered (+butler--offer hits)))
      (+butler--answer (car +butler--offered) hits))
     ;; The words leave it open: he says the best of them and lays the
     ;; rest out in a menu, so the answer is there at once and what
     ;; else the question could have meant is a keypress away, with
     ;; Claude among the choices.
     (t (setq +butler--offered-hits hits)
        (+butler--answer (car +butler--offered) hits)
        ;; A transient prefix expects to have been called as a command.
        (call-interactively #'+butler/choices)))))

;;;###autoload
(defun +butler/ask-claude (question)
  "Ask him QUESTION and have him put it to Claude at once, with the
lines the docs give him: the hard question, without the prefix
argument.  The docs are still all he may answer from."
  (interactive (list (read-string (format "%s, ask Claude: " +butler-name)
                                  nil '+butler-ask-history)))
  (+butler/ask question t))

;;;###autoload
(defun +butler/ask-again ()
  "Put the last question to Claude: what the docs said of it was not
what you meant."
  (interactive)
  (unless +butler--question
    (user-error "%s: you have asked me nothing yet, %s" +butler-name +butler-address))
  (+butler/ask +butler--question t))

;;;###autoload
(defun +butler/show-source ()
  "Open the docs where his last answer came from, the sheet at that
line, or the README."
  (interactive)
  (unless +butler--answer
    (user-error "%s: I have not answered anything yet, %s" +butler-name +butler-address))
  (pcase-let ((`(,file . ,line) +butler--answer))
    (if (equal file +docs-cheatsheet-file)
        ;; get-buffer-window of no buffer is the selected window, so
        ;; without the check a sheet not open at all would open bare,
        ;; without its own mode.
        (progn (unless (when-let* ((buffer (get-file-buffer file)))
                         (get-buffer-window buffer))
                 (+docs/cheatsheet))
               (pop-to-buffer (find-file-noselect file)))
      (find-file file))
    (widen)
    (goto-char (point-min))
    (forward-line (1- line))
    (when (derived-mode-p 'org-mode)
      (org-fold-show-context))
    (recenter)))
