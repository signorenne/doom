;; -*- no-byte-compile: t; -*-
;;; private/ai/packages.el
;; gptel, gptel-quick and gptel-magit come from :tools llm.

;; Claude Code, connected to Emacs over MCP: it sees the buffer and the
;; diagnostics, its edits open in ediff, and it can call Emacs tools.
(package! claude-code-ide
  :recipe (:host github :repo "manzaltu/claude-code-ide.el"
           :files (:defaults (:exclude "claude-code-ide-tests.el")))
  :pin "50a3d55262805d7207889ed429ff30da96fbf68b")

;; Agents in a plain Emacs buffer over ACP, with permission buttons and
;; diffs: Claude through claude-agent-acp, others if they are installed.
(package! agent-shell :pin "5f3a8525c979ff92de0de951c9bf41e681c6b2c5")

;; agent-shell's own dependencies, pinned here so they move with it.
(package! acp :pin "2959da5fa8657da17a78ac6ceef303a50e3e69de")
(package! shell-maker :pin "b28ee61a2533e408ed180662f83bb84fc8f84ba6")

;; Lets gptel use MCP servers, through gptel-mcp-connect.
(package! mcp :pin "2d172809cbdb2a40d86b28ad73bd65547cefe0e1")

;; The MCP server above runs on eschulte's web-server. org-roam-ui's
;; simple-httpd names a repository emacs-web-server too, so a local repo
;; name of its own keeps straight from building the wrong one.
(package! web-server
  :recipe (:host github :repo "eschulte/emacs-web-server" :local-repo "web-server")
  :pin "6357a1c2d1718778503f7ee0909585094117525b")
