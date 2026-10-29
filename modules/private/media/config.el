;;; private/media/config.el -*- lexical-binding: t; -*-
;;
;; A media player in a buffer of its own, on mpv: music plays in the
;; background, a video in mpv's window, and the buffer shows what plays
;; and its queue, with mpv's own keys. Opening a music or video file plays
;; it.

(defvar +media-docs
  '(:groups (("media" "Media" (dired) +media-player-mode-map dired-mode-map)))
  "How the cheat sheet documents this module; see `+docs--module-docs'.")

;; Opened from a command, from the file manager or SPC f f, music and
;; video play rather than open as bytes. From the file manager the
;; player shows beside it, as a buffer change there ends its layout.
(defadvice! +media--play-instead-a (fn filename &rest args)
  "Play FILENAME when it is music or a video and a command opens it."
  :around #'find-file
  (if (and this-command (stringp filename) (+media-file-p filename)
           (not (file-remote-p (expand-file-name filename)))
           (file-regular-p filename))
      (+media/play-file (expand-file-name filename) (derived-mode-p 'dired-mode))
    (apply fn filename args)))

;;;###autoload
(defun +media/queue-marked ()
  "Add the marked files, or the one at point, to the player's queue."
  (interactive)
  (+media-play (dired-get-marked-files) t))

(map! :leader
      :desc "Media player" "o M" #'+media/player)

(map! :after dired
      :map dired-mode-map
      :localleader
      :desc "Queue in the player" "p" #'+media/queue-marked)
