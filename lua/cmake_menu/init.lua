-- cmake_menu - the menu's single entry point (the command/keybind target).
--
-- open() captures the session once (the buffer the user was in, its resolved
-- project root) and then hands off to the tab layer. Everything downstream -
-- tab switching, each tab_*'s render - reads from cmake_menu.session and never
-- re-captures, so buf 0 becoming the float's buffer can't corrupt the state.

local session = require("cmake_menu.session")

local M = {}

--- Open the menu at `tab` (default the first tab).
---@param tab string? tab name, e.g. "Project"
function M.open(tab)
	session.capture()
	require("cmake_menu.tabs").open(tab or "Project")
end

return M
