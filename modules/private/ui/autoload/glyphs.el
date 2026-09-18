;;; private/ui/autoload/glyphs.el -*- lexical-binding: t; -*-
;;
;; The rows in `+ui/glyph-test' are deliberately non-ASCII: they are the
;; sample text used to check that the fonts render.

(declare-function nerd-icons-insert "nerd-icons")
(declare-function nerd-icons-devicon "nerd-icons")
(declare-function nerd-icons-sucicon "nerd-icons")
(declare-function nerd-icons-mdicon "nerd-icons")
(declare-function nerd-icons-faicon "nerd-icons")
(declare-function nerd-icons-octicon "nerd-icons")
(declare-function nerd-icons-codicon "nerd-icons")
(declare-function nerd-icons-wicon "nerd-icons")
(declare-function nerd-icons-powerline "nerd-icons")
(declare-function nerd-icons-pomicon "nerd-icons")

(defun +ui--font-family (spec)
  "Family name of font SPEC, or \"unset\"."
  (or (and spec (font-get spec :family)) "unset"))

(defvar +ui-glyph-families
  '(("mdicon"    . nerd-icons/mdicon-alist)
    ("faicon"    . nerd-icons/faicon-alist)
    ("octicon"   . nerd-icons/octicon-alist)
    ("devicon"   . nerd-icons/devicon-alist)
    ("codicon"   . nerd-icons/codicon-alist)
    ("sucicon"   . nerd-icons/sucicon-alist)
    ("wicon"     . nerd-icons/wicon-alist)
    ("flicon"    . nerd-icons/flicon-alist)
    ("ipsicon"   . nerd-icons/ipsicon-alist)
    ("pomicon"   . nerd-icons/pomicon-alist)
    ("powerline" . nerd-icons/powerline-alist))
  "Nerd Font icon families and the nerd-icons alists that define them.")

;;;###autoload
(defun +ui/insert-glyph (&optional arg)
  "Insert a Nerd Font glyph chosen with completion across all icon sets.
With prefix ARG, insert it propertized (keeps the icon's face)."
  (interactive "P")
  (require 'nerd-icons)
  (nerd-icons-insert arg))

;;;###autoload
(defun +ui/insert-glyph-form ()
  "Insert a form like (nerd-icons-mdicon \"nf-md-robot\") for a chosen glyph.
For writing config: modeline segments, dashboards, org-modern."
  (interactive)
  (require 'nerd-icons)
  (let* ((family (completing-read "Icon family: "
                                  (mapcar #'car +ui-glyph-families) nil t))
         (alist (symbol-value (cdr (assoc family +ui-glyph-families))))
         (candidates (mapcar (lambda (cell)
                               (format "%s %s" (cdr cell) (car cell)))
                             alist))
         (choice (completing-read (format "%s glyph: " family)
                                  candidates nil t))
         (name (cadr (split-string choice " "))))
    (insert (format "(nerd-icons-%s \"%s\")" family name))))

;;;###autoload
(defun +ui/glyph-test ()
  "Open a buffer that renders icons, emoji, symbols and operators.
Anything shown as a box is a missing glyph."
  (interactive)
  (require 'nerd-icons)
  (let ((buf (get-buffer-create "*glyph-test*"))
        (rows
         `(("Nerd devicon"  . ,(list (nerd-icons-devicon "nf-dev-emacs")
                                     (nerd-icons-devicon "nf-dev-git")
                                     (nerd-icons-devicon "nf-dev-cplusplus")
                                     (nerd-icons-devicon "nf-dev-cmake")))
           ("Nerd sucicon"  . ,(list (nerd-icons-sucicon "nf-custom-emacs")
                                     (nerd-icons-sucicon "nf-custom-cpp")
                                     (nerd-icons-sucicon "nf-custom-c")))
           ("Nerd mdicon"   . ,(list (nerd-icons-mdicon "nf-md-robot")
                                     (nerd-icons-mdicon "nf-md-brain")
                                     (nerd-icons-mdicon "nf-md-chip")
                                     (nerd-icons-mdicon "nf-md-language_cpp")
                                     (nerd-icons-mdicon "nf-md-file_document")))
           ("Nerd faicon"   . ,(list (nerd-icons-faicon "nf-fa-github")
                                     (nerd-icons-faicon "nf-fa-check")
                                     (nerd-icons-faicon "nf-fa-terminal")
                                     (nerd-icons-faicon "nf-fa-microchip")))
           ("Nerd octicon"  . ,(list (nerd-icons-octicon "nf-oct-mark_github")
                                     (nerd-icons-octicon "nf-oct-bug")
                                     (nerd-icons-octicon "nf-oct-rocket")
                                     (nerd-icons-octicon "nf-oct-project")))
           ("Nerd codicon"  . ,(list (nerd-icons-codicon "nf-cod-terminal")
                                     (nerd-icons-codicon "nf-cod-debug")
                                     (nerd-icons-codicon "nf-cod-symbol_method")))
           ("Nerd weather"  . ,(list (nerd-icons-wicon "nf-weather-day_sunny")))
           ("Nerd powerline". ,(list (nerd-icons-powerline "nf-pl-left_hard_divider")
                                     (nerd-icons-powerline "nf-pl-right_hard_divider")))
           ("Nerd pomicon"  . ,(list (nerd-icons-pomicon "nf-pom-pomodoro_done")))
           ("Emoji"         . ("😀" "🚀" "✅" "🧠" "🔧" "📚" "🇮🇹"))
           ("Box drawing"   . ("┌─┬─┐ │ ├─┼─┤ └─┴─┘" "╔═╦═╗ ║ ╠═╬═╣ ╚═╩═╝" "▁▂▃▄▅▆▇█ ░▒▓"))
           ("Arrows"        . ("← → ↑ ↓ ↔ ⇐ ⇒ ⇔ ⇨ ➜ ➤ ⟶ ⤴ ⤵ ↩ ↪"))
           ("Math / Greek"  . ("∀ ∃ ∈ ∉ ∑ ∏ ∫ √ ∞ ≠ ≤ ≥ ≈ ≡ ¬ ∧ ∨ ⊕ λ π Σ Ω μ ∂ ∇"))
           ("Symbols"       . ("✓ ✗ ★ ☆ ♥ ♦ ☰ ☑ ☒ ⚠ ⚡ ⚙ ⏻ ⌘ ⌥ ⇧ ⌫ ⏎ ␣ ⏱"))
           ("Operators"     . ("-> => != === <= >= :: |> <| <> ++ -- ** // /* */ <!-- --> www"))
           ("Powerline/PUA" . ("        ")))))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (propertize "Glyph rendering test\n" 'face 'bold)
                "No row should show empty boxes. SPC h ' tells you which font\n"
                "draws the glyph at point. Operators stay as typed:\n"
                "ligatures are off in this config.\n\n")
        (dolist (row rows)
          (insert (format "%-16s" (concat (car row) ":")))
          (insert (mapconcat #'identity (cdr row) "  ") "\n"))
        (insert (format "\nFonts: %s, symbol %s, emoji %s\n"
                        (face-attribute 'default :family)
                        (+ui--font-family doom-symbol-font)
                        (+ui--font-family doom-emoji-font))))
      (special-mode))
    (pop-to-buffer buf)))
