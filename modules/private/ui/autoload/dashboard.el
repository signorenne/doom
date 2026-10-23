;;; private/ui/autoload/dashboard.el -*- lexical-binding: t; -*-
;;
;; The top of the dashboard: the name as a banner that is alive, a ripple
;; running through the letters and a wave of colour behind it, then the
;; greeting a module registers (the butler's, when he is on), and the
;; date as it would be announced. Plain characters only, so a terminal
;; frame draws what the GUI does; only the size of the type differs.

(defvar +dashboard-name)
(defvar +ui-banner-name)
(defvar +ui-dashboard-greeting-function)
(defvar +ui-dashboard-tick-hook)
(declare-function doom-color "doom-themes")
(declare-function doom-blend "doom-themes")

;; The widgets are laid out in an 80-column block, then handed to Doom's
;; dashboard for their horizontal alignment.

(defun +ui--dashboard-width ()
  "The columns the dashboard is laid out in."
  80)

(defun +ui--dashboard-centre-from (start)
  "Centre the dashboard text inserted since START with Doom's layout."
  (let ((text (delete-and-extract-region start (point))))
    (+dashboard-insert (string-remove-suffix "\n" text))))

(defun +ui--centre (text)
  "TEXT centred in the dashboard, as Doom centres its own lines."
  (concat (make-string (ceiling (max 0 (- (+ui--dashboard-width) (length text))) 2)
                       ?\s)
          text))

(defun +ui--dashboard-frame ()
  "The frame showing the dashboard, else the selected one."
  (if-let* ((window (get-buffer-window +dashboard-name 'visible)))
      (window-frame window)
    (selected-frame)))

;;
;;; The banner

(defvar +ui-banner nil
  "Lines to draw in place of the name, one string per line, for art of
your own.  Nil, and the banner is `+ui-banner-name' in the font.")

(defconst +ui-banner-font
  '(
    (?a "       " "  mmm  " " \"   # " " m\"\"\"# " " \"mm\"# " "       " "       ")
    (?b " #     " " #mmm  " " #\" \"# " " #   # " " ##m#\" " "       " "       ")
    (?c "       " "  mmm  " " #\"  \" " " #     " " \"#mm\" " "       " "       ")
    (?d "     # " "  mmm# " " #\" \"# " " #   # " " \"#m## " "       " "       ")
    (?e "       " "  mmm  " " #\"  # " " #\"\"\"\" " " \"#mm\" " "       " "       ")
    (?f "   m\"\" " " mm#mm " "   #   " "   #   " "   #   " "       " "       ")
    (?g "       " "  mmmm " " #\" \"# " " #   # " " \"#m\"# " "  m  # " "   \"\"  ")
    (?h " #     " " # mm  " " #\"  # " " #   # " " #   # " "       " "       ")
    (?i "   \"   " " mmm   " "   #   " "   #   " " mm#mm " "       " "       ")
    (?j "    \"  " "  mmm  " "    #  " "    #  " "    #  " "    #  " "  \"\"   ")
    (?k " #     " " #   m " " # m\"  " " #\"#   " " #  \"m " "       " "       ")
    (?l " \"\"#   " "   #   " "   #   " "   #   " "   \"mm " "       " "       ")
    (?m "       " " mmmmm " " # # # " " # # # " " # # # " "       " "       ")
    (?n "       " " m mm  " " #\"  # " " #   # " " #   # " "       " "       ")
    (?o "       " "  mmm  " " #\" \"# " " #   # " " \"#m#\" " "       " "       ")
    (?p "       " " mmmm  " " #\" \"# " " #   # " " ##m#\" " " #     " " \"     ")
    (?q "       " "  mmmm " " #\" \"# " " #   # " " \"#m## " "     # " "     \" ")
    (?r "       " "  m mm " "  #\"  \"" "  #    " "  #    " "       " "       ")
    (?s "       " "  mmm  " " #   \" " "  \"\"\"m " " \"mmm\" " "       " "       ")
    (?t "   m   " " mm#mm " "   #   " "   #   " "   \"mm " "       " "       ")
    (?u "       " " m   m " " #   # " " #   # " " \"mm\"# " "       " "       ")
    (?v "       " " m   m " " \"m m\" " "  #m#  " "   #   " "       " "       ")
    (?w "       " "m     m" "\"m m m\"" " #m#m# " "  # #  " "       " "       ")
    (?x "       " " m   m " "  #m#  " "  m#m  " " m\" \"m " "       " "       ")
    (?y "       " " m   m " " \"m m\" " "  #m#  " "  \"#   " "  m\"   " " \"\"    ")
    (?z "       " " mmmmm " "    m\" " "  m\"   " " #mmmm " "       " "       ")
    (?A "   mm  " "   ##  " "  #  # " "  #mm# " " #    #" "       " "       ")
    (?B " mmmmm " " #    #" " #mmmm\"" " #    #" " #mmmm\"" "       " "       ")
    (?C "   mmm " " m\"   \"" " #     " " #     " "  \"mmm\"" "       " "       ")
    (?D " mmmm  " " #   \"m" " #    #" " #    #" " #mmm\" " "       " "       ")
    (?E " mmmmmm" " #     " " #mmmmm" " #     " " #mmmmm" "       " "       ")
    (?F " mmmmmm" " #     " " #mmmmm" " #     " " #     " "       " "       ")
    (?G "   mmm " " m\"   \"" " #   mm" " #    #" "  \"mmm\"" "       " "       ")
    (?H " m    m" " #    #" " #mmmm#" " #    #" " #    #" "       " "       ")
    (?I " mmmmm " "   #   " "   #   " "   #   " " mm#mm " "       " "       ")
    (?J "   mmm " "     # " "     # " "     # " " \"mmm\" " "       " "       ")
    (?K " m    m" " #  m\" " " #m#   " " #  #m " " #   \"m" "       " "       ")
    (?L " m     " " #     " " #     " " #     " " #mmmmm" "       " "       ")
    (?M " m    m" " ##  ##" " # ## #" " # \"\" #" " #    #" "       " "       ")
    (?N " mm   m" " #\"m  #" " # #m #" " #  # #" " #   ##" "       " "       ")
    (?O "  mmmm " " m\"  \"m" " #    #" " #    #" "  #mm# " "       " "       ")
    (?P " mmmmm " " #   \"#" " #mmm#\"" " #     " " #     " "       " "       ")
    (?Q "  mmmm " " m\"  \"m" " #    #" " #    #" "  #mm#\"" "     # " "       ")
    (?R " mmmmm " " #   \"#" " #mmmm\"" " #   \"m" " #    \"" "       " "       ")
    (?S "  mmmm " " #\"   \"" " \"#mmm " "     \"#" " \"mmm#\"" "       " "       ")
    (?T "mmmmmmm" "   #   " "   #   " "   #   " "   #   " "       " "       ")
    (?U " m    m" " #    #" " #    #" " #    #" " \"mmmm\"" "       " "       ")
    (?V " m    m" " \"m  m\"" "  #  # " "  \"mm\" " "   ##  " "       " "       ")
    (?W "m     m" "#  #  #" "\" #\"# #" " ## ##\"" " #   # " "       " "       ")
    (?X " m    m" "  #  # " "   ##  " "  m\"\"m " " m\"  \"m" "       " "       ")
    (?Y "m     m" " \"m m\" " "  \"#\"  " "   #   " "   #   " "       " "       ")
    (?Z " mmmmmm" "     #\"" "   m#  " "  m\"   " " ##mmmm" "       " "       ")
    (?0 "  mmmm " " m\"  \"m" " #  m #" " #    #" "  #mm# " "       " "       ")
    (?1 " mmm   " "   #   " "   #   " "   #   " " mm#mm " "       " "       ")
    (?2 "  mmmm " " \"   \"#" "     m\"" "   m\"  " " m#mmmm" "       " "       ")
    (?3 "  mmmm " " \"   \"#" "   mmm\"" "     \"#" " \"mmm#\"" "       " "       ")
    (?4 "    mm " "   m\"# " "  #\" # " " #mmm#m" "     # " "       " "       ")
    (?5 " mmmmm " " #     " " \"\"\"\"mm" "      #" " \"mmm#\"" "       " "       ")
    (?6 "   mmm " " m\"   \"" " #m\"\"#m" " #    #" "  #mm#\"" "       " "       ")
    (?7 " mmmmmm" "     #\"" "    m\" " "   m\"  " "  m\"   " "       " "       ")
    (?8 "  mmmm " " #    #" " \"mmmm\"" " #   \"#" " \"#mmm\"" "       " "       ")
    (?9 "  mmmm " " #\"  \"m" " #m  m#" "  \"\"\" #" " \"mmm\" " "       " "       ")
    (?- "       " "       " "       " "  \"\"\"  " "       " "       " "       ")
    (?_ "       " "       " "       " "       " "       " "       " "\"\"\"\"\"\" ")
    (?. "       " "       " "       " "       " "   #   " "       " "       ")
    (?+ "       " "   m   " "   #   " "\"\"\"#\"\"\"" "   #   " "       " "       ")
    (?\s "       " "       " "       " "       " "       " "       " "       "))
  "The letters, the ascii9 figlet font: seven rows of seven columns each,
so a name is drawn by laying its glyphs side by side.  A character the
font has none for is drawn as a space.")

(defvar +ui-banner-gradient '(blue . magenta)
  "Two theme colours the wave runs between.
Names `doom-color' knows; without a Doom theme the banner keeps Doom's
own face.")

(defvar +ui-banner-wave-steps 24
  "How many colours the wave is made of.")

(defvar +ui-banner-ripple-letters 6
  "Letters from one crest of the ripple to the next.")

(defvar +ui-banner-ripple-speed 0.25
  "Letters the ripple advances per tick.")

(defvar +ui--letters nil
  "For every column of the banner, which letter it belongs to.")

(defvar +ui--palette nil
  "Faces of the wave, from the first colour to the second and back.")

(defvar +ui--frames nil
  "The banner at every phase of one ripple, a vector of row lists.
The ripple repeats every `+ui--ripple-period' ticks, so the rows are
computed once and a tick only picks its frame.")

(defvar +ui--runs nil
  "For every phase of the wave, the runs of columns that share a colour,
a vector of lists of (START END INDEX).  The wave repeats every banner
width of ticks.")

(defvar +ui--rows nil
  "The banner's lines, all of one width.  The ripple and the wave ask
for them a thousand times a drawing, so the name is set in the font
once and they read it here.")

(defun +ui--trim-blank (rows)
  "ROWS without the blank lines above and below the letters: a name with
no dot over an i and no tail under a g needs neither."
  (let* ((top (seq-drop-while #'string-blank-p rows))
         (bottom (seq-drop-while #'string-blank-p (reverse top))))
    (nreverse bottom)))

(defun +ui--name-rows (name)
  "NAME set in `+ui-banner-font', one string per row."
  (when-let* ((glyphs (mapcar (lambda (char)
                                (or (alist-get char +ui-banner-font)
                                    (alist-get ?\s +ui-banner-font)))
                              (string-to-list name))))
    (+ui--trim-blank
     (apply #'cl-mapcar (lambda (&rest row) (apply #'concat row)) glyphs))))

(defun +ui--rows ()
  "Compute `+ui--rows': the name in the font, or `+ui-banner' when art is
set by hand, every line padded out to the widest."
  (let* ((name (or +ui-banner-name (user-login-name)))
         (lines (or +ui-banner (+ui--name-rows name) (list " ")))
         (width (max 1 (apply #'max (mapcar #'length lines)))))
    (setq +ui--rows
          (mapcar (lambda (line)
                    (concat line (make-string (- width (length line)) ?\s)))
                  lines))))

(defun +ui--banner-width ()
  "Width of the banner; every line is padded out to it."
  (length (car (+ui--banner-rows))))

(defun +ui--banner-rows ()
  "The letters as rows of equal width."
  (or +ui--rows (+ui--rows)))

(defun +ui--letters ()
  "Compute `+ui--letters': columns that are blank on every row split the
letters, so each letter moves as one piece and keeps its shape."
  (let* ((rows (+ui--banner-rows))
         (width (+ui--banner-width))
         (letters (make-vector width 0))
         (letter 0)
         (in-letter nil))
    (dotimes (col width)
      (let ((blank (cl-every (lambda (row) (= (aref row col) ?\s)) rows)))
        (when (and in-letter blank) (cl-incf letter))
        (setq in-letter (not blank))
        (aset letters col letter)))
    (setq +ui--letters letters)))

(defun +ui--ripple-shift (column phase)
  "How many rows COLUMN's letter is lifted at PHASE: 1, 0 or -1."
  (let ((letter (aref +ui--letters column)))
    (round (sin (* 2 float-pi
                   (/ (+ letter (* phase +ui-banner-ripple-speed))
                      (float +ui-banner-ripple-letters)))))))

(defun +ui--rippled-rows (phase)
  "The banner at PHASE: one row above and below, each column moved a little.
This is what makes it move: the letters keep their shape, the wave rolls
through them."
  (let* ((rows (+ui--banner-rows))
         (count (length rows))
         (width (+ui--banner-width)))
    (cl-loop for row from -1 to count
             collect (let ((line (make-string width ?\s)))
                       (dotimes (col width)
                         (let ((source (- row (+ui--ripple-shift col phase))))
                           (when (< -1 source count)
                             (aset line col (aref (nth source rows) col)))))
                       line))))

(defun +ui--ripple-period ()
  "Ticks after which the ripple is back where it started."
  (max 1 (round (/ +ui-banner-ripple-letters +ui-banner-ripple-speed))))

(defun +ui--frames ()
  "Compute `+ui--frames', one frame per phase of the ripple."
  (setq +ui--frames
        (vconcat (cl-loop for phase below (+ui--ripple-period)
                          collect (+ui--rippled-rows phase)))))

(defun +ui--frame (tick)
  "The rows of the banner at TICK."
  (aref +ui--frames (mod tick (length +ui--frames))))

(defun +ui--palette ()
  "Compute `+ui--palette' from the theme, or nil when there is no theme."
  (setq +ui--palette
        (when-let* (((fboundp 'doom-blend))
                    (from (ignore-errors
                            (doom-color (car +ui-banner-gradient))))
                    (to (ignore-errors
                          (doom-color (cdr +ui-banner-gradient)))))
          (cl-loop for i below +ui-banner-wave-steps
                   for pos = (/ (float i) +ui-banner-wave-steps)
                   ;; Up to the second colour and back down, so it loops.
                   for mix = (if (< pos 0.5) (* 2 pos) (* 2 (- 1 pos)))
                   collect (list :foreground (doom-blend to from mix))))))

(defun +ui--wave-index (column phase)
  "Which palette entry COLUMN gets when the wave is at PHASE."
  (/ (* (mod (+ column phase) (+ui--banner-width)) +ui-banner-wave-steps)
     (+ui--banner-width)))

(defun +ui--wave-runs (phase)
  "The runs of columns sharing a colour at PHASE, as (START END INDEX)."
  (let ((width (+ui--banner-width)) (col 0) runs)
    (while (< col width)
      (let ((index (+ui--wave-index col phase))
            (start col))
        (while (and (< col width) (= index (+ui--wave-index col phase)))
          (cl-incf col))
        (push (list start col index) runs)))
    (nreverse runs)))

(defun +ui--runs ()
  "Compute `+ui--runs', the wave's runs for every phase."
  (setq +ui--runs
        (vconcat (cl-loop for phase below (+ui--banner-width)
                          collect (+ui--wave-runs phase)))))

(defun +ui--banner-lines ()
  "Regions of the banner lines, each with its centring offset."
  (save-excursion
    (goto-char (point-min))
    (let (lines match)
      (while (setq match (text-property-search-forward '+ui-banner))
        (push (list (prop-match-beginning match)
                    (prop-match-end match)
                    (prop-match-value match))
              lines))
      (nreverse lines))))

(defun +ui--colour-banner (phase)
  "Colour every banner line for wave PHASE, a run of columns at a time."
  (when +ui--palette
    (let ((runs (aref +ui--runs (mod phase (length +ui--runs)))))
      (pcase-dolist (`(,start ,end ,offset) (+ui--banner-lines))
        (let ((base (+ start offset)))
          (pcase-dolist (`(,from ,to ,index) runs)
            (when (< (+ base from) end)
              (put-text-property (+ base from) (min end (+ base to))
                                 'face (nth index +ui--palette)))))))))

(defun +ui--redraw-banner (phase)
  "Put the banner at PHASE in place of the one on screen, then colour it."
  (let ((rows (+ui--frame phase)))
    (pcase-dolist (`(,start ,end ,offset) (+ui--banner-lines))
      (let ((props (text-properties-at start)))
        (save-excursion
          (goto-char start)
          (insert (apply #'propertize
                         (concat (make-string offset ?\s) (pop rows))
                         props))
          (delete-region (point) (+ (point) (- end start)))))))
  (+ui--colour-banner phase))

;;;###autoload
(defun +ui-dashboard-banner ()
  "Draw the banner centred, the way Doom draws its own ASCII banner.
Every line is marked with how many spaces the centring put in front, so
the ripple and the wave know where the letters start."
  (+ui--palette)
  ;; From scratch, so a name set since the last drawing is the one drawn.
  (+ui--rows)
  (+ui--letters)
  (+ui--frames)
  (+ui--runs)
  ;; At the current tick, so a reload of the dashboard does not restart
  ;; the ripple with a jump.
  (let ((block-start (point)))
    (dolist (row (+ui--frame +ui--tick))
      (let* ((centred (+ui--centre row))
             (offset (- (length centred) (length row)))
             (start (point)))
        (insert centred "\n")
        (add-text-properties start (1- (point))
                             (list 'face '+dashboard-banner
                                   '+ui-banner offset))))
    (+ui--dashboard-centre-from block-start))
  (+ui--colour-banner +ui--tick))


;;
;;; The greeting

(defface +ui-greeting
  '((t :inherit +dashboard-footer :weight bold))
  "The greeting above the date. It keeps the normal size, since a bubble
drawn in characters round it would break with larger type."
  :group '+dashboard)

(defface +ui-date
  '((t :inherit +dashboard-loaded :height 1.15))
  "The date under the greeting."
  :group '+dashboard)

(defun +ui--centre-scaled (text scale)
  "TEXT centred in the dashboard when drawn SCALE times the normal width.
Doom's centring counts columns; larger type needs fewer spaces in front.
Measured on the frame that shows the dashboard: the timer that redraws
the clock may fire while a terminal client is selected."
  (let ((shown (if (display-graphic-p (+ui--dashboard-frame))
                   (* scale (length text))
                 (length text))))
    (concat (make-string (max 0 (ceiling (- (+ui--dashboard-width) shown) 2)) ?\s)
            text)))

(defun +ui--ordinal (n)
  "N with its English suffix: 1st, 2nd, 3rd, 4th, 11th, 21st."
  (format "%d%s" n
          (if (<= 11 (% n 100) 13) "th"
            (pcase (% n 10) (1 "st") (2 "nd") (3 "rd") (_ "th")))))

(defun +ui--greeting-date ()
  "The date the way it is announced: Tuesday, the 15th of September 2026."
  (let ((system-time-locale "C")
        (now (decode-time)))
    (format "%s, the %s of %s %d, at %02d:%02d"
            (format-time-string "%A")
            (+ui--ordinal (decoded-time-day now))
            (format-time-string "%B")
            (decoded-time-year now)
            (decoded-time-hour now)
            (decoded-time-minute now))))

;;;###autoload
(defun +ui-dashboard-greeting ()
  "Dashboard widget: the greeting `+ui-dashboard-greeting-function'
inserts, when a module set one, a blank line, then the date. The date
line is marked so the clock can be kept."
  (let ((block-start (point)))
    (insert "\n")
    (when +ui-dashboard-greeting-function
      (funcall +ui-dashboard-greeting-function (+ui--dashboard-width)))
    (insert "\n")
    (let ((start (point)))
      (insert (+ui--centre-scaled (+ui--greeting-date) 1.15))
      (add-text-properties start (point)
                           '(face +ui-date +ui-clock t)))
    (insert "\n")
    (+ui--dashboard-centre-from block-start))
  (+ui--dashboard-animate))


;;
;;; Animation

(defvar +ui-dashboard-animate t
  "Whether the ripple and the wave run and the clock keeps the minute.")

(defvar +ui-dashboard-tick-interval 0.1
  "Seconds between two steps of the animation.")

(defvar +ui--dashboard-timer nil
  "The timer behind the animation, while the dashboard exists.")

(defvar +ui--tick 0
  "How many ticks the animation has run; the phase of the ripple and the
wave, kept across a reload of the dashboard.")

(defun +ui--dashboard-region (property)
  "Start and end of the first text carrying PROPERTY, or nil."
  (save-excursion
    (goto-char (point-min))
    (when-let* ((match (text-property-search-forward property)))
      (cons (prop-match-beginning match) (prop-match-end match)))))

(defun +ui--replace-region (region text)
  "Put TEXT in place of REGION, keeping the properties that were there."
  (let ((props (text-properties-at (car region))))
    (save-excursion
      (goto-char (car region))
      (insert (apply #'propertize text props))
      (delete-region (point) (+ (point) (- (cdr region) (car region)))))))

(defun +ui--dashboard-animate ()
  "Start the ticks, unless they are running already.
Every tick makes Emacs redisplay, so the ticks run only while someone
can see the dashboard: `+ui--dashboard-tick' stops them when nobody
can, and `+ui--dashboard-shown-h' starts them again."
  (when (and +ui-dashboard-animate (not noninteractive)
             (+ui--dashboard-visible-p))
    (unless (timerp +ui--dashboard-timer)
      (setq +ui--dashboard-timer
            (run-with-timer +ui-dashboard-tick-interval
                            +ui-dashboard-tick-interval
                            #'+ui--dashboard-tick)))))

(defun +ui--dashboard-visible-p ()
  "Non-nil when someone can see the dashboard.
A daemon's initial frame is `terminal-frame': it counts as visible and
always shows the dashboard, so it is not a viewer, or the ticks would run
with no client frame open."
  (when-let* ((buffer (get-buffer +dashboard-name)))
    (seq-some (lambda (window)
                (not (eq (window-frame window) terminal-frame)))
              (get-buffer-window-list buffer nil 'visible))))

;;;###autoload
(defun +ui--dashboard-shown-h (&rest _)
  "On `window-buffer-change-functions': the dashboard back on screen, the
animation starts again."
  (when (and (not (timerp +ui--dashboard-timer))
             (+ui--dashboard-visible-p))
    (+ui--dashboard-animate)))

(defun +ui--dashboard-tick ()
  "One step: the ripple and the wave move on, the clock every second or so.
Only while the dashboard is on screen: out of sight, the ticks stop."
  (let ((buffer (get-buffer +dashboard-name)))
    (cond
     ((not (and (buffer-live-p buffer) (+ui--dashboard-visible-p)))
      (when (timerp +ui--dashboard-timer) (cancel-timer +ui--dashboard-timer))
      (setq +ui--dashboard-timer nil))
     (t
      (with-current-buffer buffer
        ;; Not an edit: no undo entry, no modified flag, no hooks.
        (with-silent-modifications
          (cl-incf +ui--tick)
          (+ui--redraw-banner +ui--tick)
          ;; Whatever else lives on the dashboard moves on with it.
          (run-hook-with-args '+ui-dashboard-tick-hook 1)
          (when (zerop (% +ui--tick 10))
            (when-let* ((region (+ui--dashboard-region '+ui-clock)))
              (+ui--replace-region
               region (+ui--centre-scaled (+ui--greeting-date) 1.15))))))))))
