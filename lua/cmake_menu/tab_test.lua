--- cmake_menu.tab_test — an empty tab, for scratching out new tab content.
---
--- Renders the shared chrome (tab strip in the header, key hint in the footer)
--- and an otherwise blank body. Wired into the tab strip via cmake_menu.tabs,
--- so <Tab>/<S-Tab> cycle to it like any other tab; drop rendering into the
--- body below to try things out.

local HL = require("cmake_menu.hl")
local actions = require("cmake_menu.actions")
local dropdown = require("cmake_menu.dropdown")
local float = require("cmake_menu.float")
local render_mod = require("cmake_menu.render")
local session = require("cmake_menu.session")
local tabs = require("cmake_menu.tabs")
local utils = require("utils")

local M = {}

-- persists across renders: selection + the current frame's action map
local sel = 2
local acts = actions.new()

-- expansion state for the source-root dropdown (just the flag; the anchor row
-- and its toggle action are rendered below, in the tab itself)
local root_dd = { expanded = false }

--- Candidate roots to override with: session.dir() and its ancestors, nearest
--- first. Recomputed each render (depends on session.buf), passed to the dropdown
--- as a function.
---@return string[]
local function root_candidates()
	local dirs = {}
	local dir = session.dir()
	while dir do
		dirs[#dirs + 1] = dir
		local parent = vim.fs.dirname(dir)
		if parent == dir then break end
		dir = parent
	end
	return dirs
end

---@param m CMenu.Float
local function render(m)
	tabs.render(m.header)

	-- footer: key hint
	do
		local text = " tab/S-tab switch   q quit"
		m.footer:set_lines({ text })
		m.footer:hl(0, 0, { end_col = #text, hl_group = HL.Dim })
	end

	-- body: a fresh render context per pass; actions rebind to it
	local r = render_mod.new(m.body)
	r.margin = "  "
	acts:begin(r)

	r:item_begin()
	r:line2{
		{ text="source root" },
		{ fill=true },
		{
			text=session.root and vim.fn.fnamemodify(session.root, ":~") or "(unset)",
			hl=session.root and HL.Value or HL.Dim
		},
	}
	r:line2{
		"   ",
		{ text="found via", hl=HL.Dim },
		{ fill=true },
		{ text=utils.inspect(session.found_via or {}),
			hl=HL.Dim
		},
	}
	r:line2{
		"   ",
		{ text="path", hl=HL.Dim },
		{ fill=true },
		{
			text=vim.fn.fnamemodify(
				vim.api.nvim_buf_get_name(session.buf),
				":~:h"
			),
			hl=HL.Dim
		},
	}
	r:item_end()
	-- the source-root row is the expandable anchor; <CR> toggles its dropdown
	acts:set{ key = "<CR>", action = function()
		root_dd.expanded = not root_dd.expanded
	end }
	acts:set{ key = "x", action = function()
		session.set_root(nil)
	end }

	-- the expansion itself: candidate roots (state-dependent) + pick callback
	dropdown.render(root_dd, r, acts, {
		choices = root_candidates,
		text = function(dir) return vim.fn.fnamemodify(dir, ":~") end,
		on_pick = session.set_root,
	})

	r:render()
	sel = r:render_selection(sel)
end

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
		{ lhs="<CR>",   rhs=function() acts:dispatch(sel, "<CR>"); m:render() end },
		{ lhs="x",      rhs=function() acts:dispatch(sel, "x"); m:render() end },
	}
	m:map(tabs.mappings())
	return m
end

return M
