;;; private/core/+dired.el -*- lexical-binding: t; -*-
;;
;; Every dired buffer is dirvish underneath, even without +dirvish (that
;; flag would take SPC o p from treemacs). This is the file manager: a
;; listing with icons, sizes and git state, and a preview pane on the right
;; for the file under the cursor. F hides the pane; b jumps to a place you
;; go often, the keys being the first letter of where you are going.

(declare-function dirvish-yank--get-srcs "dirvish-yank")
(declare-function +core--image-header-size "images")

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

;; Each file's git state is marked in the fringe. To find it dirvish
;; runs git twice per file, in a batch Emacs in the background, each time
;; a directory of a repository is entered. That is off the editor's
;; thread, so the listing shows and moves as fast with it.
(defvar-local +core--dirvish-drawn nil
  "(POINT . KEY): where the cursor was when this listing was last drawn,
and what else the drawing depended on; see the redraw below.")
(defvar +core--dirvish-in-redraw nil)

(after! dirvish
  (setq dirvish-default-layout '(0 0 0.45)
        ;; All but vc-state read from the file attributes dired already
        ;; has, no process.
        dirvish-attributes '(subtree-state nerd-icons collapse vc-state
                             file-time file-modes file-size)
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
  ;; megabyte: the pane shows a screenful, and reading more only slows
  ;; every preview.
  (setq dirvish-preview-large-file-threshold (* 64 1024))
  ;; Only once the cursor stops. Its delay is its own, not
  ;; `dirvish-input-debounce', and is none by default, so holding a key
  ;; down would open file after file and the list would stutter. Held,
  ;; it opens none; stopped, the file shows 0.15 s later.
  (setq dirvish-peek-key '(:debounce 0.15 any))
  ;; The file manager's own pane the same, so j held through a
  ;; directory does not open every file it passes.
  (setq dirvish-input-debounce 0.15)

  ;; Dirvish kills the buffers it previewed with, and Doom records a jump
  ;; whenever a file buffer that is in a window is killed, so opening a
  ;; file from a listing would leave the jump list holding every file the
  ;; cursor passed over, and C-o would walk into those instead of back to
  ;; the listing. Dirvish quiets undo-tree and recentf in this function
  ;; for the same reason; this is one more of them.
  (declare-function dirvish--kill-buffer "dirvish")
  (declare-function doom-set-jump-h "doom-editor")
  (defadvice! +core--dirvish-kill-no-jump-a (fn &rest args)
    :around #'dirvish--kill-buffer
    (cl-letf (((symbol-function 'doom-set-jump-h) #'ignore))
      (apply fn args)))

  ;; The icons and sizes are overlays, and before every redraw dirvish
  ;; deletes them all and makes them again. Any overlay change has Emacs
  ;; lay the whole window out afresh, so a listing on screen would keep
  ;; a core busy doing nothing and make scrolling slow. A redraw that
  ;; finds the window as the last one
  ;; left it keeps what is there, and one where only the cursor moved
  ;; draws the line it left and the line it is on, for the highlight.
  ;; dirvish's own calls, as when an answer from git arrives, draw all.
  (defvar dirvish--props)
  (declare-function dirvish--render-attrs "dirvish")
  (declare-function dirvish-pre-redisplay-h "dirvish")

  (declare-function dirvish--apply-hiding-p "dirvish")
  (defvar dirvish-hide-cursor)

  (defun +core--dirvish-draw-key (window selected)
    "What drawing WINDOW's attributes depends on but the cursor.
SELECTED is the window dirvish draws as selected. The first element says
whether the cursor's line is highlighted, the one thing it changes."
    (with-current-buffer (window-buffer window)
      (list (and (dirvish--apply-hiding-p dirvish-hide-cursor) t)
            window (window-start window)
            (buffer-modified-tick) (window-width window)
            (frame-height (window-frame window))
            (eq window (or selected (frame-selected-window)))
            buffer-invisibility-spec
            (assq :attrs dirvish--props) (assq :gui dirvish--props)
            (assq :narrow-info dirvish--props))))

  (defun +core--dirvish-line-end (pos)
    "The end of POS's line and its newline, or nil on the last line."
    (save-excursion
      (goto-char pos)
      (let ((end (1+ (line-end-position))))
        (and (<= end (point-max)) end))))

  (defun +core--dirvish-draw-line (fn window selected pos cursor)
    "Have FN draw the attributes of the line at POS alone.
The buffer is narrowed to that line, which holds all its overlays; when
CURSOR is nil, point goes past the line so it is drawn unhighlighted."
    (save-excursion
      (save-restriction
        (goto-char pos)
        (narrow-to-region (line-beginning-position) (+core--dirvish-line-end pos))
        (unless cursor (goto-char (point-max)))
        (funcall fn window selected))))

  (defadvice! +core--dirvish-in-redraw-a (fn window)
    :around #'dirvish-pre-redisplay-h
    (let ((+core--dirvish-in-redraw t))
      (funcall fn window)))

  (defadvice! +core--dirvish-draw-changed-a (fn window &optional selected)
    :around #'dirvish--render-attrs
    (let* ((buffer (window-buffer window))
           (drawn (buffer-local-value '+core--dirvish-drawn buffer))
           (same (and +core--dirvish-in-redraw
                      (equal (cdr drawn) (+core--dirvish-draw-key window selected)))))
      (with-selected-window window
        (let ((old (car drawn)) (here (point)))
          (cond
           ((and same (or (not (cadr drawn))
                          (= (line-beginning-position)
                             (save-excursion (goto-char old) (line-beginning-position))))))
           ;; Only within what is on show: a cursor gone past it, as after
           ;; G, has Emacs scroll to lines drawn around the old one.
           ((and same (>= here (window-start window)) (< here (window-end window))
                 (+core--dirvish-line-end old) (+core--dirvish-line-end here))
            (+core--dirvish-draw-line fn window selected old nil)
            (+core--dirvish-draw-line fn window selected here t))
           (t (funcall fn window selected)))
          ;; Read after drawing: drawing can set text properties, which
          ;; moves the buffer's tick.
          (setq +core--dirvish-drawn
                (cons here (+core--dirvish-draw-key window selected)))))))

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
  ;; so every candidate would be looked for under the wrong root and the
  ;; preview would say it does not exist. The project is the one of the
  ;; buffer the minibuffer was opened from, and that is known while it
  ;; opens.
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
  ;; remembers that file from one prompt to the next, so a prompt opening
  ;; on the file the last one showed (the usual case for SPC SPC) would
  ;; preview nothing until the cursor moves. Each prompt starts with
  ;; nothing previewed.
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
  ;; that value with `functionp' before using it as a name; in Emacs 31
  ;; `all' is a function, so p, P and the links would fail with a wrong
  ;; argument count. A function that does what `all' means.
  (setq dirvish-yank-sources (lambda () (dirvish-yank--get-srcs 'all)))

  ;; dirvish wants vipsthumbnail, ffmpegthumbnailer and mediainfo for
  ;; images, videos and audio. The three previews below use ImageMagick
  ;; and ffmpeg instead, and vipsthumbnail when it is installed.
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
  ;; interpolates, and a small icon blown up that way arrives in
  ;; blocks. Emacs does the enlarging instead, at draw time and smoothly,
  ;; which is also why the cache stays small.
  (defvar +core-image-thumb-width 1000
    "The square a thumbnail is made to fit, whatever the pane happens to be.
A square, not a width: a tall picture made 1000 wide was 2667 high, and
drawing it took a fifth of a second.
Emacs scales it to the pane as it draws, so one thumbnail serves every
width: resizing the frame redraws from the file already there instead of
making another, and the preview does not blink while ImageMagick runs.")

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
    "Preview images, a thumbnail made by vipsthumbnail or ImageMagick.
A GIF as well, its first frame: dirvish's own opened it whole in
image-mode and played it."
    (when (or (member ext dirvish-image-exts) (equal ext "gif"))
      (let* ((w (dirvish-media--img-size preview-window))
             (h (dirvish-media--img-size preview-window 'height))
             (alpha (member ext +core-image-alpha-exts))
             (box (format "%dx%d" +core-image-thumb-width +core-image-thumb-width))
             (cache (dirvish--img-thumb-name file (concat "box" box)
                                              (if alpha ".png" ".jpg"))))
        (cond
         ;; A thumbnail older than its picture is made again: the name
         ;; comes from the path, so an edited picture would keep showing
         ;; as it was.
         ((and (file-exists-p cache) (not (file-newer-than-file-p file cache)))
          `(img . ,(+core--preview-image cache w h)))
         ((equal ext "ico")
          `(img . ,(+core--preview-image file w h)))
         ;; vips draws an SVG in its own process, once, so a large one
         ;; never holds the cursor up; and to fill the thumbnail's square
         ;; whatever its own size, a drawing not being made of pixels to
         ;; sample.
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

  ;; Every other file as plain text, its first 64 KB read and nothing
  ;; run: no mode set up, no colour, no grammar built, so no file can hold
  ;; the cursor up. dirvish's own preview sets the mode up for each. A
  ;; file with a NUL in it is a binary, said in a line; a pipe or a
  ;; socket is not read at all, which would wait for good.
  (dirvish-define-preview +core-text (file)
    "Preview any other file as its plain text."
    (cond
     ((file-directory-p file) nil)
     ((not (file-regular-p file))
      '(info . "Not a regular file: a pipe, a socket or a device"))
     (t
      (let ((buffer (get-buffer-create " *+core-preview*"))
            (size (file-attribute-size (file-attributes file))))
        (with-current-buffer buffer
          (let ((inhibit-read-only t))
            (erase-buffer)
            (condition-case err
                (insert-file-contents file nil 0 dirvish-preview-large-file-threshold)
              (file-error (insert (error-message-string err))))
            (goto-char (point-min))
            (setq buffer-read-only t
                  truncate-lines t)))
        (if (with-current-buffer buffer
              (search-forward "\0" (min (point-max) 8192) t))
            `(info . ,(format "Binary, %s" (file-size-human-readable (or size 0))))
          `(buffer . ,buffer))))))

  (setq dirvish-preview-dispatchers
        '(+core-image +core-video +core-audio archive font pdf +core-text)))

;; The keys that make it a file manager. M-n narrows the listing as you
;; type, which is Doom's; the rest of the file manager's own work is on
;; the localleader below, SPC m f to search the tree under here, SPC m n
;; to make a file or a directory, SPC m m to move the marked files here.
;; In the listing: M-y is the menu of everything paste can do, r
;; refreshes the listing, TAB and S-TAB fold it. Under y, next to Doom's
;; copy name and path: yc puts the files themselves on the system
;; clipboard, yv pastes files from it, yd duplicates, yt copies a file's
;; text.
;; dirvish takes S and Y for itself, so the two link commands go on the
;; localleader next to Doom's omit toggle.
(map! :after dirvish
      :map dirvish-mode-map
      :n "M-y" #'dirvish-yank-menu
      ;; dired's r redisplays the lines under the cursor, which in
      ;; dirvish can leave a listing looking emptied; this r refreshes the
      ;; whole listing, the same as gr, and never touches a file.
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
;; preview beside the minibuffer would appear only once a listing had
;; been opened. Load it at the first prompt, which is when it is first
;; wanted, and set this prompt up too since the mode adds its own hook
;; while the hook is already running.
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
