-- The configure part of the :Cpp menu (a gui over cmake's configure step).
-- Responsible for working with configs.

local M = {}

---@class Cpp.Config
---@field cmake_preset_name string?
---@field build_dir string?
---@field generator string?
---@field defines { name: string, value: string }[]

---@param config Cpp.Config
---@param name string
---@return string? value nil if `name` isn't set
local function define_get(config, name)
	for _, d in ipairs(config.defines) do
		if d.name == name then
			return d.value
		end
	end
end

---@param config Cpp.Config
---@param name string
local function define_clear(config, name)
	for i, d in ipairs(config.defines) do
		if d.name == name then
			table.remove(config.defines, i)
			return
		end
	end
end

---@param config Cpp.Config
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
---@param config Cpp.Config
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
		parts[#parts + 1] = "-D" .. escape(d.name) .. "=" .. escape(d.value)
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

---@type Cpp.Config
local config = {
	cmake_preset_name = nil,
	build_dir = nil,
	generator = nil,
	defines = {},
}

local interact = {
	--primary = { "l", "<Right>", "i", "a" },
	--secondary = { "h", "<Left>", "I", "A" },
	any = {
		"h", "<Left>",
		"l", "<Right>",
		"i", "I",
		"a", "A",
	}
}

---@return Cpp.MenuItem
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

	return {
		key = "d",
		label = "Build dir",
		-- TODO build_dir can be generated/unset/set
		value = function() return config.build_dir and escape(config.build_dir) or "(unset)" end,
		value_hl = function() return config.build_dir and "String" or "Comment" end,
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

---@return Cpp.MenuItem
local function bi_build_type()
	-- TODO explore if cmake doesnt expose valid CMAKE_BUILD_TyPE values
	local choices = { "(unset)", "Debug", "Release", "RelWithDebInfo", "MinSizeRel" }
	return {
		key = "t",
		label = "Build type",
		value = function()
			local value = define_get(config, "CMAKE_BUILD_TYPE")
			return value or "(unset)"
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

---@return Cpp.MenuItem
local function bi_generator()
	-- TODO explore if cmake doesnt expose valid -G values
	local choices = { "(unset)", "Ninja", "Ninja Multi-Config", "Unix Makefiles" }
	return {
		key = "g",
		label = "Generator",
		value = function()
			return config.generator or "(unset)"
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

---@return Cpp.MenuItem
local function bi_build_command()
	return {
		label = function() return table.concat(M.command_parts(config), "\n") end,
		label_hl = "Comment",
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

---@return Cpp.MenuItem[]
local function build_items()
	local items = {} ---@type Cpp.MenuItem[]

	items[#items+1] = {
		label = function() return "config: " .. vim.inspect(config) end,
		label_hl = "Comment",
	}
	items[#items+1] = { section = "config" }

	items[#items+1] = bi_build_dir()
	items[#items+1] = bi_build_type()
	items[#items+1] = bi_generator()

	items[#items+1] = { label = "" }
	items[#items+1] = bi_build_command()

	return items
end

---@return Cpp.MenuSpec
local function create_spec()
	return {
		title = " configure ",
		min_width = 54,
		items = build_items(),
	}
end

function M.menu()
	return require("cpp.menu").open(create_spec())
end

-- testing
package.loaded["cpp.menu"] = nil
package.loaded["cpp.configure"] = nil

M.menu()
--config.build_dir = "asd"
--config.generator = "Ninja"
--
--vim.print(M.command_parts(config))
--vim.print(config)

vim.keymap.set("n", "<C-Space>", ":RunLuaBuffer silent<CR>")

return M
