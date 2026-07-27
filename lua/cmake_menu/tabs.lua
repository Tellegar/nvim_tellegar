--- cmake_menu.tabs — the header tab strip and tab switching.
---
--- render() draws  "CMake:  Project  Configure "  into the header pane, each
--- tab name wrapped in its own extmark (active vs inactive). <Tab>/<S-Tab>
--- cycle between tabs; `open` is lazy so there's no require cycle with the tabs.
---
--- A tab's identity is its name, not its slot in M.tabs: callers pass the name
--- string (e.g. "Project") to render()/mappings(), so they don't depend on the
--- ordering here. M.tabs stays ordered only to fix the strip layout and the
--- <Tab>/<S-Tab> cycle direction.

local HL = require("cmake_menu.hl")

local M = {}

-- ordered only for layout + cycle direction; identity is the `name` field
M.tabs = {
	{ name = "Project",   open = function() require("cmake_menu.tab_project").open() end },
	{ name = "Configure", open = function() require("cmake_menu.tab_configure").open() end },
}

--- Index of the tab named `name`, or nil.
---@param name string
local function index_of(name)
	for i, tab in ipairs(M.tabs) do
		if tab.name == name then return i end
	end
end

--- Draw the tab strip into the header pane.
---@param header CMenu.Pane
---@param current string   -- name of the active tab
function M.render(header, current)
	local prefix = "CMake:"
	local text = prefix
	local marks = {}
	for _, tab in ipairs(M.tabs) do
		text = text .. " "
		local col = #text
		local label = " " .. tab.name .. " "
		text = text .. label
		marks[#marks + 1] = { col, col + #label, tab.name == current and HL.TabActive or HL.TabInactive }
	end

	header:set_lines({ text })
	header:hl(0, 0, { end_col = #prefix, hl_group = HL.Heading })
	for _, mk in ipairs(marks) do
		header:hl(0, mk[1], { end_col = mk[2], hl_group = mk[3] })
	end
end

--- Open the tab `delta` steps away from the one named `current` (wraps around).
---@param current string
---@param delta integer
function M.step(current, delta)
	local i = index_of(current) or 1
	M.tabs[(i - 1 + delta) % #M.tabs + 1].open()
end

--- Mappings a tab spreads into its spec so <Tab>/<S-Tab> cycle tabs.
---@param current string
function M.mappings(current)
	return {
		{ lhs = "<Tab>",   rhs = function() M.step(current, 1) end },
		{ lhs = "<S-Tab>", rhs = function() M.step(current, -1) end },
	}
end

return M
