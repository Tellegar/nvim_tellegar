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


require("lsp.shrink_unnecessary").setup()

-- vim.lsp.config("qmlls", {
-- 	cmd = {"qmlls", "-E"}
-- })
