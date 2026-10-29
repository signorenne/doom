;;; private/core/autoload/convert.el -*- lexical-binding: t; -*-
;;
;; Converting files into new ones beside them: pictures, video, audio,
;; documents and PDFs, with the tools already installed (vips or
;; ImageMagick, exiftool, ffmpeg, pandoc, poppler). Nothing is
;; overwritten, and every conversion runs in the background.

(require 'transient)

(defvar +core-convert-kinds
  '((image "png" "jpg" "jpeg" "webp" "avif" "heic" "heif" "gif" "bmp" "tif" "tiff" "psd" "jxl")
    (video "mp4" "m4v" "mkv" "mov" "webm" "avi" "wmv" "flv" "mpg" "mpeg" "3gp")
    (audio "mp3" "flac" "m4a" "aac" "ogg" "oga" "opus" "wav" "aif" "aiff" "wma")
    (document "md" "markdown" "org" "html" "htm" "docx" "odt" "rst" "tex" "epub" "txt")
    (pdf "pdf"))
  "The kinds of file the converter knows, by extension.")

(defvar +core--convert-files nil
  "The files the converter's menu was opened on.")

(defvar +core--convert-taken nil
  "The new names a batch has given out so far, so two of its files do
not get the same one.")

(defun +core--convert-kind (file)
  "The kind of FILE, a symbol of `+core-convert-kinds', or nil."
  (let ((ext (downcase (or (file-name-extension file) ""))))
    (car (seq-find (lambda (kind) (member ext (cdr kind))) +core-convert-kinds))))

(defun +core--convert-of (kind)
  "The selected files of KIND."
  (seq-filter (lambda (file) (eq (+core--convert-kind file) kind)) +core--convert-files))

(defun +core--convert-target (file ext &optional suffix)
  "A new file beside FILE with EXT, and SUFFIX after its name, numbered
when such a file exists already."
  (let* ((base (concat (file-name-sans-extension file) (if suffix (concat "-" suffix) "")))
         (target (concat base "." ext))
         (n 1))
    (while (or (file-exists-p target) (member target +core--convert-taken))
      (setq n (1+ n) target (format "%s-%d.%s" base n ext)))
    (push target +core--convert-taken)
    target))

(defun +core--convert-dir (file suffix)
  "A new folder beside FILE named after it with SUFFIX, numbered when
such a folder exists, made."
  (let* ((base (concat (file-name-sans-extension file) "-" suffix))
         (dir base) (n 1))
    (while (file-exists-p dir)
      (setq n (1+ n) dir (format "%s-%d" base n)))
    (make-directory dir t)
    dir))


;;
;;; Running

(defvar +core--convert-log "*Conversions*"
  "Where a failed conversion's command and output are kept.")

(defun +core--convert-run (jobs &optional parallel)
  "Run JOBS, each (COMMAND . OUTPUT), PARALLEL at a time (one by default),
in the background, and say how it went. A failed one's output is
deleted, when it made it."
  (when-let* ((missing (seq-find (lambda (job) (not (executable-find (caar job)))) jobs)))
    (user-error "No %s: see doom doctor" (caar missing)))
  (let ((queue jobs) (running 0) (done 0) (failed nil) (total (length jobs))
        (dirs (delete-dups (mapcar (lambda (job) (file-name-directory (cdr job))) jobs)))
        next)
    (setq next
          (lambda ()
            (while (and queue (< running (or parallel 1)))
              (pcase-let* ((`(,command . ,output) (pop queue))
                           (buffer (generate-new-buffer " *convert*"))
                           (existed (file-exists-p output))
                           ;; Beside the file, where pandoc finds its pictures.
                           (default-directory (file-name-directory (directory-file-name output)))
                           ;; ffmpeg colours its errors, which the log would show raw.
                           (process-environment (cons "AV_LOG_FORCE_NOCOLOR=1" process-environment)))
                (setq running (1+ running))
                (make-process
                 :name "convert" :buffer buffer :noquery t :command command
                 :sentinel
                 (lambda (process _event)
                   (unless (process-live-p process)
                     (setq running (1- running) done (1+ done))
                     (unless (zerop (process-exit-status process))
                       (push (file-name-nondirectory output) failed)
                       (unless (and existed (not (file-directory-p output)))
                         (ignore-errors
                           (if (file-directory-p output)
                               (delete-directory output t)
                             (delete-file output))))
                       (let ((said (with-current-buffer buffer (buffer-string))))
                         (with-current-buffer (get-buffer-create +core--convert-log)
                           (goto-char (point-max))
                           (insert (format "$ %s\n%s\n" (mapconcat #'shell-quote-argument command " ")
                                           said)))))
                     (kill-buffer buffer)
                     (if (< done total)
                         (progn (message "Converting... %d of %d" done total)
                                (funcall next))
                       (when (fboundp 'dired-buffers-for-dir)
                         (dolist (dir dirs)
                           (dolist (dired (dired-buffers-for-dir dir))
                             (with-current-buffer dired (revert-buffer)))))
                       (message (if failed
                                    (format "Converted %d of %d; %s failed, see %s"
                                            (- total (length failed)) total
                                            (string-join (nreverse failed) ", ")
                                            +core--convert-log)
                                  (format "Converted %d file%s" total (if (= total 1) "" "s"))))))))))))
    (if (null jobs)
        (user-error "Nothing here to convert that way")
      (message "Converting %d file%s..." total (if (= total 1) "" "s"))
      (funcall next))))

(defun +core--convert-each (kind make &optional parallel)
  "Run MAKE on each selected file of KIND, which returns (COMMAND . OUTPUT)."
  (let ((+core--convert-taken nil))
    (+core--convert-run (mapcar make (+core--convert-of kind)) parallel)))


;;
;;; Pictures

(defun +core--image-to (ext)
  "Convert the selected pictures to EXT."
  (let ((options (pcase ext ("jpg" "[Q=90]") ("webp" "[Q=85]") ("avif" "[Q=60]") (_ ""))))
    (+core--convert-each
     'image
     (lambda (file)
       (let ((out (+core--convert-target file ext)))
         (cons (if (executable-find "vips")
                   (list "vips" "copy" file (concat out options))
                 (list "magick" (concat file "[0]") out))
               out)))
     4)))

;;;###autoload
(defun +core/convert-to-png () "Pictures to PNG." (interactive) (+core--image-to "png"))
;;;###autoload
(defun +core/convert-to-jpg () "Pictures to JPEG." (interactive) (+core--image-to "jpg"))
;;;###autoload
(defun +core/convert-to-webp () "Pictures to WebP." (interactive) (+core--image-to "webp"))
;;;###autoload
(defun +core/convert-to-avif () "Pictures to AVIF." (interactive) (+core--image-to "avif"))

;;;###autoload
(defun +core/convert-resize (size)
  "Resize the selected pictures: SIZE is the long side in pixels, or a
percentage such as 50%."
  (interactive (list (read-string "Long side in pixels, or a percentage (50%): ")))
  (let ((percent (string-suffix-p "%" size))
        (n (string-to-number size)))
    (when (<= n 0) (user-error "Not a size: %s" size))
    (+core--convert-each
     'image
     (lambda (file)
       (let* ((ext (downcase (file-name-extension file)))
              ;; vips writes neither of these.
              (ext (if (member ext '("bmp" "psd")) "png" ext))
              (out (+core--convert-target file ext (if percent (format "%dpc" n) (number-to-string n)))))
         (cons (cond ((not (executable-find "vips"))
                      (list "magick" file "-resize" (if percent size (format "%dx%d>" n n)) out))
                     (percent (list "vips" "resize" file out (number-to-string (/ n 100.0))))
                     (t (list "vips" "thumbnail" file out (number-to-string n) "--size" "down")))
               out)))
     4)))

;;;###autoload
(defun +core/convert-strip-metadata ()
  "Copies of the selected pictures without their metadata: place, camera,
dates. The way up and the colour profile are kept."
  (interactive)
  (+core--convert-each
   'image
   (lambda (file)
     (let ((out (+core--convert-target file (downcase (file-name-extension file)) "clean")))
       (cons (if (executable-find "exiftool")
                 (list "exiftool" "-q" "-all=" "-tagsfromfile" "@" "-icc_profile" "-Orientation"
                       "-o" out file)
               ;; Without exiftool the picture is turned upright instead.
               (list "vips" "autorot" file (concat out "[strip]")))
             out)))
   4))


;;
;;; Video and audio

(defun +core--ffmpeg (input output &rest args)
  "An ffmpeg command from INPUT to OUTPUT with ARGS between."
  `("ffmpeg" "-nostdin" "-n" "-hide_banner" "-loglevel" "error" "-i" ,input ,@args ,output))

;;;###autoload
(defun +core/convert-to-mp4 ()
  "Videos to MP4 (H.264 and AAC), which plays everywhere."
  (interactive)
  (+core--convert-each
   'video
   (lambda (file)
     (let ((out (+core--convert-target file "mp4")))
       (cons (+core--ffmpeg file out "-c:v" "libx264" "-crf" "20" "-preset" "medium"
                            "-c:a" "aac" "-b:a" "160k" "-movflags" "+faststart")
             out)))))

;;;###autoload
(defun +core/convert-to-webm ()
  "Videos to WebM (VP9 and Opus)."
  (interactive)
  (+core--convert-each
   'video
   (lambda (file)
     (let ((out (+core--convert-target file "webm")))
       (cons (+core--ffmpeg file out "-c:v" "libvpx-vp9" "-crf" "32" "-b:v" "0"
                            "-c:a" "libopus" "-b:a" "128k")
             out)))))

;;;###autoload
(defun +core/convert-compress-video ()
  "Smaller videos for sending: at most 1280 wide, H.264 at a lower quality."
  (interactive)
  (+core--convert-each
   'video
   (lambda (file)
     (let ((out (+core--convert-target file "mp4" "small")))
       (cons (+core--ffmpeg file out "-vf" "scale='min(1280,iw)':-2" "-c:v" "libx264"
                            "-crf" "28" "-preset" "slow" "-c:a" "aac" "-b:a" "96k"
                            "-movflags" "+faststart")
             out)))))

(defun +core--read-time (prompt)
  "A time read as seconds, minutes:seconds or h:mm:ss."
  (let ((time (read-string prompt)))
    (unless (string-match-p "\\`[0-9:.]+\\'" time) (user-error "Not a time: %s" time))
    time))

;;;###autoload
(defun +core/convert-clip (start end)
  "A clip of each selected video from START to END, as m:ss or seconds."
  (interactive (list (+core--read-time "From (m:ss): ") (+core--read-time "To (m:ss): ")))
  (+core--convert-each
   'video
   (lambda (file)
     (let ((out (+core--convert-target file "mp4" "clip")))
       (cons `("ffmpeg" "-nostdin" "-n" "-hide_banner" "-loglevel" "error"
               "-ss" ,start "-to" ,end "-i" ,file "-c:v" "libx264" "-crf" "18"
               "-c:a" "aac" "-b:a" "160k" "-movflags" "+faststart" ,out)
             out)))))

;;;###autoload
(defun +core/convert-gif (start length)
  "A GIF of each selected video, LENGTH seconds from START."
  (interactive (list (+core--read-time "From (m:ss): ")
                     (read-number "Seconds long: " 5)))
  (+core--convert-each
   'video
   (lambda (file)
     (let ((out (+core--convert-target file "gif")))
       (cons `("ffmpeg" "-nostdin" "-n" "-hide_banner" "-loglevel" "error"
               "-ss" ,start "-t" ,(number-to-string length) "-i" ,file
               "-vf" "fps=12,scale=480:-1:flags=lanczos,split[a][b];[a]palettegen[p];[b][p]paletteuse"
               ,out)
             out)))))

(defvar +core--ffmpeg-encoders nil
  "The encoders this ffmpeg has, asked once.")

(defun +core--ffmpeg-has (encoder)
  "Non-nil when ffmpeg has ENCODER."
  (unless +core--ffmpeg-encoders
    (setq +core--ffmpeg-encoders
          (ignore-errors (process-lines "ffmpeg" "-hide_banner" "-encoders"))))
  (seq-some (lambda (line) (string-match-p (concat " " (regexp-quote encoder) " ") line))
            +core--ffmpeg-encoders))

(defun +core--audio-args (ext)
  "ffmpeg's encoder arguments for audio as EXT."
  (pcase ext
    ("mp3" '("-c:a" "libmp3lame" "-q:a" "2"))
    ("flac" '("-c:a" "flac"))
    ("m4a" '("-c:a" "aac" "-b:a" "192k"))
    ;; Vorbis where ffmpeg has it; Homebrew's has Opus only.
    ("ogg" (if (+core--ffmpeg-has "libvorbis")
               '("-c:a" "libvorbis" "-q:a" "5")
             '("-c:a" "libopus" "-b:a" "160k")))
    ("opus" '("-c:a" "libopus" "-b:a" "128k"))
    ("wav" '("-c:a" "pcm_s16le"))))

(defun +core--audio-to (ext)
  "The selected audio, and the sound of the selected videos, as EXT."
  (let ((+core--convert-taken nil))
    (+core--convert-run
     (mapcar (lambda (file)
               (let ((out (+core--convert-target file ext)))
                 (cons (apply #'+core--ffmpeg file out "-vn" (+core--audio-args ext)) out)))
             (append (+core--convert-of 'audio) (+core--convert-of 'video)))
     2)))

;;;###autoload
(defun +core/convert-to-mp3 () "Audio, or a video's sound, to MP3." (interactive) (+core--audio-to "mp3"))
;;;###autoload
(defun +core/convert-to-flac () "Audio, or a video's sound, to FLAC." (interactive) (+core--audio-to "flac"))
;;;###autoload
(defun +core/convert-to-m4a () "Audio, or a video's sound, to M4A." (interactive) (+core--audio-to "m4a"))
;;;###autoload
(defun +core/convert-to-ogg () "Audio, or a video's sound, to Ogg." (interactive) (+core--audio-to "ogg"))
;;;###autoload
(defun +core/convert-to-wav () "Audio, or a video's sound, to WAV." (interactive) (+core--audio-to "wav"))


;;
;;; Documents and PDFs

(defun +core--pdf-engine ()
  "The program pandoc writes a PDF with, or nil."
  (seq-find #'executable-find '("xelatex" "lualatex" "pdflatex" "tectonic" "weasyprint" "wkhtmltopdf")))

(defun +core--document-to (ext)
  "The selected documents to EXT, through pandoc."
  (when (and (equal ext "pdf") (not (+core--pdf-engine)))
    (user-error "No PDF engine: install a LaTeX (brew install --cask basictex)"))
  (+core--convert-each
   'document
   (lambda (file)
     (let ((out (+core--convert-target file ext)))
       (cons `("pandoc" ,file "-o" ,out "--standalone"
               ,@(and (equal ext "html") '("--embed-resources"))
               ,@(and (equal ext "pdf") (list (concat "--pdf-engine=" (+core--pdf-engine)))))
             out)))
   2))

;;;###autoload
(defun +core/convert-to-docx () "Documents to Word." (interactive) (+core--document-to "docx"))
;;;###autoload
(defun +core/convert-to-odt () "Documents to OpenDocument." (interactive) (+core--document-to "odt"))
;;;###autoload
(defun +core/convert-to-html () "Documents to a web page." (interactive) (+core--document-to "html"))
;;;###autoload
(defun +core/convert-to-pdf () "Documents to PDF." (interactive) (+core--document-to "pdf"))
;;;###autoload
(defun +core/convert-to-markdown () "Documents to Markdown." (interactive) (+core--document-to "md"))
;;;###autoload
(defun +core/convert-to-org () "Documents to Org." (interactive) (+core--document-to "org"))

;;;###autoload
(defun +core/convert-pdf-pages ()
  "Each page of the selected PDFs as a PNG, in a folder beside it."
  (interactive)
  (+core--convert-each
   'pdf
   (lambda (file)
     (let ((dir (+core--convert-dir file "pages")))
       (cons (list "pdftoppm" "-png" "-r" "150" file
                   (expand-file-name (file-name-base file) dir))
             dir)))
   2))

;;;###autoload
(defun +core/convert-pdf-merge ()
  "The selected PDFs as one, in the order they are listed."
  (interactive)
  (let ((pdfs (+core--convert-of 'pdf)))
    (when (< (length pdfs) 2) (user-error "Mark two PDFs or more"))
    (let* ((+core--convert-taken nil)
           (out (+core--convert-target (car pdfs) "pdf" "merged")))
      (+core--convert-run (list (cons (append '("pdfunite") pdfs (list out)) out))))))

;;;###autoload
(defun +core/convert-pdf-split ()
  "Each page of the selected PDFs as a PDF of its own, in a folder beside it."
  (interactive)
  (+core--convert-each
   'pdf
   (lambda (file)
     (let ((dir (+core--convert-dir file "split")))
       ;; Not the file's own name: pdfseparate reads a % in it as its own.
       (cons (list "pdfseparate" file (expand-file-name "page-%d.pdf" dir))
             dir)))))


;;
;;; The menu

;;;###autoload (autoload '+core/convert-menu "private/core/autoload/convert" nil t)
(transient-define-prefix +core/convert-menu ()
  "Convert the selected files into new ones beside them."
  [:description
   (lambda () (format "Convert %d file%s into new ones beside them"
                      (length +core--convert-files)
                      (if (cdr +core--convert-files) "s" "")))
   ["Pictures"
    :if (lambda () (+core--convert-of 'image))
    ("p" "to PNG" +core/convert-to-png)
    ("j" "to JPEG" +core/convert-to-jpg)
    ("w" "to WebP" +core/convert-to-webp)
    ("a" "to AVIF" +core/convert-to-avif)
    ("r" "resize" +core/convert-resize)
    ("x" "without metadata" +core/convert-strip-metadata)]
   ["Video"
    :if (lambda () (+core--convert-of 'video))
    ("4" "to MP4" +core/convert-to-mp4)
    ("W" "to WebM" +core/convert-to-webm)
    ("s" "smaller, for sending" +core/convert-compress-video)
    ("c" "a clip" +core/convert-clip)
    ("g" "a GIF" +core/convert-gif)]
   ["Audio"
    :if (lambda () (or (+core--convert-of 'audio) (+core--convert-of 'video)))
    ("3" "to MP3" +core/convert-to-mp3)
    ("f" "to FLAC" +core/convert-to-flac)
    ("m" "to M4A" +core/convert-to-m4a)
    ("o" "to Ogg" +core/convert-to-ogg)
    ("v" "to WAV" +core/convert-to-wav)]
   ["Documents"
    :if (lambda () (+core--convert-of 'document))
    ("d" "to Word" +core/convert-to-docx)
    ("O" "to OpenDocument" +core/convert-to-odt)
    ("h" "to a web page" +core/convert-to-html)
    ("P" "to PDF" +core/convert-to-pdf)
    ("M" "to Markdown" +core/convert-to-markdown)
    ("R" "to Org" +core/convert-to-org)]
   ["PDF"
    :if (lambda () (+core--convert-of 'pdf))
    ("i" "pages as pictures" +core/convert-pdf-pages)
    ("u" "merge into one" +core/convert-pdf-merge)
    ("S" "split into pages" +core/convert-pdf-split)]])

;;;###autoload
(defun +core/convert ()
  "Convert the marked files, or the one at point or in this buffer, into
new files beside them."
  (interactive)
  (setq +core--convert-files
        (cond ((derived-mode-p 'dired-mode) (dired-get-marked-files))
              (buffer-file-name (list buffer-file-name))
              (t (user-error "No file here"))))
  (unless (seq-some #'+core--convert-kind +core--convert-files)
    (user-error "Nothing here the converter knows"))
  (call-interactively #'+core/convert-menu))
