--- cmake_menu.tab_configure — STATIC example "Configure" tab, rendered by hand.
---
--- header: the tab strip (see cmake_menu.tabs).  footer: the key hint.
--- body: right-aligned editable values, a -D defines list, an "add" action, and
--- a multi-line command preview. Nothing here is wired to real cmake yet.

local float = require("cmake_menu.float")
local tabs = require("cmake_menu.tabs")

local cmake_utils = require("cpp_project.cmake")

local CURRENT = "Configure" -- this tab's identity in cmake_menu.tabs

local M = {}

---@type CMake.Config
local config = {
	build_dir = "build/Debug",
	generator = "Ninja",
	defines = {
		{ name = "CMAKE_EXPORT_COMPILE_COMMANDS", value = "ON" },
		{ name = "CMAKE_C_COMPILER",              value = "gcc" },
		{ name = "CMAKE_CXX_COMPILER",            value = "g++" },
	},
}

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

	-- multi-line command preview (one logical entry, dimmed)
	for _, l in ipairs({
		"cmake -B build/Debug \\",
		"  -S . -G Ninja \\",
		"  -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \\",
		"  -DCMAKE_C_COMPILER=gcc -DCMAKE_CXX_COMPILER=g++",
	}) do
		local row = push(l)
		hl(row, 0, { end_col = #l, hl_group = "CMenuDim" })
	end

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
