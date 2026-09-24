;;; private/uml/autoload/preview.el -*- lexical-binding: t; -*-
;;
;; The diagram beside the text, following what you type.
;;
;; A render is cheap once the server is warm, but a keystroke is
;; cheaper still, so the refresh is debounced: typing schedules one
;; render for when you pause, and a burst of keys causes one render
;; rather than one per key. The same shape the file manager's preview
;; uses.

(declare-function +uml-render "server")
(declare-function +uml-server-ensure "server")

(defvar +uml--preview-timer nil
  "The pending refresh, so a burst of keys costs one render.")

(defvar-local +uml--preview-source nil
  "The buffer this preview was drawn from.")

(defvar +uml--preview-last nil
  "The text last rendered, so an edit that changes nothing costs nothing.")

(defvar +uml--preview-showing nil
  "The buffer the preview is currently drawn from.")

(defun +uml--preview-buffer ()
  "The buffer the diagram is drawn in."
  (get-buffer-create +uml-preview-buffer-name))

(defun +uml--preview-window ()
  "The window showing the preview, or nil."
  (get-buffer-window (+uml--preview-buffer) t))

(defun +uml--show (image-data)
  "Put IMAGE-DATA in the preview buffer, keeping the window where it is."
  (let ((buffer (+uml--preview-buffer))
        (source (current-buffer)))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert-image (create-image (string-to-unibyte image-data)
                                    (if (eq +uml-preview-format 'svg) 'svg 'png)
                                    t :scale +uml-preview-scale))
        (goto-char (point-min)))
      (setq +uml--preview-source source)
      (unless (derived-mode-p 'special-mode) (special-mode))
      (setq-local cursor-type nil))
    (setq +uml--preview-showing source)
    buffer))

(defun +uml--show-waiting ()
  "Say the diagram is being drawn, so the window appears at once.
The first drawing of a session starts a JVM, about a second; every one
after it is milliseconds."
  (with-current-buffer (+uml--preview-buffer)
    (let ((inhibit-read-only t))
      (erase-buffer)
      (insert (propertize "Drawing..." 'face 'font-lock-comment-face)))
    (unless (derived-mode-p 'special-mode) (special-mode))))

(defun +uml--show-error (message)
  "Say MESSAGE in the preview buffer, in place of a diagram."
  (with-current-buffer (+uml--preview-buffer)
    (let ((inhibit-read-only t))
      (erase-buffer)
      (insert (propertize "PlantUML could not draw this\n\n" 'face 'error)
              (propertize message 'face 'font-lock-comment-face)))
    (unless (derived-mode-p 'special-mode) (special-mode))))

;;;###autoload
(defun +uml--preview-refresh (&optional buffer)
  "Draw BUFFER, or the current one, into the preview.
Does nothing when the text has not changed since the last render."
  (with-current-buffer (or buffer (current-buffer))
    (when (derived-mode-p 'plantuml-mode)
      (let ((source (buffer-substring-no-properties (point-min) (point-max))))
        (unless (equal source +uml--preview-last)
          (setq +uml--preview-last source)
          (condition-case err
              (+uml--show (+uml-render source +uml-preview-format))
            (error (+uml--show-error (error-message-string err)))))))))

(defun +uml--preview-schedule (&rest _)
  "Ask for a refresh once the typing stops."
  (when (and +uml-preview-follow (+uml--preview-window))
    (when (timerp +uml--preview-timer) (cancel-timer +uml--preview-timer))
    (let ((buffer (current-buffer)))
      (setq +uml--preview-timer
            (run-with-idle-timer
             +uml-preview-idle nil
             (lambda ()
               (when (buffer-live-p buffer) (+uml--preview-refresh buffer))))))))

(defun +uml--display-preview-window ()
  "Put the preview in its side window, and leave the cursor where it is.

Moving to another diagram should redraw the preview for that one, which
needs a hook on every window selection. That hook is added here rather
than when the module loads: a session that never opens a diagram should
not pay for one, however small, and this config does not leave always-on
work lying around. `+uml--preview-close' takes it off again."
  (add-hook 'window-selection-change-functions #'+uml--preview-follow-h)
  (display-buffer (+uml--preview-buffer)
                  `(display-buffer-in-side-window
                    (side . ,+uml-preview-side)
                    (window-width . ,+uml-preview-width)
                    (slot . 0)
                    (window-parameters . ((no-other-window . t)
                                          (no-delete-other-windows . t))))))

;;;###autoload
(defun +uml/preview ()
  "Show this diagram beside the text, and keep it up to date."
  (interactive)
  (unless (derived-mode-p 'plantuml-mode)
    (user-error "Not a PlantUML buffer"))
  (setq +uml--preview-last nil)
  (+uml--preview-refresh)
  (+uml--display-preview-window))

;;;###autoload
(defun +uml--preview-close ()
  "Close the preview and stop following the selection."
  (remove-hook 'window-selection-change-functions #'+uml--preview-follow-h)
  (setq +uml--preview-showing nil
        +uml--preview-last nil)
  (when (timerp +uml--preview-timer)
    (cancel-timer +uml--preview-timer)
    (setq +uml--preview-timer nil))
  (when-let* ((window (+uml--preview-window)))
    (delete-window window)))

;;;###autoload
(defun +uml/preview-toggle ()
  "Open the preview beside the text, or close it."
  (interactive)
  (if (+uml--preview-window)
      (progn (+uml--preview-close) (message "Preview closed"))
    (+uml/preview)))

;;;###autoload
(defun +uml/preview-follow-toggle ()
  "Follow what you type, or wait to be asked."
  (interactive)
  (setq +uml-preview-follow (not +uml-preview-follow))
  (message "The preview %s"
           (if +uml-preview-follow "follows your typing"
             "refreshes when you ask, on SPC m p r")))

;;;###autoload
(defun +uml/preview-refresh ()
  "Draw the diagram again now."
  (interactive)
  (setq +uml--preview-last nil)
  (+uml--preview-refresh)
  (unless (+uml--preview-window) (+uml/preview)))

;;;###autoload
(defun +uml--preview-setup-h ()
  "Follow the buffer's changes, for the preview."
  (add-hook 'after-change-functions #'+uml--preview-schedule nil t))

;;;###autoload
(defun +uml/preview-format-toggle ()
  "Draw the preview as SVG or as PNG.
SVG stays sharp at any size; PNG is what a few diagram kinds render
more faithfully."
  (interactive)
  (setq +uml-preview-format (if (eq +uml-preview-format 'svg) 'png 'svg))
  (message "The preview is drawn as %s" (upcase (symbol-name +uml-preview-format)))
  (+uml/preview-refresh))

;;;###autoload
(defun +uml--preview-open-h ()
  "Open the preview beside a diagram you have actually opened.

Deferred to an idle moment and guarded on the buffer reaching a
window, so a .puml visited in the background, by a search, an export
or the scaffold, does not put a window on your screen or start a
server you did not ask for.

The window appears at once saying it is drawing, and the diagram
replaces that when it arrives: the first drawing of a session has a
JVM to start and you should not wait on it with a blank frame."
  (when +uml-preview-on-open
    (let ((buffer (current-buffer)))
      (run-with-idle-timer
       0.05 nil
       (lambda ()
         (when (and (buffer-live-p buffer)
                    (get-buffer-window buffer t)
                    (not (+uml--preview-window)))
           (with-current-buffer buffer
             (+uml--show-waiting)
             (+uml--display-preview-window)
             (run-with-idle-timer
              0.05 nil
              (lambda ()
                (when (buffer-live-p buffer)
                  (setq +uml--preview-last nil)
                  (+uml--preview-refresh buffer)))))))))))

;;;###autoload
(defun +uml--preview-follow-h (&rest _)
  "Draw whichever diagram you have moved to.
Only when the preview is already open, and only when the buffer you
are now in is a different diagram from the one on show."
  (when-let* (((+uml--preview-window))
              (buffer (window-buffer (selected-window))))
    (when (and (buffer-live-p buffer)
               (not (eq buffer +uml--preview-showing))
               (buffer-local-value 'major-mode buffer)
               (with-current-buffer buffer (derived-mode-p 'plantuml-mode)))
      (setq +uml--preview-last nil)
      (+uml--preview-refresh buffer))))

;;;###autoload
(defun +uml/preview-on-open-toggle ()
  "Open the preview with every diagram, or wait to be asked."
  (interactive)
  (setq +uml-preview-on-open (not +uml-preview-on-open))
  (message "A diagram %s"
           (if +uml-preview-on-open "opens with its preview"
             "opens on its own; SPC m p shows the preview")))
