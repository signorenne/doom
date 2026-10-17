;;; private/notes/autoload/protocol.el -*- lexical-binding: t; -*-
;;
;; org-protocol: the browser hands a page to Emacs. The desktop needs a
;; handler for the org-protocol:// scheme, which is what this installs:
;; a desktop entry on Linux. On macOS only an app can say which links it
;; opens, and Emacs+ brings one, Emacs Client.app; with no app for them,
;; a small one is made.

(defvar +notes-protocol-app (expand-file-name "~/Applications/OrgProtocol.app")
  "Where the macOS app that hands org-protocol:// links to Emacs is made.")

(defconst +notes--lsregister
  "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
  "The tool that tells macOS which app opens which links.")

(defun +notes--protocol-run (program &rest args)
  "Run PROGRAM with ARGS, and stop with its output if it fails."
  (with-temp-buffer
    (unless (zerop (apply #'call-process program nil t nil args))
      (user-error "%s failed: %s" (file-name-nondirectory program)
                  (string-trim (buffer-string))))))

(defun +notes--protocol-macos-handler ()
  "The app macOS opens an org-protocol:// link with, or nil."
  (with-temp-buffer
    (call-process "osascript" nil '(t nil) nil "-l" "JavaScript" "-e"
                  "ObjC.import('AppKit');
var app = $.NSWorkspace.sharedWorkspace.URLForApplicationToOpenURL($.NSURL.URLWithString('org-protocol://'));
app.isNil() ? '' : app.path.js")
    (let ((app (string-trim (buffer-string))))
      (unless (string-empty-p app) app))))

(defun +notes--install-protocol-app ()
  "Make `+notes-protocol-app' and register it for org-protocol://.
An AppleScript applet that passes the link to emacsclient; it is given
the scheme in its Info.plist, kept out of the Dock, signed again since
the plist changed, and registered."
  (let* ((client (or (executable-find "emacsclient")
                     (user-error "No emacsclient on PATH")))
         (app +notes-protocol-app)
         (plist (expand-file-name "Contents/Info.plist" app))
         (script (make-temp-file
                  "org-protocol" nil ".applescript"
                  ;; LaunchServices starts the app without the shell's
                  ;; PATH, so emacsclient is named in full.
                  (format "on open location this_URL\n\tdo shell script quoted form of %S & \" -n \" & quoted form of this_URL\nend open location\n"
                          client))))
    (unwind-protect
        (progn
          (when (file-directory-p app)
            (delete-directory app t))
          (make-directory (file-name-directory (directory-file-name app)) t)
          (+notes--protocol-run "osacompile" "-o" app script)
          (+notes--protocol-run
           "/usr/libexec/PlistBuddy"
           "-c" "Add :CFBundleIdentifier string org.gnu.emacs.org-protocol"
           "-c" "Add :LSUIElement bool true"
           "-c" "Add :CFBundleURLTypes array"
           "-c" "Add :CFBundleURLTypes:0 dict"
           "-c" "Add :CFBundleURLTypes:0:CFBundleURLName string org-protocol"
           "-c" "Add :CFBundleURLTypes:0:CFBundleURLSchemes array"
           "-c" "Add :CFBundleURLTypes:0:CFBundleURLSchemes:0 string org-protocol"
           plist)
          (+notes--protocol-run "codesign" "--force" "--sign" "-" app)
          (+notes--protocol-run +notes--lsregister "-f" app))
      (delete-file script))))

(defvar +notes-protocol-desktop-file
  (expand-file-name "~/.local/share/applications/org-protocol.desktop")
  "Where the desktop entry for the org-protocol:// scheme is written.")

(defvar +notes-protocol-desktop-entry
  '("[Desktop Entry]"
    "Name=org-protocol"
    "Comment=Hand a page to Emacs"
    "Exec=emacsclient -- %u"
    "Icon=emacs"
    "Type=Application"
    "Terminal=false"
    "NoDisplay=true"
    "Categories=Utility;TextEditor;"
    "MimeType=x-scheme-handler/org-protocol;")
  "The desktop entry that makes the browser call emacsclient.")

;;;###autoload
(defun +notes/install-protocol-handler ()
  "Register org-protocol:// with the desktop, so the browser can capture.
Emacs must be running as a server for the handler to reach it, which it is
here.  The bookmarklets to paste into the browser are printed afterwards."
  (interactive)
  (let ((said
         (if (featurep :system 'macos)
             (let ((handler (+notes--protocol-macos-handler)))
               (if (and handler (not (file-equal-p handler +notes-protocol-app)))
                   (format "org-protocol:// opens in %s already" handler)
                 (+notes--install-protocol-app)
                 (format "Handler made: %s" (abbreviate-file-name +notes-protocol-app))))
           (make-directory (file-name-directory +notes-protocol-desktop-file) t)
           (with-temp-file +notes-protocol-desktop-file
             (insert (string-join +notes-protocol-desktop-entry "\n") "\n"))
           (when (executable-find "update-desktop-database")
             (call-process "update-desktop-database" nil nil nil
                           (file-name-directory +notes-protocol-desktop-file)))
           (when (executable-find "xdg-mime")
             (call-process "xdg-mime" nil nil nil "default" "org-protocol.desktop"
                           "x-scheme-handler/org-protocol"))
           (format "Handler written to %s"
                   (abbreviate-file-name +notes-protocol-desktop-file)))))
    (+notes/protocol-bookmarklets)
    (message "%s" said)))

;;;###autoload
(defun +notes/protocol-bookmarklets ()
  "Show the bookmarklets that send the current page to Emacs."
  (interactive)
  (let ((buffer (get-buffer-create "*org-protocol bookmarklets*")))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert "#+title: Send a page to Emacs\n\n"
                "Make a bookmark in the browser for each of these, with the\n"
                "javascript: line as its address. Pressing one hands the page\n"
                "to Emacs, which opens the matching capture.\n\n"
                "* Capture the page into the reading list\n"
                "#+begin_src js\n"
                "javascript:location.href='org-protocol://capture?"
                "template=w&url='+encodeURIComponent(location.href)"
                "+'&title='+encodeURIComponent(document.title)"
                "+'&body='+encodeURIComponent(window.getSelection())\n"
                "#+end_src\n\n"
                "* Make it a reference note\n"
                "#+begin_src js\n"
                "javascript:location.href='org-protocol://roam-ref?"
                "template=w&ref='+encodeURIComponent(location.href)"
                "+'&title='+encodeURIComponent(document.title)"
                "+'&body='+encodeURIComponent(window.getSelection())\n"
                "#+end_src\n\n"
                "The second one makes a roam note whose ROAM_REFS is the URL,\n"
                "so opening the same page again finds the note you already\n"
                "wrote.\n")
        (goto-char (point-min))
        (org-mode)
        (view-mode +1)))
    (pop-to-buffer buffer)))
