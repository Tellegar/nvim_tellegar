-- cmake_menu.session - the shared per-open state for one menu instance.
--
-- The menu has a single entry point (a command/keybind). Before the float
-- opens, it captures the buffer the user was in; that buffer is fixed for the
-- whole lifetime of the menu and everything downstream keys off it.
--
-- Every tab_* reads from here instead of carrying its own project_root and
-- passing it around, and instead of re-reading buffer 0 (which becomes the
-- float's own buffer once it's open, not the user's file).
--
--   session.capture()          -- at the entry point, before opening the float
--   session.buf                -- the captured buffer (fixed for the lifetime)
--   session.root               -- resolved project root for that buffer
--   session.found_via          -- how find_root arrived at it
--   session.refresh()          -- re-resolve after a manual override changes

local cpp_project = require("cpp_project")

local M = {}

M.buf = nil        ---@type integer?
M.root = nil       ---@type string?
M.found_via = nil  ---@type CppProject.RootSource?

--- Re-resolve the root for the already-captured buffer. Call after an override
--- (session_roots) changes so the menu reflects the new pick.
function M.refresh()
	M.root, M.found_via = cpp_project.find_root(M.buf)
end

--- Capture the current buffer and resolve its root. Call once at the entry
--- point, before the float opens (while buffer 0 is still the user's file).
function M.capture()
	M.buf = vim.api.nvim_get_current_buf()
	M.refresh()
end

return M
