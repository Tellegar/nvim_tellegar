-- Parse a project's CMakePresets.json / CMakeUserPresets.json and resolve a
-- configure preset into a config-shaped table matching the one cpp.scratch
-- edits: { cmake_preset_name, build_dir, generator, defines = {{name,value}} }.
--
-- This is the "config_cmake" source: the values a chosen preset contributes,
-- fully resolved (inherits chain + macro expansion + include files) so the
-- menu can display them and mark them as preset-derived (dark).
--
-- Scope: best-effort resolver, enough for the menu. It does NOT evaluate
-- `condition` blocks (all non-hidden presets are listed); if we ever need
-- cmake-exact selectability, `cmake --list-presets` is the authoritative set.
--
-- TODO: bi_generator()'s hardcoded choices list (configure.lua) should be
-- replaced by shelling out to `cmake --help` and parsing the "Generators"
-- section (confirmed it lists the full valid set, `*` marks the default --
-- see cmake_default_generator() in cpp.scratch for the existing
-- single-match version of this parse). Watch for: long generator names
-- wrapping onto their own line with no `=` (e.g. "Sublime Text 2 - Unix
-- Makefiles", `=` follows on the next line), and no space before `=` for
-- some entries (e.g. "Eclipse CDT4 - Unix Makefiles="). Also decide
-- whether to filter out "(deprecated)" generators.

local M = {}

local uv = vim.uv or vim.loop
local PRESET_FILES = { "CMakePresets.json", "CMakeUserPresets.json" }

---@class CMake.PresetListEntry
---@field name string
---@field display string

---@class CMake.PresetRaw
---@field generator string?
---@field binaryDir string?
---@field toolchainFile string?
---@field cacheVariables table<string, any>

---@class CMake.PresetMacroCtx
---@field sourceDir string
---@field sourceParentDir string
---@field sourceDirName string
---@field presetName string
---@field generator string
---@field hostSystemName string
---@field dollar string

---@param path string
---@return table? data decoded JSON, nil on read/parse failure
local function read_json(path)
	local ok, lines = pcall(vim.fn.readfile, path)
	if not ok then
		return nil
	end
	local ok2, data = pcall(vim.json.decode, table.concat(lines, "\n"))
	return ok2 and data or nil
end

--- Collects configurePresets from a file and everything it `include`s, keyed
--- by name (first definition wins). `seen` guards include cycles.
---@param path string
---@param into table<string, table> raw preset json objects, keyed by name
---@param seen table<string, true>
local function collect_from_file(path, into, seen)
	path = vim.fs.normalize(path)
	if seen[path] then
		return
	end
	seen[path] = true
	local data = read_json(path)
	if not data then
		return
	end
	local dir = vim.fs.dirname(path)
	for _, inc in ipairs(data.include or {}) do
		collect_from_file(vim.startswith(inc, "/") and inc or (dir .. "/" .. inc), into, seen)
	end
	for _, p in ipairs(data.configurePresets or {}) do
		if p.name and not into[p.name] then
			into[p.name] = p
		end
	end
end

--- All configure presets for a root, keyed by name (raw, unresolved).
---@param root string
---@return table<string, table> raw preset json objects, keyed by name
local function collect(root)
	local into, seen = {}, {}
	for _, f in ipairs(PRESET_FILES) do
		collect_from_file(root .. "/" .. f, into, seen)
	end
	return into
end

--- True if the project has any presets file.
---@param root string
---@return boolean
function M.available(root)
	for _, f in ipairs(PRESET_FILES) do
		if uv.fs_stat(root .. "/" .. f) then
			return true
		end
	end
	return false
end

--- Selectable (non-hidden) configure presets: { { name, display }, ... }.
---@param root string
---@return CMake.PresetListEntry[]
function M.list(root)
	local out = {}
	for name, p in pairs(collect(root)) do
		if not p.hidden then
			out[#out + 1] = { name = name, display = p.displayName or name }
		end
	end
	table.sort(out, function(a, b)
		return a.name < b.name
	end)
	return out
end

------------------------------------------------------------------------------
-- Resolution: inherits chain + macros.
------------------------------------------------------------------------------

---@param v string|table|nil
---@return table
local function as_list(v)
	if v == nil then
		return {}
	end
	if type(v) == "string" then
		return { v }
	end
	return v
end

--- cacheVariables value -> string. Accepts string | bool | number | {value=}.
---@param v string|boolean|number|{value: string|boolean|number}
---@return string
local function cache_value(v)
	if type(v) == "table" then
		v = v.value
	end
	if type(v) == "boolean" then
		return v and "ON" or "OFF"
	end
	return tostring(v)
end

--- Overlay one preset's raw fields (child) over an accumulator (base).
---@param acc CMake.PresetRaw
---@param p table raw preset json object
local function overlay(acc, p)
	if p.generator then
		acc.generator = p.generator
	end
	if p.binaryDir then
		acc.binaryDir = p.binaryDir
	end
	if p.toolchainFile then
		acc.toolchainFile = p.toolchainFile
	end
	for k, v in pairs(p.cacheVariables or {}) do
		acc.cacheVariables[k] = v
	end
end

--- Resolve a preset's raw fields, walking inherits. First-listed inherit wins;
--- the preset's own fields win over all inherited.
---@param name string
---@param presets table<string, table> raw preset json objects, keyed by name
---@param visiting table<string, true> guards inherits cycles
---@return CMake.PresetRaw
local function resolve_raw(name, presets, visiting)
	local p = presets[name]
	if not p or visiting[name] then
		return { cacheVariables = {} }
	end
	visiting[name] = true
	local acc = { cacheVariables = {} }
	local inh = as_list(p.inherits)
	for i = #inh, 1, -1 do -- apply last->first so inh[1] wins
		overlay(acc, resolve_raw(inh[i], presets, visiting))
	end
	overlay(acc, p) -- own fields win over inherited
	visiting[name] = nil
	return acc
end

---@param root string
---@param preset_name string
---@param generator string?
---@return CMake.PresetMacroCtx
local function macro_ctx(root, preset_name, generator)
	return {
		sourceDir = root,
		sourceParentDir = vim.fs.dirname(root),
		sourceDirName = vim.fs.basename(root),
		presetName = preset_name,
		generator = generator or "",
		hostSystemName = uv.os_uname().sysname,
		dollar = "$",
	}
end

---@param str string?
---@param ctx CMake.PresetMacroCtx
---@return string?
local function expand(str, ctx)
	if type(str) ~= "string" then
		return str
	end
	str = str:gsub("%$p?env{([%w_]+)}", function(var)
		return vim.env[var] or ""
	end)
	str = str:gsub("%${([%w]+)}", function(key)
		return ctx[key] or ""
	end)
	return str
end

--- Resolve a configure preset into a config-shaped table, or nil if unknown.
--- Shape mirrors cpp.scratch's config:
---   { cmake_preset_name, build_dir, generator, defines = {{name,value},...} }
--- `build_dir` is the basename of the resolved binaryDir (our build/<name>
--- convention); binaryDir pointing elsewhere is an edge case we ignore for now.
---@param root string
---@param name string
---@return Cpp.Config? config nil if `name` isn't a known preset
function M.resolve(root, name)
	local presets = collect(root)
	if not presets[name] then
		return nil
	end
	local raw = resolve_raw(name, presets, {})
	local ctx = macro_ctx(root, name, raw.generator)

	local defines = {}
	for k, v in pairs(raw.cacheVariables) do
		defines[#defines + 1] = { name = k, value = expand(cache_value(v), ctx) }
	end
	table.sort(defines, function(a, b)
		return a.name < b.name
	end)

	return {
		cmake_preset_name = name,
		build_dir = raw.binaryDir and vim.fs.basename(expand(raw.binaryDir, ctx)) or nil,
		generator = raw.generator and expand(raw.generator, ctx) or nil,
		defines = defines,
	}
end

return M
