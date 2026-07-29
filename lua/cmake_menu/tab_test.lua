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

local float = require("cmake_menu.float")
local tabs = require("cmake_menu.tabs")
local cmake = require("cpp_project.cmake")
local cmake_presets = require("cpp_project.cmake_presets")
local HL = require("cmake_menu.hl")
local render_mod = require("cmake_menu.render")

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
	--build_dir = "~/t/build/gcc-debug",
	--cmake_preset_name = "gcc-debug",
	--generator = "Ninja",
	defines = {
		{ name = "CMAKE_BUILD_TYPE",              value = "Debug" },
		{ name = "CMAKE_CXX_COMPILER",            value = "g++" },
		{ name = "CMAKE_C_COMPILER",              value = "gcc" },
		{ name = "CMAKE_EXPORT_COMPILE_COMMANDS", value = "ON" }
	},
}

---@param cfg CMake.Config
---@param name string
---@return CMake.Define def
---@return integer? idx
local function get_define(cfg, name)
	local def, idx = { name=name }, nil
	for i, d in ipairs(cfg.defines or {}) do
		if d.name == name then
			def, idx = d, i
			break
		end
	end
	return def, idx
end
----------

local Source = {
	value = "value",
	default = "default",
	preset = "default",
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

	local eff_config, eff_source = eval_config()

	local hl_from_source = {
		value=HL.Value,
		default=HL.Dim,
	}

	r:item_begin()
	r:line2{
		"build dir",
		{ fill=true },
		{ text=eff_config.build_dir, hl=hl_from_source[eff_source.build_dir]}
	}
	r:item_end()

	do
		local def, idx = get_define(eff_config, "CMAKE_BUILD_TYPE")
		local source = (eff_source.defines or {})[idx] or "default"
		r:item_begin()
		r:line2{
			"build type",
			{ fill=true },
			{ text=def.value or "(unset)", hl=hl_from_source[source] }
		}
		r:item_end()
	end

	r:item_begin()
	r:line2{
		"generator",
		{ fill=true },
		{ text=eff_config.generator or "(unset)", hl=hl_from_source[eff_source.generator] }
	}
	r:item_end()

	r:line("")

	r:line2{
		{ text="-D Defines:", hl=HL.Heading }
	}

	--vim.print(eff_config)
	--vim.print(eff_sources)
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
	r:line2{
		{ text="+Add -Define", hl=HL.Action }
	}
	r:item_end()

	r:line("")

	r:item_begin()
	render_command_preview(cmake.command_parts(eff_config))
	r:item_end()

	r:render()
	sel = r:render_selection(sel)
end

function M.open()
	local m
	local function move(delta)
		sel = sel + delta
		m:render()
	end
	m = float.open({
		render = render,
		mappings = vim.list_extend({
			{ lhs = "j",      rhs = function() move(1) end },
			{ lhs = "k",      rhs = function() move(-1) end },
			{ lhs = "<Down>", rhs = function() move(1) end },
			{ lhs = "<Up>",   rhs = function() move(-1) end },
		}, tabs.mappings()),
	})
	return m
end

return M
