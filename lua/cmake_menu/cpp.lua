-- Single source of truth for "what is the current C/C++ project root" and
-- everything downstream of that answer: neovim-tasks (cmake) and clangd.
--
-- neovim-tasks has no per-call root parameter - every function it exposes
-- reads `vim.loop.cwd()` (via ProjectConfig.new()) and expands the `{cwd}`
-- token in build_dir. So instead of fighting that, we make the *window's*
-- cwd track whichever C/C++ project the buffer in it belongs to (`:lcd`,
-- window-local, never global `:cd`), which lets multiple projects stay open
-- in different windows/tabs of one nvim instance without clobbering each
-- other. clangd doesn't have this limitation - it gets one real client per
-- detected root via vim.lsp.start(), so that side is exact rather than
-- cwd-tracking.
--
-- The automatic side (lcd, clangd client) is gated on filetype: buffers that
-- aren't c/cpp/objc/objcpp/cuda never trigger it. `:Cpp` itself is not gated -
-- it can be opened from any buffer and falls back to marker-sniffing from cwd.

local M = {}

local HL = require("cmake_menu.hl").HL

local FT = { c = true, cpp = true, objc = true, objcpp = true, cuda = true }

local function is_cpp_buf(bufnr)
	return FT[vim.bo[bufnr].filetype] == true
end

------------------------------------------------------------------------------
-- Known-projects store: a single file under stdpath("state") (not the project
-- directory - we deliberately don't want a neovim.json-style file scattered
-- across every repo), mapping root path -> cmake config. Its keys are also
-- find_root's highest-priority signal: an explicitly-remembered root always
-- wins over marker-sniffing, since CMakeLists.txt/build dirs can exist at
-- multiple nesting levels and are never fully reliable.
--
-- Entries only get written here deliberately - via ":Cpp" > "Set project
-- root", or by changing build kit/type/target through the menu. Merely
-- opening a file under an auto-detected root never registers it, so this
-- stays a curated list rather than a cache of every file you've opened.
------------------------------------------------------------------------------

local STATE_FILE = vim.fn.stdpath("state") .. "/cpp_projects.json"

local function load_known_projects()
	local ok, lines = pcall(vim.fn.readfile, STATE_FILE)
	if not ok then
		return {}
	end
	local ok2, data = pcall(vim.json.decode, table.concat(lines, "\n"))
	return ok2 and data or {}
end

local known_projects = load_known_projects()

local function save_known_projects()
	vim.fn.writefile({ vim.json.encode(known_projects) }, STATE_FILE)
end

-- Session-only root overrides: set by ":Cpp" > "project root:" <CR>, never
-- written to disk on their own. This is deliberately separate from
-- known_projects - selecting a root is a "use this for now" action, saving
-- it (<C-s> on the same line) is the separate, explicit "remember this
-- forever" action.
local session_roots = {}

-- In-memory session cache: created lazily for *any* root touched (auto-
-- detected or remembered), backing ProjectConfig.new()/:write() correctness
-- within a session. Distinct from known_projects: every root that's ever
-- open gets a session-cache entry, but only deliberately-saved ones get
-- persisted to disk.
local project_state = {}

local function get_root_config(root)
	local cfg = project_state[root]
	if not cfg then
		cfg = vim.deepcopy(known_projects[root] or require("tasks.config").default_params)
		project_state[root] = cfg
	end
	return cfg
end

--- Deliberately remembers a root's current config across restarts.
---@param root string
local function persist_root(root)
	known_projects[root] = vim.deepcopy(get_root_config(root))
	save_known_projects()
end

local function nearest_ancestor_in(path, set)
	local dir = vim.fs.dirname(path)
	while dir do
		if set[dir] then
			return dir
		end
		local parent = vim.fs.dirname(dir)
		if parent == dir then
			break
		end
		dir = parent
	end
end

--- Finds the project root for a buffer, in priority order: this session's
--- manual override, then a saved/known root, then marker-sniffing from most
--- to least reliable.
---@param bufnr integer?
---@return string?
function M.find_root(bufnr)
	bufnr = bufnr or 0
	local path = vim.api.nvim_buf_get_name(bufnr)

	return nearest_ancestor_in(path, session_roots)
		or nearest_ancestor_in(path, known_projects)
		or vim.fs.root(bufnr, { ".git" })
		or vim.fs.root(bufnr, { "CMakePresets.json" })
		or vim.fs.root(bufnr, { "build" })
end

-- Must run before neovim-tasks' per-module files (e.g. tasks/module/cmake.lua)
-- are ever `require`d, because that file captures `cmake_utils.reconfigureClangd`
-- into a local at load time (see patch_cmake_utils below) - a live table-field
-- patch after that point wouldn't be seen. Since those modules are only
-- required lazily on first real `:Task`/menu use (never during startup), and
-- this function runs during plugin setup, the ordering is safe in practice.
local function patch_project_config()
	local ProjectConfig = require("tasks.project_config")

	ProjectConfig.new = function()
		return setmetatable(get_root_config(vim.loop.cwd()), ProjectConfig)
	end

	-- get_root_config already returns the live cached table, and callers hold
	-- that same reference - mutations are already "persisted" in memory the
	-- moment they happen. We just deliberately never touch disk here.
	ProjectConfig.write = function() end
end

------------------------------------------------------------------------------
-- Window-local cwd sync, for neovim-tasks' benefit.
------------------------------------------------------------------------------

local function sync_cwd(bufnr)
	if not is_cpp_buf(bufnr) then
		return
	end
	local root = M.find_root(bufnr)
	if root and vim.fn.getcwd(0) ~= root then
		vim.cmd.lcd(root)
	end
end

------------------------------------------------------------------------------
-- clangd: one real client per root, via vim.lsp.start (not the static
-- vim.lsp.enable path), so multiple open projects get independent clients.
------------------------------------------------------------------------------

local function clangd_cmd_for(root)
	if vim.loop.cwd() ~= root then
		vim.cmd.lcd(root)
	end
	return require("tasks.cmake_utils.cmake_utils").currentClangdArgs()
end

local function start_clangd(bufnr, root)
	vim.lsp.start({
		name = "clangd",
		cmd = clangd_cmd_for(root),
		root_dir = root,
		filetypes = { "c", "cpp", "objc", "objcpp", "cuda" },
		capabilities = { offsetEncoding = { "utf-8" } },
	}, { bufnr = bufnr })
end

--- Restarts clangd for one project root only, reloading every buffer that
--- was actually attached (not just the current one) so diagnostics come back
--- everywhere, not just wherever your cursor happened to be.
---@param root string
function M.restart_clangd(root)
	local bufs_to_reload = {}
	for _, client in ipairs(vim.lsp.get_clients({ name = "clangd" })) do
		if client.root_dir == root then
			for bufnr in pairs(client.attached_buffers or {}) do
				bufs_to_reload[bufnr] = true
			end
			if not client:is_stopped() then
				client:stop()
			end
		end
	end

	vim.defer_fn(function()
		for bufnr in pairs(bufs_to_reload) do
			if vim.api.nvim_buf_is_valid(bufnr) then
				start_clangd(bufnr, root)
			end
		end
	end, 500)
end

-- Patches neovim-tasks' after-cmake-configure hook to restart clangd only for
-- the root that was just configured, instead of every clangd client alive.
local function patch_cmake_utils()
	local cmake_utils = require("tasks.cmake_utils.cmake_utils")
	cmake_utils.reconfigureClangd = function()
		M.restart_clangd(vim.loop.cwd())
	end
end

------------------------------------------------------------------------------
-- :Task wrapper: runs a task against a specific window's project root and
-- keeps focus on that window afterward, regardless of the quickfix window
-- neovim-tasks opens for command output.
------------------------------------------------------------------------------

--- @param win integer window to derive root from and return focus to
--- @param task_args string arguments after `:Task`, e.g. "start cmake build"
function M.run_task(win, task_args)
	local bufnr = vim.api.nvim_win_get_buf(win)
	local root = M.find_root(bufnr)
	if not root then
		vim.notify("cpp: no project root found for this buffer", vim.log.levels.WARN)
		return
	end

	vim.api.nvim_set_current_win(win)
	if vim.fn.getcwd(0) ~= root then
		vim.cmd.lcd(root)
	end
	vim.cmd("Task " .. task_args)

	-- neovim-tasks already does `copen` + `wincmd p` on its own, which
	-- normally lands back on `win`. This is a deterministic safety net rather
	-- than trusting Vim's "previous window" heuristic, since our root
	-- detection is pinned to a specific window, not whatever "previous" means.
	vim.defer_fn(function()
		if vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_set_current_win(win)
		end
	end, 50)
end

------------------------------------------------------------------------------
-- Menu: item specs for the :Cpp floating menu, so :Task/:Cpp params never
-- need to be typed directly. Rendering, movement, quick-launch keys and the
-- hint bar all live in lua/cmake_menu/menu.lua; this section only describes *what*
-- each entry shows and does.
------------------------------------------------------------------------------

--- "saved" (in the persisted store), "guessed" (session override or
--- marker-sniffed - anything not yet in known_projects), or nil if no root.
---@param root string?
---@return "saved"|"guessed"|nil
local function root_status(root)
	if not root then
		return nil
	end
	return known_projects[root] and "saved" or "guessed"
end

--- Home-relative root path, head-truncated so a deeply nested root can't
--- blow the menu width out.
local function display_path(root)
	local path = vim.fn.fnamemodify(root, ":~")
	if vim.fn.strdisplaywidth(path) > 38 then
		path = "…" .. vim.fn.strcharpart(path, vim.fn.strchars(path) - 37)
	end
	return path
end

--- The menu's global footer note: whether the current root is saved, guessed
--- (session/marker-only), or unset. Shown regardless of which entry is selected.
local function root_note(root)
	local status = root_status(root)
	local hl = status == "saved" and "DiagnosticOk"
		or status == "guessed" and "DiagnosticWarn"
		or "Comment"
	local text = status == "saved" and "saved"
		or status == "guessed" and "guessed, not saved"
		or "no root set"
	return { { "● ", hl }, { text, HL.Hint } }
end

--- vim.ui.select over a cmake param's choices, persisting the pick. `handle`
--- (a live menu handle, or nil if the menu already closed) refreshes the
--- menu's value column in place.
local function pick_param(root, param_name, handle, on_done)
	local ok, cmake_module = pcall(require, "tasks.module.cmake")
	if not ok then
		return
	end
	local choices = cmake_module.params[param_name]()
	vim.ui.select(choices, { prompt = param_name .. " (" .. vim.fs.basename(root) .. ")" }, function(choice)
		if not choice then
			return
		end
		get_root_config(root).cmake[param_name] = choice
		persist_root(root)
		if handle then
			handle:render()
		end
		if on_done then
			on_done()
		end
	end)
end

--- Lists every ancestor directory of `bufnr`'s path and lets the user select
--- one as the project root for this session only (see session_roots) - use
--- the menu's <C-s> on the same line to actually save it across restarts.
---@param bufnr integer
---@param origin_win integer window to re-sync (cwd + clangd) once a root is picked
local function pick_manual_root(bufnr, origin_win)
	local path = vim.api.nvim_buf_get_name(bufnr)
	local candidates = {}
	local dir = vim.fs.dirname(path)
	while dir do
		table.insert(candidates, dir)
		local parent = vim.fs.dirname(dir)
		if parent == dir then
			break
		end
		dir = parent
	end

	vim.ui.select(candidates, { prompt = "Select project root (session only, <C-s> in :Cpp to save):" }, function(choice)
		if not choice then
			return
		end
		session_roots[choice] = true

		if vim.api.nvim_win_is_valid(origin_win) then
			vim.api.nvim_set_current_win(origin_win)
			for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr, name = "clangd" })) do
				vim.lsp.buf_detach_client(bufnr, client.id)
			end
			sync_cwd(bufnr)
			start_clangd(bufnr, choice)
		end
	end)
end

--- Persists whatever root currently resolves for `bufnr` (session override,
--- if any, else the auto-detected one) to the known-projects store. The menu
--- re-renders itself after <C-s>, so the new status shows up on its own.
---@param bufnr integer
local function save_current_root(bufnr)
	local root = M.find_root(bufnr)
	if not root then
		vim.notify("cpp: no project root to save yet - select one first", vim.log.levels.WARN)
		return
	end
	persist_root(root)
	vim.notify("cpp: saved project root " .. root, vim.log.levels.INFO)
end

-- `root`/`bufnr`/`origin_win` are closed over directly (stable per menu
-- invocation). Fields that must track live state across in-place re-renders
-- (root status after <C-s>, target/kit/type after a pick) are functions;
-- static ones are plain values.
local function build_items(root, bufnr, origin_win)
	local function status_hl()
		local status = root_status(root)
		return status == "saved" and "DiagnosticOk" or status == "guessed" and "DiagnosticWarn" or "Comment"
	end

	local items = {
		{
			key = "p",
			label = "Project root",
			value = function()
				if not root then
					return { { "(none)", "Comment" } }
				end
				return { { display_path(root), HL.Value }, { " ●", status_hl() } }
			end,
			actions = {
				{ key = "<CR>", desc = "change", close = true, fn = function() pick_manual_root(bufnr, origin_win) end },
				{ key = "<C-s>", desc = "save", fn = function() save_current_root(bufnr) end },
			},
		},
	}
	if not root then
		return items
	end

	local cfg = get_root_config(root)
	vim.list_extend(items, {
		{ section = "build" },
		{
			key = "c",
			label = "Configure",
			actions = {
				{ key = "<CR>", desc = "configure", close = true, fn = function() M.run_task(origin_win, "start cmake configure") end },
			},
		},
		{
			key = "b",
			label = "Build",
			value = function()
				local target = cfg.cmake.target
				return { { target or "no target", target and "String" or "Comment" } }
			end,
			actions = {
				{
					key = "<CR>",
					desc = "build",
					close = true,
					fn = function()
						if not cfg.cmake.target then
							pick_param(root, "target", nil, function() M.run_task(origin_win, "start cmake build") end)
						else
							M.run_task(origin_win, "start cmake build")
						end
					end,
				},
				{ key = "l", desc = "pick target", fn = function(handle) pick_param(root, "target", handle) end },
			},
		},
		{
			key = "B",
			label = "Rebuild",
			value = { { "clean + build", HL.Value } },
			actions = {
				{ key = "<CR>", desc = "rebuild", close = true, fn = function() M.run_task(origin_win, "start cmake rebuild") end },
			},
		},
		{
			key = "r",
			label = "Run",
			actions = {
				{ key = "<CR>", desc = "run", close = true, fn = function() M.run_task(origin_win, "start cmake run") end },
			},
		},
		{
			key = "d",
			label = "Debug",
			actions = {
				{ key = "<CR>", desc = "debug", close = true, fn = function() M.run_task(origin_win, "start cmake debug") end },
			},
		},
		{
			key = "x",
			label = "Cancel task",
			actions = {
				{ key = "<CR>", desc = "cancel", close = true, fn = function() vim.cmd("Task cancel") end },
			},
		},
		{ section = "config" },
		{
			key = "K",
			label = "Build kit",
			value = function() return cfg.cmake.build_kit and { { cfg.cmake.build_kit, "String" } } end,
			actions = {
				{ key = "<CR>", desc = "select kit", fn = function(handle) pick_param(root, "build_kit", handle) end },
			},
		},
		{
			key = "t",
			label = "Build type",
			value = function() return cfg.cmake.build_type and { { cfg.cmake.build_type, "String" } } end,
			actions = {
				{ key = "<CR>", desc = "select type", fn = function(handle) pick_param(root, "build_type", handle) end },
			},
		},
		{ section = "tools" },
		{
			key = "R",
			label = "Restart clangd",
			actions = {
				{ key = "<CR>", desc = "restart", close = true, fn = function() M.restart_clangd(root) end },
			},
		},
		{
			key = "m",
			label = "Open ccmake",
			actions = {
				{
					key = "<CR>",
					desc = "open in build dir",
					close = true,
					fn = function()
						if vim.api.nvim_win_is_valid(origin_win) then
							vim.api.nvim_set_current_win(origin_win)
						end
						local build_dir = require("tasks.cmake_utils.cmake_utils").getBuildDirFromConfig(cfg.cmake)
						vim.cmd("botright split term://ccmake " .. vim.fn.fnameescape(tostring(build_dir)))
					end,
				},
			},
		},
	})
	return items
end

function M.open_menu()
	local origin = vim.api.nvim_get_current_win()
	local bufnr = vim.api.nvim_win_get_buf(origin)
	-- No proactive notification for a missing root anywhere else (opening a
	-- file, cwd sync, clangd startup all just silently no-op) - :Cpp is the
	-- one place that's allowed to say so, since it was invoked deliberately.
	local root = M.find_root(bufnr)

	require("cmake_menu.menu").open({
		title = " " .. (root and vim.fs.basename(root) or "no project") .. " ",
		min_width = 46,
		note = function() return root_note(root) end,
		items = build_items(root, bufnr, origin),
	})
end

------------------------------------------------------------------------------
-- Setup
------------------------------------------------------------------------------

function M.setup()
	patch_project_config()
	patch_cmake_utils()

	local group = vim.api.nvim_create_augroup("cpp_root", { clear = true })

	vim.api.nvim_create_autocmd({ "BufWinEnter", "WinEnter" }, {
		group = group,
		callback = function(args) sync_cwd(args.buf) end,
	})

	vim.api.nvim_create_autocmd("FileType", {
		group = group,
		pattern = { "c", "cpp", "objc", "objcpp", "cuda" },
		callback = function(args)
			local root = M.find_root(args.buf)
			if root then
				start_clangd(args.buf, root)
			end
		end,
	})

	require("lsp.clangd_modmap_check").setup()

	vim.api.nvim_create_user_command("Cpp", M.open_menu, { desc = "Open the C/C++ project menu" })
	vim.keymap.set("n", "<leader>cpp", M.open_menu, { desc = "Open the C/C++ project menu" })
end

return M
