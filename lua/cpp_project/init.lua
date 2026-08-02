-- cpp_project - the entry point for driving a C/C++ project (root detection,
-- clangd, cmake). Aggregates its submodules so callers can reach everything
-- through a single `require("cpp_project")` instead of requiring each file:
--
--   require("cpp_project").find_root(0)
--   require("cpp_project").cmake
--
-- Root detection lives directly here; cmake is delegated to submodules.
--
-- Project root detection for C/C++ buffers and files, independent of any UI.
--
-- Each buffer/file resolves to its own project root, so two files from two
-- different projects can be open at once and each links to the right project.
-- find_root therefore keys off a single buffer/file: pass a bufnr (0 = the
-- current buffer) or a file path.
--
-- It answers "what project does this belong to" in priority order: this
-- session's manual override, then a saved/known root, then marker-sniffing
-- (.git, CMakePresets.json, build/) from most to least reliable.
--
-- Consumers, not owners: the FileType c/cpp/objc/objcpp/cuda autocmd (to hand
-- cpp_project.clangd the right root to start in) and cmake_menu (to display /
-- re-pick the current root). Neither should reimplement any of this - they
-- call in here.

local M = {}

-- Root stores, highest priority first. Placeholders until persistence lands:
--   session_roots  - manual "use this root for now" overrides, in-memory only.
--   known_projects - saved/remembered roots, to be persisted under
--                    stdpath("state") (not scattered across each repo).
-- Both are keyed by root path; find_root climbs a file's ancestors looking for
-- a hit before falling back to marker-sniffing, since CMakeLists.txt / build
-- dirs exist at multiple nesting levels and are never fully reliable.
M.session_roots = {} ---@type table<string, true>
M.known_projects = {} ---@type table<string, any>

--- Nearest ancestor directory of `path` that is a key in `set`, or nil.
---@param path string
---@param set table<string, any>
---@return string?
local function nearest_ancestor_in(path, set)
	local dir = vim.fs.dirname(path)
	while dir do
		if set[dir] then return dir end
		local parent = vim.fs.dirname(dir)
		if parent == dir then break end
		dir = parent
	end
end

-- Sniffed in order, most to least reliable; the first ancestor carrying any of
-- these wins if no session/known root matched.
local MARKERS = { ".git", "CMakePresets.json", "build" }

--- How find_root arrived at a root, so callers can tell a remembered root from
--- a mere guess (e.g. cmake_menu's "saved" vs "guessed" marker).
---@class CppProject.RootSource
---@field source "session_roots"|"known_projects"|"marker"
---@field marker string? which marker matched, only when source == "marker"

--- Finds the project root for a single buffer or file.
--- Priority: session override -> saved/known root -> marker-sniffing.
---@param source nil|integer|string bufnr (0 = current) or a file path
---@return string? root nil if none found (e.g. an unnamed buffer)
---@return CppProject.RootSource? found_via nil iff root is nil
function M.find_root(source)
	-- normalize to an absolute file path
	local path = ""
	source = source or 0
	if type(source) == "number" then
		path = vim.api.nvim_buf_get_name(source)
	elseif type(source) == "string" then
		path = vim.fn.fnamemodify(source, ":p")
	end
	if path == "" then return nil end

	local root = nearest_ancestor_in(path, M.session_roots)
	if root then return root, { source = "session_roots" } end

	root = nearest_ancestor_in(path, M.known_projects)
	if root then return root, { source = "known_projects" } end

	for _, marker in ipairs(MARKERS) do
		root = vim.fs.root(path, { marker })
		if root then return root, { source = "marker", marker = marker } end
	end

	return nil
end

return M
