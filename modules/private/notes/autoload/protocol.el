;;; private/notes/autoload/protocol.el -*- lexical-binding: t; -*-
;;
;; org-protocol: the browser hands a page to Emacs. The desktop needs a
;; handler for the org-protocol:// scheme, which is what this installs.

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
  (make-directory (file-name-directory +notes-protocol-desktop-file) t)
  (with-temp-file +notes-protocol-desktop-file
    (insert (string-join +notes-protocol-desktop-entry "\n") "\n"))
  (when (executable-find "update-desktop-database")
    (call-process "update-desktop-database" nil nil nil
                  (file-name-directory +notes-protocol-desktop-file)))
  (when (executable-find "xdg-mime")
    (call-process "xdg-mime" nil nil nil "default" "org-protocol.desktop"
                  "x-scheme-handler/org-protocol"))
  (+notes/protocol-bookmarklets)
  (message "Handler written to %s"
           (abbreviate-file-name +notes-protocol-desktop-file)))

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
