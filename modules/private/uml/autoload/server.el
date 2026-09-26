;;; private/uml/autoload/server.el -*- lexical-binding: t; -*-
;;
;; One long-lived PlantUML process, reused for every render.
;;
;; PlantUML in executable mode starts a JVM per diagram, which is about
;; a second; its own picoweb server renders in 30 ms once warm. That
;; difference is the whole reason a preview can follow your typing. The
;; server is started when something first needs it and stays until Emacs
;; exits or you stop it.

(require 'url)
(require 'json)

(defvar +uml--server-process nil
  "The running picoweb process, or nil.")

(defvar +uml--server-port nil
  "The port the running server answers on, or nil.")

;;;###autoload
(defun +uml-server-running-p ()
  "Non-nil when our picoweb server is up."
  (and +uml--server-process (process-live-p +uml--server-process)))

(defun +uml--port-free-p (port)
  "Non-nil when nothing is listening on PORT."
  (condition-case nil
      (let ((p (make-network-process :name "uml-probe" :host "127.0.0.1"
                                     :service port :nowait nil)))
        (delete-process p)
        nil)
    (error t)))

(defun +uml--pick-port ()
  "A free port at or above `+uml-server-port'."
  (or (cl-loop for port from +uml-server-port to (+ +uml-server-port 20)
               when (+uml--port-free-p port) return port)
      (user-error "No free port for the PlantUML server near %d"
                  +uml-server-port)))

;;;###autoload
(defun +uml-server-ensure ()
  "Start the picoweb server if it is not already up, and return its port.
Waits for it to answer, since the first start has a JVM to load."
  (unless (+uml-server-running-p)
    (unless (executable-find +uml-executable)
      (user-error "No %s on PATH; SPC h r d says how to install it"
                  +uml-executable))
    (let ((port (+uml--pick-port)))
      (setq +uml--server-process
            (make-process
             :name "plantuml-picoweb"
             :buffer (get-buffer-create " *plantuml server*")
             :command (list +uml-executable (format "-picoweb:%d" port))
             :noquery t
             :sentinel
             (lambda (_proc event)
               (unless (string-match-p "\\`\\(run\\|open\\)" event)
                 (setq +uml--server-process nil +uml--server-port nil))))
            +uml--server-port port)
      ;; The first start loads a JVM; wait for it rather than failing the
      ;; render that asked for it.
      ;; Wait for it to answer: the port stops being free once it
      ;; listens. A fresh start has a JVM to load, which is the only
      ;; slow render you pay.
      (let ((deadline (+ (float-time) +uml-server-start-timeout)))
        (while (and (< (float-time) deadline) (+uml--port-free-p port))
          (sleep-for 0.1))
        (when (+uml--port-free-p port)
          (setq +uml--server-process nil +uml--server-port nil)
          (user-error "The PlantUML server did not start within %ss"
                      +uml-server-start-timeout)))))
  +uml--server-port)

;;;###autoload
(defun +uml/server-stop ()
  "Stop the PlantUML server."
  (interactive)
  (if (not (+uml-server-running-p))
      (message "The PlantUML server is not running")
    (delete-process +uml--server-process)
    (setq +uml--server-process nil +uml--server-port nil)
    (message "PlantUML server stopped")))

;;;###autoload
(defun +uml/server-restart ()
  "Stop the PlantUML server and start it again."
  (interactive)
  (when (+uml-server-running-p) (+uml/server-stop))
  (message "PlantUML server on port %d" (+uml-server-ensure)))

;;;###autoload
(defun +uml-render (source format &optional options)
  "Render SOURCE, PlantUML text, as FORMAT (a symbol, `svg' or `png').
OPTIONS are extra PlantUML flags, a list of strings; the preview uses
them to colour the diagram for the theme without touching the file.
Returns the bytes, or signals with what PlantUML said."
  (let* ((port (+uml-server-ensure))
         (url-request-method "POST")
         (url-request-extra-headers '(("Content-Type" . "application/json")))
         (url-request-data
          (encode-coding-string
           (json-encode `((source . ,source)
                          (options . ,(vconcat (list (format "-t%s" format))
                                               options))))
           'utf-8)))
    (with-current-buffer
        (url-retrieve-synchronously (format "http://127.0.0.1:%d/render" port)
                                    t t +uml-render-timeout)
      (goto-char (point-min))
      (let* ((case-fold-search t)
             (status (and (re-search-forward "^HTTP/[0-9.]+ \\([0-9]+\\)" nil t)
                          (string-to-number (match-string 1))))
             (end (save-excursion (and (re-search-forward "^\r?$" nil t) (point))))
             ;; A diagram that does not parse still comes back 200, as a
             ;; picture of the words "Syntax Error". The headers say so;
             ;; read them, so the caller can keep the last good drawing
             ;; and an export never writes the error picture to disk.
             (problem (save-excursion
                        (and (re-search-forward "^X-PlantUML-Diagram-Error: *\\(.*?\\)\r?$" end t)
                             (match-string 1))))
             (line (save-excursion
                     (and (re-search-forward "^X-PlantUML-Diagram-Error-Line: *\\([0-9]+\\)" end t)
                          (match-string 1)))))
        (when problem
          (kill-buffer)
          (error "%s" (if line (format "line %s: %s" line problem) problem)))
        (unless (search-forward "\n\n" nil t)
          (error "PlantUML sent no body"))
        (let ((body (buffer-substring-no-properties (point) (point-max))))
          (prog1 (if (and status (>= status 400))
                     (error "PlantUML: %s" (string-trim (truncate-string-to-width body 200)))
                   body)
            (kill-buffer)))))))

;;;###autoload
(defun +uml/server-status ()
  "Say whether the PlantUML server is up, and on which port."
  (interactive)
  (if (+uml-server-running-p)
      (message "PlantUML server on port %d, %s"
               +uml--server-port
               (or (ignore-errors
                     (format "%s" (car (process-command +uml--server-process))))
                   "running"))
    (message "The PlantUML server is not running; it starts with the first preview")))
