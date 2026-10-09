;;; private/pascal/autoload/indent.el -*- lexical-binding: t; -*-
;;
;; opascal-mode's indentation, brought to what the formatter writes: the
;; Lazarus IDE's JEDI Code Format with the settings in jcfsettings.cfg.
;; Typing and SPC c f then agree, so formatting moves nothing a key had
;; already put right.

(defvar opascal-indent-level)
(defvar opascal-case-label-indent)
(defvar opascal-whitespace)
(defvar opascal-comments)
(defvar opascal-composite-types)
(defvar opascal-visibilities)
(defvar opascal-unit-sections)
(defvar opascal-unit-statements)
(defvar opascal-decl-sections)
(defvar opascal-routine-statements)
(defvar opascal-expr-statements)
(defvar opascal-expr-delimiters)
(defvar opascal-block-statements)
(defvar opascal-mid-block-statements)
(defvar opascal-end-block-statements)
(declare-function opascal-current-token "opascal")
(declare-function opascal-token-at "opascal")
(declare-function opascal-token-start "opascal")
(declare-function opascal-next-token "opascal")
(declare-function opascal-previous-token "opascal")
(declare-function opascal-token-kind "opascal")
(declare-function opascal-group-start "opascal")
(declare-function opascal-block-start "opascal")
(declare-function opascal-else-start "opascal")
(declare-function opascal-composite-type-start "opascal")
(declare-function opascal-line-indent-of "opascal")
(declare-function opascal-stmt-line-indent-of "opascal")

(defconst +pascal--routine-kinds '(procedure function constructor destructor)
  "The keywords a routine header starts with.")

(defun +pascal--previous-solid (token)
  "The token before TOKEN that is neither whitespace nor a comment."
  (let ((previous (opascal-previous-token token)))
    (while (and previous (memq (opascal-token-kind previous) opascal-whitespace))
      (setq previous (opascal-previous-token previous)))
    previous))

(defun +pascal--next-solid (token)
  "The token after TOKEN that is neither whitespace nor a comment."
  (let ((next (opascal-next-token token)))
    (while (and next (memq (opascal-token-kind next) opascal-whitespace))
      (setq next (opascal-next-token next)))
    next))

(defun +pascal--routine-start-p (token)
  "Non-nil when TOKEN begins a routine header: procedure, function and
the rest, or class before one of them."
  (let ((kind (opascal-token-kind token)))
    (or (memq kind +pascal--routine-kinds)
        ;; Not `opascal-next-visible-token': it asks for the token after
        ;; the same one again and again, and loops for ever on a space.
        (and (eq kind 'class)
             (memq (opascal-token-kind (+pascal--next-solid token))
                   +pascal--routine-kinds)))))

(defun +pascal--routine-header-p (token)
  "Non-nil when TOKEN, a procedure or function keyword, starts a header,
not a procedural type after = or a variable of one after :."
  (let ((previous (+pascal--previous-solid token)))
    (or (null previous)
        (memq (opascal-token-kind previous)
              `(semicolon class ,@opascal-unit-sections ,@opascal-visibilities
                          ,@opascal-decl-sections)))))

(defun +pascal--in-interface-p ()
  "Non-nil when point is in a unit's interface section."
  (save-excursion
    (let ((case-fold-search t))
      (and (re-search-backward "^[ \t]*\\(interface\\|implementation\\)\\_>" nil t)
           (string-equal (downcase (match-string 1)) "interface")))))

(defun +pascal--routine-indent (token)
  "Where the routine header starting with TOKEN goes, or nil to leave it
to opascal, as inside a class.  At the level of the unit or the program
it is 0; declared inside another routine, one level in from that one.
opascal indented every header after a type, var or const section as if
it were a declaration of that section."
  (let ((interface (+pascal--in-interface-p))
        (nested 0) (last token) (tok token))
    (catch 'done
      (while (setq tok (opascal-previous-token tok))
        (let ((kind (opascal-token-kind tok)))
          (unless (memq kind opascal-whitespace)
            (cond
             ((eq kind 'close-group) (setq tok (opascal-group-start tok)))
             ((eq kind 'open-group) (throw 'done nil))
             ((memq kind opascal-end-block-statements)
              ;; An end at the margin closes a routine of the unit or the
              ;; program, so what follows it is at the top level.
              (when (and (= nested 0) (not interface)
                         (eq 'newline (opascal-token-kind (opascal-previous-token tok))))
                (throw 'done 0))
              (let ((start (opascal-block-start tok 'stop-on-class)))
                (if (memq (opascal-token-kind start) opascal-composite-types)
                    ;; A class or record ended: step past its "=" too.
                    (setq tok (+pascal--previous-solid start))
                  ;; A routine's body ended: its header is further back.
                  (setq nested (1+ nested)
                        tok start))))
             ((eq kind 'forward) (setq nested (1+ nested)))
             ((memq kind opascal-visibilities) (throw 'done nil))
             ((opascal-composite-type-start tok last) (throw 'done nil))
             ((memq kind opascal-block-statements) (throw 'done nil))
             ((eq kind 'interface)
              ;; The unit section, unless "= interface" starts a type.
              (throw 'done (unless (eq 'equals (opascal-token-kind
                                                  (+pascal--previous-solid tok)))
                             0)))
             ((memq kind opascal-unit-sections) (throw 'done 0))
             ((and (memq kind +pascal--routine-kinds) (not interface)
                   (+pascal--routine-header-p tok))
              (if (> nested 0)
                  (setq nested (1- nested))
                (throw 'done (opascal-line-indent-of tok opascal-indent-level))))))
          (when (and tok (not (memq (opascal-token-kind tok) opascal-whitespace)))
            (setq last tok))))
      0)))

(defun +pascal--open-expression (token)
  "The if, while, for, case or on whose expression TOKEN's line goes on
with, still waiting for its then, do or of; nil when it is not one."
  (unless (memq (opascal-token-kind token) opascal-expr-delimiters)
    (let ((tok token)
          (stops `(open-group semicolon else ,@opascal-expr-delimiters
                              ,@opascal-block-statements ,@opascal-mid-block-statements
                              ,@opascal-end-block-statements ,@opascal-decl-sections
                              ,@opascal-routine-statements ,@opascal-unit-statements)))
      (catch 'done
        (while (setq tok (opascal-previous-token tok))
          (let ((kind (opascal-token-kind tok)))
            (cond ((memq kind opascal-whitespace))
                  ((eq kind 'close-group) (setq tok (opascal-group-start tok)))
                  ((memq kind opascal-expr-statements) (throw 'done tok))
                  ((memq kind stops) (throw 'done nil)))))
        nil))))

;;;###autoload
(defun +pascal--indentation-a (fn)
  "The indentation FN, opascal's, works out for this line, with the rules
the formatter keeps where opascal has others of its own."
  (let* ((indent (funcall fn))
         (token (opascal-current-token))
         (kind (and token (opascal-token-kind token))))
    (or (cond
         ((null token) nil)
         ((+pascal--routine-start-p token)
          (+pascal--routine-indent token))
         ;; A comment starting on this line before a routine header goes
         ;; with the header, as the formatter keeps it.
         ((and (memq kind opascal-comments)
               (= (opascal-token-start token) (point)))
          (let ((next (+pascal--next-solid token)))
            (when (and next (+pascal--routine-start-p next))
              (+pascal--routine-indent next))))
         ;; A line inside an unmatched ( or [ goes one level in from the
         ;; statement's line, as the formatter writes a parameter list or
         ;; an enumeration broken over lines, not under the first item.
         ((and (not (eq kind 'close-group))
               (nth 1 (syntax-ppss)))
          (opascal-stmt-line-indent-of (opascal-token-at (nth 1 (syntax-ppss)))
                                       opascal-indent-level))
         ;; A case's else sits with the labels, not under the case.
         ((and (eq kind 'else)
               (eq 'case (opascal-token-kind (opascal-else-start token))))
          (+ indent opascal-case-label-indent))
         ;; A begin under a case label sits with the label.
         ((and (eq kind 'begin)
               (eq 'colon (opascal-token-kind (+pascal--previous-solid token))))
          (opascal-line-indent-of (+pascal--previous-solid token) 0))
         ;; A condition broken over lines goes on one level in from its
         ;; statement's line, not two past its first word: after
         ;; "else if" that was twenty columns out.
         (t
          (when-let* ((statement (+pascal--open-expression token)))
            (opascal-stmt-line-indent-of statement opascal-indent-level))))
        indent)))

;;;###autoload
(defun +pascal--open-group-indent-a (token _last-token &optional _offset)
  "A line inside an unmatched ( or [ at TOKEN goes one level in from the
statement's line, as the formatter writes it, not under the first
argument."
  (when (eq 'open-group (opascal-token-kind token))
    (opascal-stmt-line-indent-of token opascal-indent-level)))
