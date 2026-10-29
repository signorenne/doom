;;; private/core/autoload/tools.el -*- lexical-binding: t; -*-
;;
;; Tools for files in the file manager: checksums and their checking,
;; comparing two files, duplicates under a folder, renaming many files with
;; a preview, and a hex view. What reads whole files runs in the
;; background.

(require 'transient)

(declare-function dired-get-marked-files "dired")
(declare-function dired-current-directory "dired")
(declare-function dired-buffers-for-dir "dired")

(defvar +core-checksum-algorithms '("sha256" "sha512" "sha1" "md5")
  "The checksums offered, the first the default.")

(defun +core--tool-files ()
  "The marked files, or the one at point, in the file manager; this
buffer's file elsewhere."
  (or (seq-remove #'file-directory-p
                  (cond ((derived-mode-p 'dired-mode) (dired-get-marked-files))
                        (buffer-file-name (list buffer-file-name))
                        (t (user-error "No file here"))))
      (user-error "No file here, only folders")))

(defun +core--digest (files algorithm done)
  "Hash FILES with ALGORITHM in the background; DONE gets ((FILE . HASH) ...)
for the files that could be read."
  (unless (executable-find "openssl") (user-error "No openssl"))
  ;; A few hundred files a run, as a command line has a limit, and one
  ;; unreadable file fails only its own line.
  (let ((chunks (seq-split files 200)) (sums nil) next)
    (setq next
          (lambda ()
            (let ((buffer (generate-new-buffer " *checksum*")))
              (make-process
               :name "checksum" :buffer buffer :noquery t
               :command (append (list "openssl" "dgst" (concat "-" algorithm) "-r") (pop chunks))
               :sentinel (lambda (process _event)
                           (unless (process-live-p process)
                             (with-current-buffer buffer
                               (goto-char (point-min))
                               (while (re-search-forward "^\\([0-9a-f]+\\) \\*\\(.+\\)$" nil t)
                                 (push (cons (match-string 2) (match-string 1)) sums)))
                             (kill-buffer buffer)
                             (cond (chunks (funcall next))
                                   (sums (funcall done (nreverse sums)))
                                   (t (message "The checksum failed")))))))))
    (funcall next)))

(defun +core--show-lines (name lines)
  "Show LINES in a buffer called NAME."
  (with-current-buffer (get-buffer-create name)
    (let ((inhibit-read-only t))
      (erase-buffer)
      (insert (string-join lines "\n") "\n")
      (goto-char (point-min))
      (special-mode))
    (pop-to-buffer (current-buffer))))


;;
;;; Checksums

;;;###autoload
(defun +core/checksum (&optional algorithm)
  "The checksum of the marked files, SHA-256 unless ALGORITHM; one file's
is copied, several are listed."
  (interactive)
  (let ((files (+core--tool-files))
        (algorithm (or algorithm (car +core-checksum-algorithms))))
    (message "Hashing %d file%s..." (length files) (if (cdr files) "s" ""))
    (+core--digest files algorithm
                   (lambda (sums)
                     (if (cdr sums)
                         (+core--show-lines (format "*%s*" (upcase algorithm))
                                            (mapcar (lambda (sum)
                                                      (format "%s  %s" (cdr sum)
                                                              (file-name-nondirectory (car sum))))
                                                    sums))
                       (kill-new (cdar sums))
                       (message "%s %s, copied" (upcase algorithm) (cdar sums)))))))

;;;###autoload
(defun +core/checksum-choose (algorithm)
  "The checksum of the marked files, as ALGORITHM."
  (interactive (list (completing-read "Checksum: " +core-checksum-algorithms nil t)))
  (+core/checksum algorithm))

(defun +core--algorithm-for (hash)
  "The algorithm HASH's length says it is, or nil."
  (pcase (length hash) (32 "md5") (40 "sha1") (64 "sha256") (128 "sha512")))

;;;###autoload
(defun +core/checksum-verify (expected)
  "Check the file at point against EXPECTED, a checksum pasted, its kind
told by its length."
  (interactive
   (list (string-trim (read-string "Expected checksum: "
                                   (ignore-errors (string-trim (current-kill 0 t)))))))
  (let* ((expected (downcase (car (split-string expected))))
         (algorithm (or (+core--algorithm-for expected)
                        (user-error "Not an MD5, SHA-1, SHA-256 or SHA-512 checksum")))
         (file (car (+core--tool-files))))
    (+core--digest (list file) algorithm
                   (lambda (sums)
                     (if (equal (cdar sums) expected)
                         (message "%s %s matches" (upcase algorithm) (file-name-nondirectory file))
                       (message "%s DOES NOT MATCH: %s is %s"
                                (upcase algorithm) (file-name-nondirectory file) (cdar sums)))))))

;;;###autoload
(defun +core/checksum-verify-list (sums-file)
  "Check every file SUMS-FILE lists, as sha256sum and friends write it:
a checksum, then a file name, a line each."
  (interactive (list (car (+core--tool-files))))
  (let* ((dir (file-name-directory sums-file))
         (wanted (with-temp-buffer
                   (insert-file-contents sums-file)
                   (let (entries)
                     (goto-char (point-min))
                     (while (re-search-forward "^\\([0-9a-fA-F]\\{32,128\\}\\) [ *]\\(.+\\)$" nil t)
                       (push (cons (expand-file-name (match-string 2) dir) (downcase (match-string 1)))
                             entries))
                     (nreverse entries))))
         (algorithm (or (and wanted (+core--algorithm-for (cdar wanted)))
                        (user-error "%s lists no checksums" (file-name-nondirectory sums-file))))
         (present (seq-filter (lambda (entry) (file-exists-p (car entry))) wanted)))
    (message "Checking %d file%s..." (length wanted) (if (cdr wanted) "s" ""))
    (let ((report
           (lambda (sums)
             (let ((lines (mapcar (lambda (entry)
                                    (let ((got (cdr (assoc (car entry) sums))))
                                      (format "%-7s %s"
                                              (cond ((null got) "MISSING")
                                                    ((equal got (cdr entry)) "OK")
                                                    (t "FAILED"))
                                              (file-relative-name (car entry) dir))))
                                  wanted)))
               (+core--show-lines "*Checksums*" lines)
               (message "%d of %d match"
                        (seq-count (lambda (line) (string-prefix-p "OK" line)) lines)
                        (length wanted))))))
      (if present
          (+core--digest (mapcar #'car present) algorithm report)
        (funcall report nil)))))


;;
;;; Comparing

;;;###autoload
(defun +core/compare-files (a b)
  "Whether files A and B are the same, and where they first differ; two
text files that differ can be compared side by side."
  (interactive
   (let ((files (+core--tool-files)))
     (if (= (length files) 2)
         files
       (list (car files) (read-file-name "Compare with: " nil nil t)))))
  (setq a (expand-file-name a) b (expand-file-name b))
  (let ((said (with-temp-buffer
                (cons (call-process "cmp" nil t nil a b)
                      ;; cmp names both files first; where they differ is the news.
                      (replace-regexp-in-string "\\`.* differ: " "" (string-trim (buffer-string)))))))
    (pcase (car said)
      (0 (message "The same, byte for byte"))
      (1 (if (and (not (+core--binary-p a)) (not (+core--binary-p b))
                  (y-or-n-p (format "They differ (%s). Side by side? " (cdr said))))
             (ediff-files a b)
           (message "They differ: %s" (cdr said))))
      (_ (message "cmp: %s" (cdr said))))))

(defun +core--binary-p (file)
  "Non-nil when FILE's first 8 KB hold a NUL."
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (insert-file-contents-literally file nil 0 8192)
    (goto-char (point-min))
    (search-forward "\0" nil t)))


;;
;;; Duplicates

(defvar-local +core--duplicates-dir nil
  "The folder the duplicates were looked for under.")

(define-derived-mode +core-duplicates-mode special-mode "Duplicates"
  "Files the same as another, a group each.
RET visits the file on the line; m marks it, u unmarks it, x sends the
marked ones to the trash, as long as each group keeps a copy."
  (setq-local truncate-lines t))

(with-eval-after-load 'evil
  (evil-define-key* 'normal +core-duplicates-mode-map
    (kbd "RET") #'+core/duplicates-visit "m" #'+core/duplicates-mark
    "u" #'+core/duplicates-unmark "x" #'+core/duplicates-trash))
(define-key +core-duplicates-mode-map (kbd "RET") #'+core/duplicates-visit)
(define-key +core-duplicates-mode-map "m" #'+core/duplicates-mark)
(define-key +core-duplicates-mode-map "u" #'+core/duplicates-unmark)
(define-key +core-duplicates-mode-map "x" #'+core/duplicates-trash)

;;;###autoload
(defun +core/find-duplicates (dir)
  "Find the files under DIR that are the same as another: those of one
size are hashed, in the background."
  (interactive (list (if (derived-mode-p 'dired-mode) (dired-current-directory)
                       (read-directory-name "Duplicates under: "))))
  (message "Looking under %s..." (abbreviate-file-name dir))
  (let ((buffer (generate-new-buffer " *find*")))
    (make-process
     :name "duplicates" :buffer buffer :noquery t
     :command (list "find" (expand-file-name dir) "-type" "f" "-size" "+0" "-not" "-path" "*/.git/*")
     :sentinel
     (lambda (process _event)
       (unless (process-live-p process)
         (let* ((files (with-current-buffer buffer (split-string (buffer-string) "\n" t)))
                (by-size (make-hash-table)))
           (kill-buffer buffer)
           (dolist (file files)
             (when-let* ((size (file-attribute-size (file-attributes file))))
               (push file (gethash size by-size))))
           (let ((candidates (let (out)
                               (maphash (lambda (_size group) (when (cdr group) (setq out (append group out))))
                                        by-size)
                               out)))
             (if (null candidates)
                 (message "No duplicates under %s" (abbreviate-file-name dir))
               (+core--digest candidates "sha256"
                              (lambda (sums) (+core--show-duplicates dir sums)))))))))))

(defun +core--show-duplicates (dir sums)
  "Show the files of SUMS, (FILE . HASH), that share a hash, under DIR."
  (let ((groups (make-hash-table :test #'equal)))
    (dolist (sum sums) (push (car sum) (gethash (cdr sum) groups)))
    (with-current-buffer (get-buffer-create "*Duplicates*")
      (let ((inhibit-read-only t) (count 0))
        (erase-buffer)
        (+core-duplicates-mode)
        (setq +core--duplicates-dir dir)
        (maphash (lambda (_hash group)
                   (when (cdr group)
                     (setq count (1+ count))
                     (insert (propertize (format "%s, %d copies\n"
                                                 (file-size-human-readable
                                                  (file-attribute-size (file-attributes (car group)))
                                                  nil " " "B")
                                                 (length group))
                                         'face 'bold))
                     (dolist (file (sort group #'string<))
                       (insert (propertize (concat "    " (file-relative-name file dir) "\n")
                                           '+core-file file '+core-group count)))
                     (insert "\n")))
                 groups)
        (goto-char (point-min))
        (insert (format "%d group%s of the same files under %s\nRET visit  m mark  u unmark  x trash the marked\n\n"
                        count (if (= count 1) "" "s") (abbreviate-file-name dir)))
        (goto-char (point-min)))
      (pop-to-buffer (current-buffer)))))

(defun +core--duplicate-at-point ()
  "The file on this line of the duplicates."
  (or (get-text-property (line-beginning-position) '+core-file)
      (user-error "No file on this line")))

;;;###autoload
(defun +core/duplicates-visit ()
  "Visit the file on this line."
  (interactive)
  (find-file (+core--duplicate-at-point)))

(defun +core--duplicates-set-mark (marked)
  "Mark this line's file when MARKED, else unmark it, and go to the next."
  (let ((inhibit-read-only t) (file (+core--duplicate-at-point)))
    (save-excursion
      (beginning-of-line)
      (delete-char 1)
      (insert (propertize (if marked "*" " ") '+core-file file
                          '+core-group (get-text-property (point) '+core-group)
                          'face (if marked 'error 'default))))
    (put-text-property (line-beginning-position) (line-end-position) '+core-marked marked)
    (forward-line 1)))

;;;###autoload
(defun +core/duplicates-mark () "Mark this file." (interactive) (+core--duplicates-set-mark t))
;;;###autoload
(defun +core/duplicates-unmark () "Unmark this file." (interactive) (+core--duplicates-set-mark nil))

;;;###autoload
(defun +core/duplicates-trash ()
  "Send the marked files to the trash."
  (interactive)
  (let (files (kept (make-hash-table)))
    (save-excursion
      (goto-char (point-min))
      (while (not (eobp))
        (when-let* ((group (get-text-property (point) '+core-group)))
          (if (get-text-property (point) '+core-marked)
              (push (get-text-property (point) '+core-file) files)
            (puthash group t kept))
          (unless (gethash group kept) (puthash group nil kept)))
        (forward-line 1)))
    (unless files (user-error "Nothing marked"))
    (when (let (bare) (maphash (lambda (_group some) (unless some (setq bare t))) kept) bare)
      (user-error "Every copy of a group is marked: leave one"))
    (when (y-or-n-p (format "Send %d file%s to the trash? " (length files) (if (cdr files) "s" "")))
      (let ((delete-by-moving-to-trash t))
        (dolist (file files) (delete-file file t)))
      (message "%d in the trash" (length files))
      (+core/find-duplicates +core--duplicates-dir))))


;;
;;; Renaming

(defvar-local +core--rename-plan nil
  "(OLD . NEW) for each file the preview would rename.")

(define-derived-mode +core-rename-mode special-mode "Rename"
  "The names the marked files would take. C-c C-c renames them, C-c C-k
or q leaves them as they are.")

(define-key +core-rename-mode-map (kbd "C-c C-c") #'+core/rename-apply)
(define-key +core-rename-mode-map (kbd "C-c C-k") #'quit-window)

(defun +core--photo-dates (files)
  "When each of FILES, photos, was taken, as YYYY-MM-DD HH.MM.SS, in a
table by file; one run of exiftool for them all."
  (let ((dates (make-hash-table :test #'equal))
        (args (make-temp-file "exiftool-args")))
    (when (executable-find "exiftool")
      (unwind-protect
          (progn
            (with-temp-file args (insert (string-join files "\n") "\n"))
            (with-temp-buffer
              (call-process "exiftool" nil (list t nil) nil "-q" "-m" "-T"
                            "-d" "%Y-%m-%d %H.%M.%S" "-Directory" "-FileName" "-DateTimeOriginal"
                            "-@" args)
              (dolist (line (split-string (buffer-string) "\n" t))
                (pcase (split-string line "\t")
                  (`(,dir ,name ,date)
                   (unless (equal date "-")
                     (puthash (expand-file-name name dir) date dates)))))))
        (delete-file args)))
    dates))

(defun +core--same-name-p (a b)
  "Non-nil when names A and B are one on this system's disks: macOS's
ignore case."
  (if (eq system-type 'darwin) (string-equal-ignore-case a b) (equal a b)))

(defun +core--bad-name-p (name)
  "Non-nil when NAME, without its folder, cannot be a file's name."
  (or (member name '("" "." ".."))
      (string-search "/" name)
      (> (string-bytes (encode-coding-string name 'utf-8)) 255)))

(defun +core--rename-clashes (plan)
  "The entries of PLAN whose new name is not a name, is taken by a file
the plan does not move, or is given to two files."
  (seq-filter (lambda (entry)
                (let ((new (cdr entry)))
                  (or (+core--bad-name-p (file-name-nondirectory new))
                      (and (file-exists-p new)
                           (not (seq-some (lambda (other) (file-equal-p new (car other))) plan)))
                      (> (seq-count (lambda (other) (+core--same-name-p (cdr other) new)) plan) 1))))
              plan))

(defun +core--rename-preview (plan)
  "Show PLAN, ((OLD . NEW) ...), and wait for C-c C-c."
  (let* ((clashes (+core--rename-clashes plan)))
    (with-current-buffer (get-buffer-create "*Rename*")
      (let ((inhibit-read-only t))
        (erase-buffer)
        (+core-rename-mode)
        (setq +core--rename-plan plan)
        (insert (if clashes
                    (propertize "Some names are taken twice, taken by a file that is there, or not names: nothing can be renamed.\n\n" 'face 'error)
                  "C-c C-c renames, C-c C-k leaves them.\n\n"))
        (dolist (entry plan)
          (insert (format "%s  ->  %s\n" (file-name-nondirectory (car entry))
                          (propertize (file-name-nondirectory (cdr entry))
                                      'face (if (memq entry clashes) 'error 'success)))))
        (goto-char (point-min)))
      (when clashes (setq +core--rename-plan nil))
      (pop-to-buffer (current-buffer)))))

;;;###autoload
(defun +core/rename-apply ()
  "Rename the files as the preview shows."
  (interactive)
  (unless +core--rename-plan (user-error "Nothing to rename, or names clash"))
  (let ((plan (seq-remove (lambda (entry) (equal (car entry) (cdr entry))) +core--rename-plan))
        (dirs nil) (moved nil))
    (when (+core--rename-clashes plan)
      (user-error "A name was taken since the preview: nothing renamed"))
    ;; Through temporary names, so swapping two names works. Each step is
    ;; (OLD TEMP NEW AT-NEW), so a failure puts every file back.
    (condition-case err
        (progn
          (dolist (entry plan)
            (let ((temp (make-temp-name (concat (file-name-directory (car entry)) ".rename-"))))
              (rename-file (car entry) temp)
              (push (list (car entry) temp (cdr entry) nil) moved)))
          (dolist (step moved)
            (rename-file (nth 1 step) (nth 2 step))
            (setf (nth 3 step) t)))
      (error
       (dolist (step moved)
         (when (nth 3 step)
           (let ((temp (make-temp-name (concat (file-name-directory (nth 2 step)) ".rename-"))))
             (ignore-errors (rename-file (nth 2 step) temp)
                            (setf (nth 1 step) temp)))))
       (dolist (step moved)
         (ignore-errors (rename-file (nth 1 step) (nth 0 step))))
       (user-error "Nothing renamed: %s" (error-message-string err))))
    (dolist (entry plan)
      (push (file-name-directory (cdr entry)) dirs)
      (when-let* ((buffer (get-file-buffer (car entry))))
        (with-current-buffer buffer (set-visited-file-name (cdr entry) nil t))))
    (quit-window t)
    (when (fboundp 'dired-buffers-for-dir)
      (dolist (dir (delete-dups dirs))
        (dolist (dired (dired-buffers-for-dir dir))
          (with-current-buffer dired (revert-buffer)))))
    (message "Renamed %d file%s" (length plan) (if (cdr plan) "s" ""))))

(defun +core--rename (make)
  "Preview the marked files renamed by MAKE, a function of the file and
its index from 1 that returns the new name without the folder."
  (let ((files (+core--tool-files)) (i 0))
    (+core--rename-preview
     (mapcar (lambda (file)
               (setq i (1+ i))
               (let ((name (funcall make file i)))
                 (when (+core--bad-name-p name) (user-error "Not a file name: %S" name))
                 (cons file (expand-file-name name (file-name-directory file)))))
             files))))

(defun +core--name-and-ext (file)
  "FILE's name without its folder and extension, and its extension with
the dot, or an empty one."
  (let ((ext (file-name-extension file t)))
    (cons (file-name-base file) (or ext ""))))

;;;###autoload
(defun +core/rename-replace (from to)
  "Rename the marked files, FROM, a regexp, replaced by TO in each name."
  (interactive (list (read-regexp "Replace: ") (read-string "With: ")))
  (+core--rename (lambda (file _i)
                   (replace-regexp-in-string from to (file-name-nondirectory file) t))))

;;;###autoload
(defun +core/rename-prefix (prefix)
  "Rename the marked files with PREFIX before each name."
  (interactive (list (read-string "Before each name: ")))
  (+core--rename (lambda (file _i) (concat prefix (file-name-nondirectory file)))))

;;;###autoload
(defun +core/rename-suffix (suffix)
  "Rename the marked files with SUFFIX after each name, before its
extension."
  (interactive (list (read-string "After each name: ")))
  (+core--rename (lambda (file _i)
                   (pcase-let ((`(,name . ,ext) (+core--name-and-ext file)))
                     (concat name suffix ext)))))

;;;###autoload
(defun +core/rename-number (base start)
  "Rename the marked files BASE and a number from START, in their order,
each keeping its extension."
  (interactive (list (read-string "Name before the number: ")
                     (read-number "First number: " 1)))
  (let ((width (length (number-to-string (+ start (length (+core--tool-files)) -1)))))
    (+core--rename (lambda (file i)
                     (format (format "%%s%%0%dd%%s" width) base (+ start i -1)
                             (cdr (+core--name-and-ext file)))))))

;;;###autoload
(defun +core/rename-lower () "Rename the marked files in lower case." (interactive)
       (+core--rename (lambda (file _i) (downcase (file-name-nondirectory file)))))
;;;###autoload
(defun +core/rename-upper () "Rename the marked files in upper case." (interactive)
       (+core--rename (lambda (file _i) (upcase (file-name-nondirectory file)))))

;;;###autoload
(defun +core/rename-photo-date ()
  "Rename the marked photos by when they were taken; one without a date
keeps its name."
  (interactive)
  (message "Reading when the photos were taken...")
  (let ((dates (+core--photo-dates (+core--tool-files)))
        (given (make-hash-table :test #'equal)))
    ;; Photos of one burst share their second, so the later ones are numbered.
    (+core--rename (lambda (file _i)
                     (if-let* ((date (gethash file dates)))
                         (let* ((ext (downcase (cdr (+core--name-and-ext file))))
                                (n (puthash (downcase (concat date ext))
                                            (1+ (gethash (downcase (concat date ext)) given 0))
                                            given)))
                           (concat date (if (> n 1) (format "-%d" n) "") ext))
                       (file-name-nondirectory file))))))


;;
;;; The menu

;;;###autoload
(defun +core/hex-view ()
  "The file at point, in hex."
  (interactive)
  (let ((file (car (+core--tool-files))))
    (when (or (< (file-attribute-size (file-attributes file)) (* 64 1024 1024))
              (y-or-n-p "Over 64 MB, which hexl reads whole. Open? "))
      (hexl-find-file file))))

;;;###autoload (autoload '+core/file-tools "private/core/autoload/tools" nil t)
(transient-define-prefix +core/file-tools ()
  "Tools for the marked files, or the one at point."
  [["Checksum"
    ("c" "SHA-256, copied" +core/checksum)
    ("C" "another kind" +core/checksum-choose)
    ("v" "verify against one pasted" +core/checksum-verify)
    ("V" "verify a sums file" +core/checksum-verify-list)]
   ["Compare"
    ("=" "two files" +core/compare-files)
    ("d" "duplicates under here" +core/find-duplicates)]
   ["Rename, with a preview"
    ("r" "replace text" +core/rename-replace)
    ("p" "a prefix" +core/rename-prefix)
    ("s" "a suffix" +core/rename-suffix)
    ("n" "numbered" +core/rename-number)
    ("l" "lower case" +core/rename-lower)
    ("u" "upper case" +core/rename-upper)
    ("t" "when the photo was taken" +core/rename-photo-date)]
   ["Look inside"
    ("h" "hex" +core/hex-view)]])
