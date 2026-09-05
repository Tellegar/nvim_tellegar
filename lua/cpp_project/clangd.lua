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
-- header). There is a FileType autocmd here too, but it's the opposite of an
-- autostart: it only attaches buffers to a client that's *already* running
-- (see watch_new_buffers), and it registers only once someone has started
-- one. Root detection lives in cpp_project.find_root - this module only
-- starts/attaches clients, given a root someone else resolved.
--
-- TODO(next): when a session's root override changes for a buffer already
-- attached to a client at the old root, nvim won't retarget that client in
-- place - reuse_client only runs at start() time. That needs an explicit
-- stop-old/reattach-buffers path (old lua/cpp.lua's restart_clangd did this
-- for same-root restarts; the override case additionally needs the new
-- root_dir), to be wired from cmake_menu once its root-picker is real.

local cpp_project = require("cpp_project")

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

--- Whether `bufnr` is a source buffer that belongs to `root` - the test both
--- attach paths below share. "Belongs" is `cpp_project.find_root` agreeing on
--- the root, not a mere path-prefix check: a nested project inside another
--- project's tree resolves to its own root, and attaching those files to the
--- outer client would hand clangd a compile database that doesn't describe
--- them. Equality against the client's root is therefore the whole point -
--- descendants of a root that resolve elsewhere are deliberately excluded, as
--- are buffers that resolve to no root at all (unnamed ones included, which
--- find_root returns nil for).
---@param bufnr integer
---@param root string
---@return boolean
local function belongs_to(bufnr, root)
	if not (vim.api.nvim_buf_is_loaded(bufnr) and vim.tbl_contains(M.FILETYPES, vim.bo[bufnr].filetype)) then
		return false
	end
	return cpp_project.find_root(bufnr) == root
end

--- Attaches every already-open source buffer belonging to `root` to the
--- just-started client. vim.lsp.start() only attaches the one buffer it's
--- given, and there's no autostart autocmd to catch the rest (see the
--- header), so without this a project's other open files stay LSP-less until
--- each is re-entered - the "why does it only attach to the buffer I started
--- it from" case. The starting buffer is in this set too when it belongs to
--- `root`; attaching twice is a no-op.
---@param client_id integer
---@param root string
local function attach_open_buffers(client_id, root)
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if belongs_to(buf, root) then
			vim.lsp.buf_attach_client(buf, client_id)
		end
	end
end

--- The forward-looking half of attach_open_buffers: a source file opened
--- *after* a client is up attaches to it too - to the client whose root is
--- the file's own root, and to no other (see belongs_to). Not an autostart:
--- it only ever attaches to a client someone already started deliberately, so
--- a project whose lsp row was never pressed stays untouched. Registered on
--- first start() (clear=true makes re-registering idempotent) and left in
--- place across stops, since it does nothing while no client matches.
local function watch_new_buffers()
	local group = vim.api.nvim_create_augroup("cpp_project.clangd", { clear = true })
	vim.api.nvim_create_autocmd("FileType", {
		group = group,
		pattern = M.FILETYPES,
		callback = function(args)
			for _, c in ipairs(vim.lsp.get_clients({ name = "clangd" })) do
				if c.config.root_dir and belongs_to(args.buf, c.config.root_dir) then
					vim.lsp.buf_attach_client(args.buf, c.id)
				end
			end
		end,
	})
end

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
	local id = vim.lsp.start({
		name = "clangd",
		cmd = cmd,
		cmd_cwd = root,
		root_dir = root,
		filetypes = M.FILETYPES,
		capabilities = { offsetEncoding = { "utf-8" } },
	}, { bufnr = bufnr })
	if not id then
		return
	end
	attach_open_buffers(id, root)
	watch_new_buffers()
	return id
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

--- The buffers currently attached to `root`'s client, in bufnr order. Reads
--- the client's own `attached_buffers` rather than a list kept here: buffers
--- leave a client on their own (wipeout detaches them), so any local copy
--- would go stale without anything telling us. Unloaded buffers are dropped -
--- a bufnr the client still lists but that no longer has a window's worth of
--- content behind it isn't something the menu can meaningfully offer to open.
---@param root string?
---@return integer[]
function M.buffers(root)
	local c = find(root)
	if not c then
		return {}
	end
	local bufs = {}
	for buf in pairs(c.attached_buffers) do
		if vim.api.nvim_buf_is_loaded(buf) then
			bufs[#bufs + 1] = buf
		end
	end
	table.sort(bufs)
	return bufs
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
