;;; private/uml/autoload/server.el -*- lexical-binding: t; -*-
;;
;; One long-lived PlantUML process, reused for every render.
;;
;; PlantUML in executable mode starts a JVM per diagram, which is slow;
;; its own picoweb server renders quickly once warm, which is what lets
;; a preview follow your typing. The server is started when something
;; first needs it and stays until Emacs exits or you stop it.

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

(defvar +uml--server-waiters nil
  "Functions waiting for the server started in the background, each
called with its port, or nil and why it did not start.")

(defvar +uml--server-starting nil
  "The timer watching a server start in the background, or nil.")

(defun +uml--server-start ()
  "Start the picoweb process and return its port; it is not answering
yet, since the first start has a JVM to load."
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
          +uml--server-port port)))

(defun +uml--server-answering-p ()
  "Non-nil once the started server listens: its port stops being free."
  (and (+uml-server-running-p) (not (+uml--port-free-p +uml--server-port))))

;;;###autoload
(defun +uml-server-start-async (done)
  "Start the server if it is not up, without waiting for it, and call
DONE with its port once it answers, or with nil and why it did not. A
start already under way is joined, not repeated."
  (cond
   ((and (+uml-server-running-p) (not +uml--server-starting))
    (funcall done +uml--server-port nil))
   (t
    (push done +uml--server-waiters)
    (unless +uml--server-starting
      (condition-case err
          (let ((deadline (+ (float-time) +uml-server-start-timeout))
                (finish (lambda (port problem)
                          (when (timerp +uml--server-starting)
                            (cancel-timer +uml--server-starting))
                          (setq +uml--server-starting nil)
                          (unless port
                            (when (+uml-server-running-p)
                              (delete-process +uml--server-process))
                            (setq +uml--server-process nil +uml--server-port nil))
                          (let ((waiters (nreverse +uml--server-waiters)))
                            (setq +uml--server-waiters nil)
                            ;; One that fails does not leave the others
                            ;; waiting for good.
                            (dolist (waiter waiters)
                              (with-demoted-errors "PlantUML preview: %S"
                                (funcall waiter port problem)))))))
            (+uml--server-start)
            (message "Starting PlantUML...")
            (setq +uml--server-starting
                  (run-at-time
                   0.1 0.1
                   (lambda ()
                     (cond ((+uml--server-answering-p)
                            (funcall finish +uml--server-port nil))
                           ((not (+uml-server-running-p))
                            (funcall finish nil "the PlantUML server stopped as it started; see the buffer \" *plantuml server*\""))
                           ((> (float-time) deadline)
                            (funcall finish nil (format "the PlantUML server did not start within %ss"
                                                        +uml-server-start-timeout))))))))
        (error
         (let ((waiters +uml--server-waiters))
           (setq +uml--server-waiters nil)
           (dolist (waiter waiters)
             (with-demoted-errors "PlantUML preview: %S"
               (funcall waiter nil (error-message-string err)))))))))))

;;;###autoload
(defun +uml-server-ensure ()
  "Start the picoweb server if it is not already up, and return its port.
Waits for it to answer, since the first start has a JVM to load."
  ;; One already starting in the background, for the preview: wait for
  ;; that one, whose timer says when it answers.
  (let ((deadline (+ (float-time) +uml-server-start-timeout)))
    (while (and +uml--server-starting (< (float-time) deadline))
      (sleep-for 0.1)))
  (unless (+uml-server-running-p)
    (let ((port (+uml--server-start)))
      ;; Wait for it to answer, rather than failing the render that asked
      ;; for it: the port stops being free once it listens. A server that
      ;; died at once (no java, say) is not waited for, since the wait
      ;; cannot be interrupted from the drawing's idle timer.
      (let ((process +uml--server-process)
            (deadline (+ (float-time) +uml-server-start-timeout)))
        (while (and (< (float-time) deadline) (process-live-p process)
                    (+uml--port-free-p port))
          (sleep-for 0.1))
        (when (+uml--port-free-p port)
          (setq +uml--server-process nil +uml--server-port nil)
          (if (process-live-p process)
              (user-error "The PlantUML server did not start within %ss"
                          +uml-server-start-timeout)
            (user-error "The PlantUML server stopped as it started; see the buffer \" *plantuml server*\""))))))
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
(defun +uml--request (source format options)
  "The request that renders SOURCE as FORMAT with OPTIONS, as the `url'
variables to bind around a retrieval."
  `((url-request-method . "POST")
    (url-request-extra-headers . (("Content-Type" . "application/json")))
    (url-request-data
     . ,(encode-coding-string
         (json-encode `((source . ,source)
                        (options . ,(vconcat (list (format "-t%s" format))
                                             options))))
         'utf-8))))

(defun +uml--read-response ()
  "Read the server's answer in this buffer: (ok BYTES), or (problem
MESSAGE LINE), LINE the diagram's line at fault or nil."
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
                      (string-to-number (match-string 1))))))
    (cond
     (problem (list 'problem (if line (format "line %d: %s" line problem) problem) line))
     ((not (search-forward "\n\n" nil t)) (list 'problem "PlantUML sent no body" nil))
     (t (let ((body (buffer-substring-no-properties (point) (point-max))))
          (if (and status (>= status 400))
              (list 'problem (format "PlantUML: %s"
                                     (string-trim (truncate-string-to-width body 200)))
                    nil)
            (list 'ok body)))))))

;;;###autoload
(defun +uml-render (source format &optional options)
  "Render SOURCE, PlantUML text, as FORMAT (a symbol, `svg' or `png').
OPTIONS are extra PlantUML flags, a list of strings; the preview uses
them to colour the diagram for the theme without touching the file.
Returns the bytes, or signals with what PlantUML said."
  (let ((port (+uml-server-ensure)))
    (let ((request (+uml--request source format options)))
     (cl-progv (mapcar #'car request) (mapcar #'cdr request)
      (let ((buffer (url-retrieve-synchronously
                     (format "http://127.0.0.1:%d/render" port) t t +uml-render-timeout)))
        (unless buffer (error "PlantUML did not answer within %ss" +uml-render-timeout))
        (pcase (prog1 (with-current-buffer buffer (+uml--read-response))
                 (kill-buffer buffer))
          (`(ok ,body) body)
          (`(problem ,message ,_) (error "%s" message))))))))

;;;###autoload
(defun +uml-render-async (source format options done)
  "Render SOURCE as FORMAT with OPTIONS without holding up the editor,
starting the server first when it is not up. DONE gets (ok BYTES) or
\(problem MESSAGE LINE). Returns a function that stops the render."
  (let* (buffer cancelled timer
         (stop (lambda ()
                 (setq cancelled t)
                 (when (timerp timer) (cancel-timer timer))
                 (when (buffer-live-p buffer)
                   (when-let* ((process (get-buffer-process buffer)))
                     (delete-process process))
                   (kill-buffer buffer)))))
    (+uml-server-start-async
     (lambda (port problem)
       (cond
        (cancelled)
        ((not port) (funcall done (list 'problem problem nil)))
        (t
         (let ((request (+uml--request source format options)))
          (cl-progv (mapcar #'car request) (mapcar #'cdr request)
           (condition-case err
               (setq buffer
                     (url-retrieve
                      (format "http://127.0.0.1:%d/render" port)
                      (lambda (status)
                        (when (timerp timer) (cancel-timer timer))
                        (let ((answer (if-let* ((err (plist-get status :error)))
                                          (list 'problem (format "PlantUML: %s" (cadr err)) nil)
                                        (+uml--read-response))))
                          (kill-buffer (current-buffer))
                          (unless cancelled (funcall done answer))))
                      nil t t))
             (error (funcall done (list 'problem (error-message-string err) nil))))))
         ;; A server that hangs would leave the view saying "Drawing..."
         ;; for good, and the request's buffer behind.
         (when buffer
           (setq timer
                 (run-at-time +uml-render-timeout nil
                              (lambda ()
                                (unless cancelled
                                  (funcall stop)
                                  (funcall done
                                           (list 'problem
                                                 (format "PlantUML did not answer within %ss"
                                                         +uml-render-timeout)
                                                 nil)))))))))))
    stop))

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
