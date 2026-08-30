-- cpp_project.project_store — the on-disk record of which projects are
-- tracked, and the config each one uses. One file for all projects, at
-- stdpath("state")/cmake_menu/projects.json:
--
--   { "version": 1, "projects": { "<root>": { selected_config, configs } } }
--
-- Roots are the map keys, so the file stays readable and greppable by hand.
--
-- Concurrency, in short: readers take no lock, writers take an exclusive one.
--   * Writes finish with an atomic temp+rename, so a reader always sees either
--     the whole old file or the whole new one - never a torn read, and a crash
--     mid-write leaves the previous version intact. That's what makes the
--     reader lock unnecessary.
--   * Writers still need to exclude each other: a save is read-modify-write
--     over every project, so two unlocked concurrent saves would drop one of
--     the two projects' entries entirely. acquire() below is an O_EXCL
--     lockfile held across read->modify->write->rename.
--   * Nothing here writes on its own. Saves happen only on an explicit user
--     action (cmake_menu's <C-s>), which is what keeps one instance from
--     silently resurrecting a project another instance deliberately removed.
--
-- Reads are mtime-cached: re-parsing is skipped while the file is unchanged,
-- so callers can call read() freely at each point they need current data.

local M = {}

local uv = vim.uv or vim.loop

-- Lock tuning: a save writes one small file, so waits are short by
-- construction. A lockfile older than STALE_MS is assumed to be left over
-- from a crashed instance and is removed rather than waited out.
local LOCK_STALE_MS = 5000
local LOCK_RETRY_MS = 10
local LOCK_TIMEOUT_MS = 1000

-- Last parsed file contents plus the mtime it was parsed at; read() re-parses
-- only when the mtime moved (nil mtime = file absent).
local cache = { mtime = nil, data = nil }

---@return string
local function dir()
	return vim.fn.stdpath("state") .. "/cmake_menu"
end

---@return string
function M.file()
	return dir() .. "/projects.json"
end

---@return string
local function lockfile()
	return M.file() .. ".lock"
end

---@return table
local function empty_data()
	return { version = 1, projects = {} }
end

--- Modification time of `path` as a comparable number, or nil if absent.
---@param path string
---@return number?
local function mtime_of(path)
	local st = uv.fs_stat(path)
	return st and (st.mtime.sec * 1000000000 + st.mtime.nsec) or nil
end

--- The whole store. Re-parses only when the file's mtime has moved since the
--- last call (or when `force`), so this is cheap to call at every point that
--- needs current data. A missing or unparseable file reads as empty.
---@param force boolean? re-parse even if the mtime is unchanged
---@return table data
function M.read(force)
	local path = M.file()
	local mt = mtime_of(path)
	if not force and cache.data and cache.mtime == mt then
		return cache.data
	end

	local data = empty_data()
	if mt then
		local ok, lines = pcall(vim.fn.readfile, path)
		if ok then
			local ok2, decoded = pcall(vim.json.decode, table.concat(lines, "\n"))
			if ok2 and type(decoded) == "table" and type(decoded.projects) == "table" then
				data = decoded
			else
				vim.notify("cmake_menu: failed to parse " .. path, vim.log.levels.ERROR)
			end
		end
	end

	cache.data, cache.mtime = data, mt
	return data
end

--- Take the writer lock, or return false if it can't be had in time.
---@return boolean
local function acquire()
	local path = lockfile()
	local waited = 0
	while true do
		local fd = uv.fs_open(path, "wx", 420) -- O_CREAT|O_EXCL, 0644
		if fd then
			uv.fs_close(fd)
			return true
		end
		local st = uv.fs_stat(path)
		if st and (os.time() - st.mtime.sec) * 1000 > LOCK_STALE_MS then
			uv.fs_unlink(path) -- left behind by a crashed instance
		end
		if waited >= LOCK_TIMEOUT_MS then
			return false
		end
		uv.sleep(LOCK_RETRY_MS)
		waited = waited + LOCK_RETRY_MS
	end
end

local function release()
	uv.fs_unlink(lockfile())
end

--- Run `mutate(data)` against the current on-disk state and write the result
--- back, all under the writer lock. Re-reads inside the lock (force) so a
--- change another instance made between our last read and now isn't lost.
---@param mutate fun(data: table)
---@return boolean ok
local function write_locked(mutate)
	vim.fn.mkdir(dir(), "p")
	if not acquire() then
		vim.notify("cmake_menu: timed out waiting for " .. lockfile(), vim.log.levels.ERROR)
		return false
	end

	local ok, err = pcall(function()
		local data = M.read(true)
		mutate(data)
		-- an empty lua table encodes as [], not {} - keep `projects` an object
		-- so the file stays valid against its own shape when the last project
		-- is removed
		if next(data.projects or {}) == nil then
			data.projects = vim.empty_dict()
		end
		local tmp = M.file() .. ".tmp"
		vim.fn.writefile({ vim.json.encode(data) }, tmp)
		assert(uv.fs_rename(tmp, M.file()), "rename failed")
		cache.data, cache.mtime = data, mtime_of(M.file())
	end)

	release()

	if not ok then
		vim.notify("cmake_menu: failed to write " .. M.file() .. ": " .. tostring(err), vim.log.levels.ERROR)
	end
	return ok
end

--- Every tracked root, sorted.
---@return string[]
function M.roots()
	local out = {}
	for root in pairs(M.read().projects or {}) do
		out[#out + 1] = root
	end
	table.sort(out)
	return out
end

--- `root`'s saved entry, or nil if it isn't tracked.
---@param root string
---@return table?
function M.get(root)
	return (M.read().projects or {})[root]
end

---@param root string
---@return boolean
function M.tracked(root)
	return M.get(root) ~= nil
end

--- Save `entry` as `root`'s config, creating the store if needed.
---@param root string
---@param entry table
---@return boolean ok
function M.set(root, entry)
	return write_locked(function(data)
		data.projects = data.projects or {}
		data.projects[root] = entry
	end)
end

--- Stop tracking `root`.
---@param root string
---@return boolean ok
function M.remove(root)
	return write_locked(function(data)
		if data.projects then
			data.projects[root] = nil
		end
	end)
end

return M
