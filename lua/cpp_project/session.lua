-- cpp_project.session - the current project: which root is active, which
-- config it's using, and the in-memory copy of everything cpp_project.project_store
-- has saved for that root.
--
-- This is the single owner of "the current project's config". It lives in
-- cpp_project rather than cmake_menu because the fact is a project fact, not a
-- menu fact: clangd, cmake invocation and root resolution all want it, and the
-- menu is only one (current) reader. cmake_menu.session stays on top of this
-- one, holding the strictly-UI half (which buffer the menu was opened from).
--
--   session.resolve(path)   -- (re-)resolve a file's root, loading its config
--   session.root            -- the resolved root, nil if none
--   session.found_via       -- how cpp_project.find_root arrived at it
--   session.config          -- the selected CMake.Config ({} when none is picked)
--   session.configs         -- every config saved for this root
--
-- Two things about `config` that the rest of the code depends on:
--
--   * It is a *reference into* `configs` whenever it has anything beyond a
--     preset name. So editing it (cmake_menu.tab_configure) edits the stored
--     entry in place - no lookup by identity, which is the question current.md
--     leaves open. Only the plain "this preset, unmodified" case is a
--     standalone table outside `configs`, matching the store's rule that such
--     a config needs no entry at all. commit() moves a config between those
--     two states as it gains/loses overrides.
--   * It is never nil, so callers can read config.build_dir etc. without
--     guarding first. has_config() is the "has the user actually picked one"
--     test.
--
-- Writing: save() persists, but only for an already-tracked root, and only
-- when called - nothing in here writes on a timer or on resolve(). Tracking a
-- new root is track()'s job alone (cmake_menu's <C-s>). That keeps
-- project_store's rule intact: this instance can never resurrect a project
-- another instance deliberately removed, because every write is a user action.

local cmake_presets = require("cpp_project.cmake_presets")
local cpp_project = require("cpp_project")
local project_store = require("cpp_project.project_store")

local M = {}

M.path = nil ---@type string? the file path root resolution last ran on
M.root = nil ---@type string?
M.found_via = nil ---@type CppProject.RootSource?

---@type CMake.Config the selected config; `{}` when nothing is picked
M.config = {}
---@type CMake.Config[] every config saved for M.root
M.configs = {}

-- Resolved presets, keyed by "<root>\0<preset name>". A preset resolves to the
-- same thing until CMakePresets.json changes, and resolving walks the inherits
-- chain over freshly-parsed json, so this is cached rather than redone on
-- every render. invalidate_presets() drops it when the root changes.
local preset_cache = {}

----------------------------------------------------------------------------------------------------
-- config shape helpers
----------------------------------------------------------------------------------------------------

--- Whether `cfg` is nothing but a preset name - the case the store deliberately
--- keeps *out* of `configs`, since "use this preset unmodified" is fully
--- described by `selected_config` alone.
---@param cfg CMake.Config
---@return boolean
local function is_bare_preset(cfg)
	return cfg.cmake_preset_name ~= nil
		and cfg.build_dir == nil
		and cfg.generator == nil
		and (cfg.defines == nil or #cfg.defines == 0)
end

--- Whether `cfg` says anything at all.
---@param cfg CMake.Config
---@return boolean
local function is_empty(cfg)
	return next(cfg) == nil
end

--- The string written to `selected_config`, and matched against on load.
--- build_dir first, since that's the identifier for anything with overrides;
--- a bare preset is identified by its name.
---@param cfg CMake.Config
---@return string?
local function identify(cfg)
	return cfg.build_dir or cfg.cmake_preset_name
end

---@param cfg CMake.Config
---@return integer? index of `cfg` in M.configs
local function index_of(cfg)
	for i, c in ipairs(M.configs) do
		if c == cfg then
			return i
		end
	end
end

----------------------------------------------------------------------------------------------------
-- loading
----------------------------------------------------------------------------------------------------

local function clear()
	M.config, M.configs = {}, {}
end

--- Load M.root's saved state out of project_store into config/configs,
--- discarding whatever was in memory. Called when the root changes; call it
--- directly to drop in-session edits and go back to what's on disk.
---
--- Lookup follows the store's rule: `selected_config` is matched against
--- `configs` (by build_dir, or by preset name for an entry that has no
--- build_dir); a miss means it's a bare preset name, used unmodified.
---@return boolean loaded false if the root isn't tracked
function M.reload()
	clear()
	if not M.root then
		return false
	end

	local data = project_store.get(M.root)
	if not data then
		return false
	end

	for _, c in ipairs(data.configs or {}) do
		M.configs[#M.configs + 1] = vim.deepcopy(c)
	end

	local sel = data.selected_config
	if sel then
		for _, c in ipairs(M.configs) do
			if c.build_dir == sel or (c.build_dir == nil and c.cmake_preset_name == sel) then
				M.config = c
				break
			end
		end
		if is_empty(M.config) then
			M.config = { cmake_preset_name = sel }
		end
	end

	return true
end

--- Point the session at `root`, loading its saved config. A no-op when it's
--- already the current root, so re-resolving the same project doesn't throw
--- away edits the user hasn't saved yet.
---@param root string?
---@param found_via CppProject.RootSource?
local function set_root(root, found_via)
	M.found_via = found_via
	if root == M.root then
		return
	end
	M.root = root
	preset_cache = {}
	M.reload()
end

--- Resolve `path`'s project root (see cpp_project.find_root) and make it the
--- current one, loading its saved config if it has one.
---
--- Mirrors project_store into cpp_project.known_projects first: that mirror is
--- what lets a tracked project resolve to the root it was saved with even when
--- markers would miss it, so it has to be current *before* find_root runs.
--- Cheap when the file hasn't changed (project_store.read is mtime-cached),
--- and picks up another instance's saves/removals in passing.
---@param path string a file path (not a bufnr - see cmake_menu.session.path)
---@return string? root
function M.resolve(path)
	M.path = path
	cpp_project.refresh_known_projects()
	set_root(cpp_project.find_root(path))
	return M.root
end

--- Pin `dir` as this session's root override for the current path, then
--- re-resolve. Replaces the currently-resolved override rather than just
--- adding one: find_root picks the *nearest* pinned ancestor, so leaving the
--- old (deeper) pin in place would keep winning and a shallower re-pick would
--- silently do nothing.
---@param dir string|nil nil clears the override
function M.set_root(dir)
	if M.root then
		cpp_project.session_roots[M.root] = nil
	end
	if dir then
		cpp_project.session_roots[dir] = true
	end
	if M.path then
		M.resolve(M.path)
	end
end

----------------------------------------------------------------------------------------------------
-- reading the selection
----------------------------------------------------------------------------------------------------

--- Whether a config has actually been picked for the current root, not just
--- one being available to pick. Gates cmake_menu.tab_configure - editing cmake
--- options makes no sense before something has settled on which preset /
--- build dir they apply to.
---@return boolean
function M.has_config()
	return not is_empty(M.config)
end

--- Whether the current root is saved in project_store.
---@return boolean
function M.tracked()
	return M.root ~= nil and project_store.tracked(M.root)
end

--- The saved configs that are *not* tied to a cmake preset - what the menu
--- offers as "manual config" choices. Derived from `configs` rather than kept
--- as a second list, so adding one is just adding a config.
---@return CMake.Config[]
function M.manual_configs()
	local out = {}
	for _, c in ipairs(M.configs) do
		if not c.cmake_preset_name then
			out[#out + 1] = c
		end
	end
	return out
end

--- The selected config's cmake preset, fully resolved (see
--- cpp_project.cmake_presets.resolve), or nil when no preset is selected or
--- the name isn't one this project defines. Cached per root+name.
---
--- This is what the preset-sourced fallbacks in cmake_menu.tab_configure read:
--- an unset build_dir/generator/define falls through to whatever the preset
--- says before falling through to a hardcoded default.
---@return CMake.Config?
function M.preset()
	local name = M.config.cmake_preset_name
	if not name or not M.root then
		return nil
	end
	local key = M.root .. "\0" .. name
	local hit = preset_cache[key]
	if hit == nil then
		hit = cmake_presets.resolve(M.root, name) or false
		preset_cache[key] = hit
	end
	return hit or nil
end

----------------------------------------------------------------------------------------------------
-- changing the selection
----------------------------------------------------------------------------------------------------

--- Reconcile `config`'s membership in `configs` with its contents, then save.
--- Call after mutating `config` in place (cmake_menu.tab_configure's field
--- edits): a config that has gained an override has to become a stored entry,
--- and one that has lost its last override stops needing one.
function M.commit()
	local i = index_of(M.config)
	if is_bare_preset(M.config) or is_empty(M.config) then
		if i then
			table.remove(M.configs, i)
		end
	elseif not i then
		M.configs[#M.configs + 1] = M.config
	end
	M.save()
end

--- Select `cfg` - either an existing member of `configs` or a new config to
--- add. Passing `{}` clears the selection without touching `configs`.
---@param cfg CMake.Config
function M.select(cfg)
	M.config = cfg
	M.commit()
end

--- Select cmake preset `name`, unmodified. Reuses the existing entry if this
--- project already has overrides saved for that preset.
---@param name string
function M.select_preset(name)
	for _, c in ipairs(M.configs) do
		if c.cmake_preset_name == name then
			return M.select(c)
		end
	end
	M.select({ cmake_preset_name = name })
end

--- Select the manual config for `build_dir`, adding one if it's new.
---@param build_dir string
function M.select_build_dir(build_dir)
	for _, c in ipairs(M.configs) do
		if c.build_dir == build_dir and not c.cmake_preset_name then
			return M.select(c)
		end
	end
	M.select({ build_dir = build_dir })
end

--- Clear the selection. The config's entry (if it had one) stays in `configs`,
--- so this un-picks rather than deletes.
function M.unselect()
	M.select({})
end

----------------------------------------------------------------------------------------------------
-- writing
----------------------------------------------------------------------------------------------------

---@return table entry the projects.json record for the current state
local function entry()
	local configs = {}
	for _, c in ipairs(M.configs) do
		configs[#configs + 1] = c
	end
	return {
		selected_config = identify(M.config),
		configs = configs,
	}
end

--- Persist the current root's config to project_store, but only if it's
--- already tracked - saving an untracked root would silently start tracking
--- it, which is track()'s (i.e. the user's) decision to make, not a side
--- effect of picking a config in the menu.
---@return boolean written
function M.save()
	if not M.tracked() then
		return false
	end
	return project_store.set(assert(M.root), entry())
end

--- "Start tracking this project": write the current root and config into
--- project_store even though it isn't tracked yet, which is also what puts the
--- root into cpp_project.known_projects (a root is tracked exactly when it's
--- in the store - there is no separate flag).
---
--- Deliberately the only path that starts tracking, alongside a manage-entries
--- UI: nothing here tracks a project on its own.
---
--- Re-resolves afterwards, because tracking changes the answer: the root is
--- now in known_projects, which outranks marker-sniffing, so `found_via` would
--- otherwise keep reporting the marker that got us here (".git") long after
--- that stopped being why this root wins. Re-resolving also re-reads
--- projects.json, so anything another instance wrote alongside our own entry
--- is picked up in the same pass. It can't clobber what we just saved: the
--- root is unchanged, so resolve() keeps the in-memory config rather than
--- reloading over it.
---@return boolean written
function M.track()
	if not M.root then
		return false
	end
	if not project_store.set(M.root, entry()) then
		return false
	end
	if M.path then
		M.resolve(M.path)
	else
		cpp_project.refresh_known_projects()
	end
	return true
end

--- Stop tracking the current root. Deliberately does *not* re-resolve the way
--- track() does: dropping out of known_projects can leave a marker-less
--- project resolving to nothing at all, and a root that vanishes takes the
--- displayed config and the ability to press <C-s> again with it. So the
--- in-memory root and config are left standing - the project is simply no
--- longer saved. Whoever wires this to a key should decide whether untracking
--- the *current* project should also pin its root as a session override, which
--- is what would keep it resolving honestly rather than by a stale mirror.
---@return boolean written
function M.untrack()
	if not M.root or not project_store.remove(M.root) then
		return false
	end
	cpp_project.refresh_known_projects()
	return true
end

return M
