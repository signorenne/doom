;;; private/media/autoload/player.el -*- lexical-binding: t; -*-
;;
;; The media player: mpv plays, in the background for music and in its own
;; window for video, and a buffer of its own shows and controls it. Emacs
;; talks to mpv over its IPC socket, a JSON line each way.

(defvar +media-player-buffer-name "*Player*"
  "The player's buffer.")

(defvar +media-mpv-args nil
  "More arguments for mpv, such as --ao=null for no sound.")

(defvar +media--process nil
  "The mpv process.")

(defvar +media--connection nil
  "The connection to mpv's IPC socket.")

(defvar +media--state nil
  "What mpv last said of each property it is watched for, by name.")

(defvar +media--pending nil
  "Commands sent before the connection was up.")

(defvar +media--render-timer nil
  "The redraw, at most a couple of times a second.")

(defvar +media--cover-cache (make-hash-table :test #'equal)
  "File to the picture shown for it, or `none'.")

(defconst +media--watched
  '(pause duration time-pos volume mute metadata media-title playlist
    playlist-pos loop-file loop-playlist path)
  "The properties the player shows.")

(defun +media--socket ()
  "The socket this Emacs and its mpv talk over."
  (expand-file-name (format "emacs-mpv-%d.sock" (emacs-pid)) temporary-file-directory))


;;
;;; Talking to mpv

(defun +media--send (&rest command)
  "Send COMMAND, a list of strings and numbers, to mpv."
  (let ((line (concat (json-serialize `((command . ,(vconcat command)))) "\n")))
    (if (process-live-p +media--connection)
        (process-send-string +media--connection line)
      (setq +media--pending (append +media--pending (list line)))
      (+media--start))))

(defun +media--filter (_process output)
  "Read mpv's JSON lines in OUTPUT."
  (with-current-buffer (get-buffer-create " *mpv ipc*")
    (goto-char (point-max))
    (insert output)
    (goto-char (point-min))
    (while (search-forward "\n" nil t)
      (let ((line (buffer-substring (point-min) (1- (point)))))
        (delete-region (point-min) (point))
        (when-let* ((event (ignore-errors
                             (json-parse-string line :object-type 'alist
                                                :array-type 'list :null-object nil))))
          (when (equal (alist-get 'event event) "property-change")
            (setf (alist-get (intern (alist-get 'name event)) +media--state)
                  (alist-get 'data event))
            (+media--render-soon)))))))

(defun +media--connect ()
  "Connect to mpv's socket, watch the properties, send what waited."
  (setq +media--connection
        (make-network-process :name "mpv-ipc" :family 'local :noquery t
                              :service (+media--socket) :coding 'utf-8
                              :filter #'+media--filter))
  (seq-do-indexed (lambda (name i)
                    (process-send-string
                     +media--connection
                     (concat (json-serialize
                              `((command . ["observe_property" ,(1+ i) ,(symbol-name name)])))
                             "\n")))
                  +media--watched)
  (dolist (line +media--pending)
    (process-send-string +media--connection line))
  (setq +media--pending nil))

(defun +media--start ()
  "Start mpv, idle, and connect once its socket is there."
  (unless (process-live-p +media--process)
    (unless (executable-find "mpv")
      (user-error "No mpv: brew install mpv, or zypper in mpv"))
    (ignore-errors (delete-file (+media--socket)))
    (setq +media--state nil
          +media--process
          (make-process :name "mpv" :noquery t :buffer nil
                        :command (append
                                  (list "mpv" "--idle=yes" "--no-terminal"
                                        "--force-window=no" "--audio-display=no"
                                        (concat "--input-ipc-server=" (+media--socket)))
                                  +media-mpv-args)
                        :sentinel (lambda (_process _event)
                                    (setq +media--connection nil)
                                    (+media--render-soon))))
    (let ((tries 0) timer)
      (setq timer (run-at-time 0.05 0.05
                               (lambda ()
                                 (setq tries (1+ tries))
                                 (when (or (file-exists-p (+media--socket)) (> tries 100))
                                   (cancel-timer timer)
                                   (condition-case err (+media--connect)
                                     (error (message "mpv did not answer: %s"
                                                     (error-message-string err)))))))))))

(defun +media--get (name)
  "What mpv last said of property NAME."
  (alist-get name +media--state))


;;
;;; Playing

(defvar +media-audio-extensions
  '("mp3" "flac" "m4a" "aac" "ogg" "oga" "opus" "wav" "aif" "aiff" "alac" "wma" "ape")
  "Files the player takes as music.")

(defvar +media-video-extensions
  '("mp4" "m4v" "mkv" "mov" "webm" "avi" "wmv" "flv" "mpg" "mpeg" "ts" "3gp")
  "Files the player plays in mpv's window.")

;;;###autoload
(defun +media-file-p (file)
  "Non-nil when FILE is music or a video."
  (member (downcase (or (file-name-extension file) ""))
          (append +media-audio-extensions +media-video-extensions)))

(defun +media--expand (files)
  "FILES with each directory replaced by the media files under it, in order."
  (mapcan (lambda (file)
            (if (file-directory-p file)
                (sort (seq-filter #'+media-file-p
                                  (directory-files-recursively file "." nil))
                      #'string-version-lessp)
              (and (+media-file-p file) (list file))))
          files))

;;;###autoload
(defun +media-play (files &optional append)
  "Play FILES, directories expanded, replacing the queue, or after it
with APPEND."
  (let ((files (+media--expand (mapcar #'expand-file-name files))))
    (unless files (user-error "Nothing here to play"))
    (seq-do-indexed (lambda (file i)
                      (+media--send "loadfile" file
                                    (if (or append (> i 0)) "append-play" "replace")))
                    files)
    (when (or (not append) (eq (+media--get 'pause) t))
      (+media--send "set_property" "pause" :false))
    (message "%s %d file%s" (if append "Queued" "Playing") (length files)
             (if (cdr files) "s" ""))))

;;;###autoload
(defun +media/play-file (file)
  "Play FILE, or every media file under it, now."
  (interactive "fPlay: ")
  (+media-play (list file))
  (+media/player))

;;;###autoload
(defun +media/queue-files (files)
  "Add FILES, or what is under them, to the queue."
  (interactive (list (list (read-file-name "Queue: "))))
  (+media-play files t))


;;
;;; The player's buffer

(defvar +media-player-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "p") #'+media/pause)
    (define-key map (kbd "RET") #'+media/play-at-point)
    (define-key map (kbd "<") #'+media/previous)
    (define-key map (kbd ">") #'+media/next)
    (define-key map (kbd "h") #'+media/back)
    (define-key map (kbd "l") #'+media/forward)
    (define-key map (kbd "H") #'+media/back-more)
    (define-key map (kbd "L") #'+media/forward-more)
    (define-key map (kbd "9") #'+media/quieter)
    (define-key map (kbd "0") #'+media/louder)
    (define-key map (kbd "m") #'+media/mute)
    (define-key map (kbd "r") #'+media/repeat)
    (define-key map (kbd "z") #'+media/shuffle)
    (define-key map (kbd "s") #'+media/stop)
    (define-key map (kbd "d") #'+media/remove-at-point)
    (define-key map (kbd "a") #'+media/queue-files)
    (define-key map (kbd "q") #'quit-window)
    map)
  "Keys of the player, mpv's own where Emacs leaves them free.")

(define-derived-mode +media-player-mode special-mode "Player"
  "The media player: what plays, its queue, and the keys to steer it.
\\{+media-player-mode-map}"
  (setq-local cursor-type nil
              truncate-lines t
              revert-buffer-function (lambda (&rest _) (+media--render)))
  (add-hook 'kill-buffer-hook #'+media--quit nil t))

(with-eval-after-load 'evil
  (evil-set-initial-state '+media-player-mode 'normal)
  (evil-define-key* 'normal +media-player-mode-map
    "p" #'+media/pause (kbd "RET") #'+media/play-at-point
    "<" #'+media/previous ">" #'+media/next
    "h" #'+media/back "l" #'+media/forward "H" #'+media/back-more "L" #'+media/forward-more
    "9" #'+media/quieter "0" #'+media/louder "m" #'+media/mute
    "r" #'+media/repeat "z" #'+media/shuffle "s" #'+media/stop
    "d" #'+media/remove-at-point "a" #'+media/queue-files "q" #'quit-window))

(defun +media--quit ()
  "Stop mpv with the player's buffer."
  (dolist (process (list +media--connection +media--process))
    (when (processp process) (delete-process process)))
  (ignore-errors (delete-file (+media--socket)))
  (setq +media--process nil +media--connection nil +media--state nil))

(defun +media--time (seconds)
  "SECONDS as m:ss, or h:mm:ss."
  (if (not (numberp seconds)) "-:--"
    (let* ((s (floor seconds)) (h (/ s 3600)) (m (/ (% s 3600) 60)))
      (if (> h 0) (format "%d:%02d:%02d" h m (% s 60)) (format "%d:%02d" m (% s 60))))))

(defun +media--bar (position duration width)
  "A progress bar WIDTH wide."
  (let ((done (if (and (numberp position) (numberp duration) (> duration 0))
                  (min width (round (* width (/ position duration))))
                0)))
    (concat (propertize (make-string done ?━) 'face 'success)
            (propertize (make-string (- width done) ?─) 'face 'shadow))))

(defun +media--cover (file)
  "The picture to show for FILE: a cover beside it, else the one inside
it, taken out once in the background; nil until there is one."
  (let ((have (gethash file +media--cover-cache)))
    (cond
     ((eq have 'none) nil)
     (have have)
     (t
      (if-let* ((beside (seq-find #'file-exists-p
                                  (mapcar (lambda (name) (expand-file-name name (file-name-directory file)))
                                          '("cover.jpg" "cover.png" "folder.jpg" "folder.png" "front.jpg")))))
          (puthash file beside +media--cover-cache)
        (puthash file 'none +media--cover-cache)
        (when (executable-find "ffmpeg")
          (let ((out (expand-file-name (concat (secure-hash 'sha1 file) ".jpg")
                                       (file-name-concat doom-cache-dir "media-covers/"))))
            (make-directory (file-name-directory out) t)
            (if (file-exists-p out)
                (puthash file out +media--cover-cache)
              (make-process :name "media-cover" :noquery t :buffer nil
                            :command (list "ffmpeg" "-y" "-loglevel" "error" "-i" file
                                           "-an" "-frames:v" "1" "-vf" "scale=400:-2" out)
                            :sentinel (lambda (process _event)
                                        (when (and (not (process-live-p process))
                                                   (file-exists-p out)
                                                   (> (file-attribute-size (file-attributes out)) 0))
                                          (puthash file out +media--cover-cache)
                                          (+media--render-soon)))))))
        nil)))))

(defun +media--tag (metadata &rest keys)
  "The first of KEYS that METADATA has, in any case."
  (seq-some (lambda (key)
              (cdr (seq-find (lambda (entry) (string-equal-ignore-case (symbol-name (car entry)) key))
                             metadata)))
            keys))

(defun +media--render ()
  "Draw the player."
  (when-let* ((buffer (get-buffer +media-player-buffer-name)))
    (with-current-buffer buffer
      (let* ((inhibit-read-only t)
             (line (line-number-at-pos))
             (metadata (+media--get 'metadata))
             (path (+media--get 'path))
             (title (or (+media--tag metadata "title") (+media--get 'media-title)
                        (and path (file-name-nondirectory path))))
             (artist (+media--tag metadata "artist" "album_artist"))
             (album (+media--tag metadata "album"))
             (year (+media--tag metadata "date" "year"))
             (cover (and path (+media--cover path)))
             (width (max 20 (min 60 (- (window-width (get-buffer-window buffer t)) 20)))))
        (erase-buffer)
        (insert "\n")
        (cond
         ((not (process-live-p +media--process))
          (insert (propertize "  Nothing playing. " 'face 'shadow)
                  "RET on music or a video in the file manager plays it; a queues a file or folder.\n"))
         ((not path)
          (insert (propertize "  Nothing playing.\n" 'face 'shadow)))
         (t
          (when cover
            (insert "  ")
            (insert-image (create-image cover nil nil :max-width 220 :max-height 220))
            (insert "\n\n"))
          (insert "  " (propertize (or title "") 'face '(:inherit bold :height 1.3)) "\n")
          (when artist (insert "  " (propertize artist 'face 'font-lock-keyword-face) "\n"))
          (when (or album year)
            (insert "  " (propertize (string-join (delq nil (list album year)) ", ") 'face 'shadow) "\n"))
          (insert "\n  " (propertize (if (eq (+media--get 'pause) t) "Paused   " "Playing  ")
                                     'face 'shadow)
                  (+media--bar (+media--get 'time-pos) (+media--get 'duration) width)
                  "  " (+media--time (+media--get 'time-pos))
                  " / " (+media--time (+media--get 'duration)) "\n")
          (insert "  " (propertize
                        (format "volume %s%%%s%s"
                                (round (or (+media--get 'volume) 100))
                                (if (eq (+media--get 'mute) t) ", muted" "")
                                (cond ((equal (+media--get 'loop-file) "inf") ", repeat one")
                                      ((equal (+media--get 'loop-playlist) "inf") ", repeat all")
                                      (t "")))
                        'face 'shadow)
                  "\n")))
        (let ((playlist (+media--get 'playlist)))
          (when playlist
            (insert "\n  " (propertize (format "Queue, %d" (length playlist)) 'face 'bold) "\n")
            (seq-do-indexed
             (lambda (entry i)
               (let ((current (eq (alist-get 'current entry) t))
                     (name (or (alist-get 'title entry)
                               (file-name-nondirectory (alist-get 'filename entry)))))
                 (insert (propertize (format "  %s %s\n" (if current ">" " ") name)
                                     'face (if current 'bold 'default)
                                     '+media-index i))))
             playlist)))
        (insert "\n  " (propertize "p pause  < > previous next  h l seek  H L a minute  9 0 volume  m mute\n  r repeat  z shuffle  s stop  RET play the track  d remove  a add  q hide"
                                   'face 'shadow)
                "\n")
        (goto-char (point-min))
        (forward-line (1- line))))))

(defun +media--render-soon ()
  "Redraw the player shortly, if it is on screen: mpv says where it is
many times a second."
  (unless (timerp +media--render-timer)
    (setq +media--render-timer
          (run-at-time 0.4 nil (lambda ()
                                 (setq +media--render-timer nil)
                                 (when (get-buffer-window +media-player-buffer-name t)
                                   (+media--render)))))))

;;;###autoload
(defun +media/player ()
  "Show the player, starting mpv if it is not running."
  (interactive)
  (+media--start)
  (let ((buffer (get-buffer-create +media-player-buffer-name)))
    (with-current-buffer buffer
      (unless (derived-mode-p '+media-player-mode) (+media-player-mode)))
    (pop-to-buffer buffer)
    (+media--render)))


;;
;;; The keys

(defun +media--index-at-point ()
  "The queue entry on this line, or nil."
  (get-text-property (line-beginning-position) '+media-index))

;;;###autoload
(defun +media/pause ()
  "Pause, or play on."
  (interactive)
  (+media--send "cycle" "pause"))

;;;###autoload
(defun +media/play-at-point ()
  "Play the queue entry on this line, or pause and play on elsewhere."
  (interactive)
  (if-let* ((index (+media--index-at-point)))
      (progn (+media--send "playlist-play-index" index)
             (+media--send "set_property" "pause" :false))
    (+media/pause)))

;;;###autoload
(defun +media/next () "The next track." (interactive) (+media--send "playlist-next"))
;;;###autoload
(defun +media/previous () "The track before." (interactive) (+media--send "playlist-prev"))
;;;###autoload
(defun +media/back () "Five seconds back." (interactive) (+media--send "seek" -5))
;;;###autoload
(defun +media/forward () "Five seconds on." (interactive) (+media--send "seek" 5))
;;;###autoload
(defun +media/back-more () "A minute back." (interactive) (+media--send "seek" -60))
;;;###autoload
(defun +media/forward-more () "A minute on." (interactive) (+media--send "seek" 60))
;;;###autoload
(defun +media/quieter () "Lower the volume." (interactive) (+media--send "add" "volume" -5))
;;;###autoload
(defun +media/louder () "Raise the volume." (interactive) (+media--send "add" "volume" 5))
;;;###autoload
(defun +media/mute () "Mute, or not." (interactive) (+media--send "cycle" "mute"))
;;;###autoload
(defun +media/shuffle () "Shuffle the queue." (interactive) (+media--send "playlist-shuffle"))

;;;###autoload
(defun +media/repeat ()
  "Repeat nothing, then the queue, then the track."
  (interactive)
  (cond ((equal (+media--get 'loop-file) "inf")
         (+media--send "set_property" "loop-file" "no")
         (+media--send "set_property" "loop-playlist" "no")
         (message "Repeat: off"))
        ((equal (+media--get 'loop-playlist) "inf")
         (+media--send "set_property" "loop-playlist" "no")
         (+media--send "set_property" "loop-file" "inf")
         (message "Repeat: this track"))
        (t (+media--send "set_property" "loop-playlist" "inf")
           (message "Repeat: the queue"))))

;;;###autoload
(defun +media/stop ()
  "Stop and empty the queue."
  (interactive)
  (+media--send "stop"))

;;;###autoload
(defun +media/remove-at-point ()
  "Take the queue entry on this line out."
  (interactive)
  (if-let* ((index (+media--index-at-point)))
      (+media--send "playlist-remove" index)
    (user-error "No track on this line")))
