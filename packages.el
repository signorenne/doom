;; -*- no-byte-compile: t; -*-
;;; $DOOMDIR/packages.el
;;
;; Packages that don't belong to one module; the rest are declared in
;; each private module's packages.el. After editing any of them, run
;; `doom sync' (SPC h r s) and restart. Every package! carries a :pin,
;; the commit installed; `doom/bump-package-at-point' moves it.
;;
;; :lang org already installs org-contrib, so ox-extra and ox-koma-letter
;; are available. platformio-mode is not used: :private cpp has its own
;; PlatformIO commands with environment selection and a real serial monitor.
