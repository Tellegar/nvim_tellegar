--- cmake_menu.tab_configure — the "Configure" tab: the editor for whichever
--- config the Project tab has selected.
---
--- cmake_menu's end goal is to be the interface for driving cmake on a project;
--- this tab is where that project's build-dir configuration is set up and
--- previewed before a build_dir is actually created — build type, generator,
--- and -D defines.
---
--- It holds no config of its own. Every field below reads and writes
--- cpp_project.session's selected config in place, and every edit ends in
--- session.commit(), which both keeps that config's membership in the saved
--- list correct (a preset that has just gained its first override needs a
--- stored entry; one that lost its last override stops needing one) and
--- persists it when the project is tracked.
---
--- Fields left unset here fall through to the selected cmake preset, and then
--- to a hardcoded default — see eval_config below, which reports where each
--- effective value came from so the display can dim inherited ones.
---
--- header: the tab strip (see cmake_menu.tabs).  footer: the key hint.
--- body: right-aligned editable values, a -D defines list, an "add" action, and
--- a multi-line command preview.

local HL = require("cmake_menu.hl")
local actions = require("cmake_menu.actions")
local cmake = require("cpp_project.cmake")
local dropdown = require("cmake_menu.dropdown")
local float = require("cmake_menu.float")
local project = require("cpp_project.session")
local render_mod = require("cmake_menu.render")
local tabs = require("cmake_menu.tabs")
local utils = require("utils")

local M = {}

-- Tab state, passed by reference into the dropdown so it can mutate it in place
-- (see cmake_menu.dropdown). Module-level so it survives across renders/tab
-- switches.
--   sel            - 1-based index into this render's `layout` (selectable items,
--                    top to bottom); clamped in render() since #layout isn't
--                    known until then.
--   dd_build_type,
--   dd_generator   - expansion bools for the inline dropdowns (the anchor rows
--                    and their toggle actions are rendered in the body_item_*
--                    functions below).
local state = {
	sel = 1,
	dd_build_type = false,
	dd_generator = false,
}
local r

----------------------------------------------------------------------------------------------------
-- state
----------------------------------------------------------------------------------------------------

--- Mutate the selected config and write the result through. Every field
--- action below goes via this rather than touching cpp_project.session.config
--- directly, so none of them can forget the commit that persists the edit.
---@param fn fun(config: CMake.Config)
local function edit(fn)
	fn(project.config)
	project.commit()
end

----------------------------------------------------------------------------------------------------
-- define helpers
----------------------------------------------------------------------------------------------------

---@param cfg CMake.Config
---@param name string
---@return string? value nil if `name` isn't set
---@return integer? index nil if `name` isn't set
local function define_get(cfg, name)
	for i, d in ipairs(cfg.defines or {}) do
		if d.name == name then
			return d.value, i
		end
	end
end

---@param cfg CMake.Config
---@param name string
local function define_clear(cfg, name)
	if not cfg.defines then return end
	for i, d in ipairs(cfg.defines or {}) do
		if d.name == name then
			table.remove(cfg.defines, i)
			return
		end
	end
	if next(cfg.defines) == nil then
		cfg.defines = nil
	end
end

---@param cfg CMake.Config
---@param name string
---@param value string|nil
local function define_set(cfg, name, value)
	if value == nil then
		return define_clear(cfg, name)
	end
	cfg.defines = cfg.defines or {}
	for _, d in ipairs(cfg.defines) do
		if d.name == name then
			d.value = value
			return
		end
	end
	cfg.defines[#cfg.defines + 1] = { name = name, value = value }
end

----------------------------------------------------------------------------------------------------
-- effective config
----------------------------------------------------------------------------------------------------

local Source = {
	value = "value",
	default = "default",
	preset = "preset",
}

---@class CMake.ConfigSource
---@field cmake_preset_name string Source.*
---@field build_dir string Source.*
---@field generator string Source.*
---@field defines string[] Source.* per entry, parallel to CMake.Config.defines

--- Fold the selected config over its preset: for each field, the explicitly
--- set value wins, else the preset's, else a hardcoded default. The parallel
--- `source` says which of the three each effective value came from, which is
--- what lets the display dim inherited values and config_filter_preset drop
--- the ones `--preset` will supply on its own.
---@return CMake.Config eff
---@return CMake.ConfigSource source
local function eval_config()
	local eff, source = {}, {}
	local config = project.config
	local config_preset = project.preset()

	if config.cmake_preset_name then
		eff.cmake_preset_name = config.cmake_preset_name
		source.cmake_preset_name = Source.value
	else
		eff.cmake_preset_name = nil
		source.cmake_preset_name = Source.default
	end

	if config.build_dir then
		eff.build_dir = config.build_dir
		source.build_dir = Source.value
	elseif config.cmake_preset_name and config_preset and config_preset.build_dir then
		eff.build_dir = config_preset.build_dir
		source.build_dir = Source.preset
	else
		eff.build_dir = "build"
		source.build_dir = Source.default
	end

	if config.generator then
		eff.generator = config.generator
		source.generator = Source.value
	elseif config.cmake_preset_name and config_preset and config_preset.generator then
		eff.generator = config_preset.generator
		source.generator = Source.preset
	else
		eff.generator = nil
		source.generator = Source.default
	end

	eff.defines = {}
	source.defines = {}

	local defines = {} ---@type table[string,integer]
	for _, d in ipairs(config.defines or {}) do
		eff.defines[#eff.defines+1] = { name=d.name, value=d.value }
		source.defines[#source.defines+1] = Source.value
		defines[d.name] = true
		defines[d.name] = #eff.defines
	end

	if config.cmake_preset_name and config_preset and config_preset.defines then
		for _, d in ipairs(config_preset.defines or {}) do
			if not defines[d.name] then
				eff.defines[#eff.defines+1] = { name=d.name, value=d.value }
				source.defines[#source.defines+1] = Source.preset
				defines[d.name] = #eff.defines
			end
		end
	end

	return eff, source
end

--- Strips preset-sourced values out of `eff_config`, leaving only what was
--- set explicitly or falls back to a hardcoded default (e.g. build_dir
--- defaulting to "build"). This is what should actually be passed to cmake —
--- preset-sourced defines/build_dir/generator are handled by --preset itself
--- once presets are wired up, and shouldn't also be re-emitted as explicit
--- flags.
---@param eff_config CMake.Config
---@param eff_source CMake.ConfigSource
---@return CMake.Config
local function config_filter_preset(eff_config, eff_source)
	local raw = {}

	for _, key in ipairs{ "cmake_preset_name", "build_dir", "generator" } do
		if eff_source[key] ~= Source.preset then
			raw[key] = eff_config[key]
		end
	end

	raw.defines = {}
	for i, d in ipairs(eff_config.defines or {}) do
		if eff_source.defines[i] ~= Source.preset then
			raw.defines[#raw.defines + 1] = d
		end
	end

	return raw
end

----------------------------------------------------------------------------------------------------
-- command preview
----------------------------------------------------------------------------------------------------

--- Renders the cmake command implied by `config` as a dimmed, multi-line preview.
---@param parts string[]
local function render_command_preview(parts)
	-- e.g.
	--   cmake -B build/Debug           \
	--     -G Ninja                     \
	--     -DCMAKE_C_COMPILER=gcc       \
	--     -DCMAKE_CXX_COMPILER=g++

	local lines = {}
	local max_len = 0
	for i, part in ipairs(parts) do
		local l = i > 1 and "  " .. part or part
		lines[i] = l
		max_len = math.max(max_len, i == #parts and #l - 2 or #l)
	end

	for i, l in ipairs(lines) do
		if i < #lines then
			l = l .. string.rep(" ", max_len - #l) .. " \\"
		end
		r:line2{{
			text = l,
			hl = HL.Dim
		}}
	end
end

----------------------------------------------------------------------------------------------------
-- item actions
----------------------------------------------------------------------------------------------------

-- per-item key->handler map for this menu; rebuilt each render via acts:begin(r).
-- The body_item_* functions attach handlers with acts:set() right after they
-- close an item, and open()'s key mappings fire them with acts:dispatch(sel, k).
local acts = actions.new()

----------------------------------------------------------------------------------------------------
-- body items
----------------------------------------------------------------------------------------------------

-- Effective config + per-field source for the current render, set by render()
-- before the body_item_* functions below run.
---@type CMake.Config
local eff_config
---@type CMake.ConfigSource
local eff_source

local hl_from_source = {
	value=HL.Value,
	default=HL.Dim,
	preset=HL.Dim,
}

local function body_item_build_dir()
	r:item_begin()
	r:line2{
		"build dir",
		{ fill=true },
		{ text=utils.shell_escape(eff_config.build_dir), hl=hl_from_source[eff_source.build_dir]}
	}
	r:item_end()
	acts:set{
		{ key="<CR>",
			action=function()
				local default = eff_config.build_dir
				vim.ui.input(
					{ prompt = "build dir name: ", default = default },
					function(v)
						if not v then return end
						edit(function(c) c.build_dir = v ~= "" and v or nil end)
					end
				)
			end },
		{ key="x",
			action=function()
				edit(function(c) c.build_dir = nil end)
			end },
	}
end

local function body_item_build_type()
	local value, idx = define_get(eff_config, "CMAKE_BUILD_TYPE")
	local source = (eff_source.defines or {})[idx] or "default"
	r:item_begin()
	r:line2{
		"build type",
		{ fill=true },
		{ text=value or "(unset)", hl=hl_from_source[source] }
	}
	r:item_end()
	-- <CR> toggles the dropdown; x clears the value
	acts:set{
		{ key="<CR>", action=function() state.dd_build_type = not state.dd_build_type end },
		{ key="x",    action=function() edit(function(c) define_clear(c, "CMAKE_BUILD_TYPE") end) end },
	}
	local choices = { "(unset)", "Debug", "Release", "RelWithDebInfo", "MinSizeRel" }
	dropdown.render{
		state = state,
		open = "dd_build_type",
		choices = function() return choices end,
		on_pick = function(choice)
			if choice == choices[1] then choice = nil end
			edit(function(c) define_set(c, "CMAKE_BUILD_TYPE", choice) end)
			state.dd_build_type = false
		end,
	}
end

--- (unset) plus each known generator, labelled with its cmake-default marker and
--- -G flag; the picked entry's `value` is the bare generator name (nil = unset).
---@return { label: string, value: string? }[]
local function generator_choices()
	local list = { { label = "(unset)" } }
	for _, gen in ipairs(cmake.GENERATORS) do
		local label = gen.name
		if gen.default then label = label .. " (cmake default)" end
		if gen.flag then label = label .. " " .. gen.flag end
		list[#list + 1] = { label = label, value = gen.name }
	end
	return list
end

local function body_item_generator()
	r:item_begin()
	r:line2{
		"generator",
		{ fill=true },
		{ text=eff_config.generator or "(unset)", hl=hl_from_source[eff_source.generator] }
	}
	r:item_end()
	-- <CR> toggles the dropdown; x clears the value
	acts:set{
		{ key="<CR>", action=function() state.dd_generator = not state.dd_generator end },
		{ key="x",    action=function() edit(function(c) c.generator = nil end) end },
	}
	dropdown.render{
		state = state,
		open = "dd_generator",
		choices = generator_choices,
		text = function(c) return c.label end,
		on_pick = function(choice)
			edit(function(c) c.generator = choice.value end)
			state.dd_generator = false
		end,
	}
end

local function body_item_defines()
	r:line2{{ text="-D Defines:", hl=HL.Heading }}
	for i, d in ipairs(eff_config.defines or {}) do
		r:item_begin()
		local source = eff_source.defines[i]
		r:line2{
			" ",
			{ text=d.name, hl=hl_from_source[source] },
			{ fill=true },
			{ text=d.value, hl=hl_from_source[source] },
		}
		r:item_end()
		acts:set{
			{ key="<CR>",
				action=function(dispatched_key)
					local default = dispatched_key == "i" and "" or d.value
					if not default then
						vim.notify("default is nil, should not happen")
						return
					end

					vim.ui.input(
						{ prompt = d.name .. " = ", default = default },
						function(v)
							if not v then return end
							edit(function(c) define_set(c, d.name, v) end)
						end)
				end },
			{ key="<S-CR>",
				action=function(dispatched_key)
					local default = dispatched_key == "I" and "" or d.name
					if not default then
						vim.notify("default is nil, should not happen")
						return
					end

					local _, idx = define_get(project.config, d.name)

					vim.ui.input(
						{ prompt = "var name: ", default = default },
						function(v)
							if not v then return end
							-- TODO strip v
							edit(function(c)
								if not idx then
									define_set(c, v, d.value)
								else
									c.defines[idx].name = v
								end
							end)
						end
					)

				end },
			{
				key="x",
				action=function()
					edit(function(c) define_clear(c, d.name) end)
				end },
		}
	end
end

local function body_item_add_define()
	r:item_begin()
	r:line2{{ text="+Add -Define", hl=HL.Action }}
	r:item_end()
	acts:set{
		{ key="<CR>",
			action=function()
				vim.ui.input(
					{ prompt = "NAME=VALUE: " },
					function(v)
						if not v then return end
						local name, value = v:match("^%s*([^=]-)%s*=(.*)$")
						if not name or not value then
							vim.notify("cmake_menu: expected NAME=VALUE, got: " .. v, vim.log.levels.ERROR)
							return
						end
						edit(function(c) define_set(c, name, value) end)
						state.sel = state.sel + 1
					end)
			end },
	}
end

local function body_item_command_preview()
	r:item_begin()
	render_command_preview(cmake.command_parts(config_filter_preset(eff_config, eff_source)))
	r:item_end()
end

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

	-- Gated on the Project tab having settled on a config: float.lua/tabs.lua
	-- have no notion of a disabled/hidden tab (tabs.step()/tabs.open() switch
	-- unconditionally), so this renders a single explanatory line in place of
	-- the body instead.
	if not project.has_config() then
		local body = render_mod.new(m.body)
		body.margin = "  "
		body:line("")
		body:line2{{ text="pick a cmake preset or set a build dir in the Project tab first", hl=HL.Dim }}
		body:render()
		return
	end

	-- body
	r = render_mod.new(m.body)
	r.margin = "  "
	acts:begin(r)

	eff_config, eff_source = eval_config()

	r:line("")
	-- A preset name that this project's CMakePresets.json doesn't define
	-- resolves to nothing, so every field silently loses its inherited value
	-- and reads as a bare default. Say so rather than letting the config look
	-- merely empty - the usual cause is a preset renamed or removed since it
	-- was saved.
	if project.config.cmake_preset_name and not project.preset() then
		r:line2{{
			text = "unknown cmake preset: " .. project.config.cmake_preset_name,
			hl = HL.Error,
		}}
		r:line("")
	end

	body_item_build_dir()
	body_item_build_type()
	body_item_generator()

	r:line("")
	body_item_defines()
	body_item_add_define()

	r:line("")
	body_item_command_preview()

	r:render()
	r:render_selection(state)
	r = nil
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
		{ lhs="<S-CR>", rhs=function() acts:dispatch(state.sel, "<S-CR>"); m:render() end },
		{ lhs="x",      rhs=function() acts:dispatch(state.sel, "x"); m:render() end },
	}
	m:map(tabs.mappings())
	return m
end

return M
