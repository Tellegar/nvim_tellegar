-- Queries for the cmake binary itself, and cmake command-building utilities,
-- independent of any UI.
--
-- Two things that "valid choices" means for cmake, in different senses:
-- build types aren't a fixed enum cmake enforces (CMAKE_BUILD_TYPE is a
-- plain cache string), just the conventional set every stock toolchain
-- file understands, so that list is static. Generators, on the other
-- hand, vary by platform and cmake build - `cmake --help` reports exactly
-- what this machine's cmake can hand to -G right now - so that list comes
-- from parsing its output.
--
-- CMake.Config/CMake.Define and the command_parts/command builders also
-- live here rather than in cmake_menu, since turning a config into an
-- actual cmake invocation is UI-independent too.

local utils = require("utils")

local M = {}

M.BUILD_TYPES = { "Debug", "Release", "RelWithDebInfo", "MinSizeRel" }

-- will be populated when the M.generators finishes
-- ignores deprecated
-- [default == true] are(is) bubbled to front
-- [flag ~= nil] are bubbled to back
M.GENERATORS = {}

----------------------------------------------------------------------------------------------------
-- parse `cmake --help` for -G options
----------------------------------------------------------------------------------------------------

---@class CMake.Generator
---@field name string
---@field default boolean          -- this is the "* marks default" entry
---@field flag string?             -- trailing parenthetical, e.g. "(deprecated)"
---@field deprecated true?         -- set when flag == "(deprecated)"

--- Parse the "Generators" section of `cmake --help` output into a list of
--- CMake.Generator entries, in the order cmake printed them (default first).
--- @param help_text string
--- @return CMake.Generator[]
function M.parse_generators(help_text)
	local generators = {}
	local in_section = false
	local name, default, desc

	local function flush()
		if not name then return end
		-- trailing parenthetical on the (possibly multi-line-joined) description,
		-- e.g. "(deprecated)" or "(experimental, work-in-progress)".
		local flag = desc:match("(%(.-%))%.?%s*$")
		generators[#generators + 1] = {
			name = name,
			default = default,
			flag = flag,
			deprecated = flag == "(deprecated)" or nil,
		}
		name, default, desc = nil, nil, nil
	end

	for line in help_text:gmatch("[^\n]+") do
		if line:match("^Generators") then
			in_section = true
		elseif in_section then
			local leading = #line:match("^(%s*)")
			-- Entry lines are indented exactly 2 spaces ("  Ninja  = ...") or
			-- marked with a leading "*" for the default ("* Unix Makefiles = ...").
			-- Longer names wrap their "= description" onto a further-indented
			-- continuation line, which we fold into desc to catch a flag like
			-- "(deprecated)" even when it lands on its own wrapped line.
			if leading == 2 or line:match("^%*") then
				flush()
				local rest = line:gsub("^%*?%s*", "")
				local rest_name, rest_desc = rest:match("^(.-)%s*=%s*(.*)$")
				name = (rest_name or rest):gsub("%s+$", "")
				default = line:match("^%*") ~= nil
				desc = rest_desc or ""
				if name == "" then name = nil end
			elseif name then
				desc = desc .. " " .. line:gsub("^%s*", "")
			end
		end
	end
	flush()

	return generators
end

--- Async: list the generators this machine's `cmake` reports via -G --help.
--- @param on_done fun(generators: CMake.Generator[])
function M.generators(on_done)
	vim.system({ "cmake", "--help" }, { text = true }, function(result)
		local generators = result.code == 0 and M.parse_generators(result.stdout) or {}
		vim.schedule(function() on_done(generators) end)
	end)
end

----------------------------------------------------------------------------------------------------
-- CMake.Config utilities
----------------------------------------------------------------------------------------------------

---@class CMake.Config
---@field cmake_preset_name string?
---@field build_dir string? -- nil defers to the preset's own binaryDir (if any), else "build"
---@field generator string?
---@field defines CMake.Define[]?

---@class CMake.Define
---@field name string
---@field value string

---@param config CMake.Config
---@return string[]
function M.command_parts(config)
	local parts = {}
	if config.build_dir then
		parts[#parts + 1] = "-B " .. utils.shell_escape(config.build_dir)
	end
	if config.cmake_preset_name then
		parts[#parts + 1] = "--preset " .. utils.shell_escape(config.cmake_preset_name)
	end
	if config.generator then
		parts[#parts + 1] = "-G " .. utils.shell_escape(config.generator)
	end
	for _, d in ipairs(config.defines or {}) do
		parts[#parts + 1] = utils.shell_escape("-D" .. d.name .. "=" .. d.value)
	end

	parts[1] = parts[1] and "cmake "..parts[1] or "cmake"

	return parts
end

--- @param config CMake.Config
--- @return string
function M.command(config)
	return table.concat(M.command_parts(config), " ")
end

----------------------------------------------------------------------------------------------------
-- require runtime
----------------------------------------------------------------------------------------------------

M.generators(function (generators)
	local out_default = {}
	local out = {}
	local out_with_flag = {}
	for _, g in ipairs(generators) do
		if g.deprecated then
			goto continue
		elseif g.flag then
			out_with_flag[#out_with_flag+1] = g
		elseif g.default then
			out_default[#out_default+1] = g
		else
			out[#out+1] = g
		end
		::continue::
	end
	M.GENERATORS = utils.concat{ out_default, out, out_with_flag }
end)

return M
