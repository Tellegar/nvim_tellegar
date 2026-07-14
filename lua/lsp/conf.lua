-- vim.lsp.config("qmlls", {
-- 	cmd = {
-- 		"qmlls",
-- 		"-E",
-- 		"-I", "/usr/lib/qt6/qml",
-- 		"-I", "/usr/lib/qt6/qml/Quickshell",
-- 	},
-- 	filetypes = { "qml" },
-- 	root_dir = function(bufnr, on_dir)
-- 		local root = vim.fs.dirname(
-- 			vim.fs.find({ ".git", "CMakeLists.txt" }, {
-- 				upward = true,
-- 				path = vim.api.nvim_buf_get_name(bufnr),
-- 			})[1]
-- 		)
-- 		on_dir(root or vim.fn.getcwd())
-- 	end,
-- })


-- clangd is started per-project-root (not via the static vim.lsp.enable
-- path) so that multiple C/C++ projects open in different windows/tabs get
-- independent clients with correct --compile-commands-dir each. See cpp.lua,
-- which also owns cwd-syncing for neovim-tasks and the :Cpp menu.
require("cpp").setup()

-- vim.lsp.config("qmlls", {
-- 	cmd = {"qmlls", "-E"}
-- })
