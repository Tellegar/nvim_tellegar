--- cmake_menu.tab_roots — the tracked-projects list: every root
--- cpp_project.project_store has a saved config for.
---
--- A read-only view for now (todo item 6's add/remove management isn't wired
--- yet). Its point is to make the store's contents visible: known_projects is
--- what makes a saved project resolve to the same root across restarts, so
--- being able to see exactly which roots are in there is how you tell a
--- resolution problem from a tracking problem.
---
--- Re-reads the store on every render (cheap - project_store.read only
--- re-parses when the file's mtime moved), so another nvim instance's save or
--- removal shows up on the next render without a watcher.

local HL = require("cmake_menu.hl")
local actions = require("cmake_menu.actions")
local cpp_project = require("cpp_project")
local float = require("cmake_menu.float")
local project = require("cpp_project.session")
local project_store = require("cpp_project.project_store")
local render_mod = require("cmake_menu.render")
local tabs = require("cmake_menu.tabs")

local M = {}

local state = { sel = 1 }
local acts = actions.new()

--- One row per tracked root, the current session's root marked. The selected
--- config is shown alongside so the list says what each project is set to,
--- not just that it exists.
---@param r CMenu.Render
local function body_items(r)
	local roots = project_store.roots()
	if #roots == 0 then
		r:line2{{ text="no tracked projects yet - <C-s> in the Project tab tracks one", hl=HL.Dim }}
		return
	end

	for _, root in ipairs(roots) do
		local entry = project_store.get(root) or {}
		local current = root == project.root
		local name = { text = (current and "> " or "  ") .. vim.fn.fnamemodify(root, ":~") }
		if current then name.hl = HL.Value end
		r:item_begin()
		r:line2{
			name,
			{ fill=true },
			{ text=entry.selected_config or "(no config)", hl=HL.Dim },
		}
		r:item_end()
	end
end

---@param m CMenu.Float
local function render(m)
	tabs.render(m.header)

	-- keep the in-memory mirror in step with what this tab is about to draw
	cpp_project.refresh_known_projects()

	local r = render_mod.new(m.body)
	r.margin = "  "
	acts:begin(r)

	r:line("")
	r:line2{{ text="tracked projects", hl=HL.Heading }}
	r:line2{{ text=project_store.file(), hl=HL.Dim }}
	r:line("")
	body_items(r)

	r:render()
	r:render_selection(state)

	do
		local text = " " .. acts:hint(state.sel)
		m.footer:set_lines({ text })
		m.footer:hl(0, 0, { end_col = #text, hl_group = HL.Dim })
	end
end

function M.open()
	local m
	local function move(delta)
		state.sel = state.sel + delta
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
