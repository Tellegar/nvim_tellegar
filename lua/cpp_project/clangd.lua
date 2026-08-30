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
--- already-running client for that root.
---@param bufnr integer
---@param root string
function M.start(bufnr, root)
	vim.lsp.start({
		name = "clangd",
		cmd = M.CMD,
		root_dir = root,
		filetypes = M.FILETYPES,
		capabilities = { offsetEncoding = { "utf-8" } },
	}, { bufnr = bufnr })
end

--- Whether a clangd client is already running for `root` - i.e. whether
--- M.start() would reuse one rather than spawn one. Asks nvim's client
--- registry directly, since that (not any bookkeeping of ours) is what does
--- the root->client dedup; cmake_menu reads this for its "start lsp" vs
--- "restart lsp" label.
---@param root string?
---@return boolean
function M.running(root)
	if not root then return false end
	for _, c in ipairs(vim.lsp.get_clients({ name = "clangd" })) do
		if c.config.root_dir == root then
			return true
		end
	end
	return false
end

return M
