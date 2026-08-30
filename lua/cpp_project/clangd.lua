-- clangd client lifecycle, independent of any UI.
--
-- One real client per project root, via vim.lsp.start() (not the static
-- vim.lsp.enable path). vim.lsp.start's default reuse_client predicate only
-- compares client.name and client.config.root_dir - not bufnr, not cmd - so
-- calling M.start() unconditionally from every qualifying buffer's FileType
-- event already gives "one client per root, buffers just attach": nvim's own
-- client registry does the root->client dedup, no bookkeeping needed here.
--
-- Consumers, not owners: the FileType c/cpp/objc/objcpp/cuda autocmd here is
-- the owner (see M.setup()); cmake_menu is a consumer, calling M.start when
-- the user re-picks a project root from the UI. Root detection itself lives
-- in cpp_project.find_root - this module only starts/attaches clients.
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

function M.setup()
	vim.api.nvim_create_autocmd("FileType", {
		group = vim.api.nvim_create_augroup("cpp_project_clangd", { clear = true }),
		pattern = M.FILETYPES,
		callback = function(args)
			local root = cpp_project.find_root(args.buf)
			if root then
				M.start(args.buf, root)
			end
		end,
	})
end

return M
