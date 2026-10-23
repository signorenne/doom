;;; private/pascal/autoload/highlight.el -*- lexical-binding: t; -*-
;;
;; What a Pascal buffer shows. opascal-mode colours its keywords, the name
;; after procedure or function, strings and comments, and nothing else;
;; its keywords only in lower case, and among them common names such as
;; index, message, read and write. Types, calls, numbers and {$...}
;; directives look alike. These rules make the parts of a program look
;; like what they are.

(defvar opascal-whitespace)
(declare-function opascal-token-at "opascal")
(declare-function opascal-token-kind "opascal")
(declare-function opascal-token-start "opascal")
(declare-function opascal-token-end "opascal")
(declare-function opascal-next-token "opascal")
(declare-function opascal-previous-token "opascal")
(declare-function opascal-block-start "opascal")

(defconst +pascal-reserved-words
  '("and" "array" "as" "asm" "begin" "case" "class" "const" "constructor"
    "destructor" "dispinterface" "div" "do" "downto" "else" "end" "except"
    "exports" "file" "finalization" "finally" "for" "function" "generic"
    "goto" "if" "implementation" "in" "inherited" "initialization"
    "interface" "is" "label" "library" "mod" "not" "object" "of" "on"
    "operator" "or" "out" "packed" "private" "procedure" "program"
    "property" "protected" "public" "published" "raise" "record" "repeat"
    "resourcestring" "set" "shl" "shr" "specialize" "strict" "then"
    "threadvar" "to" "try" "type" "unit" "until" "uses" "var" "while"
    "with" "xor" "break" "continue" "exit")
  "Words that are keywords wherever they stand, in any case.")

(defconst +pascal-routine-directives
  '("abstract" "assembler" "cdecl" "deprecated" "dynamic" "experimental"
    "export" "external" "final" "forward" "inline" "message" "noreturn"
    "overload" "override" "platform" "register" "reintroduce" "safecall"
    "static" "stdcall" "varargs" "virtual")
  "Directives after a routine's header, keywords only there: message and
register are names anywhere else.")

(defconst +pascal-property-specifiers
  '("read" "write" "default" "nodefault" "stored" "index" "implements")
  "Words that are keywords only in a property declaration.")

(defconst +pascal-builtin-types
  '("integer" "cardinal" "shortint" "smallint" "longint" "int64" "byte"
    "word" "longword" "dword" "qword" "nativeint" "nativeuint" "sizeint"
    "sizeuint" "ptrint" "ptruint" "boolean" "bytebool" "wordbool" "longbool"
    "char" "ansichar" "widechar" "unicodechar" "string" "ansistring"
    "shortstring" "widestring" "unicodestring" "rawbytestring" "utf8string"
    "pchar" "pansichar" "pwidechar" "real" "single" "double" "extended"
    "currency" "comp" "pointer" "variant" "text" "tdatetime" "tstringarray"
    "exception")
  "The built-in types and the few the library makes everyone use.")

(defconst +pascal-constants '("true" "false" "nil" "maxint")
  "Constant words.")

(defun +pascal--words-matcher (words)
  "A font-lock matcher for WORDS as whole words, in any case."
  (let ((re (concat "\\_<" (regexp-opt words t) "\\_>")))
    (lambda (limit)
      (let ((case-fold-search t))
        (re-search-forward re limit t)))))

(defun +pascal--matcher (regexp &optional fold)
  "A font-lock matcher for REGEXP, in any case when FOLD."
  (lambda (limit)
    (let ((case-fold-search fold))
      (re-search-forward regexp limit t))))

(defconst +pascal--identifier "[A-Za-z_][A-Za-z0-9_]*")

;;;###autoload
(defun +pascal-font-lock-keywords ()
  "The font-lock rules for a Pascal buffer, first match first."
  (let ((id +pascal--identifier))
    `(;; {$MODE OBJFPC}: a directive to the compiler, not a comment.
      (,(+pascal--matcher "{\\$[^}]*}\\|(\\*\\$\\(?:[^*]\\|\\*[^)]\\)*\\*)")
       (0 'font-lock-preprocessor-face t))
      ;; The name a routine is declared under: procedure TThing.Go.
      (,(+pascal--matcher
         (concat "\\_<\\(?:procedure\\|function\\|constructor\\|destructor\\|operator\\)\\_>"
                 "[ \t]+\\(?:\\(" id "\\)\\(?:<[^>]*>\\)?\\.\\)?\\(" id "\\|[-+*/=<>]+\\)")
         t)
       (1 'font-lock-type-face nil t)
       (2 'font-lock-function-name-face))
      ;; unit Options; program Hello;
      (,(+pascal--matcher (concat "\\_<\\(?:unit\\|program\\|library\\)[ \t]+\\(" id "\\(?:\\." id "\\)*\\)") t)
       (1 'font-lock-constant-face))
      (,(+pascal--words-matcher +pascal-reserved-words) (0 'font-lock-keyword-face))
      ;; ; virtual; abstract;  and ; overload;
      (,(+pascal--matcher (concat "[;)][ \t]*\\(" (regexp-opt +pascal-routine-directives) "\\)\\_>") t)
       (1 'font-lock-keyword-face))
      ;; property Count: integer read FCount write SetCount;
      (,(+pascal--matcher "^[ \t]*\\(?:class[ \t]+\\)?property\\_>" t)
       (,(+pascal--words-matcher +pascal-property-specifiers)
        nil nil (0 'font-lock-keyword-face)))
      (,(+pascal--words-matcher +pascal-constants) (0 'font-lock-constant-face))
      (,(+pascal--words-matcher '("result" "self")) (0 'font-lock-builtin-face))
      (,(+pascal--words-matcher +pascal-builtin-types) (0 'font-lock-type-face))
      ;; TOptions, EOptionError, IGreeter: the house names for types,
      ;; exceptions and interfaces. A lower case letter must follow, so
      ;; EOF and IO stay names.
      (,(+pascal--matcher "\\_<[TEI][A-Z][A-Za-z0-9_]*[a-z][A-Za-z0-9_]*\\_>")
       (0 'font-lock-type-face))
      ;; Declarations: Name: Type, in a var section or a parameter list.
      (,(+pascal--matcher
         (concat "\\_<\\(" id "\\)[ \t]*:[ \t]*\\(" id "\\(?:\\." id "\\)*\\)"
                 "[ \t]*\\(?:[;)=]\\|$\\|\\_<\\(?:read\\|do\\|of\\)\\_>\\)")
         t)
       (1 'font-lock-variable-name-face)
       (2 'font-lock-type-face))
      ;; And the names before it in a list: X, Y: integer.
      (,(+pascal--matcher
         (concat "\\_<\\(" id "\\)\\(\\(?:[ \t]*,[ \t]*" id "\\)+\\)[ \t]*:[^=]"))
       (1 'font-lock-variable-name-face)
       (,+pascal--identifier
        (progn (goto-char (match-beginning 2)) (match-end 2)) nil
        (0 'font-lock-variable-name-face)))
      ;; $FF, %1010, &17, #13: numbers the default rule does not know.
      (,(+pascal--matcher "\\(?:\\$[0-9A-Fa-f]+\\|%[01]+\\|&[0-7]+\\|#\\$?[0-9A-Fa-f]+\\)\\_>")
       (0 'font-lock-number-face))
      (,(+pascal--matcher "\\_<[0-9]+\\(?:\\.[0-9]+\\)?\\(?:[eE][-+]?[0-9]+\\)?\\_>")
       (0 'font-lock-number-face))
      ;; A call: Format(...), Box.Free(...).
      (,(+pascal--matcher (concat "\\_<\\(" id "\\)[ \t]*("))
       (1 'font-lock-function-call-face))
      ;; A field or a method after a dot: Parsed.Name.
      (,(+pascal--matcher (concat "\\.\\(" id "\\)"))
       (1 'font-lock-property-use-face)))))


;;
;;; Matching blocks

;; begin and end, case and end, try and end, repeat and until: Pascal's
;; brackets. show-paren lights them up as it does ( and ), with the cursor
;; on or right after either.

(defconst +pascal--block-openers '(begin case try repeat asm record class object interface)
  "Tokens a block starts with.")

(defun +pascal--block-token-at-point ()
  "The block keyword token point is on or right after, or nil."
  (seq-find (lambda (token)
              (and token
                   (memq (opascal-token-kind token)
                         `(end until ,@+pascal--block-openers))))
            (list (opascal-token-at (point))
                  (and (> (point) (point-min)) (opascal-token-at (1- (point)))))))

(defun +pascal--composite-p (token)
  "Non-nil when TOKEN, a class, record, object or interface keyword,
starts a type declaration: it follows an =."
  (let ((previous (opascal-previous-token token)))
    (while (and previous (memq (opascal-token-kind previous) opascal-whitespace))
      (setq previous (opascal-previous-token previous)))
    (eq 'equals (opascal-token-kind previous))))

(defun +pascal--opener-p (token)
  "Non-nil when TOKEN opens a block that an end or until closes."
  (let ((kind (opascal-token-kind token)))
    (and (memq kind +pascal--block-openers)
         (or (memq kind '(begin case try repeat asm))
             (+pascal--composite-p token)))))

(defun +pascal--block-end (token)
  "The end or until that closes the block TOKEN opens, or nil."
  (let ((depth 0) (tok token) (limit (+ (point) 200000)))
    (catch 'done
      (while (and (setq tok (opascal-next-token tok))
                  (< (opascal-token-start tok) limit))
        (let ((kind (opascal-token-kind tok)))
          (cond ((+pascal--opener-p tok) (setq depth (1+ depth)))
                ((memq kind '(end until))
                 (if (= depth 0) (throw 'done tok) (setq depth (1- depth)))))))
      nil)))

;;;###autoload
(defun +pascal-show-paren-data ()
  "What show-paren lights: a block keyword and its partner when point is
on one, else the parentheses as usual."
  (or (when-let* (((derived-mode-p 'opascal-mode))
                  ((not (nth 8 (syntax-ppss))))
                  (token (+pascal--block-token-at-point)))
        (let ((partner (if (memq (opascal-token-kind token) '(end until))
                           (opascal-block-start token 'stop-on-class)
                         (and (+pascal--opener-p token) (+pascal--block-end token)))))
          (when partner
            (list (opascal-token-start token) (opascal-token-end token)
                  (opascal-token-start partner) (opascal-token-end partner)
                  nil))))
      (show-paren--default)))
