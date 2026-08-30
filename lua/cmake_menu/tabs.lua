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

---@class Tab
---@field name string
---@field modname string

-- ordered only for layout + cycle direction; identity is the `name` field
---@type Tab[]
M.tabs = {
	{ name = "Project example",   modname = "cmake_menu.tab_old_project" },
	{ name = "Project",   modname = "cmake_menu.tab_project" },
	{ name = "Configure", modname = "cmake_menu.tab_configure" },
	{ name = "Roots",     modname = "cmake_menu.tab_roots" },
}

---@type integer index of current tab
M.current = 1

local function tab_open(tab)
	require(tab.modname).open()
end

--- Index of the tab named `name`, or nil.
---@param name string tab:name or tab:modname
local function index_of(name)
	for i, tab in ipairs(M.tabs) do
		if tab.name == name or tab.modname == name then
			return i
		end
	end
end

--- Draw the tab strip into the header pane.
---@param header CMenu.Pane
function M.render(header)
	local prefix = "CMake:"
	local text = prefix
	local marks = {}
	for i, tab in ipairs(M.tabs) do
		text = text .. " "
		local col = #text
		local label = " " .. tab.name .. " "
		text = text .. label
		marks[#marks + 1] = { col, col + #label, i == M.current and HL.TabActive or HL.TabInactive }
	end

	header:set_lines({ text })
	header:hl(0, 0, { end_col = #prefix, hl_group = HL.Heading })
	for _, mk in ipairs(marks) do
		header:hl(0, mk[1], { end_col = mk[2], hl_group = mk[3] })
	end
end

--- Open the tab `delta` steps away from the `current`
---@param delta integer
function M.step(delta)
	M.current = (M.current + delta - 1) % #M.tabs + 1
	tab_open(M.tabs[M.current])
end

--- Mappings a tab spreads into its spec so <Tab>/<S-Tab> cycle tabs.
function M.mappings()
	return {
		{ lhs = "<Tab>",   rhs = function() M.step( 1) end },
		{ lhs = "<S-Tab>", rhs = function() M.step(-1) end },
	}
end

---@param name string tab:name or tab:modname
function M.open(name)
	M.current = index_of(name) or 1
	tab_open(M.tabs[M.current])
end

return M
