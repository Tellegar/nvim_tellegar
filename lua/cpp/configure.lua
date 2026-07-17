-- The configure part of the :Cpp menu (a gui over cmake's configure step).
-- Responsible for working with configs.

local M = {}

---@class Cpp.Config
---@field cmake_preset_name string?
---@field build_dir string?
---@field generator string?
---@field defines { name: string, value: string }[]

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
	local build_dir = config.build_dir and escape(prefix .. config.build_dir) or "build"
	parts[1] = parts[1] .. " -B " .. build_dir

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

-- Explicit config: only what the user set. Populate this from real state
-- (cmake_presets.resolve, etc.) as sections move over from cpp.scratch.
local config = {
	cmake_preset_name = nil,
	build_dir = nil,
	generator = nil,
	defines = {},
}

---@return Cpp.MenuItem[]
local function build_items()
	local items = {} ---@type Cpp.MenuItem[]

	items[#items+1] = {
		label = "config: " .. vim.inspect(config),
		label_hl = "Comment",
	}
	items[#items+1] = { section = "config" }

	-- Example row - copy this shape for each field as it's ported from
	-- cpp.scratch, then delete once the real fields are in place.
	items[#items+1] = {
		key = "d",
		label = "Build dir",
		value = function() return config.build_dir or "(unset)" end,
		value_hl = function() return config.build_dir and "String" or "Comment" end,
		actions = {
			{ key = "x", desc = "clear", fn = function(h) config.build_dir = nil; h:render() end },
			{
				key = "<CR>",
				desc = "rename",
				fn = function(h)
					vim.ui.input({ prompt = "build dir name: ", default = config.build_dir }, function(v)
						config.build_dir = (v and v ~= "") and v or nil
						h:render()
					end)
				end,
			},
		},
	}

	items[#items+1] = { label = "" }
	items[#items+1] = {
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

_G.config = config

return M
