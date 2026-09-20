;; -*- no-byte-compile: t; -*-
;;; private/notes/packages.el
;; :lang org already brings org-modern, org-appear, org-roam, org-pomodoro,
;; ox-pandoc, ox-hugo, org-download, org-noter, org-tree-slide and toc-org.

;; Grouped agenda views
(package! org-super-agenda :pin "fb20ad9c8a9705aa05d40751682beae2d094e0fe")
;; Queries over org files
(package! org-ql :pin "4b8330a683c43bb4a2c64ccce8cd5a90c8b174ca")
;; Search and backlinks with previews
(package! consult-org-roam :pin "611d9a12e8dd4f4a53c89ffd9dba921267592cc4")
;; The graph, in a browser
(package! org-roam-ui :pin "2894dcbf56d2eca8d3cae2b1ae183f51724b5db6")
;; Org tree to a graphviz map
(package! org-mind-map :pin "95347b2f9291f5c5eb6ebac8e726c03634c61de3")
;; GitHub flavoured markdown
(package! ox-gfm :pin "4f774f13d34b3db9ea4ddb0b1edc070b1526ccbb")
;; LaTeX previews while the cursor is away
(package! org-fragtog :pin "562f6590843eeab30ac8aa2ced285aff8d590861")

;; Spaced repetition over the notes themselves; the awk scripts are its
;; indexer, so they have to ship with the package.
(package! org-fc
  :recipe (:host github :repo "l3kn/org-fc"
           :files (:defaults "awk" "docs"))
  :pin "fce1cb265445f9c08ecb6b524562115eba9ab7a6")

;; Shows another note's text inside this one, read only, without copying it.
(package! org-transclusion
  :recipe (:host github :repo "nobiot/org-transclusion")
  :pin "feda2f03db0b86bbcf109dbf729a1eee43dedbb3")

;; Keeps org-modern's blocks aligned under org-indent-mode.
(package! org-modern-indent
  :recipe (:host github :repo "jdtsmith/org-modern-indent")
  :pin "86bd83ee1ad95f123810eb3b116beb543db1960a")
