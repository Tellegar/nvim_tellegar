--- cmake_menu.tab_test — an empty tab, for scratching out new tab content.
---
--- Renders the shared chrome (tab strip in the header, key hint in the footer)
--- and an otherwise blank body. Wired into the tab strip via cmake_menu.tabs,
--- so <Tab>/<S-Tab> cycle to it like any other tab; drop rendering into the
--- body below to try things out.

local HL = require("cmake_menu.hl")
local float = require("cmake_menu.float")
local render_mod = require("cmake_menu.render")
local tabs = require("cmake_menu.tabs")

local M = {}

local r = render_mod.new()

---@param m CMenu.Float
local function render(m)
	tabs.render(m.header)

	-- footer: key hint
	do
		local text = " tab/S-tab switch   q quit"
		m.footer:set_lines({ text })
		m.footer:hl(0, 0, { end_col = #text, hl_group = HL.Dim })
	end

	-- body (empty — scratch new content here)
	r.target = m.body
	r.margin = "  "
	r:reset()
	r:render()
end

function M.open()
	local m = float.open{ render = render }
	m:map(tabs.mappings())
	return m
end

return M
