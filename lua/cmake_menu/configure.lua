-- The configure part of the :Cpp menu (a gui over cmake's configure step).
-- Responsible for working with configs.

local M = {}

---@class CMake.Define
---@field name string
---@field value string

---@class CMake.Config
---@field cmake_preset_name string?
---@field build_dir string?
---@field generator string?
---@field defines CMake.Define[]

---@param config CMake.Config
---@param name string
---@return string? value nil if `name` isn't set
---@return integer? index nil if `name` isn't set
local function define_get(config, name)
	for i, d in ipairs(config.defines) do
		if d.name == name then
			return d.value, i
		end
	end
end

---@param config CMake.Config
---@param name string
local function define_clear(config, name)
	for i, d in ipairs(config.defines) do
		if d.name == name then
			table.remove(config.defines, i)
			return
		end
	end
end

---@param config CMake.Config
---@param name string
---@param value string|nil
local function define_set(config, name, value)
	if value == nil then
		return define_clear(config, name)
	end
	for _, d in ipairs(config.defines) do
		if d.name == name then
			d.value = value
			return
		end
	end
	config.defines[#config.defines + 1] = { name = name, value = value }
end

------------------------------------------------------------------------------
-- Command
------------------------------------------------------------------------------

--- Concatenates any number of array-like tables into a new array.
---@param ... table
---@return table
local function concat(...)
	local result = {}
	for _, t in ipairs({ ... }) do
		vim.list_extend(result, t)
	end
	return result
end

local function escape(str)
	if str:match("^[%w%-%.,_/:=]+$") then
		return str
	end
	return "'" .. str:gsub("'", "'\\''") .. "'"
end

--- Argument parts of the cmake configure command implied by `config`, one
--- entry per -B/--preset/-G/-D. The first entry carries the "cmake" prefix.
--- Every dynamic piece (never the fixed flag text) is escaped, since none of
--- build_dir / preset name / generator / define name+value are guaranteed
--- shell-safe (e.g. nothing stops a preset name from containing a space).
---@param config CMake.Config
---@return string[]
function M.command_parts(config)
	local parts = { "cmake" }

	local prefix = "build/"
	local build_dir = config.build_dir and prefix .. config.build_dir or "build"
	parts[1] = parts[1] .. " -B " .. escape(build_dir)

	if config.cmake_preset_name then
		parts[#parts + 1] = "--preset " .. escape(config.cmake_preset_name)
	end
	if config.generator then
		parts[#parts + 1] = "-G " .. escape(config.generator)
	end
	for _, d in ipairs(config.defines) do
		parts[#parts + 1] = escape("-D" .. d.name .. "=" .. d.value)
	end

	return parts
end

function M.command(config)
	return table.concat(M.command_parts(config), " ")
end

------------------------------------------------------------------------------
-- Menu
------------------------------------------------------------------------------

local function notify(msg)
	require("fidget").notify(
		"", vim.log.levels.INFO, {
			key = "cpp.configure",
			annote = msg
		}
	)
end

local HL = require("cmake_menu.hl").HL

---@type CMake.Config
local config = {
	cmake_preset_name = nil,
	build_dir = nil,
	generator = nil,
	defines = {},
}

---@type CMake.Config
local config_preset = vim.deepcopy(config)

-- vv testing vv
config.defines = {
	{ name = "a_name", value = "a_value" },
	{ name = "b_name", value = "b_value" },
}

config_preset = {
	cmake_preset_name = "gcc-debug",
	build_dir = "gcc-debug",
	generator = "Ninja",
	defines = {
		{ name = "CMAKE_BUILD_TYPE", value = "Debug" },
		{ name = "CMAKE_CXX_COMPILER", value = "g++" },
		{ name = "CMAKE_C_COMPILER", value = "gcc" },
		{ name = "CMAKE_EXPORT_COMPILE_COMMANDS", value = "ON" },
	},
}
-- ^^ testing ^^


local interact = {
	left =   { "h", "<Left>" },
	right =  { "l", "<Right>" },
	insert = { "i", "I" },
	append = { "a", "A" },
	any = {
		"h", "<Left>",
		"l", "<Right>",
		"i", "I",
		"a", "A",
	}
}

---@return CMenu.Item[]
local build_items

---@return CMenu.Item
local function bi_build_dir()
	local function prompt(default)
		vim.ui.input(
			{ prompt = "build dir name: ", default = default },
			function(v)
				if not v then return end
				config.build_dir = (v and v ~= "") and v or nil
			end
		)
	end

	return { ---@type CMenu.Item
		key = "d",
		label = "Build dir",
		-- TODO build_dir can be generated/unset/set
		value = function()
			if config.build_dir then
				return { { escape(config.build_dir), "String" } }
			end
			return { { "(unset)", "Comment" } }
		end,
		actions = {
			{ key = "x", desc = "clear", fn = function() config.build_dir = nil end },
			{
				key = "<CR>",
				desc = "rename",
				alt_keys = {"l", "<Right>", "a", "A" },
				fn = function() prompt(config.build_dir) end,
			},
			{
				key = "<S-CR>",
				desc = "rename (empty)",
				hidden = true,
				alt_keys = {"h", "<Left>", "i", "I" },
				fn = function() prompt(nil) end,
			},
		},
	}
end

---@return CMenu.Item
local function bi_build_type()
	-- TODO explore if cmake doesnt expose valid CMAKE_BUILD_TyPE values
	local choices = { "(unset)", "Debug", "Release", "RelWithDebInfo", "MinSizeRel" }
	return { ---@type CMenu.Item
		key = "t",
		label = "Build type",
		value = function()
			local value = define_get(config, "CMAKE_BUILD_TYPE")
			return { { value or "(unset)", HL.Value } }
		end,
		actions = {
			{ key = "x", desc = "clear", fn = function() define_clear(config, "CMAKE_BUILD_TYPE") end },
			{
				key = "<CR>",
				desc = "select",
				alt_keys = interact.any,
				fn = function()
					vim.ui.select(
						choices,
						{ prompt = "build_type" },
						function(choice)
							if not choice then return end
							if choice == choices[1] then choice = nil end
							define_set(config, "CMAKE_BUILD_TYPE", choice)
						end
					)
				end,
			},
		},
	}
end

---@return CMenu.Item
local function bi_generator()
	-- TODO use cmake_menu.utils to get these options
	local choices = { "(unset)", "Ninja", "Ninja Multi-Config", "Unix Makefiles" }
	return { ---@type CMenu.Item
		key = "g",
		label = "Generator",
		value = function()
			if config.generator then
				return {{ config.generator, HL.Value }}
			end
			return {{ "(unset)", "String" }}
			--return "(unset)"
		end,
		actions = {
			{ key = "x", desc = "clear", fn = function() config.generator = nil end },
			{
				key = "<CR>",
				desc = "select",
				alt_keys = interact.any,
				fn = function()
					vim.ui.select(
						choices,
						{ prompt = "generator" },
						function(choice)
							if not choice then return end
							if choice == choices[1] then choice = nil end
							config.generator = choice
						end
					)
				end,
			},
		},
	}
end

---@return CMenu.Item
---@param define CMake.Define
local function bi_define(define)
	local name, value = define.name, define.value
	local text = escape(define.name .. "=" .. define.value)

	return { ---@type CMenu.Item
		label = function() return name end,
		value = function() return { { value, HL.Value } } end,
		actions = {
			{
				key = "x",
				desc = "remove",
				fn = function(h)
					-- if local name is not in config.defines
					--   that means that current bi_define is outdated
					--   and was not called after defines was modified
					define_clear(config, name)
					h.spec.items = build_items()
					h:render()

					--if remove_config_define(name) then
					--	M.open()
					--elseif eff_define(name) ~= nil then
					--	vim.notify(
					--		"scratch: '" .. name .. "' is a preset default - override its value instead",
					--		vim.log.levels.INFO
					--	)
					--end
				end,
			},
			{
				key = "<S-CR>",
				desc = "edit name",
				alt_keys = concat(interact.left, { "I", "A" }),
				fn = function(h)
					local default = h.dispatched_key == "I" and "" or name
					if not default then
						vim.notify("default is nil, should not happen")
						return
					end

					local _, i = define_get(config, name)

					vim.ui.input(
						{ prompt = "var name: ", default = default },
						function(v)
							if not v or v == "" then return end
							-- TODO strip v
							--notify("v: " .. tostring(v) .. " i: " .. i)
							config.defines[i].name = v -- this will not work with config_preset
							h.spec.items = build_items()
							h:render()
						end
					)

					--if not config_define(name) then
					--	vim.notify(
					--		"scratch: '" .. name .. "' is preset-derived - edit value to override it first",
					--		vim.log.levels.INFO
					--	)
					--	return
					--end
					--vim.ui.input(
					--	{ prompt = "var name: ", default = name },
					--	function(v)
					--		if v and v ~= "" and v ~= name then
					--			config_define(name).name = v
					--			M.open()
					--		end
					--	end
					--)
				end,
			},
			{
				key = "<CR>",
				desc = "edit value",
				alt_keys = concat(interact.right, { "i", "a" }),
				fn = function(h)
					local default = h.dispatched_key == "i" and "" or value
					if not default then
						vim.notify("default is nil, should not happen")
						return
					end

					vim.ui.input(
						{ prompt = name .. " = ", default = default },
						function(v)
							if not v then return end
							-- TODO rstrip v
							define_set(config, name, v)
							h.spec.items = build_items()
							h:render()
						end

						--{ prompt = name .. " = ", default = select(1, eff_define(name)) },
						--function(v)
						--	if v ~= nil then
						--		set_config_define(name, v) -- promotes a preset default to explicit
						--		h:render()
						--	end
						--end
					)
				end,
			},
			{
				key = "y",
				desc = "copy (vim)",
				hidden = true,
				fn = function()
					vim.fn.setreg('"', text)
					vim.notify("scratch: copied -D" .. name .. " (vim)", vim.log.levels.INFO)
				end,
			},
			{
				key = "+",
				desc = "copy (system)",
				hidden = true,
				fn = function()
					vim.fn.setreg("+", text)
					vim.notify("scratch: copied -D" .. name .. " (system)", vim.log.levels.INFO)
				end,
			},
		},
	}
end

---@param items CMenu.Item[]
local function bi_defines(items)
	for _, define in ipairs(config.defines) do
		items[#items+1] = bi_define(define)
	end
end

---@return CMenu.Item
local function bi_add_define()
	return { ---@type CMenu.Item
		key = "D",
		label = "Add -Define",
		actions = {
			{
				key = "<CR>",
				desc = "add cache var",
				alt_keys = interact.any,
				fn = function(h)
					vim.ui.input(
						{ prompt = "NAME=VALUE: " },
						function(v)
							if not v then return end
							local name, value = v:match("^%s*([^=]-)%s*=(.*)$")
							define_set(config, name, value)
							h.spec.items = build_items()
							h.sel = h.sel + 1
							h:render()
						end
					)
				end
			},
		},
	}
end

---@return CMenu.Item
local function bi_build_command()
	return { ---@type CMenu.Item
		label = function() return { { table.concat(M.command_parts(config), "\n"), "Comment" } } end,
		actions = {
			{
				key = "y",
				desc = "copy (vim)",
				fn = function()
					vim.fn.setreg('"', M.command(config))
					vim.notify("cpp.configure: copied cmake command (vim)", vim.log.levels.INFO)
				end,
			},
			{
				key = "+",
				desc = "copy (system)",
				fn = function()
					vim.fn.setreg("+", M.command(config))
					vim.notify("cpp.configure: copied cmake command (system)", vim.log.levels.INFO)
				end,
			},
		},
	}
end

---@return CMenu.Item[]
function build_items()
	local items = {} ---@type CMenu.Item[]

	items[#items+1] = {
		label = function() return { { "config: " .. vim.inspect(config), "Comment" } } end,
	}
	items[#items+1] = {
		label = function() return { { "config_preset: " .. vim.inspect(config_preset), "Comment" } } end,
	}
	items[#items+1] = { section = "config" }

	items[#items+1] = bi_build_dir()
	items[#items+1] = bi_build_type()
	items[#items+1] = bi_generator()

	items[#items+1] = { label = { { "-Defines", HL.Low } } }
	bi_defines(items)
	items[#items+1] = bi_add_define()

	items[#items+1] = { label = "" }
	items[#items+1] = bi_build_command()

	return items
end

---@return CMenu.Spec
local function create_spec()
	return {
		title = " configure ",
		min_width = 54,
		items = build_items(),
	}
end

function M.menu()
	return require("cmake_menu.menu").open(create_spec())
end

-- testing
package.loaded["cmake_menu.hl"] = nil
package.loaded["cmake_menu.menu"] = nil
package.loaded["cmake_menu.configure"] = nil

M.menu()
--config.build_dir = "asd"
--config.generator = "Ninja"
--
--vim.print(M.command_parts(config))
--vim.print(config)

vim.keymap.set("n", "<C-Space>", ":RunLuaBuffer silent<CR>")

--local cmake_presets = require("cmake_menu.cmake_presets")

--vim.print(cmake_presets.list("~/t"))
--vim.print(cmake_presets.resolve("~/t", "gcc-debug"))

return M

------------------------------------------------------------------------------
-- TODO: config_preset integration + deduced values (build_dir from compiler
-- + build_type). Do each phase fully inline (duplicated per-field lookups),
-- no shared helper, until phase 4 -- abstracting before seeing all three
-- cases side by side is how you miss a case.
--
-- Phase 1 -- layer `generator` inline (easiest, no defines involved, do it
-- first)
--   - bi_generator(): inline 2-way lookup by hand: explicit config.generator
--     (hl "String") -> else config_preset.generator (a "derived" hl) -> else
--     "(unset)".
--   - "clear" now only clears the explicit override (config.generator = nil),
--     which may reveal the preset value underneath instead of going straight
--     to unset.
--   - Keep using the hardcoded config_preset test literal -- don't wire up
--     the real picker yet, just prove the layering logic against the fake
--     data already in the file.
--
-- Phase 2 -- layer defines (build_type + the rest of the union) inline
--   - bi_defines(items): iterate the *union* of names from config.defines +
--     config_preset.defines (dedup by name, plain loop + seen[name] table),
--     so preset-derived defines like CMAKE_CXX_COMPILER actually show up.
--   - bi_define(define)'s actions get the promote-on-edit behavior (editing
--     a preset-derived define inserts a new explicit entry copied from the
--     preset value) and the fall-back-to-preset-derived-on-remove behavior
--     (removing an explicit define whose name also exists in
--     config_preset.defines reveals the preset value instead of vanishing)
--     -- this is the commented-out logic already sitting in bi_define from
--     cpp.scratch.lua.
--   - bi_build_type(): same 2-way lookup as generator, but sourced from the
--     defines union just built (CMAKE_BUILD_TYPE).
--   - End state: working inline "effective value of compiler"
--     (CMAKE_CXX_COMPILER/CMAKE_C_COMPILER) and "effective value of
--     build_type" (CMAKE_BUILD_TYPE) lookups -- both needed before build_dir
--     can be tackled.
--
-- Phase 3 -- layer `build_dir` inline (hardest, now unblocked)
--   - bi_build_dir()'s value(): explicit config.build_dir -> else
--     config_preset.build_dir -> else *deduced* from the effective compiler +
--     effective build_type from phase 2 (call/duplicate that lookup here,
--     don't share code yet) -> else "(unset)". Three hl tiers this time
--     (explicit/preset/deduced) instead of two.
--   - "clear" again only clears the explicit override.
--
-- Phase 4 -- only now, extract the common shape
--   - Compare the three "explicit -> preset -> (maybe deduced) -> unset"
--     resolutions (generator, build_type, build_dir) and the two
--     defines-union loops (bi_defines, the compiler/build_type lookups
--     inside build_dir's deduction). Pull out only what's actually
--     identical -- likely an effective(config, config_preset, getter) helper
--     returning (value, source), and a merged_define_names(config,
--     config_preset) helper.
--   - Update the three call sites; delete the inline duplicates.
--
-- Phase 5 -- wire up the real config_preset (moved last)
--   - Add bi_preset(): vim.ui.select over cmake_presets.list(root), then
--     config_preset = cmake_presets.resolve(root, name) or <empty config>.
--   - root = vim.fn.getcwd() for now.
--   - Delete the hardcoded config/config_preset test literals and the
--     vim.print(cmake_presets.resolve(...)) scratch line at the bottom, now
--     that phases 1-4 were proven against fake data and this swaps in the
--     real source.
--
-- Phase 6 -- cleanup
--   - Remove leftover notify() debug calls once everything above is
--     confirmed working end-to-end.
------------------------------------------------------------------------------
