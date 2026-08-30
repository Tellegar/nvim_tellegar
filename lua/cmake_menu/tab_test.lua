--- cmake_menu.tab_test — an empty tab, for scratching out new tab content.
---
--- Renders the shared chrome (tab strip in the header, key hint in the footer)
--- and an otherwise blank body. Wired into the tab strip via cmake_menu.tabs,
--- so <Tab>/<S-Tab> cycle to it like any other tab; drop rendering into the
--- body below to try things out.

local HL = require("cmake_menu.hl")
local actions = require("cmake_menu.actions")
local clangd = require("cpp_project.clangd")
local cmake_presets = require("cpp_project.cmake_presets")
local cpp_project = require("cpp_project")
local dropdown = require("cmake_menu.dropdown")
local float = require("cmake_menu.float")
local render_mod = require("cmake_menu.render")
local session = require("cmake_menu.session")
local tabs = require("cmake_menu.tabs")
local utils = require("utils")

local M = {}

-- Tab state, passed by reference into the dropdown so it can mutate it in place
-- (see cmake_menu.dropdown). Persists across renders.
--   sel       - current selection index
--   dd_root   - expansion bool for the source-root dropdown (the anchor row and
--               its toggle action are rendered below, in the tab itself).
--   dd_preset - expansion bool for the cmake-preset dropdown (see body_item_preset).
local state = {
	sel = 1,
	dd_root = false,
	dd_preset = false,
}
-- the current frame's action map; persists across renders
local acts = actions.new()

----------------------------------------------------------------------------------------------------
-- build dir config: cmake_preset_name -> build_dir, same value/default/preset
-- source tracking as tab_configure.eval_config, but scoped to just these two
-- fields since that's all clangd's --compile-commands-dir needs. Manual
-- override (config.build_dir set directly, bypassing any preset) covers a
-- not-yet-created build dir - vim.ui.input just takes a typed path.
----------------------------------------------------------------------------------------------------

---@type CMake.Config
local config = {
	--cmake_preset_name = nil,
	--build_dir = nil,
}

local Source = {
	value = "value",
	default = "default",
	preset = "preset",
}

---@param root string
---@return CMake.Config eff
---@return table<string, string> source Source.* per field
local function eval_config(root)
	local eff, source = {}, {}

	local preset_resolved = config.cmake_preset_name
		and cmake_presets.resolve(root, config.cmake_preset_name)

	if config.cmake_preset_name and preset_resolved then
		eff.cmake_preset_name = config.cmake_preset_name
		source.cmake_preset_name = Source.value
	else
		eff.cmake_preset_name = nil
		source.cmake_preset_name = Source.default
	end

	if config.build_dir then
		eff.build_dir = config.build_dir
		source.build_dir = Source.value
	elseif preset_resolved and preset_resolved.build_dir then
		eff.build_dir = preset_resolved.build_dir
		source.build_dir = Source.preset
	else
		eff.build_dir = "build/debug"
		source.build_dir = Source.default
	end

	return eff, source
end

local hl_from_source = {
	value = HL.Value,
	default = HL.Dim,
	preset = HL.Dim,
}

----------------------------------------------------------------------------------------------------
-- body items: cmake preset + build dir
----------------------------------------------------------------------------------------------------

---@param r CMenu.Render
---@param eff_config CMake.Config
---@param eff_source table<string, string>
local function body_item_preset(r, eff_config, eff_source)
	r:item_begin()
	r:line2{
		"cmake preset",
		{ fill=true },
		{ text=eff_config.cmake_preset_name or "(unset)", hl=hl_from_source[eff_source.cmake_preset_name] },
	}
	r:item_end()
	acts:set{
		{ key="<CR>", desc="pick",  action=function() state.dd_preset = not state.dd_preset end },
		{ key="x",    desc="unset", action=function() config.cmake_preset_name = nil end },
	}
	dropdown.render{
		state = state,
		open = "dd_preset",
		choices = function()
			local list = { { name = nil, display = "(unset)" } }
			for _, p in ipairs(cmake_presets.list(session.root)) do
				list[#list + 1] = p
			end
			return list
		end,
		text = function(p) return p.display end,
		on_pick = function(p)
			config.cmake_preset_name = p.name
			state.dd_preset = false
		end,
	}
end

--- `path` relative to `root` when it's a descendant of it (so display never
--- grows a leading "../..") - otherwise `path` unchanged, absolute.
---@param root string?
---@param path string
---@return string
local function relative_to_root(root, path)
	if not root then return path end
	local prefix = vim.fs.normalize(root):gsub("/+$", "") .. "/"
	local norm = vim.fs.normalize(path)
	if norm:sub(1, #prefix) == prefix then
		return norm:sub(#prefix + 1)
	end
	return path
end

---@param r CMenu.Render
---@param eff_config CMake.Config
---@param eff_source table<string, string>
local function body_item_build_dir(r, eff_config, eff_source)
	r:item_begin()
	r:line2{
		"build dir",
		{ fill=true },
		{
			text=relative_to_root(session.root, eff_config.build_dir),
			hl=hl_from_source[eff_source.build_dir],
		},
	}
	r:item_end()
	acts:set{
		{ key="<CR>", desc="edit",
			action=function()
				vim.ui.input(
					{ prompt = "build dir: ", default = eff_config.build_dir },
					function(v)
						if not v then return end
						config.build_dir = (v ~= "") and v or nil
					end
				)
			end },
		{ key="x", desc="reset",
			action=function()
				config.build_dir = nil
			end },
	}
end

--- The "start lsp" row: a deliberate, explicit action rather than an
--- autostart, so it only fires once the preset/build-dir rows above read the
--- way the user wants - see cpp_project.clangd's header for why. Also marks
--- the root known, so cmake_menu.setup()'s autocmd stops offering the menu
--- for it.
---@param r CMenu.Render
local function body_item_start_lsp(r)
	r:item_begin()
	local label = cpp_project.known_projects[session.root] and "restart lsp" or "start lsp"
	r:line2{{ text="+" .. label, hl=HL.Action }}
	r:item_end()
	acts:set{
		{ key="<CR>", desc=label,
			action=function()
				clangd.start(session.buf, session.root)
				cpp_project.known_projects[session.root] = true
			end },
	}
end

--- Visual-only scratch rows: every key combo cmake_menu.keyicon knows how to
--- render, bound to nops. Select one and read the footer to check the icons
--- (not wired into open()'s m:map, so most of these don't actually fire -
--- that's fine, these items exist to be looked at, not pressed). Split across
--- several rows (max 5 actions each) just so the footer hint doesn't get cut
--- off/wrap - not a general rule for other items. Remove once keyicon's
--- rendering has been eyeballed against the real terminal font.
---@param r CMenu.Render
local function body_item_keyicon_scratch(r)
	local nop = function() end

	r:item_begin()
	r:line2{{ text="(keyicon scratch 1)", hl=HL.Dim }}
	r:item_end()
	acts:set{
		{ key="<CR>",        desc="plain",      action=nop },
		{ key="<S-CR>",      desc="shift",      action=nop },
		{ key="<C-CR>",      desc="ctrl",       action=nop },
		{ key="<C-S-CR>",    desc="ctrl+shift", action=nop },
		{ key="x",           desc="letter",     action=nop },
	}

	r:item_begin()
	r:line2{{ text="(keyicon scratch 2)", hl=HL.Dim }}
	r:item_end()
	acts:set{
		{ key="<Tab>",       desc="tab",        action=nop },
		{ key="<S-Tab>",     desc="s-tab",      action=nop },
		{ key="<Esc>",       desc="esc",        action=nop },
		{ key="<BS>",        desc="bs",         action=nop },
		{ key="<Del>",       desc="del",        action=nop },
	}

	r:item_begin()
	r:line2{{ text="(keyicon scratch 3)", hl=HL.Dim }}
	r:item_end()
	acts:set{
		{ key="<Up>",        desc="up",         action=nop },
		{ key="<Down>",      desc="down",       action=nop },
		{ key="<Left>",      desc="left",       action=nop },
		{ key="<Right>",     desc="right",      action=nop },
		{ key="<Home>",      desc="home",       action=nop },
	}

	r:item_begin()
	r:line2{{ text="(keyicon scratch 4)", hl=HL.Dim }}
	r:item_end()
	acts:set{
		{ key="<End>",       desc="end",        action=nop },
		{ key="<PageUp>",    desc="pgup",       action=nop },
		{ key="<PageDown>",  desc="pgdn",       action=nop },
		{ key="<Space>",     desc="space",      action=nop },
		{ key="<M-x>",       desc="alt",        action=nop },
	}

	r:item_begin()
	r:line2{{ text="(keyicon scratch 5)", hl=HL.Dim }}
	r:item_end()
	acts:set{
		{ key="<D-a>",       desc="cmd",        action=nop },
	}
end

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

----------------------------------------------------------------------------------------------------
-- render
----------------------------------------------------------------------------------------------------

---@param m CMenu.Float
local function render(m)
	tabs.render(m.header)

	-- body: a fresh render context per pass; actions rebind to it
	local r = render_mod.new(m.body)
	r.margin = "  "
	acts:begin(r)

	r:line("")
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
	acts:set{ key = "<CR>", desc = "pick", action = function()
		state.dd_root = not state.dd_root
	end }
	acts:set{ key = "x", desc = "clear override", action = function()
		session.set_root(nil)
	end }

	-- the expansion itself: candidate roots (state-dependent) + pick callback.
	-- render() also collapses the dropdown when state.sel steps off it, writing
	-- the (possibly-collapsed) open flag and the adjusted sel back into state.
	-- on_pick does the pick and closes the dropdown (the tab owns the flag).
	dropdown.render{
		state = state,
		open = "dd_root",
		choices = root_candidates,
		text = function(dir) return vim.fn.fnamemodify(dir, ":~") end,
		on_pick = function(dir) session.set_root(dir); state.dd_root = false end,
	}

	if session.root then
		local eff_config, eff_source = eval_config(session.root)

		r:line("")
		if cmake_presets.available(session.root) then
			body_item_preset(r, eff_config, eff_source)
		end
		body_item_build_dir(r, eff_config, eff_source)
		body_item_start_lsp(r)
	end

	r:line("")
	body_item_keyicon_scratch(r)

	r:render()
	r:render_selection(state) -- clamps state.sel in place; footer reads the clamped value

	-- footer: the selected item's own actions, not a generic movement hint -
	-- j/k/tab are assumed known, so repeating them here added nothing.
	do
		local text = " " .. acts:hint(state.sel)
		m.footer:set_lines({ text })
		m.footer:hl(0, 0, { end_col = #text, hl_group = HL.Dim })
	end
end

----------------------------------------------------------------------------------------------------
-- open
----------------------------------------------------------------------------------------------------

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
		{ lhs="<CR>",   rhs=function() acts:dispatch(state.sel, "<CR>"); m:render() end },
		{ lhs="x",      rhs=function() acts:dispatch(state.sel, "x"); m:render() end },
	}
	m:map(tabs.mappings())
	return m
end

return M
