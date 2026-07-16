-- Throwaway prototype surface for the :Cpp menu's *config section* only.
-- Drives cpp.menu directly with fake state so layouts can be iterated without
-- any cmake / clangd plumbing. Delete once the config-section shape is settled.
--
-- TWO-CONFIG MODEL
--   config        - values the user has EXPLICITLY set (overrides).
--   config_cmake  - values a chosen preset contributes, resolved from the
--                   project's CMakePresets.json (see cpp.cmake_presets).
--   The effective view rendered in the menu is `config` overlaid on
--   `config_cmake`. Values that come only from config_cmake (not overridden)
--   render dark - they're preset-derived defaults, not explicit choices.
--   The cmake command is built from the RAW `config` (+ --preset), since cmake
--   resolves the preset itself; build_dir is always present (explicit, preset,
--   or generated).
--
-- Points at /tmp/t (our example project) so presets are real.
-- Plain unicode only, same as cpp.menu (no nerd-font glyphs).

local M = {}
local presets = require("cpp.cmake_presets")

local ROOT = "/tmp/t"

-- Explicit config: only what the user set. Empty by default.
local config = {
	cmake_preset_name = nil,
	build_dir = nil,
	generator = nil,
	defines = {},
}

-- Preset-derived config (config-shaped), or nil when no preset is chosen.
local config_cmake = nil

------------------------------------------------------------------------------
-- Effective view: overlay config over config_cmake, tracking the source of
-- each value ("config" = explicit/normal, "cmake" = preset/dark).
------------------------------------------------------------------------------

--- Scalar field (build_dir / generator): returns value, source.
local function eff_scalar(field)
	if config[field] ~= nil then
		return config[field], "config"
	end
	if config_cmake and config_cmake[field] ~= nil then
		return config_cmake[field], "cmake"
	end
	return nil, nil
end

--- The config.defines entry for `name`, if the user set one explicitly.
local function config_define(name)
	for _, d in ipairs(config.defines) do
		if d.name == name then
			return d
		end
	end
end

--- Effective value + source for a cache var by name.
local function eff_define(name)
	local d = config_define(name)
	if d then
		return d.value, "config"
	end
	if config_cmake then
		for _, cd in ipairs(config_cmake.defines) do
			if cd.name == name then
				return cd.value, "cmake"
			end
		end
	end
	return nil, nil
end

--- Ordered union of cache-var names: preset order first, explicit extras last.
local function union_define_names()
	local order, seen = {}, {}
	if config_cmake then
		for _, d in ipairs(config_cmake.defines) do
			if not seen[d.name] then
				order[#order + 1], seen[d.name] = d.name, true
			end
		end
	end
	for _, d in ipairs(config.defines) do
		if not seen[d.name] then
			order[#order + 1], seen[d.name] = d.name, true
		end
	end
	return order
end

local function eff_build_type()
	return (select(1, eff_define("CMAKE_BUILD_TYPE")))
end

--- Generated build-dir name (kit mode only - preset mode carries binaryDir).
local function gen_dir()
	return (eff_build_type() or "debug"):lower()
end

--- Build dir always resolves to something: explicit, preset, or generated.
local function build_dir_eff()
	local v, s = eff_scalar("build_dir")
	if v then
		return v, s
	end
	return gen_dir(), "generated"
end

-- hl by source: explicit is bright, everything derived is dark.
local function val_hl(source)
	return source == "config" and "String" or "Comment"
end
local function name_hl(source)
	return source == "config" and "CppMenuLabel" or "Comment"
end

--- What `cmake` would pick with no -G: it marks its choice with `*` in
--- `cmake --help`'s generator list, e.g. "* Unix Makefiles = ...". Cached
--- since it shells out; false means "queried and failed" vs. nil "not yet".
local cmake_default_generator_cache
local function cmake_default_generator()
	if cmake_default_generator_cache == nil then
		cmake_default_generator_cache = false
		local ok, res = pcall(function() return vim.system({ "cmake", "--help" }, { text = true }):wait() end)
		if ok and res.code == 0 then
			for line in res.stdout:gmatch("[^\n]+") do
				local name = line:match("^%*%s*(.-)%s*=")
				if name then
					cmake_default_generator_cache = name
					break
				end
			end
		end
	end
	return cmake_default_generator_cache or nil
end

------------------------------------------------------------------------------
-- Mutations: everything writes to `config` (the explicit overrides).
------------------------------------------------------------------------------

local function set_config_define(name, value)
	local d = config_define(name)
	if d then
		d.value = value
	else
		table.insert(config.defines, { name = name, value = value })
	end
end

local function remove_config_define(name)
	for i, d in ipairs(config.defines) do
		if d.name == name then
			table.remove(config.defines, i)
			return true
		end
	end
	return false
end

local function choose_preset(name)
	config = { cmake_preset_name = name, build_dir = nil, generator = nil, defines = {} }
	config_cmake = presets.resolve(ROOT, name)
	M.open()
end

local function clear_preset()
	config.cmake_preset_name = nil
	config_cmake = nil
	M.open()
end

------------------------------------------------------------------------------
-- The cmake configure command implied by the RAW config.
------------------------------------------------------------------------------

local function command()
	local parts = { "cmake" }
	if config.cmake_preset_name then
		parts[#parts + 1] = "--preset " .. config.cmake_preset_name
	end
	parts[#parts + 1] = "-B build/" .. (select(1, build_dir_eff()))
	if config.generator then
		parts[#parts + 1] = "-G " .. vim.fn.shellescape(config.generator)
	end
	for _, d in ipairs(config.defines) do
		parts[#parts + 1] = "-D" .. d.name .. "=" .. d.value
	end
	return table.concat(parts, " ")
end

------------------------------------------------------------------------------
-- Item spec.
------------------------------------------------------------------------------

local function build_items()
	local items = { { section = "config" } }

	if presets.available(ROOT) then
		table.insert(items, {
			key = "p",
			label = "CMake preset",
			value = function() return config.cmake_preset_name or "(none)" end,
			value_hl = function() return config.cmake_preset_name and "String" or "Comment" end,
			actions = {
				{ key = "x", desc = "clear", fn = clear_preset },
				{
					key = "<CR>",
					desc = "select",
					alt_keys = { "l", "<Right>", "i", "I", "a", "A" },
					fn = function()
						local list = presets.list(ROOT)
						vim.ui.select(list, {
							prompt = "cmake configure preset",
							format_item = function(it) return it.display end,
						}, function(choice)
							if choice then
								choose_preset(choice.name)
							end
						end)
					end,
				},
			},
		})
	end

	table.insert(items, {
		key = "d",
		label = "Build dir",
		value = function()
			local v, s = build_dir_eff()
			if s == "generated" then
				return { { v, "Comment" }, { " (generated)", "NonText" } }
			end
			return { { v, val_hl(s) } }
		end,
		actions = {
			{ key = "x", desc = "clear", fn = function(h) config.build_dir = nil; h:render() end },
			{
				key = "<CR>",
				desc = "rename",
				alt_keys = { "l", "<Right>", "i", "I", "a", "A" },
				fn = function(h)
					vim.ui.input({ prompt = "build dir name: ", default = select(1, build_dir_eff()) }, function(v)
						config.build_dir = (v and v ~= "") and v or nil
						h:render()
					end)
				end,
			},
		},
	})

	table.insert(items, {
		key = "t",
		label = "Build type",
		value = function()
			local v, s = eff_define("CMAKE_BUILD_TYPE")
			return v and { { v, val_hl(s) } } or { { "None (unset)", "Comment" } }
		end,
		actions = {
			{
				key = "x",
				desc = "clear",
				fn = function(h)
					if remove_config_define("CMAKE_BUILD_TYPE") then
						h:render()
					elseif eff_define("CMAKE_BUILD_TYPE") ~= nil then
						vim.notify("scratch: build type is a preset default - override it instead", vim.log.levels.INFO)
					end
				end,
			},
			{
				key = "<CR>",
				desc = "select",
				alt_keys = { "l", "<Right>", "i", "I", "a", "A" },
				fn = function(h)
					vim.ui.select({ "Debug", "RelWithDebInfo", "Release", "MinSizeRel" }, { prompt = "build type" }, function(choice)
						if not choice then
							return
						end
						local existed = eff_define("CMAKE_BUILD_TYPE") ~= nil
						set_config_define("CMAKE_BUILD_TYPE", choice)
						if existed then
							h:render()
						else
							M.open()
						end
					end)
				end,
			},
		},
	})

	table.insert(items, {
		key = "g",
		label = "Generator",
		value = function()
			local v, s = eff_scalar("generator")
			if v then
				return { { v, val_hl(s) } }
			end
			local default = cmake_default_generator()
			if default then
				return { { default, "Comment" }, { " (default)", "NonText" } }
			end
			return { { "(unset)", "Comment" } }
		end,
		actions = {
			{ key = "x", desc = "clear", fn = function(h) config.generator = nil; h:render() end },
			{
				key = "<CR>",
				desc = "select",
				alt_keys = { "l", "<Right>", "i", "I", "a", "A" },
				fn = function(h)
					local choices = { "Ninja", "Ninja Multi-Config", "Unix Makefiles" }
					local default = cmake_default_generator()
					local default_choice = default and ("(default: " .. default .. ")")
					if default_choice then
						table.insert(choices, 1, default_choice)
					end
					vim.ui.select(choices, { prompt = "generator" }, function(choice)
						if not choice then
							return
						end
						-- picking the default entry clears the override so cmake resolves it itself
						config.generator = (choice ~= default_choice) and choice or nil
						h:render()
					end)
				end,
			},
		},
	})

	-- -D cache vars: one row per union name (value/source computed live), then
	-- an add row. Each row: <CR> edit value, <C-CR> edit name, x remove.
	table.insert(items, { section = "-Defines" })
	for _, name in ipairs(union_define_names()) do
		table.insert(items, {
			label = function() return name end,
			label_hl = function() return name_hl(select(2, eff_define(name))) end,
			value = function()
				local v, s = eff_define(name)
				return { { v or "", val_hl(s) } }
			end,
			actions = {
				{
					key = "x",
					desc = "remove",
					fn = function()
						if remove_config_define(name) then
							M.open()
						elseif eff_define(name) ~= nil then
							vim.notify("scratch: '" .. name .. "' is a preset default - override its value instead", vim.log.levels.INFO)
						end
					end,
				},
				{
					key = "<C-CR>",
					desc = "edit name",
					alt_keys = { "h", "<Left>", "I", "A" },
					fn = function()
						if not config_define(name) then
							vim.notify("scratch: '" .. name .. "' is preset-derived - edit value to override it first", vim.log.levels.INFO)
							return
						end
						vim.ui.input({ prompt = "var name: ", default = name }, function(v)
							if v and v ~= "" and v ~= name then
								config_define(name).name = v
								M.open()
							end
						end)
					end,
				},
				{
					key = "<CR>",
					desc = "edit value",
					alt_keys = { "l", "<Right>", "i", "a" },
					fn = function(h)
						vim.ui.input({ prompt = name .. " = ", default = select(1, eff_define(name)) }, function(v)
							if v ~= nil then
								set_config_define(name, v) -- promotes a preset default to explicit
								h:render()
							end
						end)
					end,
				},
			},
		})
	end
	table.insert(items, {
		key = "D",
		label = "Add -D…",
		actions = {
			{
				key = "<CR>",
				desc = "add cache var",
				alt_keys = { "h", "<Right>", "i", "I", "a", "A" },
				fn = function()
					vim.ui.input({ prompt = "NAME=VALUE: " }, function(v)
						if not v or v == "" then
							return
						end
						local n, val = v:match("^%s*([^=]-)%s*=(.*)$")
						if not n or n == "" then
							vim.notify("scratch: expected NAME=VALUE", vim.log.levels.WARN)
							return
						end
						set_config_define(n, val)
						M.open()
					end)
				end,
			},
		},
	})

	-- Command preview (built from the raw config), full and untruncated so it
	-- can be inspected; selectable (actions, not a section) so it can be
	-- navigated to and yanked with `y`.
	table.insert(items, { label = "" })
	table.insert(items, {
		label = function() return command() end,
		label_hl = "Comment",
		actions = {
			{
				key = "y",
				desc = "copy (vim)",
				fn = function()
					vim.fn.setreg('"', command())
					vim.notify("scratch: copied cmake command (vim)", vim.log.levels.INFO)
				end,
			},
			{
				key = "+",
				desc = "copy (system)",
				fn = function()
					vim.fn.setreg("+", command())
					vim.notify("scratch: copied cmake command (system)", vim.log.levels.INFO)
				end,
			},
		},
	})

	return items
end

function M.open()
	return require("cpp.menu").open({
		title = " config scratch ",
		min_width = 54,
		items = build_items(),
	})
end

vim.api.nvim_create_user_command("CppScratch", M.open, { desc = "Prototype the :Cpp config section" })

return M
