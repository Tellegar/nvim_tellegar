--- cmake_menu.tab_project — STATIC example "Project" front page.
---
--- The project front page: the active project root, then the primary actions
--- grouped into "build", "config", and "tools" sections (see plan.md's mockup).
--- Values are right-aligned to the window edge; the root carries a "guessed,
--- not saved" marker. Everything here is placeholder data — this scratches the
--- layout and selection, not the wiring.
---
--- header: the tab strip (see cmake_menu.tabs).  footer: the key hint.
--- Rendered via cmake_menu.render, the same way tab_configure is.

local HL = require("cmake_menu.hl")
local float = require("cmake_menu.float")
local render_mod = require("cmake_menu.render")
local tabs = require("cmake_menu.tabs")

local M = {}

-- 1-based index into this render's `layout` (selectable items, top to bottom).
-- Module-level so it survives across renders/tab switches; clamped in render()
-- since #layout isn't known until then.
local sel = 1

local r = render_mod.new()

----------------------------------------------------------------------------------------------------
-- state (placeholder front-page data)
----------------------------------------------------------------------------------------------------

local project_root = "~/.config/nvim_tellegar"

----------------------------------------------------------------------------------------------------
-- render
----------------------------------------------------------------------------------------------------

---@param m CMenu.Float
local function render(m)
	tabs.render(m.header)

	-- footer: key hint
	do
		local text = " tab/S-tab switch   j/k move   q quit"
		m.footer:set_lines({ text })
		m.footer:hl(0, 0, { end_col = #text, hl_group = HL.Dim })
	end

	-- body
	r.target = m.body
	r.margin = "  "
	r:reset()

	-- "name ──────" section divider (heading text + a rule filling the width)
	local function section(name)
		r:line("")
		r:line2{
			{ text=string.rep("─", 2), hl=HL.Dim },
			" ",
			{ text=name, hl=HL.Heading },
			" ",
			{ fill="─", hl=HL.Dim },
		}
	end

	-- selectable action row: label left, optional value right-aligned
	local function item(label, value)
		r:item_begin()
		if value then
			r:line2{ label, { fill = true }, { text = value, hl = HL.Value } }
		else
			r:line2{ label }
		end
		r:item_end()
	end

	r:line("")

	-- project root; the ● marks a guessed, not-yet-saved value
	r:item_begin()
	r:line2{
		"Project root",
		{ fill=true },
		{ text=project_root, hl = HL.Value },
		" ",
		{ text="●", hl = HL.Action },
	}
	r:item_end()

	section("build")
	item("Configure")
	item("Build", "no target")
	item("Rebuild", "clean + build")
	item("Run")
	item("Debug")
	item("Cancel task")

	section("config")
	item("Build kit", "clang-libc++")
	item("Build type", "Debug")

	section("tools")
	item("Restart clangd")
	item("Open ccmake")

	r:render()
	sel = r:render_selection(sel)
end

----------------------------------------------------------------------------------------------------
-- open
----------------------------------------------------------------------------------------------------

function M.open()
	local m
	local function move(delta)
		sel = sel + delta
		m:render()
	end
	m = float.open{ render = render }
	m:map{
		{ lhs="j",      rhs=function() move(1) end },
		{ lhs="k",      rhs=function() move(-1) end },
		{ lhs="<Down>", rhs=function() move(1) end },
		{ lhs="<Up>",   rhs=function() move(-1) end },
	}
	m:map(tabs.mappings())
	return m
end

return M
