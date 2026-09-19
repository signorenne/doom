;; -*- no-byte-compile: t; -*-
;;; private/cpp/packages.el

;; Configure, build, test, run and debug per project type, with CMake
;; presets, the CMake File API and ctest.
(package! projection :pin "898c6fc2e8333fa72431f433414e5aad74455e54")
;; Targets: cmake, ctest, make, ...
(package! projection-multi :pin "898c6fc2e8333fa72431f433414e5aad74455e54")
;; Act on a target, e.g. make it default
(package! projection-multi-embark :pin "898c6fc2e8333fa72431f433414e5aad74455e54")
;; Debug an executable target
(package! projection-dape :pin "898c6fc2e8333fa72431f433414e5aad74455e54")
(package! compile-multi :pin "2976058c416b19f9761d5b8cf596210803afd2d7")
(package! compile-multi-embark :pin "2976058c416b19f9761d5b8cf596210803afd2d7")
(package! compile-multi-nerd-icons :pin "2976058c416b19f9761d5b8cf596210803afd2d7")

;; clang-format on demand; apheleia does it on save.
(package! clang-format :pin "a099177b5cd5060597d454e4c1ffdc96b92ba985")

;; Assembly beside the source, line for line, recompiled as you type.
(package! rmsbolt :pin "05c4795226f859009bc570940139473b6b6f7555")
