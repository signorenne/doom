;; -*- no-byte-compile: t; -*-
;;; private/web/packages.el

;; Doom has no Svelte module: a .svelte file is a template with a script
;; and a style in it, and this mode reads it as one thing.
(package! svelte-mode :pin "ac8fba901dc790976f9893e338c8ad1241b897c6")
