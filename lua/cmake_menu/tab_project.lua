--- cmake_menu.tab_project — STATIC example "Project" front page, rendered by hand.
---
--- header: the tab strip (see cmake_menu.tabs).  footer: the key hint.
--- body: project + active-config info, primary actions (build / run /
--- reconfigure), and the target list. The first action is drawn "selected".

local float = require("cmake_menu.float")
local tabs = require("cmake_menu.tabs")
local HL = require("cmake_menu.hl")
local render_mod = require("cmake_menu.render")

local M = {}

local r = render_mod.new()

local function render(m)
	tabs.render(m.header)

	-- footer: key hint
	do
		local text = " tab/S-tab switch   j/k move   enter run   q quit"
		m.footer:set_lines({ text })
		m.footer:hl(0, 0, { end_col = #text, hl_group = HL.Dim })
	end

	-- body
	r.target = m.body
	r:reset()
	local w = m.body:width()

	-- "name        value" info row, value right-aligned to the window edge
	local function info(name, value)
		local pad = math.max(1, w - #name - #value)
		local text = name .. string.rep(" ", pad) .. value
		local row = r:line(text)
		r:mark(row, #text - #value, { end_col = #text, hl_group = HL.Value })
	end
	info("project", "~/code/hello-cmake")
	info("config",  "Debug (gcc)")

	r:line("")

	-- primary actions; the first is drawn selected (full-row highlight)
	local function action(label, selected)
		local row = r:line("→ " .. label)
		if selected then
			r:mark(row, 0, {
				end_row = row + 1, end_col = 0, hl_eol = true,
				hl_group = HL.Selected, priority = 100,
			})
		end
	end
	action("Build", true)
	action("Run")
	action("Reconfigure")

	r:line("")

	do
		local row = r:line("Targets")
		r:mark(row, 0, { end_col = 7, hl_group = HL.Heading })
	end
	r:line("  app")
	r:line("  tests")
	r:line("  bench")

	r:render()
end

function M.open()
	return float.open({
		render = render,
		mappings = tabs.mappings(),
	})
end

return M
