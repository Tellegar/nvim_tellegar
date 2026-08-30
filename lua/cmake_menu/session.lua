-- cmake_menu.session - the shared per-open state for one menu instance.
--
-- The menu has a single entry point (a command/keybind). Before the float
-- opens, it captures the buffer the user was in; that buffer is fixed for the
-- whole lifetime of the menu and everything downstream keys off it.
--
-- Every tab_* reads from here instead of carrying its own source_root and
-- passing it around, and instead of re-reading buffer 0 (which becomes the
-- float's own buffer once it's open, not the user's file).
--
--   session.capture()          -- at the entry point, before opening the float
--   session.buf                -- the captured buffer (fixed for the lifetime)
--   session.root               -- resolved source root for that buffer
--   session.found_via          -- how find_root arrived at it
--   session.refresh()          -- re-resolve after a manual override changes

local cpp_project = require("cpp_project")

local M = {}

M.buf = nil        ---@type integer?
M.root = nil       ---@type string?
M.found_via = nil  ---@type CppProject.RootSource?

--- The captured buffer's file path for root resolution, or the current working
--- directory when it's an unnamed buffer (treated as if it lived in cwd).
---@return string
function M.path()
	local name = vim.api.nvim_buf_get_name(M.buf)
	return name ~= "" and name or vim.fn.getcwd()
end

--- The directory that root candidates are enumerated from (this dir and its
--- ancestors): the buffer's containing directory, or cwd for an unnamed buffer.
--- Note it's cwd itself (not dirname(cwd)) for unnamed, so cwd is a candidate.
---@return string
function M.dir()
	local name = vim.api.nvim_buf_get_name(M.buf)
	return name ~= "" and vim.fs.dirname(name) or vim.fn.getcwd()
end

--- Re-resolve the root for the already-captured buffer. Call after an override
--- (session_roots) changes so the menu reflects the new pick.
function M.refresh()
	M.root, M.found_via = cpp_project.find_root(M.path())
end

--- Pin `dir` as the session override for the captured buffer, then re-resolve.
--- Replaces the currently-resolved root rather than just adding: find_root picks
--- the *nearest* pinned ancestor, so leaving the old (deeper) pin in place would
--- keep winning and a shallower re-pick would silently do nothing.
---@param dir string|nil
function M.set_root(dir)
	if M.root then
		cpp_project.session_roots[M.root] = nil
	end
	if dir then
		cpp_project.session_roots[dir] = true
	end
	M.refresh()
end

--- Capture `bufnr` (default: the current buffer) and resolve its root. Call
--- once at the entry point, before the float opens (while buffer 0 is still
--- the user's file). Takes an explicit bufnr for callers driven by an event's
--- own buffer (e.g. cmake_menu.setup()'s FileType autocmd) rather than
--- "whatever's current" - a FileType event can be re-fired nested (lazy.nvim
--- re-triggers it after lazy-loading plugins that match it), by which point
--- the current buffer may already be the float's own body buffer from the
--- first firing, not the file that triggered it.
---@param bufnr integer?
function M.capture(bufnr)
	M.buf = bufnr or vim.api.nvim_get_current_buf()
	M.refresh()
end

return M
