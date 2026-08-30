-- clangd client lifecycle, independent of any UI.
--
-- One real client per project root, via vim.lsp.start() (not the static
-- vim.lsp.enable path). vim.lsp.start's default reuse_client predicate only
-- compares client.name and client.config.root_dir - not bufnr, not cmd - so
-- calling M.start() unconditionally from every call site already gives "one
-- client per root, buffers just attach": nvim's own client registry does the
-- root->client dedup, no bookkeeping needed here.
--
-- Not autostarted: starting is a deliberate action from cmake_menu (the
-- "start lsp" row in tab_project, after the user has confirmed the project's
-- build dir), not a FileType autocmd - a not-yet-configured build dir makes
-- clangd fail to find its compile database, so starting eagerly just floods
-- the buffer with bogus errors. cmake_menu.setup() owns the FileType
-- c/cpp/objc/objcpp/cuda autocmd that offers the menu instead (see its
-- header). Root detection lives in cpp_project.find_root - this module only
-- starts/attaches clients, given a root someone else resolved.
--
-- TODO(next): when a session's root override changes for a buffer already
-- attached to a client at the old root, nvim won't retarget that client in
-- place - reuse_client only runs at start() time. That needs an explicit
-- stop-old/reattach-buffers path (old lua/cpp.lua's restart_clangd did this
-- for same-root restarts; the override case additionally needs the new
-- root_dir), to be wired from cmake_menu once its root-picker is real.

local M = {}

M.FILETYPES = { "c", "cpp", "objc", "objcpp", "cuda" }

M.CMD = {
	"clangd",
	"--background-index",
	"--clang-tidy",
	"--header-insertion=never",
	"--completion-style=detailed",
	"--offset-encoding=utf-8",
	"-j=16",
	"--pch-storage=memory",
}

--- Starts a clangd client rooted at `root` and attaches `bufnr` to it, or -
--- via vim.lsp.start's (name, root_dir) reuse - attaches `bufnr` to the
--- already-running client for that root. `compile_commands_dir` is passed
--- through as `--compile-commands-dir` rather than left to clangd's own
--- upward search from root_dir: a build dir doesn't have to be a child of the
--- project root (a manually-typed one can be anywhere), so the search isn't
--- reliable enough to lean on. cmd_cwd is pinned to `root` too, since without
--- it clangd would inherit nvim's own cwd - not necessarily this project's
--- root when several are open, or nvim was launched from somewhere else
--- entirely.
---@param bufnr integer
---@param root string
---@param compile_commands_dir string
function M.start(bufnr, root, compile_commands_dir)
	-- M.CMD[1] is the "clangd" argv[0]; the rest (M.CMD[2..]) are flags, so the
	-- compile-commands-dir flag slots in right after it rather than at the end
	-- (order doesn't matter to clangd, but this keeps argv[0] recognizable).
	local cmd = { M.CMD[1], "--compile-commands-dir=" .. compile_commands_dir }
	vim.list_extend(cmd, M.CMD, 2)
	vim.lsp.start({
		name = "clangd",
		cmd = cmd,
		cmd_cwd = root,
		root_dir = root,
		filetypes = M.FILETYPES,
		capabilities = { offsetEncoding = { "utf-8" } },
	}, { bufnr = bufnr })
end

--- Finds the clangd client for `root`, initialized or not. Threads
--- `_uninitialized = true` through explicitly: vim.lsp.get_clients() filters
--- out not-yet-initialized clients *by default*, which is what made
--- M.running() (below) read as "stopped" for the whole handshake window right
--- after M.start() - the client object exists immediately, but the LSP
--- initialize response hasn't arrived yet. M.status() below is what actually
--- wants to see it during that window.
---@param root string?
---@return vim.lsp.Client?
local function find(root)
	if not root then return nil end
	for _, c in ipairs(vim.lsp.get_clients({ name = "clangd", _uninitialized = true })) do
		if c.config.root_dir == root then
			return c
		end
	end
end

--- Stops the clangd client for `root`, if any - initialized or still starting
--- up, so this doubles as "cancel" for a client stuck mid-handshake. The
--- counterpart to M.start()'s reuse: cmake_menu's lsp row toggles start/stop
--- rather than offering a separate restart, so this is the only other
--- lifecycle action it needs.
---@param root string?
function M.stop(root)
	local c = find(root)
	if c then
		c:stop()
	end
end

--- `root`'s clangd lifecycle state, for cmake_menu's lsp row:
---   "stopped"  - no client; the row offers "start lsp"
---   "starting" - client exists but hasn't finished the initialize handshake;
---                the row shows that and offers to cancel (M.stop)
---   "running"  - initialized; the row offers "stop lsp"
--- Split out from a plain running()/not check because vim.lsp.start() doesn't
--- block - the row needs an answer to show *immediately* after the action
--- that started it, well before "running" would turn true.
---@param root string?
---@return "stopped"|"starting"|"running"
function M.status(root)
	local c = find(root)
	if not c then return "stopped" end
	return c.initialized and "running" or "starting"
end

--- Whether an *initialized* clangd client exists for `root` - i.e. whether
--- M.start() would reuse a fully-up client rather than spawn one. Shorthand
--- for M.status(root) == "running"; see that for the "starting" state this
--- deliberately doesn't distinguish from "stopped".
---@param root string?
---@return boolean
function M.running(root)
	return M.status(root) == "running"
end

return M
