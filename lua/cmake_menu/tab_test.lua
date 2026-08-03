--- cmake_menu.tab_test — an empty tab, for scratching out new tab content.
---
--- Renders the shared chrome (tab strip in the header, key hint in the footer)
--- and an otherwise blank body. Wired into the tab strip via cmake_menu.tabs,
--- so <Tab>/<S-Tab> cycle to it like any other tab; drop rendering into the
--- body below to try things out.

local HL = require("cmake_menu.hl")
local float = require("cmake_menu.float")
local render_mod = require("cmake_menu.render")
local session = require("cmake_menu.session")
local tabs = require("cmake_menu.tabs")
local utils = require("utils")

local M = {}

local sel = 2
local r = render_mod.new()

-- scratch dropdown state
local expanded = false          -- is the dummy item's option list open
local choice                    -- the currently picked option, nil = unset
local options = { "a", "b", "c", "d" }

-- actions[i] = what <CR> does on the i-th selectable item; rebuilt each render
-- so it stays aligned with the layout as expansion adds/removes items.
local actions = {}

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
	actions = {}

	r:item_begin()
	r:line2{
		{ text="project root" },
		{ fill=true },
		{
			text=session.root or "(unset)",
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
	actions[#actions + 1] = function() end

	-- dummy item: <CR> toggles the option list; right-aligned current choice
	r:item_begin()
	r:line2{
		{ text="dummy" },
		{ fill=true },
		{
			text=choice or "(unset)",
			hl=choice and HL.Value or HL.Dim
		},
	}
	r:item_end()
	actions[#actions + 1] = function()
		expanded = not expanded
		m:render()
	end

	-- expanded option list: <CR> picks the option and collapses
	if expanded then
		for _, opt in ipairs(options) do
			r:item_begin()
			r:line2{ "  ", { text=opt } }
			r:item_end()
			actions[#actions + 1] = function()
				choice = opt
				expanded = false
				m:render()
			end
		end
	end

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
		{ lhs="<CR>",   rhs=function() if actions[sel] then actions[sel]() end end },
	}
	m:map(tabs.mappings())
	return m
end

return M
