;;; private/cpp/autoload/scaffold.el -*- lexical-binding: t; -*-
;;
;; New projects from the templates in `+cpp-templates-dir'.

(defvar +core-projects-dir)
(defvar +cpp-templates-dir)
(declare-function +core-leave-dirvish "dired")
(declare-function +core-copy-template "scaffold")
(declare-function +core-read-new-project "scaffold")
(declare-function +pio/new-project "pio")
(declare-function +cpp--qt-headers "lsp")
(declare-function +pio--read-board "pio")
(declare-function +pio--read-framework "pio")


;;
;;; Scaffolds

;;;###autoload
(defun +cpp-project-kinds ()
  "The project templates in `+cpp-templates-dir'.
A directory starting with _ is an overlay every kind is built on, not a
kind of its own."
  (when (file-directory-p +cpp-templates-dir)
    (mapcar #'file-name-nondirectory
            (seq-filter #'file-directory-p
                        (directory-files +cpp-templates-dir t "^[^._]")))))

(defun +cpp--scaffold (kind dir name)
  "Copy template KIND into DIR, replacing the placeholders with NAME.
The _base overlay goes first, what every kind shares (the editorconfig,
the gitignore, the warnings target, the agent rules); the kind's own
files go on top and win."
  (let ((src (file-name-concat +cpp-templates-dir kind))
        (base (file-name-concat +cpp-templates-dir "_base")))
    (unless (file-directory-p src)
      (user-error "No template named %s in %s" kind +cpp-templates-dir))
    (when (and (file-exists-p dir) (directory-files dir nil "^[^.]"))
      (unless (y-or-n-p (format "%s is not empty.  Continue? " dir))
        (user-error "Aborted")))
    (make-directory dir t)
    (when (file-directory-p base)
      (+core-copy-template base dir name))
    (+core-copy-template src dir name)
    (when (and (executable-find "git")
               (not (file-directory-p (expand-file-name ".git" dir)))
               (y-or-n-p "Initialise a git repository? "))
      (let ((default-directory dir))
        (call-process "git" nil nil nil "init" "-q")))
    dir))

(defun +cpp--configure-scaffold (dir)
  "Configure the project just made in DIR, so the editor knows it.
Qt's headers, doctest's, anything CMake finds or fetches: none of it can
be guessed from the file, and all of it is in the compilation database
that configuring writes.  A template configures in under a second, so it
is done here rather than left as a thing to remember."
  (when (and (executable-find "cmake")
             (file-exists-p (expand-file-name "CMakePresets.json" dir)))
    (let* ((default-directory (file-name-as-directory dir))
           ;; CMake writes what the project builds only for someone who
           ;; asked before it ran. Without the query there is no reply,
           ;; and SPC k r has no executable to offer.
           (query (expand-file-name "build/dev/.cmake/api/v1/query/codemodel-v2"
                                    dir)))
      (make-directory (file-name-directory query) t)
      (unless (file-exists-p query) (write-region "" nil query nil 'quiet))
      (with-temp-buffer
        (if (zerop (call-process "cmake" nil t nil "--preset" "dev"))
            t
          (message "Created, but cmake --preset dev failed; SPC k c to try again")
          nil)))))

(defun +cpp--add-qt-includes (dir)
  "Tell the .clangd of the project in DIR where Qt\='s headers are.
Until the project is configured clangd works from that file alone, and
Qt gives each module a directory of its own, so every #include <QObject>
in a new project is underlined until then.  The modules are the ones the
template asks CMake for; after configuring, the compilation database
answers for the rest."
  (when-let* ((headers (+cpp--qt-headers))
              (file (expand-file-name ".clangd" dir))
              ((file-exists-p file)))
    (let ((dirs (cons headers
                      (seq-filter
                       #'file-directory-p
                       (mapcar (lambda (module) (file-name-concat headers module))
                               '("QtCore" "QtGui" "QtQml" "QtQuick"
                                 "QtQuickControls2"))))))
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (when (re-search-forward "^  CompilationDatabase:" nil t)
          (goto-char (match-beginning 0))
          (dolist (d dirs) (insert (format "    - -isystem\n    - %s\n" d)))
          (write-region (point-min) (point-max) file nil 'quiet))))))

(defun +cpp--project-entry-file (dir name)
  "The file to open after creating project NAME in DIR."
  (or (seq-find #'file-exists-p
                (mapcar (lambda (f) (expand-file-name f dir))
                        (list "src/main.cpp"
                              (format "include/%s/%s.hpp" name name)
                              "CMakeLists.txt")))
      dir))

;;;###autoload
(defun +cpp/new-project (kind dir name)
  "Create project NAME from template KIND in DIR, then open it.
KIND is one of the directories in `+cpp-templates-dir': lib for a
header-only library, app for a command line program, qt for a Qt Quick
application in MVVM.  It is also \"platformio\", which is not a template
of ours but pio's own project init, asked for the board and the
framework: one key for whatever kind of project is being started."
  (interactive
   (let ((kinds (append (or (+cpp-project-kinds)
                            (user-error "No templates in %s" +cpp-templates-dir))
                        (when (executable-find "pio") '("platformio")))))
     (cons (completing-read "Template: " kinds nil t nil nil (car kinds))
           (+core-read-new-project))))
  (if (equal kind "platformio")
      (progn
        (+core-leave-dirvish)
        (+pio/new-project dir (+pio--read-board) (+pio--read-framework)))
    (+cpp--scaffold kind dir name)
    (when (equal kind "qt") (+cpp--add-qt-includes dir))
    ;; Made from a listing, the dirvish panes would stay standing round it.
    (+core-leave-dirvish)
    (let ((configured (+cpp--configure-scaffold dir)))
      (find-file (+cpp--project-entry-file dir name))
      (message "%s created from the %s template%s" name kind
               (if configured
                   " and configured: F7 builds it"
                 ". SPC k c configures it")))))

;;;###autoload
(defun +cpp/new-qt-project (dir name)
  "Create the Qt Quick MVVM project NAME in DIR."
  (interactive (+core-read-new-project))
  (+cpp/new-project "qt" dir name))
