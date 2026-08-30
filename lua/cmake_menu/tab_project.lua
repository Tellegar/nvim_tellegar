--- cmake_menu.tab_project — the main tab of cmake_menu: pick/override the
--- source root, and pick which config (a cmake preset, or a manual one) to
--- use. cmake_menu.tab_configure gates itself on cpp_project.session's
--- has_config() - a config gets picked here before its fields get edited there.
---
--- This tab owns no project state of its own: the root and the selected config
--- both live in cpp_project.session, which is also what persists them. Every
--- pick below is a mutation of that session, so the Configure tab and clangd
--- see the same thing without anything being passed between tabs.

local HL = require("cmake_menu.hl")
local actions = require("cmake_menu.actions")
local clangd = require("cpp_project.clangd")
local cmake_presets = require("cpp_project.cmake_presets")
local dropdown = require("cmake_menu.dropdown")
local float = require("cmake_menu.float")
local project = require("cpp_project.session")
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
--   dd_config - expansion bool for the config-picker dropdown (see body_item_config).
local state = {
	sel = 1,
	dd_root = false,
	dd_config = false,
}
-- the current frame's action map; persists across renders
local acts = actions.new()

--- <C-s>'s handler: "start tracking this project" - write the current root and
--- config into project_store, which is also what puts the root into
--- cpp_project.known_projects (a root is tracked exactly when it's in the
--- store, so <C-s>'s state and known_projects membership are the same fact).
---
--- Once tracked, picking a config below saves straight through; until then the
--- picks are session-only. Either way nothing saves without a user action -
--- that's what stops this instance from silently resurrecting a project
--- another instance removed.
local function track_project()
	if not project.root then
		return
	end
	if project.tracked() then
		vim.notify("cmake_menu: already tracking this project", vim.log.levels.INFO)
		return
	end
	if project.track() then
		vim.notify("cmake_menu: now tracking " .. project.root, vim.log.levels.INFO)
	end
end

----------------------------------------------------------------------------------------------------
-- body item: config (picks the cmake preset or manual config to use)
----------------------------------------------------------------------------------------------------

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

--- The config-picker dropdown's choices: every cmake preset, then every
--- manual config, then a trailing action to create a new manual one. `kind`
--- drives both on_pick (below) and the right-aligned source tag
--- (config_tag_of).
---@param root string
---@return table[]
local function config_choices(root)
	local list = { { kind = "unset", label = "(unset)" } }
	for _, p in ipairs(cmake_presets.list(root)) do
		list[#list + 1] = { kind = "preset", label = p.display, name = p.name }
	end
	for _, c in ipairs(project.manual_configs()) do
		list[#list + 1] = { kind = "manual", label = relative_to_root(root, c.build_dir), config = c }
	end
	list[#list + 1] = { kind = "add", label = "+ add manual config" }
	return list
end

local config_tag_of = {
	preset = "cmake preset",
	manual = "manual config",
}

--- Picking writes straight through cpp_project.session, which persists it when
--- the project is tracked - so a pick here is what the Configure tab edits and
--- what a later nvim reads back.
---@param c table one of config_choices()'s entries
local function config_on_pick(c)
	if c.kind == "unset" then
		project.unselect()
	elseif c.kind == "preset" then
		project.select_preset(c.name)
	elseif c.kind == "manual" then
		project.select(c.config)
	elseif c.kind == "add" then
		vim.ui.input({ prompt = "build dir: " }, function(v)
			if not v or v == "" then return end
			project.select_build_dir(v)
		end)
	end
	state.dd_config = false
end

---@param r CMenu.Render
local function body_item_config(r)
	local config = project.config
	local label, hl
	if not project.has_config() then
		label, hl = "(unset)", HL.Dim
	elseif config.cmake_preset_name then
		label = assert(config.cmake_preset_name)
		hl = HL.Value
	else
		label = relative_to_root(project.root, config.build_dir)
		hl = HL.Value
	end

	r:item_begin()
	r:line2{ "config", { fill=true }, { text=label, hl=hl } }
	r:item_end()
	acts:set{
		{ key="<CR>", desc="pick",  action=function() state.dd_config = not state.dd_config end },
		{ key="x",    desc="unset", action=function() project.unselect() end },
	}
	dropdown.render{
		state = state,
		open = "dd_config",
		choices = function() return config_choices(project.root) end,
		text = function(c) return c.label end,
		tag = function(c) return config_tag_of[c.kind] end,
		on_pick = config_on_pick,
	}
end

--- The "start lsp" row: a deliberate, explicit action rather than an
--- autostart, so it only fires once the config row above reads the way the
--- user wants - see cpp_project.clangd's header for why. The label asks
--- clangd whether a client is already running for this root (not
--- known_projects, which now means "tracked in project_store" - a different
--- fact entirely).
---@param r CMenu.Render
local function body_item_start_lsp(r)
	r:item_begin()
	local label = clangd.running(project.root) and "restart lsp" or "start lsp"
	r:line2{{ text="+" .. label, hl=HL.Action }}
	r:item_end()
	acts:set{
		{ key="<CR>", desc=label,
			action=function()
				clangd.start(session.buf, project.root)
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
			text=project.root and vim.fn.fnamemodify(project.root, ":~") or "(unset)",
			hl=project.root and HL.Value or HL.Dim
		},
	}
	r:line2{
		"   ",
		{ text="found via", hl=HL.Dim },
		{ fill=true },
		{ text=utils.inspect(project.found_via or {}),
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
		project.set_root(nil)
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
		on_pick = function(dir) project.set_root(dir); state.dd_root = false end,
	}

	if project.root then
		r:line("")
		body_item_config(r)
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
		{ lhs="<C-s>",  rhs=track_project },
	}
	m:map(tabs.mappings())
	return m
end

return M
