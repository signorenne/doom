;;; private/core/+dired.el -*- lexical-binding: t; -*-
;;
;; Every dired buffer is dirvish underneath, even without +dirvish (that
;; flag would take SPC o p from treemacs). This is the file manager: a
;; listing with icons, sizes and git state, and a preview pane on the right
;; for the file under the cursor. F hides the pane; b jumps to a place you
;; go often, the keys being the first letter of where you are going.

(declare-function dirvish-yank--get-srcs "dirvish-yank")

;; The mouse: a file dragged out of the listing lands in Dolphin, a
;; browser's upload box or a chat, and a right click is a menu of what
;; can be done with the file under it. Dropping files in works by itself.
(setq dired-mouse-drag-files t
      mouse-drag-and-drop-region-cross-program t)
(context-menu-mode 1)

;; In wdired the permission bits are text like the names; a rename of a
;; tracked file is a git mv, so the history follows it.
(setq wdired-allow-to-change-permissions t
      dired-vc-rename-file t)

;; The places b jumps to. The entries added from a listing with SPC m b
;; live in `+core-quick-access-extra', which savehist keeps, and win
;; over these on the same key; the menu is rebuilt by the variable's
;; own setter, which is why it is never set with setq.
(defvar +core-quick-access
  `(("h" "~/"              "Home")
    ("/" "/"               "The root of the filesystem")
    ("o" ,+core-notes-dir    "Notes")
    ("p" ,+core-projects-dir "Projects")
    ("d" ,doom-user-dir      "Doom config")
    ("g" "~/grab_box/"     "Downloads")
    ("D" "~/documents/"    "Documents")
    ("m" "~/media/"        "Media")
    ("t" "~/tmp/"          "Scratch"))
  "The quick access entries of this config, (KEY PATH DESC).")

(defvar +core-quick-access-extra nil
  "Quick access entries added from a listing, (KEY PATH DESC), kept for
the next session by savehist.")
(after! savehist
  (add-to-list 'savehist-additional-variables '+core-quick-access-extra))

;; No vc-state attribute: to mark files in the fringe, dirvish runs git
;; twice for every file of a directory each time it is entered, in a
;; batch Emacs in the background; browsing a repository kept a core busy.
;; Git state is one keypress away in magit.
(after! dirvish
  (setq dirvish-default-layout '(0 0 0.45)
        dirvish-attributes '(subtree-state nerd-icons collapse file-size)
        dirvish-use-header-line 'global
        dirvish-header-line-format '(:left (path) :right (free-space))
        dirvish-use-mode-line t
        dirvish-mode-line-format '(:left (sort file-time symlink)
                                   :right (omit yank index)))
  (customize-set-variable 'dirvish-quick-access-entries
                          (+core--quick-access-entries))

  ;; The same preview beside the minibuffer while choosing a file.
  (dirvish-peek-mode 1)
  ;; A text file is previewed from its first 64 KB, not the first
  ;; megabyte: a 900 KB header was parsed whole by tree-sitter at every
  ;; preview, two thirds of a second, for the fifty lines on show.
  (setq dirvish-preview-large-file-threshold (* 64 1024))
  ;; Only once the cursor stops. Its delay is its own, not
  ;; `dirvish-input-debounce', and was none: holding a key down opened a
  ;; file every quarter second, 20 to 150 ms each, and the list stuttered
  ;; under it. Held, it now opens none; stopped, the file shows 0.15 s on.
  (setq dirvish-peek-key '(:debounce 0.15 any))
  ;; The file manager's own pane the same: j held through a directory
  ;; opened a file every quarter second as it went.
  (setq dirvish-input-debounce 0.15)

  ;; Dirvish kills the buffers it previewed with, and Doom records a jump
  ;; whenever a file buffer that is in a window is killed, so opening a
  ;; file from a listing left the jump list holding every file the cursor
  ;; had passed over: C-o then walked into those instead of back to the
  ;; listing. Dirvish quiets undo-tree and recentf in this very function
  ;; for the same reason; this is one more of them.
  (declare-function dirvish--kill-buffer "dirvish")
  (declare-function doom-set-jump-h "doom-editor")
  (defadvice! +core--dirvish-kill-no-jump-a (fn &rest args)
    :around #'dirvish--kill-buffer
    (cl-letf (((symbol-function 'doom-set-jump-h) #'ignore))
      (apply fn args)))

  (defvar +core--peek-root nil
    "The directory the preview beside the minibuffer expands a
project-relative candidate against.  The project of the buffer the
prompt was opened from to begin with, and the one the candidate is
really under once that is known.")
  (declare-function dirvish-peek-setup-h "dirvish-peek")
  (declare-function dirvish-peek-update-h "dirvish-peek")
  (declare-function dirvish--vc-root-dir "dirvish")

  ;; A project-relative candidate, the kind `SPC SPC' offers, is resolved
  ;; against `vc-root-dir', read in whatever buffer the peek happens to
  ;; run in. That is the minibuffer, whose directory is not the project's,
  ;; so every candidate was looked for under the wrong root and the
  ;; preview said it does not exist. The project is the one of the buffer
  ;; the minibuffer was opened from, and that is known while it opens.
  (defadvice! +core--dirvish-peek-root-a (&rest _)
    :before #'dirvish-peek-setup-h
    (setq +core--peek-root
          (when-let* ((window (minibuffer-selected-window))
                      ((window-live-p window)))
            (with-current-buffer (window-buffer window)
              (or (ignore-errors (+core-project-root)) default-directory)))))

  (defadvice! +core--dirvish-peek-in-project-a (fn &rest args)
    :around #'dirvish-peek-update-h
    (cl-letf (((symbol-function 'dirvish--vc-root-dir) #'+core--peek-root-for))
      (apply fn args)))

  ;; dirvish skips a preview asked for the file it previewed last, and
  ;; remembers that file from one prompt to the next: SPC SPC opening on
  ;; the file the last prompt had shown, the usual case with the list in
  ;; the order files were opened, previewed nothing until the cursor
  ;; moved. Each prompt starts with nothing previewed.
  (declare-function dirvish--run-with-delay "dirvish")
  (defadvice! +core--peek-fresh-a (&rest _)
    :before #'dirvish-peek-setup-h
    (dirvish--run-with-delay 'reset))

  (declare-function dirvish-curr "dirvish")
  (declare-function dv-type "dirvish")
  (declare-function dv-preview-window "dirvish")
  ;; The preview goes in the window the prompt was opened from. Opened
  ;; from inside core's view, a picture's report or an SVG's drawing,
  ;; that is a window kept for the view alone, so the preview goes to the
  ;; window the view stands beside, where the file will open. The slot is
  ;; set by its offset: this file loads before dirvish, and the struct's
  ;; setf and `cl-struct-slot-value' want its definition when read.
  (defadvice! +core--peek-beside-view-a (&rest _)
    :after #'dirvish-peek-setup-h
    (when-let* ((dv (dirvish-curr))
                ((eq (dv-type dv) 'peek))
                (window (dv-preview-window dv))
                ((window-live-p window))
                ((window-parameter window '+core-view))
                (main (get-mru-window nil nil t)))
      (aset dv (cl-struct-slot-offset 'dirvish 'preview-window) main)))

  ;; dirvish-yank-sources is the symbol `all' by default, and it checks
  ;; that value with `functionp' before using it as a name; Emacs 31 made
  ;; `all' a function, so p, P and the links died with a wrong argument
  ;; count. A function that does what `all' meant.
  (setq dirvish-yank-sources (lambda () (dirvish-yank--get-srcs 'all)))

  ;; dirvish wants vipsthumbnail, ffmpegthumbnailer and mediainfo for
  ;; images, videos and audio. This machine has ImageMagick and ffmpeg, so
  ;; these three use those, and vipsthumbnail the day it is installed.
  (require 'dirvish-widgets)

  ;; A thumbnail is a JPEG by default, and JPEG holds no transparency: an
  ;; icon drawn on nothing comes back on a black square. So the formats
  ;; that can carry an alpha channel are thumbnailed to PNG, which keeps
  ;; it, and the pane's own colour shows behind them.
  (defvar +core-image-alpha-exts
    '("png" "webp" "gif" "tiff" "tif" "avif" "heic" "heif" "bmp" "xpm"
      "jxl" "psd" "ico" "svg" "svgz" "apng" "exr" "tga")
    "The image formats that can carry transparency, thumbnailed to PNG.")

  ;; Nothing is made larger on disk: -thumbnail samples rather than
  ;; interpolates, and a 66 pixel telltale blown up that way arrives in
  ;; blocks. Emacs does the enlarging instead, at draw time and smoothly,
  ;; which is also why the cache stays small.
  (defvar +core-image-thumb-width 1000
    "The square a thumbnail is made to fit, whatever the pane happens to be.
A square, not a width: a tall picture made 1000 wide was 2667 high, and
drawing it took a fifth of a second.
Emacs scales it to the pane as it draws, so one thumbnail serves every
width: resizing the frame redraws from the file already there instead of
making another, and the preview does not blink while ImageMagick runs.")

  (defun +core--image-header-size (file)
    "The (WIDTH . HEIGHT) of FILE read off its header, a PNG or a JPEG,
else nil. Asking Emacs decodes the whole picture only to learn that, and
it is decoded again to be drawn: a quarter second for a large one."
    (with-temp-buffer
      (set-buffer-multibyte nil)
      (insert-file-contents-literally file nil 0 65536)
      (let ((byte (lambda (i) (or (char-after i) 0)))
            (word (lambda (i) (logior (ash (or (char-after i) 0) 8)
                                      (or (char-after (1+ i)) 0)))))
        (cond
         ((and (> (buffer-size) 24)
               (equal (buffer-substring 1 9) "\211PNG\r\n\032\n")
               (equal (buffer-substring 13 17) "IHDR"))
          (cons (logior (ash (funcall word 17) 16) (funcall word 19))
                (logior (ash (funcall word 21) 16) (funcall word 23))))
         ((equal (buffer-substring 1 (min 3 (point-max))) "\377\330")
          ;; The segments, to the first start of frame: its height, then
          ;; its width, after the length and the precision.
          (let ((pos 3) size)
            (while (and (not size) (< (+ pos 8) (point-max))
                        (= (funcall byte pos) #xff))
              (let ((marker (funcall byte (1+ pos))))
                (cond ((= marker #xff) (setq pos (1+ pos)))
                      ((or (= marker 1) (<= #xd0 marker #xd9)) (setq pos (+ pos 2)))
                      ((memq marker '(#xc0 #xc1 #xc2 #xc3 #xc5 #xc6 #xc7
                                      #xc9 #xca #xcb #xcd #xce #xcf))
                       (setq size (cons (funcall word (+ pos 7))
                                        (funcall word (+ pos 5)))))
                      (t (setq pos (+ pos 2 (funcall word (+ pos 2))))))))
            size))))))

  (defun +core--preview-image (file w h)
    "FILE drawn to fill W by H, enlarged when it is smaller than that.
A picture is there to be looked at, so the pane shows it at the size of
the pane, the way an image viewer does."
    (let* ((size (or (+core--image-header-size file)
                     (ignore-errors (image-size (create-image file nil nil) t)))))
      (if (or (null size) (zerop (car size)) (zerop (cdr size)))
          (create-image file nil nil :max-width w :max-height h)
        (create-image file nil nil
                      :scale (min (/ (float w) (car size))
                                  (/ (float h) (cdr size)))))))

  (dirvish-define-preview +core-image (file ext preview-window)
    "Preview images, a thumbnail made by vipsthumbnail or ImageMagick."
    (when (member ext dirvish-image-exts)
      (let* ((w (dirvish-media--img-size preview-window))
             (h (dirvish-media--img-size preview-window 'height))
             (alpha (member ext +core-image-alpha-exts))
             (box (format "%dx%d" +core-image-thumb-width +core-image-thumb-width))
             (cache (dirvish--img-thumb-name file (concat "box" box)
                                              (if alpha ".png" ".jpg"))))
        (cond
         ;; A thumbnail older than its picture is made again: the name is
         ;; the path's, so an edited picture kept showing as it was.
         ((and (file-exists-p cache) (not (file-newer-than-file-p file cache)))
          `(img . ,(+core--preview-image cache w h)))
         ((equal ext "ico")
          `(img . ,(+core--preview-image file w h)))
         ;; An SVG was drawn here, in Emacs, while the cursor waited: 2.4 s
         ;; for a 2.7 MB one, then another second to show it. vips draws
         ;; it in its own process, once, the pane waiting instead; and to
         ;; fill the thumbnail's square whatever its own size, a drawing
         ;; not being made of pixels to sample.
         ((executable-find dirvish-vipsthumbnail-program)
          `(cache . (,dirvish-vipsthumbnail-program ,file
                     "--size" ,(if (member ext '("svg" "svgz")) box (concat box ">"))
                     "--output" ,cache)))
         ((executable-find dirvish-magick-program)
          `(cache . (,dirvish-magick-program ,(concat (expand-file-name file) "[0]")
                     "-auto-orient" "-thumbnail" ,(concat box ">")
                     ,@(unless alpha '("-quality" "85"))
                     ,cache)))))))

  (dirvish-define-preview +core-video (file ext preview-window)
    "Preview videos, a frame taken by ffmpeg."
    ;; Not `:require': dirvish builds its keyword plist by popping two
    ;; elements for one keyword, which lands the value where the next
    ;; keyword should be, so nothing ever reads it, not for its own
    ;; dispatchers either. The test is here instead.
    (when (and (member ext dirvish-video-exts) (executable-find "ffmpeg"))
      (let* ((w (dirvish-media--img-size preview-window))
             (h (dirvish-media--img-size preview-window 'height))
             (cache (dirvish--img-thumb-name file w ".jpg")))
        (if (file-exists-p cache)
            `(img . ,(create-image cache nil nil :max-width w :max-height h))
          `(cache . ("ffmpeg" "-y" "-loglevel" "error" "-ss" "1" "-i" ,(expand-file-name file)
                     "-frames:v" "1" "-vf" ,(format "scale=%d:-2" w)
                     "-q:v" "3" ,cache))))))

  (dirvish-define-preview +core-audio (file ext)
    "Preview audio files with what ffprobe knows about them."
    (when (and (member ext dirvish-audio-exts) (executable-find "ffprobe"))
      `(shell . ("ffprobe" "-hide_banner" ,file))))

  (setq dirvish-preview-dispatchers
        '(+core-image gif +core-video +core-audio archive font pdf)))

;; The keys that make it a file manager. M-n narrows the listing as you
;; type, which is Doom's; the rest of the file manager's own work is on
;; the localleader below, SPC m f to search the tree under here, SPC m n
;; to make a file or a directory, SPC m m to move the marked files here.
;; Here: M-y is the menu of everything paste can do, r refreshes the
;; listing, TAB and S-TAB fold it. Under y, next to Doom's copy name and
;; path: yc puts the files themselves on the system clipboard, yv pastes
;; files from it, yd duplicates, yt copies a file's text.
;; dirvish takes S and Y for itself, so the two link commands go on the
;; localleader next to Doom's omit toggle.
(map! :after dirvish
      :map dirvish-mode-map
      :n "M-y" #'dirvish-yank-menu
      ;; r meant redisplay the lines under the cursor, which in dirvish
      ;; can leave a listing looking emptied; r now refreshes the whole
      ;; listing, the same as gr, and never touches a file.
      :n "r"   #'revert-buffer
      ;; TAB opens the directory under the cursor, as it opens a heading
      ;; in an Org document; S-TAB is the other half, the whole listing
      ;; open one level or shut again.
      :n "TAB"     #'+core/dired-subtree-cycle
      :n [tab]     #'+core/dired-subtree-cycle
      :n [backtab] #'+core/dired-fold-cycle
      :n "S-TAB"   #'+core/dired-fold-cycle
      (:prefix "y"
       :n "c" #'+core/files-to-clipboard
       :n "v" #'+core/files-from-clipboard
       :n "d" #'+core/dired-duplicate
       :n "t" #'+core/copy-file-contents))

;; The paste menu (M-y) lists the clipboard and the duplicate as well.
;; The :set handler rebuilds the transient, so the entries are added once:
;; a reload would otherwise append them again.
(after! dirvish-yank
  (let ((mine '(("c" "Copy to the system clipboard, for other apps" +core/files-to-clipboard)
                ("v" "Paste the files on the system clipboard here" +core/files-from-clipboard)
                ("d" "Duplicate beside the original"    +core/dired-duplicate))))
    (customize-set-variable
     'dirvish-yank-keys
     (append (seq-remove (lambda (entry) (assoc (car entry) mine))
                         dirvish-yank-keys)
             mine))))
(map! :after dired
      :map dired-mode-map
      :localleader
      :desc "The mode's menu"       "SPC" #'casual-dired-tmenu
      :desc "Find files by words"   "f" #'+core/dired-search
      :desc "New file, or directory with /" "n" #'+core/dired-create
      :desc "Move the marked files here" "m" #'dirvish-move
      :desc "Symlink here"          "s" #'dired-do-symlink
      :desc "Relative symlink here" "S" #'dired-do-relsymlink
      :desc "Copy with rsync"       "r" #'dirvish-rsync
      :desc "The other pane"        "2" #'+core/dirvish-other-pane
      :desc "Open the marked files" "o" #'+core/dired-open-marked
      :desc "Quick access: add here" "b" #'+core/quick-access-add
      :desc "Quick access: drop one" "B" #'+core/quick-access-remove)

;; Doom's two dired keys open the file manager with the preview pane: on
;; this file's directory, or on a directory asked for.
;; `dirvish-peek-mode' is turned on inside `after! dirvish', so the
;; preview beside the minibuffer only appeared once a listing had been
;; opened: SPC SPC in a session that had not opened one had none, and
;; neither had SPC . or SPC f r. Load it at the first prompt, which is
;; when it is first wanted, and set this prompt up too since the mode
;; adds its own hook while the hook is already running.
(defun +core--peek-once-h ()
  "Load dirvish's minibuffer preview, once, at the first prompt."
  (remove-hook 'minibuffer-setup-hook #'+core--peek-once-h)
  (when (require 'dirvish nil t)
    (when (fboundp 'dirvish-peek-mode) (dirvish-peek-mode 1))
    (when (fboundp 'dirvish-peek-setup-h)
      (ignore-errors (dirvish-peek-setup-h)))))

(add-hook 'minibuffer-setup-hook #'+core--peek-once-h)

(declare-function dirvish-curr "dirvish")
(declare-function dirvish--preview-update "dirvish")
(defvar dirvish--props)
;; dirvish draws its preview from `post-command-hook', so a frame
;; resized while a listing is on screen leaves the picture drawn for the
;; pane it no longer has, until the cursor moves. Its own redraw will
;; not do: it skips the file it is already showing, which after a resize
;; is the one that needs drawing again. So the preview is asked for
;; directly, once the dragging has stopped.
(defvar +core--dirvish-resize-timers (make-hash-table :test #'eq)
  "Frame to the one-shot that redraws its preview after a resize.
One timer each: a single one meant a resize in one frame cancelled the
redraw another was still waiting for.")

(defun +core--dirvish-redraw-preview (frame)
  "Draw dirvish's preview again for every listing in FRAME.
Every window, not the selected one alone: a listing beside something
else was left holding the picture drawn for the pane it no longer has."
  (remhash frame +core--dirvish-resize-timers)
  (when (and (frame-live-p frame) (fboundp 'dirvish--preview-update))
    (dolist (window (window-list frame 'no-minibuffer))
      (when (window-live-p window)
        (with-selected-window window
          (when (derived-mode-p 'dired-mode)
            (when-let* ((dv (ignore-errors (dirvish-curr)))
                        (index (cdr (assq :index dirvish--props))))
              (ignore-errors (dirvish--preview-update dv index)))))))))

(add-hook 'window-size-change-functions
          (defun +core--dirvish-resize-h (frame)
            ;; A drag sends a great many of these; only the last matters,
            ;; and a thumbnail is a process each time.
            (when-let* ((timer (gethash frame +core--dirvish-resize-timers)))
              (cancel-timer timer))
            (puthash frame
                     (run-with-idle-timer 0.3 nil
                                          #'+core--dirvish-redraw-preview frame)
                     +core--dirvish-resize-timers)))

(map! :leader
      :desc "Dired, this file's directory" "o -" #'+core/dirvish-here
      :desc "Dired, a directory"           "f d" #'+core/dirvish-directory
      :desc "A file of another project"    "p >" #'+core/find-file-in-other-project)
