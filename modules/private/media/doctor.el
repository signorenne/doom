;; -*- lexical-binding: t; no-byte-compile: t; -*-
;;; private/media/doctor.el

(unless (executable-find "mpv")
  (warn! "No mpv: the media player cannot play anything")
  (explain! (if (featurep :system 'macos)
                "brew install mpv"
              "openSUSE: zypper in mpv")))

(unless (executable-find "ffmpeg")
  (warn! "No ffmpeg: the player shows no cover art from inside a file"))
