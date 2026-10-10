;;; private/core/+images.el -*- lexical-binding: t; -*-
;;
;; The image viewer: a picture opens at the size of the window, stays in
;; the middle of it whatever moves, and the viewer's own keys pan it, zoom
;; it and step to the next file in the directory.

(defvar +core-plain-mode)                ; config.el
(declare-function +core-image-center "images")
(declare-function +core-image-uncenter "images")
(declare-function +core--image-center-h "images")
(declare-function +core--image-recenter-a "images")
(declare-function +core--image-refit-recenter-a "images")

;; An SVG carries the size it is drawn at. ImageMagick reads one with a
;; renderer of its own that ignores it and hands back 30 by 30 pixels,
;; and `image-mode' prefers ImageMagick for every type not named in
;; `imagemagick-types-inhibit'. This Emacs is built with librsvg (RSVG
;; in `system-configuration-features'), which reads the file properly,
;; so SVG goes there and the raster formats keep ImageMagick.
(after! image
  (add-to-list 'imagemagick-types-inhibit 'SVG))

;; An image file opens at the size of the window, small ones enlarged:
;; a 66 pixel telltale is there to be looked at, not squinted at. The
;; window changing size redraws it, a second after it settles.
(setq image-auto-resize 'fit-window
      ;; A fifth of a second: long enough to batch a drag, short enough
      ;; that the redraw is not a jump you watch happen.
      image-auto-resize-on-window-resize 0.2)

;; `image-mode' runs before the buffer is in a window, so the first draw
;; has no window to fit to and comes out at the picture's own size: a 66
;; pixel icon, sat alone in a great empty buffer. The refit a second
;; later is the jump. Fit it as soon as there is a window, which is at
;; the end of the command that opened it.
(add-hook 'image-mode-hook
          (defun +core--image-viewer-h ()
            "Keep the picture in the middle of the window, whatever moves.
The block cursor sits on the one character the whole picture is drawn
on, which paints a box round the lot and reads as a selection; a viewer
has no cursor."
            (setq-local cursor-type nil)
            ;; evil sets the cursor from the state when it is entered,
            ;; and would put the box back; an empty spec leaves it alone.
            (setq-local evil-normal-state-cursor nil
                        evil-motion-state-cursor nil
                        evil-emacs-state-cursor nil)
            (when (fboundp 'evil-refresh-cursor) (evil-refresh-cursor))
            (add-hook 'post-command-hook #'+core--image-center-h nil t)
            (add-hook 'window-configuration-change-hook
                      #'+core--image-center-h nil t)))

(add-hook 'image-mode-hook
          (defun +core--image-fit-at-once-h ()
            (when (and (eq image-auto-resize 'fit-window)
                       (fboundp 'image-fit-to-window))
              (let ((buffer (current-buffer)))
                (run-at-time
                 0 nil
                 (lambda ()
                   (when (buffer-live-p buffer)
                     (when-let* ((window (get-buffer-window buffer t)))
                       (ignore-errors (image-fit-to-window window))
                       (with-current-buffer buffer
                         (ignore-errors (+core-image-center)))))))))))

(after! image-mode
  ;; `imagemagick-types-inhibit' is checked against the file's extension
  ;; only. A buffer with no file, such as the view beside a diagram or an
  ;; SVG, skips the check, so in a build with ImageMagick every image in
  ;; it goes through ImageMagick, which draws an SVG as a 30 pixel sliver.
  ;; With no file name, decide by the data instead: ImageMagick only for a
  ;; type Emacs cannot read itself.
  (defadvice! +core--image-native-first-a (fn filename)
    :around #'image--imagemagick-wanted-p
    (and (funcall fn filename)
         (not (and (null filename)
                   (when-let* ((type (image-type-from-buffer)))
                     (image-type-available-p type))))))

  (defadvice! +core--image-uncenter-a (&rest _)
    :before #'image-toggle-display
    (ignore-errors (+core-image-uncenter)))
  ;; + and - go through this one.
  (advice-add 'image--change-size :after #'+core--image-recenter-a)
  ;; That redraw does nothing while anything is in the echo area, and
  ;; something usually is: the message from whatever moved the window is
  ;; still there when the resize arrives a second later. The picture then
  ;; keeps the size it had and spills out of the smaller window. The echo
  ;; area is read there out of politeness, since the refit says nothing
  ;; itself, so it is not consulted.
  (when (fboundp 'image-fit-to-window)
    (defadvice! +core--image-refit-anyway-a (fn &rest args)
      :around #'image-fit-to-window
      (cl-letf (((symbol-function 'current-message) #'ignore))
        (apply fn args)))
    (advice-add 'image-fit-to-window :after #'+core--image-refit-recenter-a)))

;; An SVG is a text file you write and a picture you look at, and
;; changing one means watching the other. So it opens as its XML, with
;; the drawing beside it in core's view, drawn again after each pause.
;; `auto-mode-alist' sends .svg to `image-mode' first; this entry goes in
;; front of that one.
(add-to-list 'auto-mode-alist '("\\.svg\\'" . nxml-mode))
(add-hook 'nxml-mode-hook #'+core--svg-view-h)
;; An SVG exported by a tool is often one line of thousands of
;; characters, and `so-long-mode' takes it over from nxml-mode for
;; speed; it keeps its drawing there too.
(add-hook 'so-long-mode-hook #'+core--svg-view-h)
;; One past `+core-plain-file-size' opens as plain text, without
;; nxml-mode, five seconds for 2 MB, and keeps its drawing all the same.
(add-hook! 'find-file-hook
  (defun +core--svg-plain-view-h ()
    "Give an SVG opened as plain text its drawing beside it."
    (when (and +core-plain-mode (not (eq +core-plain-mode t)))
      (+core--svg-view-h))))

;; Any other image opens as the picture, with what is inside it beside:
;; its structure, chunk by chunk or marker by marker, its metadata, and
;; its first bytes. The view steps aside when you leave for a buffer that
;; has none, so a glance at a photo does not leave half the screen taken.
(add-hook 'image-mode-hook #'+core--image-inspector-h)

;; The viewer's own keys: evil-collection already pans with hjkl, zooms
;; on + and -, and scrolls with C-d and C-u. What it leaves out is the
;; whole picture at once, the picture at its true size, and stepping to
;; the next file in the directory.
(map! :after image-mode
      :map image-mode-map
      :localleader
      :desc "What is inside, beside it" "p" #'+core/view-toggle
      :desc "Read it again"             "r" #'+core/view-refresh)

(map! :after nxml-mode
      :map nxml-mode-map
      :localleader
      :desc "Drawing, beside the source" "p" #'+core/view-toggle
      (:prefix ("P" . "drawing")
       :desc "Draw it again now"    "r" #'+core/view-refresh
       :desc "Follow my typing"     "f" #'+core/view-follow-toggle
       :desc "Open it with the file, or not" "O" #'+core/view-on-open-toggle))

(map! :after image-mode
      :map image-mode-map
      :n "f" #'+core/image-fit
      :n "1" #'+core/image-original
      :n "n" #'image-next-file
      :n "p" #'image-previous-file
      ;; A character a press is ten pixels; these move by a useful amount.
      :n "h" #'+core/image-pan-left
      :n "l" #'+core/image-pan-right
      :n "j" #'+core/image-pan-down
      :n "k" #'+core/image-pan-up)
