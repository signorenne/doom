;;; private/core/autoload/os.el -*- lexical-binding: t; -*-
;;
;; What the desktop does its own way on each system: opening a file in its
;; app, files on the clipboard, the trash, a notification. macOS, and
;; Linux under Wayland or X11; the commands that use these are the same
;; on both.

(declare-function url-hexify-string "url-util")
(declare-function url-unhex-string "url-util")
(defvar url-unreserved-chars)
(declare-function notifications-notify "notifications")

;;
;;; Opening a file in its app

;;;###autoload
(defun +core-os-open (target)
  "Open TARGET, a file, a directory or a URL, in the desktop's app for it:
Finder or the app macOS picks, the file manager or app xdg-open picks."
  (let ((program (cond ((featurep :system 'macos) "open")
                       ((executable-find "xdg-open"))
                       (t (user-error "xdg-open not found on PATH")))))
    (call-process program nil 0 nil target)))


;;
;;; Files on the clipboard

;; On Linux a file goes over as a file:// URI under text/uri-list, which
;; is what Dolphin, a mail and a chat read. macOS has no such text: the
;; pasteboard holds file URLs as objects, which only AppKit writes and
;; reads, so osascript does it in JavaScript, the paths as its arguments.
;; It stays a tenth of a second after writing: exiting at once, it left
;; the pasteboard short of its last file most times, the pasteboard
;; taking the files from the process after the write returns. The paths
;; come back decomposed, as macOS spells a file name, an ò as o and its
;; accent, and are composed again.
(defconst +core--macos-files-to-clipboard
  "ObjC.import('AppKit');
function run(argv) {
  var pb = $.NSPasteboard.generalPasteboard;
  pb.clearContents;
  var ok = pb.writeObjects($(argv.map(function (p) { return $.NSURL.fileURLWithPath(p); })));
  delay(0.1);
  return ok ? '' : 'failed';
}"
  "JavaScript for osascript: put the files named by its arguments on the
pasteboard.")

(defconst +core--macos-files-from-clipboard
  "ObjC.import('AppKit');
var urls = $.NSPasteboard.generalPasteboard.readObjectsForClassesOptions($([$.NSURL]), $({}));
var out = [];
for (var i = 0; i < (urls.isNil() ? 0 : urls.count); i++) {
  var url = urls.objectAtIndex(i);
  if (url.isFileURL) out.push(url.path.js);
}
out.join('\\n');"
  "JavaScript for osascript: the paths of the files on the pasteboard,
one per line.")

(defun +core--file-uri (file)
  "FILE as a file:// URI, spaces and the like escaped."
  (require 'url-util)
  (concat "file://"
          (url-hexify-string (expand-file-name file)
                             (append url-unreserved-chars '(?/ ?~)))))

(defun +core--clipboard-tool ()
  "The copy and paste commands of a Linux display, as (COPY . PASTE)."
  (cond ((and (getenv "WAYLAND_DISPLAY") (executable-find "wl-copy"))
         (cons '("wl-copy") '("wl-paste" "-n")))
        ((executable-find "xclip")
         (cons '("xclip" "-selection" "clipboard")
               '("xclip" "-selection" "clipboard" "-o")))
        (t (user-error "Neither wl-copy nor xclip is installed"))))

;;;###autoload
(defun +core-os-files-to-clipboard (files)
  "Put FILES on the system clipboard as files, the way a file manager
copies them: a file manager, a mail or a chat pastes the files."
  (if (featurep :system 'macos)
      (with-temp-buffer
        (unless (and (zerop (apply #'call-process "osascript" nil t nil
                                   "-l" "JavaScript" "-e" +core--macos-files-to-clipboard
                                   (mapcar #'expand-file-name files)))
                     (string-blank-p (buffer-string)))
          (user-error "osascript could not put the files on the clipboard: %s"
                      (string-trim (buffer-string)))))
    (let ((copy (car (+core--clipboard-tool))))
      (with-temp-buffer
        (insert (concat (mapconcat #'+core--file-uri files "\r\n") "\r\n"))
        (unless (zerop (apply #'call-process-region (point-min) (point-max)
                              (car copy) nil nil nil
                              (append (cdr copy) '("-t" "text/uri-list"))))
          (user-error "%s failed" (car copy)))))))

;;;###autoload
(defun +core-os-clipboard-files ()
  "The files on the system clipboard, those that exist: files copied in
a file manager, or paths copied as text, one per line."
  (let ((text
         (with-temp-buffer
           ;; Files first; failing that, whatever text is there.
           (if (featurep :system 'macos)
               (let ((coding-system-for-read 'utf-8-hfs))
                 (call-process "osascript" nil '(t nil) nil
                               "-l" "JavaScript" "-e" +core--macos-files-from-clipboard)
                 (when (string-blank-p (buffer-string))
                   (erase-buffer)
                   (call-process "pbpaste" nil '(t nil) nil)))
             (let ((paste (cdr (+core--clipboard-tool))))
               (unless (zerop (apply #'call-process (car paste) nil '(t nil) nil
                                     (append (cdr paste) '("-t" "text/uri-list"))))
                 (erase-buffer)
                 (apply #'call-process (car paste) nil '(t nil) nil (cdr paste)))))
           (buffer-string))))
    (require 'url-util)
    (cl-loop for line in (split-string text "[\r\n]+" t)
             for path = (if (string-prefix-p "file://" line)
                            ;; Percent-encoded UTF-8: unhexing gives the
                            ;; bytes, and a name with an accent in it is
                            ;; then neither printable nor findable.
                            (decode-coding-string
                             (url-unhex-string (substring line 7)) 'utf-8)
                          line)
             when (file-exists-p path) collect path)))


;;
;;; The trash

;; Emacs deletes into the system's trash: on Linux the freedesktop one,
;; whose info/ says where each file came from; on macOS ~/.Trash, through
;; the same call Finder makes. Where a file came from is kept by Finder
;; there, in a format of its own, so Emacs notes it for what it deletes
;; itself, and only that can be put back from here. A file deleted on
;; another disk goes to that disk's trash, which is not listed here.

;;;###autoload
(defun +core-os-trash-dir ()
  "The trash directory: `trash-directory' when set, else the system's."
  (file-name-as-directory
   (or trash-directory
       (if (featurep :system 'macos)
           "~/.Trash"
         (expand-file-name "Trash" (or (getenv "XDG_DATA_HOME") "~/.local/share"))))))

;;;###autoload
(defun +core-os-trash-files-dir ()
  "Where the trashed files themselves are, in `+core-os-trash-dir'."
  (if (and (featurep :system 'macos) (not trash-directory))
      (+core-os-trash-dir)
    (expand-file-name "files/" (+core-os-trash-dir))))

(defconst +core--trash-store "trash-origins"
  "The `doom-store' location of where the files Emacs trashed on macOS
came from, keyed by their names in the trash.")

(defun +core--trash-names ()
  "The names in the macOS trash, or `unreadable' when Emacs may not read
it: an empty trash is nil."
  (condition-case nil
      (directory-files (+core-os-trash-dir) nil directory-files-no-dot-files-regexp t)
    (file-error 'unreadable)))

(defun +core--trash-inode (file)
  "FILE's inode number, which stays with it as it moves on its disk."
  (file-attribute-inode-number (file-attributes file)))

;;;###autoload
(defun +core--trash-note-origin-a (fn filename &rest args)
  "Trash FILENAME by FN with ARGS, and note where it came from.
The name it takes in the trash is the one that was not there before:
macOS renames a file whose name the trash holds already. The record
holds the file's inode too, so another file given that name later, once
the trash was emptied, is not taken for it."
  (let ((origin (directory-file-name (expand-file-name filename)))
        (before (+core--trash-names)))
    (prog1 (apply fn filename args)
      (let ((after (+core--trash-names)))
        (when (and (listp before) (listp after))
          (let ((new (seq-difference after before)))
            (when (= (length new) 1)
              (doom-store-put (car new)
                              (cons origin (+core--trash-inode
                                            (expand-file-name (car new) (+core-os-trash-dir))))
                              nil +core--trash-store))))))))

;;;###autoload
(defun +core-os-trash-origin (file)
  "Where FILE, now in the trash, was deleted from, as (PATH . FORGET):
FORGET is called once it is back. Nil when that is not known."
  (if (and (featurep :system 'macos) (not trash-directory))
      (let ((name (file-name-nondirectory (directory-file-name file))))
        (when-let* ((entry (doom-store-get name +core--trash-store))
                    ((equal (cdr entry) (+core--trash-inode file))))
          (cons (car entry) (lambda () (doom-store-rem name +core--trash-store)))))
    (let ((info (expand-file-name
                 (concat (file-name-nondirectory (directory-file-name file))
                         ".trashinfo")
                 (expand-file-name "info/" (+core-os-trash-dir)))))
      (when (file-exists-p info)
        (require 'url-util)
        (with-temp-buffer
          (insert-file-contents info)
          (when (re-search-forward "^Path=\\(.+\\)$" nil t)
            (let ((path (decode-coding-string
                         (url-unhex-string (match-string 1)) 'utf-8)))
              ;; The spec allows a relative Path= for a trash that is not
              ;; the home one: it is relative to the volume the trash
              ;; directory sits on, which is its grandparent.
              (unless (file-name-absolute-p path)
                (setq path (expand-file-name
                            path (file-name-directory
                                  (directory-file-name (+core-os-trash-dir))))))
              (cons path (lambda () (delete-file info))))))))))


;;
;;; The debugger

;; gdb, with its DAP interpreter, where there is one; on a Mac gdb does
;; not run on Apple silicon, and LLDB is the system's debugger.

;;;###autoload
(defun +core-os-lldb-dap ()
  "The lldb-dap to debug with: Apple's first, which macOS lets attach to
a program without a debugger signed for it, else the one on PATH."
  (or (seq-find #'file-executable-p
                '("/Library/Developer/CommandLineTools/usr/bin/lldb-dap"
                  "/Applications/Xcode.app/Contents/Developer/usr/bin/lldb-dap"))
      (executable-find "lldb-dap")))

;;;###autoload
(defun +core-os-debugger ()
  "How a program built here is debugged, as the head of a dape config:
its command and type, and a stop at main.  gdb's DAP; where there is no
gdb and there is an lldb-dap, as on a Mac, lldb-dap."
  (if-let* (((not (executable-find "gdb")))
            (lldb (+core-os-lldb-dap)))
      ;; No arguments, said outright: merged over a gdb config, gdb's
      ;; --interpreter=dap would reach lldb-dap.
      `(command ,lldb
        command-args nil
        :type "lldb-dap"
        :preRunCommands ["breakpoint set --name main --one-shot true"])
    '(command "gdb"
      command-args ("--interpreter=dap")
      :type "gdb"
      :stopAtBeginningOfMainSubprogram t)))


;;
;;; Notifications

;;;###autoload
(defun +core-os-notify (title body)
  "Show a desktop notification with TITLE and BODY, or a message when the
desktop cannot."
  (condition-case nil
      (if (featurep :system 'macos)
          ;; The two texts go as arguments, so no quote in them can end
          ;; the script's own strings.
          (call-process "osascript" nil 0 nil
                        "-e" "on run argv"
                        "-e" "display notification (item 2 of argv) with title (item 1 of argv)"
                        "-e" "end run"
                        title body)
        (require 'notifications)
        (notifications-notify :title title :body body
                              :app-name "Emacs" :timeout 6000))
    (error (message "%s: %s" title body))))
