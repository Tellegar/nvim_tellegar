--- cmake_menu.tab_project — STATIC example "Project" front page, rendered by hand.
---
--- header: the tab strip (see cmake_menu.tabs).  footer: the key hint.
--- body: project + active-config info, primary actions (build / run /
--- reconfigure), and the target list. The first action is drawn "selected".

local float = require("cmake_menu.float")
local tabs = require("cmake_menu.tabs")
local HL = require("cmake_menu.hl")

local CURRENT = "Project" -- this tab's identity in cmake_menu.tabs

local M = {}

local function render(m)
	tabs.render(m.header, CURRENT)

	-- footer: key hint
	do
		local text = " tab/S-tab switch   j/k move   enter run   q quit"
		m.footer:set_lines({ text })
		m.footer:hl(0, 0, { end_col = #text, hl_group = HL.Dim })
	end

	-- body
	local b = m.body
	local w = b:width()
	local lines, marks = {}, {}
	local function push(text) lines[#lines + 1] = text; return #lines - 1 end
	local function hl(row, col, opts) marks[#marks + 1] = { row, col, opts } end

	-- "name        value" info row, value right-aligned to the window edge
	local function info(name, value)
		local pad = math.max(1, w - #name - #value)
		local text = name .. string.rep(" ", pad) .. value
		local row = push(text)
		hl(row, #text - #value, { end_col = #text, hl_group = HL.Value })
	end
	info("project", "~/code/hello-cmake")
	info("config",  "Debug (gcc)")

	push("")

	-- primary actions; the first is drawn selected (full-row highlight)
	local function action(label, selected)
		local row = push("→ " .. label)
		if selected then
			hl(row, 0, {
				end_row = row + 1, end_col = 0, hl_eol = true,
				hl_group = HL.Selected, priority = 100,
			})
		end
	end
	action("Build", true)
	action("Run")
	action("Reconfigure")

	push("")

	do
		local row = push("Targets")
		hl(row, 0, { end_col = 7, hl_group = HL.Heading })
	end
	push("  app")
	push("  tests")
	push("  bench")

	b:set_lines(lines)
	for _, k in ipairs(marks) do b:hl(k[1], k[2], k[3]) end
end

function M.open()
	return float.open({
		render = render,
		mappings = tabs.mappings(CURRENT),
	})
end

return M
