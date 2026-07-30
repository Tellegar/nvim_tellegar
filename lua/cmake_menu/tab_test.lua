--- cmake_menu.tab_configure — STATIC example "Configure" tab, rendered by hand.
---
--- cmake_menu's end goal is to be the interface for driving cmake on a project;
--- this tab is where that project's build-dir configuration is set up and
--- previewed before a build_dir is actually created — build type, generator,
--- and -D defines.
---
--- header: the tab strip (see cmake_menu.tabs).  footer: the key hint.
--- body: right-aligned editable values, a -D defines list, an "add" action, and
--- a multi-line command preview.

local HL = require("cmake_menu.hl")
local cmake = require("cpp_project.cmake")
local cmake_presets = require("cpp_project.cmake_presets")
local float = require("cmake_menu.float")
local render_mod = require("cmake_menu.render")
local tabs = require("cmake_menu.tabs")
local utils = require("utils")

local M = {}

-- 1-based index into this render's `layout` (selectable items, top to bottom).
-- Module-level so it survives across renders/tab switches; clamped in render()
-- since #layout isn't known until then.
local sel = 1

local r = render_mod.new()

---@type CMake.Config
local config = {
	--cmake_preset_name = "gcc-debug",
	--build_dir = "build/Debug",
	--generator = "Ninja",
	--defines = {
	--	{ name = "CMAKE_BUILD_TYPE",              value = "Debug" },
	--	{ name = "CMAKE_EXPORT_COMPILE_COMMANDS", value = "ON" },
	--	{ name = "CMAKE_C_COMPILER",              value = "gcc" },
	--	{ name = "CMAKE_CXX_COMPILER",            value = "g++" },
	--},
}

-- temp --
--local root = "~/t"
--local config_preset = cmake_presets.resolve(root, "gcc-debug")
local config_preset = {
	build_dir = "~/t/build/gcc-debug",
	cmake_preset_name = "gcc-debug",
	generator = "Ninja",
	defines = {
		{ name = "CMAKE_BUILD_TYPE",              value = "Debug" },
		{ name = "CMAKE_CXX_COMPILER",            value = "g++" },
		{ name = "CMAKE_C_COMPILER",              value = "gcc" },
		{ name = "CMAKE_EXPORT_COMPILE_COMMANDS", value = "ON" }
	},
}

-----@param cfg CMake.Config
-----@param name string
-----@return CMake.Define def
-----@return integer? idx
--local function define_get(cfg, name)
--	local def, idx = { name=name }, nil
--	for i, d in ipairs(cfg.defines or {}) do
--		if d.name == name then
--			def, idx = d, i
--			break
--		end
--	end
--	return def, idx
--end

---@param cfg CMake.Config
---@param name string
---@return string? value nil if `name` isn't set
---@return integer? index nil if `name` isn't set
local function define_get(cfg, name)
	for i, d in ipairs(cfg.defines) do
		if d.name == name then
			return d.value, i
		end
	end
end

---@param cfg CMake.Config
---@param name string
local function define_clear(cfg, name)
	if not cfg.defines then return end
	for i, d in ipairs(cfg.defines) do
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

----------

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

---@return CMake.Config eff
---@return CMake.ConfigSource source
local function eval_config()
	local eff, source = {}, {}

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

--- Renders the cmake command implied by `config` as a dimmed, multi-line preview.
---@param parts string[]
local function render_command_preview(parts)
	-- e.g.
	--   cmake -B build/Debug           \
	--     -G Ninja                     \
	--     -DCMAKE_C_COMPILER=gcc       \
	--     -DCMAKE_CXX_COMPILER=g++

	-- TODO: config_preset is resolved above against a hardcoded placeholder
	-- root ("~/t"), not the actual project. Before wiring this up for real:
	-- take the project root from the caller instead of hardcoding it, and
	-- validate config.cmake_preset_name against cmake_presets.list(root) here
	-- (surfacing an invalid preset name as a UI error) rather than assuming
	-- resolve() succeeded.

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

---@class CMenu.Action
---@field key string
---@field key_alts string[]?
---@field action fun()

-- [sel] -> actions
---@type CMenu.Action[][]
local item_actions = {}

--- adds action(s) to last item
---@param spec CMenu.Action|CMenu.Action[]
local function item_actions_set(spec)
	local list = spec.key and { spec } or spec
	local idx = #r.layout
	item_actions[idx] = vim.list_extend(item_actions[idx] or {}, list)
end

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
	item_actions = {}

	local eff_config, eff_source = eval_config()

	local hl_from_source = {
		value=HL.Value,
		default=HL.Dim,
		preset=HL.Dim,
	}

	-- TODO detect preset and show it as an seletable item
	--      this probably needs to wait till the invocation of this tab is clear (as in thought out)

	r:item_begin()
	r:line2{
		"build dir",
		{ fill=true },
		{ text=utils.shell_escape(eff_config.build_dir), hl=hl_from_source[eff_source.build_dir]}
	}
	r:item_end()
	item_actions_set{
		{ key="<CR>",
			action=function()
				local default = eff_config.build_dir
				vim.ui.input(
					{ prompt = "build dir name: ", default = default },
					function(v)
						if not v then return end
						config.build_dir = (v and v ~= "") and v or nil
					end
				)
			end },
		{ key="x",
			action=function()
				config.build_dir = nil
			end },
	}

	do
		local value, idx = define_get(eff_config, "CMAKE_BUILD_TYPE")
		local source = (eff_source.defines or {})[idx] or "default"
		r:item_begin()
		r:line2{
			"build type",
			{ fill=true },
			{ text=value or "(unset)", hl=hl_from_source[source] }
		}
		r:item_end()
		local choices = { "(unset)", "Debug", "Release", "RelWithDebInfo", "MinSizeRel" }
		item_actions_set{
			{ key="<CR>",
				action=function()
					vim.ui.select(
						choices,
						{ prompt = "Select build type:"},
						function(choice)
							if not choice then return end
							if choice == choices[1] then choice = nil end
							define_set(config, "CMAKE_BUILD_TYPE", choice)
						end
					)
				end },
			{ key="x",
				action=function()
					define_clear(config, "CMAKE_BUILD_TYPE")
				end },
		}
	end

	do
		--cmake.GENERATORS
		--local choices = { "(unset)", "Ninja", "Ninja Multi-Config", "Unix Makefiles" }

		local choices, values = { "(unset)" }, { nil }
		for _, gen in ipairs(cmake.GENERATORS) do
			local choice = gen.name
			if gen.default then
				choice = choice.." (cmake default)"
			end
			if gen.flag then
				choice = choice.." "..gen.flag
			end
			choices[#choices+1] = choice
			values[#values+1] = gen.name
		end
		r:item_begin()
		r:line2{
			"generator",
			{ fill=true },
			{ text=eff_config.generator or "(unset)", hl=hl_from_source[eff_source.generator] }
		}
		r:item_end()
		item_actions_set{
			{ key="<CR>",
				action=function()
					vim.ui.select(
						choices,
						{ prompt = "build_type"},
						function(choice)
							if not choice then return end
							if choice == choices[1] then choice = nil end
							config.generator = choice
						end
					)
				end },
			{ key="x",
				action=function()
					config.generator = nil
				end },
		}
	end

	r:line("")
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
	end
	r:item_begin()
	r:line2{{ text="+Add -Define", hl=HL.Action }}
	r:item_end()

	r:line("")
	r:item_begin()
	render_command_preview(cmake.command_parts(config_filter_preset(eff_config, eff_source)))
	r:item_end()

	r:render()
	sel = r:render_selection(sel)
end

---@param key string
local function dispatcher(key)
	local actions = item_actions[sel]
	if not actions then return end
	for _, a in ipairs(actions) do
		if a.key == key then
			a.action()
			break
		end
	end
end

function M.open()
	local m
	local function move(delta)
		sel = sel + delta
		m:render()
	end
	m = float.open{ render = render }
	local dispatcher_keys = { "<CR>", "x" }
	for _, k in ipairs(dispatcher_keys) do
		m:map{ lhs=k, rhs=function()
			dispatcher(k)
			render(m)
		end }
	end
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
