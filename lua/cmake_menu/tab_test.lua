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
	--	--{ name = "CMAKE_BUILD_TYPE",              value = "Debug" },
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
	defines = {
		{ name = "CMAKE_BUILD_TYPE",              value = "Debug" },
		{ name = "CMAKE_CXX_COMPILER",            value = "g++" },
		{ name = "CMAKE_C_COMPILER",              value = "gcc" },
		{ name = "CMAKE_EXPORT_COMPILE_COMMANDS", value = "ON" }
	},
	generator = "Ninja"
}
----------

--- Renders the cmake command implied by `config` as a dimmed, multi-line preview.
local function render_command_preview()
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
	local parts = cmake.command_parts(config)

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

	local build_dir_value
	if config.build_dir then
		build_dir_value = { text=config.build_dir, hl=HL.Value }
	elseif config.cmake_preset_name and config_preset and config_preset.build_dir then
		build_dir_value = { text=config_preset.build_dir, hl=HL.Dim }
	else
		build_dir_value = { text="build", hl=HL.Dim }
	end

	r:item_begin()
	r:line2{
		"build dir",
		{ fill=true },
		build_dir_value
	}
	r:item_end()

	r:item_begin()
	r:line2{
		"build type",
		{ fill=true },
		{ text="Debug", hl=HL.Value }
	}
	r:item_end()

	r:item_begin()
	r:line2{
		"generator",
		{ fill=true },
		{ text="Ninja", hl=HL.Value }
	}
	r:item_end()

	r:line("")

	r:line2{
		{ text="-D Defines:", hl=HL.Heading }
	}

	r:item_begin()
	r:line2{
		{ text="+Add -Define", hl=HL.Action }
	}
	r:item_end()

	r:line("")

	r:item_begin()
	render_command_preview()
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
