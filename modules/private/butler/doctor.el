;; -*- lexical-binding: t; no-byte-compile: t; -*-
;;; private/butler/doctor.el

(assert! (modulep! :private docs)
         "The butler reads his hints from the cheat sheet: enable :private docs")
(assert! (modulep! :private ui)
         "The butler stands on the dashboard and speaks its greeting: enable :private ui")
