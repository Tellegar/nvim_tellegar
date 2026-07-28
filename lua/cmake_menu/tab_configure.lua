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

local M = {}

-- 1-based index into this render's `layout` (selectable items, top to bottom).
-- Module-level so it survives across renders/tab switches; clamped in render()
-- since #layout isn't known until then.
local sel = 1

---@type CMake.Config
local config = {
	cmake_preset_name = "gcc-debug",
	build_dir = "build/Debug",
	generator = "Ninja",
	defines = {
		--{ name = "CMAKE_BUILD_TYPE",              value = "Debug" },
		{ name = "CMAKE_EXPORT_COMPILE_COMMANDS", value = "ON" },
		{ name = "CMAKE_C_COMPILER",              value = "gcc" },
		{ name = "CMAKE_CXX_COMPILER",            value = "g++" },
	},
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
---@param push fun(text: string): integer
---@param hl fun(row: integer, col: integer, opts: table)
local function render_command_preview(push, hl)
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
	local parts = cmake.command_parts(config, config_preset)

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
		local row = push(l)
		hl(row, 0, { end_col = #l, hl_group = HL.Dim })
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
	local b = m.body
	local MARGIN = "  " -- 2-space gutter kept clear on both edges
	local w = b:width() - 2 * #MARGIN
	local lines, marks = {}, {}
	local function push(text) lines[#lines + 1] = MARGIN .. text .. MARGIN; return #lines - 1 end
	local function hl(row, col, opts)
		opts.end_col = opts.end_col + #MARGIN
		marks[#marks + 1] = { row, col + #MARGIN, opts }
	end

	-- Wraps a chunk of pushes as one selectable item, recording the rows it
	-- produced. `layout[i]` is the row list for the i-th selectable item.
	local layout = {}
	local function item(fn)
		local first = #lines
		fn()
		local rows = {}
		for r = first, #lines - 1 do rows[#rows + 1] = r end
		layout[#layout + 1] = rows
	end

	-- "name        value" field row, value right-aligned to the window edge
	local function field(name, value)
		local pad = math.max(1, w - #name - #value)
		local text = name .. string.rep(" ", pad) .. value
		local row = push(text)
		hl(row, #text - #value, { end_col = #text, hl_group = HL.Value })
	end
	item(function() field("build dir",  "build/Debug") end)
	item(function() field("build type", "Debug") end)
	item(function() field("generator",  "Ninja") end)

	do
		local text = "-D Defines:"
		local row = push(text)
		hl(row, 0, { end_col = #text, hl_group = HL.Heading })
	end

	for _, d in ipairs(config.defines or {}) do
		item(function() field("  " .. d.name, d.value) end)
	end

	item(function()
		local row = push("+ Add -Define")
		hl(row, 0, { end_col = 13, hl_group = HL.Action })
	end)

	item(function() -- static example (temp)
		local d = config_preset.defines[1]
		local name, value = "  "..d.name, d.value
		--item(function() field("  " .. d.name, d.value) end)
		local pad = math.max(1, w - #name - #value)
		local text = name .. string.rep(" ", pad) .. value
		local row = push(text)
		hl(row, 0, { end_col = #name, hl_group = HL.Dim })
		hl(row, #text - #value, { end_col = #text, hl_group = HL.Dim })
	end)

	push("")

	item(function() render_command_preview(push, hl) end)

	b:set_lines(lines)
	for _, k in ipairs(marks) do b:hl(k[1], k[2], k[3]) end

	-- selection: highlight + mark every row of the selected item
	sel = math.max(1, math.min(sel, #layout))
	local rows = layout[sel]
	if rows then
		for _, r in ipairs(rows) do
			b:hl(r, 0, {
				line_hl_group = HL.Selected,
				virt_text = { { "▌", HL.SelectedMarker } },
				virt_text_pos = "overlay"
			})
		end
	end
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
