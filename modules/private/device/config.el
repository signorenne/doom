;;; private/device/config.el -*- lexical-binding: t; -*-
;;
;; A machine that is not this one: a board on the bench, a box on the
;; desk. Where it is and how to reach it is a plist, which another
;; module works out, the cpp module reading it from the Qt Creator
;; kit, and this one turns into the command that runs something there,
;; copies a tree over, or stops what is running.
;;
;; Nothing here runs anything: the lines are handed back, and the
;; caller decides where they go.
