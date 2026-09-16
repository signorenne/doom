;; -*- lexical-binding: t; no-byte-compile: t; -*-
;;; private/core/doctor.el
;; Only `executable-find', `modulep!' and font checks here: requiring a
;; package from a doctor file trips an eager macro-expansion cycle on
;; Emacs 31.

;; The tools the commands shell out to. Each line says what stops working.
(dolist (tool '(("xdg-open" . "SPC f x, open a file in its desktop app")
                ("fd" . "SPC s F and the project file lists")
                ("rg" . "SPC p t, the task scan of the notes, the AI's greps")
                ("git" . "the notes repository and the copy menu's forge link")))
  (unless (executable-find (car tool))
    (warn! "Couldn't find %s: %s" (car tool) (cdr tool))))

(unless (or (and (getenv "WAYLAND_DISPLAY") (executable-find "wl-copy"))
            (executable-find "xclip"))
  (warn! "No wl-copy (Wayland) or xclip (X11): files cannot go to or come from other apps, dired's yc and yv"))

;; dirvish's previews: video frames and audio details need ffmpeg and
;; ffprobe, images one of the two thumbnailers.
(dolist (tool '(("ffmpeg" . "video frames in the preview pane")
                ("ffprobe" . "audio and video details in the preview pane")))
  (unless (executable-find (car tool))
    (warn! "Couldn't find %s: no %s" (car tool) (cdr tool))))
(unless (or (executable-find "vipsthumbnail") (executable-find "magick")
            (executable-find "convert"))
  (warn! "No vipsthumbnail or ImageMagick: no image thumbnails in the preview pane")
  (explain! "openSUSE: zypper in vips-tools, or ImageMagick"))

;; The fonts config.el asks for; a missing one falls back silently to
;; whatever fontconfig picks, which is how a wrong glyph or width shows up.
(when (display-graphic-p)
  (dolist (family '("JetBrains Mono" "DejaVu Sans"
                    "Symbols Nerd Font Mono" "Noto Color Emoji"))
    (unless (find-font (font-spec :family family))
      (warn! "The font %s is not installed; config.el asks for it" family))))
