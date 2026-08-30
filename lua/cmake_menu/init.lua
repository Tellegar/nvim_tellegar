-- cmake_menu - the menu's single entry point (the command/keybind target).
--
-- open() captures the session once (the buffer the user was in, its resolved
-- source root) and then hands off to the tab layer. Everything downstream -
-- tab switching, each tab_*'s render - reads from cmake_menu.session and never
-- re-captures, so buf 0 becoming the float's buffer can't corrupt the state.
--
-- setup() owns the FileType c/cpp/objc/objcpp/cuda autocmd that offers the
-- menu on a project nvim hasn't seen configured yet: it's the counterpart to
-- cpp_project.clangd not autostarting - the menu is where the user confirms
-- the config to use (tab_project's "config" row) and then starts clangd
-- themselves (its "start lsp" row), which is also what marks the root known.
-- A root project_store already tracks doesn't reopen the menu on every
-- subsequent buffer in that project (see the autocmd below): its saved config
-- is loaded into cpp_project.session instead of re-offering the menu to pick
-- one.

local project = require("cpp_project.session")
local session = require("cmake_menu.session")

local M = {}

--- Open the menu at `tab` (default the first tab), for `bufnr` (default the
--- current buffer) - see cmake_menu.session.capture for why a caller driven
--- by an event's own buffer should pass it explicitly.
---@param tab string? tab name, e.g. "Project"
---@param bufnr integer?
function M.open(tab, bufnr)
	-- capture() resolves through cpp_project.session, which re-reads the store
	-- on the way: opening the menu reflects another instance's saves or
	-- removals, not this session's first read of the file.
	session.capture(bufnr)
	require("cmake_menu.tabs").open(tab or "Project")
end

--- Offer the menu on the first C/C++ buffer of a not-yet-known project root.
---
--- Guarded per-buffer (vim.b[bufnr].cmake_menu_offered), not just per-root:
--- lazy.nvim re-fires FileType (nested, synchronously) after lazy-loading any
--- plugin that also matches it, so this callback runs twice for one real
--- buffer open. Without the guard the second firing would recapture the
--- session onto whatever buffer opening the menu the first time left focused
--- (the float's own, about-to-be-recreated body pane) instead of the file
--- that triggered the event, crashing when render() reads its now-wiped
--- buffer. Scoped to the buffer (not the root) so a later, different C/C++
--- buffer in the same still-unknown project still offers the menu again.
---
--- The actual M.open() is deferred a tick (vim.schedule): when this fires for
--- the file nvim was opened on directly (`nvim src/foo.cppm`), it runs mid
--- BufReadPost/FileType, before nvim's own startup code is done positioning
--- the window/cursor for the arg buffer - opening (and entering) the float's
--- body window synchronously here just gets stomped when that startup code
--- runs afterwards and refocuses the arg window, leaving the menu open but
--- unfocused. Scheduling runs M.open() on the next tick, after nvim's own
--- post-autocmd focus handling has already happened, so entering the body
--- window sticks.
function M.setup()
	vim.api.nvim_create_autocmd("FileType", {
		group = vim.api.nvim_create_augroup("cmake_menu_autoopen", { clear = true }),
		pattern = require("cpp_project.clangd").FILETYPES,
		callback = function(args)
			if vim.b[args.buf].cmake_menu_offered then
				return
			end

			-- Resolving mirrors the store first (see cpp_project.session.resolve)
			-- and loads the root's saved config if it has one, so by the time
			-- this returns the project is set up either way - the only question
			-- left is whether to bother the user about it.
			local name = vim.api.nvim_buf_get_name(args.buf)
			local root = project.resolve(name ~= "" and name or vim.fn.getcwd())
			if not root then
				return
			end

			-- A tracked root came with a config to use, not one to pick: stay
			-- out of the way. Only an untracked one gets the menu offered.
			if project.tracked() then
				return
			end

			vim.b[args.buf].cmake_menu_offered = true
			vim.schedule(function()
				M.open("Project", args.buf)
			end)
		end,
	})
end

return M
