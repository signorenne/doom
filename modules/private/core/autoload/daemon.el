;;; private/core/autoload/daemon.el -*- lexical-binding: t; -*-
;;
;; One Emacs for everything: a daemon started at login, which emacsclient,
;; org-protocol and the Claude Code hooks reach, its windows opened by
;; Emacs Client.app on macOS. The first window then opens without
;; waiting for the whole config to load. Emacs Client.app still starts a
;; daemon when none runs (emacsclient -a ''), after a crash or a kill.

(defvar +core-daemon-at-login t
  "Non-nil sets the login daemon up by itself on a machine that has none,
once Emacs is idle after starting: `+core/install-daemon'.")

(defvar +core-daemon-agent-file
  (expand-file-name "~/Library/LaunchAgents/org.gnu.emacs.daemon.plist")
  "The launchd agent that starts the Emacs daemon at login, on macOS.")

(defun +core--daemon-agent-plist (emacs)
  "The launchd agent running EMACS as a daemon at login.
Not kept alive: a daemon that quits, or finds another's server, stays
gone, where launchd would start it again every ten seconds."
  (concat
   "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
   "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
   "<plist version=\"1.0\">\n<dict>\n"
   "\t<key>Label</key>\n\t<string>org.gnu.emacs.daemon</string>\n"
   "\t<key>ProgramArguments</key>\n\t<array>\n"
   "\t\t<string>" (xml-escape-string emacs) "</string>\n"
   "\t\t<string>--fg-daemon</string>\n\t</array>\n"
   "\t<key>RunAtLoad</key>\n\t<true/>\n"
   ;; Only in the desktop session, where its windows can open.
   "\t<key>LimitLoadToSessionType</key>\n\t<string>Aqua</string>\n"
   "\t<key>ProcessType</key>\n\t<string>Interactive</string>\n"
   "</dict>\n</plist>\n"))

;;;###autoload
(defun +core/install-daemon ()
  "Start an Emacs daemon at every login.
macOS: a launchd agent running this Emacs with --fg-daemon. Linux: the
systemd user unit Emacs ships, enabled. Started now too when no server
runs; otherwise from the next login, the running one left alone."
  (interactive)
  (require 'server)
  (require 'xml)
  (let ((server-name (or (getenv "EMACS_SERVER_NAME") "server")))
    (cond
     ((featurep :system 'macos)
      (let ((emacs (expand-file-name invocation-name invocation-directory)))
        (make-directory (file-name-directory +core-daemon-agent-file) t)
        (with-temp-file +core-daemon-agent-file
          (insert (+core--daemon-agent-plist emacs)))
        (if (server-running-p)
            (message "Installed %s; the daemon starts at the next login"
                     (abbreviate-file-name +core-daemon-agent-file))
          (call-process "launchctl" nil nil nil "bootstrap"
                        (format "gui/%d" (user-uid)) +core-daemon-agent-file)
          (message "Installed %s and started the daemon"
                   (abbreviate-file-name +core-daemon-agent-file)))))
     ((executable-find "systemctl")
      (with-temp-buffer
        (unless (zerop (call-process "systemctl" nil t nil "--user"
                                     "enable" "emacs.service"))
          (user-error "systemctl could not enable emacs.service: %s"
                      (string-trim (buffer-string)))))
      (unless (server-running-p)
        (call-process "systemctl" nil nil nil "--user" "start" "emacs.service"))
      (message "emacs.service enabled; the daemon starts at login"))
     (t (user-error "No launchd or systemd here to start a daemon at login")))))

;;;###autoload
(defun +core--ensure-daemon-agent ()
  "Set the login daemon up where it is not, by `+core-daemon-at-login'.
Not from a daemon of another name, a test's or bin/check-config's, nor
an Emacs given a server name of its own: neither is the one at login."
  (when (and +core-daemon-at-login
             (not (stringp (daemonp)))
             (not (getenv "EMACS_SERVER_NAME"))
             (pcase system-type
               ('darwin (not (file-exists-p +core-daemon-agent-file)))
               ('gnu/linux (and (executable-find "systemctl")
                                (not (zerop (call-process "systemctl" nil nil nil "--user"
                                                          "--quiet" "is-enabled" "emacs.service")))))))
    (condition-case err
        (+core/install-daemon)
      (error (message "Login daemon not set up: %s" (error-message-string err))))))
