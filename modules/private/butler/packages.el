;; -*- no-byte-compile: t; -*-
;;; private/butler/packages.el

;; The child frame he floats in. Also pulled in by flycheck-posframe, but
;; he should not depend on that being on.
(package! posframe :pin "435055dd6894fd4e8b21b355d40c0b289211b714")
