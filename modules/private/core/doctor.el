;; -*- lexical-binding: t; no-byte-compile: t; -*-
;;; private/core/doctor.el
;; Only `executable-find', `modulep!' and font checks here: requiring a
;; package from a doctor file trips an eager macro-expansion cycle on
;; Emacs 31.

;; Written for Emacs 31: an older one misses what the config leans on,
;; and one setting, the cursor line kept in view, slows its redisplay
;; down a hundredfold (bug#78766).
(when (< emacs-major-version 31)
  (error! "Emacs %s: this config needs Emacs 31" emacs-version)
  (explain! (if (featurep :system 'macos)
                "brew install --cask emacs-plus-app, then doom sync"
              "Install Emacs 31 from your distribution, then doom sync")))

;; The tools the commands shell out to. Each line says what stops working.
;; macOS has its own opener and clipboard, open and osascript, always.
(dolist (tool `(,@(unless (featurep :system 'macos)
                    '(("xdg-open" . "SPC f x, open a file in its desktop app")))
                ("fd" . "SPC s F and the project file lists")
                ("rg" . "SPC p t, the task scan of the notes, the AI's greps")
                ("git" . "the notes repository and the copy menu's forge link")))
  (unless (executable-find (car tool))
    (warn! "Couldn't find %s: %s" (car tool) (cdr tool))))

(unless (or (featurep :system 'macos)
            (and (getenv "WAYLAND_DISPLAY") (executable-find "wl-copy"))
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
  (explain! (if (featurep :system 'macos)
                "brew install vips, or imagemagick"
              "openSUSE: zypper in vips-tools, or ImageMagick")))

;; The data formats. A language server validates as you type where one
;; is running; these are what `SPC m v' shells out to, and what the
;; prettify and compact keys use. A missing one is not fatal: the
;; format keeps its mode and loses its checking.
(dolist (tool '(("jq" . "JSON: prettify and compact")
                ("prettier" . "YAML and JSON with comments: prettify, keeping the comments")
                ("taplo" . "TOML: format, and the server")
                ("xmllint" . "XML: format it")
                ("yaml-language-server" . "YAML: validation as you type, with schemas")
                ("vscode-json-language-server" . "JSON: validation as you type, with schemas")))
  (unless (executable-find (car tool))
    (warn! "Couldn't find %s: no %s" (car tool) (cdr tool))))

;; bin/check-data and bin/inspect-image are python3. check-data reads
;; YAML with PyYAML; inspect-image reads the picture with PIL and the
;; metadata with exiftool, and says so in its report when one is missing.
(if (not (executable-find "python3"))
    (warn! "No python3: SPC m v cannot check data files, and images open without their inspector")
  (unless (zerop (call-process "python3" nil nil nil "-c" "import yaml"))
    (warn! "python3 has no yaml module: SPC m v cannot check a YAML file")
    (explain! (if (featurep :system 'macos)
                  "python3 -m pip install pyyaml, in a venv; Homebrew's own python3 takes no pip"
                "openSUSE: zypper in python3-PyYAML")))
  (unless (zerop (call-process "python3" nil nil nil "-c" "import PIL"))
    (warn! "python3 has no PIL: the image inspector cannot describe the picture")
    (explain! (if (featurep :system 'macos)
                  "brew install pillow for Homebrew's python3, or python3 -m pip install pillow in a venv"
                "openSUSE: zypper in python3-Pillow"))))
(unless (executable-find "exiftool")
  (warn! "Couldn't find exiftool: the image inspector shows no metadata")
  (explain! (if (featurep :system 'macos)
                "brew install exiftool"
              "openSUSE: zypper in exiftool")))

;; The fonts config.el asks for; a missing one falls back silently to
;; whatever fontconfig picks, which is how a wrong glyph or width shows up.
;; The emoji are Apple's on a Mac, which every Mac has.
(when (display-graphic-p)
  (dolist (family `("JetBrains Mono" "DejaVu Sans" "Symbols Nerd Font Mono"
                    ,@(unless (featurep :system 'macos) '("Noto Color Emoji"))))
    (unless (find-font (font-spec :family family))
      (warn! "The font %s is not installed; config.el asks for it" family))))
