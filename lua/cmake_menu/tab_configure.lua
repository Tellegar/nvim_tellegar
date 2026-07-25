--- cmake_menu.tab_configure — STATIC example "Configure" tab, rendered by hand.
---
--- header: the tab strip (see cmake_menu.tabs).  footer: the key hint.
--- body: right-aligned editable values, a -D defines list, an "add" action, and
--- a multi-line command preview. Nothing here is wired to real cmake yet.

local cmake = require("cpp_project.cmake")
local float = require("cmake_menu.float")
local tabs = require("cmake_menu.tabs")

local CURRENT = "Configure" -- this tab's identity in cmake_menu.tabs

local M = {}

local root = "~/t" -- this is just for placeholder testing

---@type CMake.Config
local config = {
	cmake_preset_name = "gcc-debug",
	--build_dir = "build/Debug",
	--generator = "Ninja",
	defines = {
	--	{ name = "CMAKE_EXPORT_COMPILE_COMMANDS", value = "ON" },
	--	{ name = "CMAKE_C_COMPILER",              value = "gcc" },
	--	{ name = "CMAKE_CXX_COMPILER",            value = "g++" },
	},
}

--- Multi-line command preview (one logical entry, dimmed). Continuation
--- lines (all but the first) get a 2-space indent; every line but the last
--- gets a trailing " \" continuation marker, column-aligned so the backslash
--- lines end flush with where the (backslash-less) last line's text ends.
---
--- TODO: config.cmake_preset_name is passed through unresolved here.
--- cmake.command_parts now asserts that any preset name has already been
--- resolved by the caller (see cpp_project.cmake.lua) - it treats a name
--- that isn't in cmake_presets.list(root) as a caller bug, not something to
--- degrade around. Before wiring this up for real, resolve config's preset
--- via cpp_project.cmake_presets.resolve(root, config.cmake_preset_name)
--- and validate it against .list(root) here (surfacing an invalid preset
--- name as a UI error), then pass the resolved CMake.Config as command_parts'
--- second argument.
---@param push fun(text: string): integer
---@param hl fun(row: integer, col: integer, opts: table)
local function render_command_preview(push, hl)
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
		local row = push(l)
		hl(row, 0, { end_col = #l, hl_group = "CMenuDim" })
	end
end

local function render(m)
	tabs.render(m.header, CURRENT)

	-- footer: key hint
	do
		local text = " tab/S-tab switch   j/k move   q quit"
		m.footer:set_lines({ text })
		m.footer:hl(0, 0, { end_col = #text, hl_group = "CMenuDim" })
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

	-- "name        value" field row, value right-aligned to the window edge
	local function field(name, value)
		local pad = math.max(1, w - #name - #value)
		local text = name .. string.rep(" ", pad) .. value
		local row = push(text)
		hl(row, #text - #value, { end_col = #text, hl_group = "CMenuValue" })
	end
	field("build dir",  "build/Debug")
	field("build type", "Debug")
	field("generator",  "Ninja")

	do
		local row = push("-D Defines")
		hl(row, 0, { end_col = 10, hl_group = "CMenuHeading" })
	end
	field("  CMAKE_EXPORT_COMPILE_COMMANDS", "ON")
	field("  CMAKE_C_COMPILER",              "gcc")
	field("  CMAKE_CXX_COMPILER",            "g++")

	do
		local row = push("+ Add -Define")
		hl(row, 0, { end_col = 13, hl_group = "CMenuAction" })
	end

	push("")

	render_command_preview(push, hl)

	b:set_lines(lines)
	for _, k in ipairs(marks) do b:hl(k[1], k[2], k[3]) end
end

function M.open()
	return float.open({
		render = render,
		mappings = tabs.mappings(CURRENT),
	})
end

return M
