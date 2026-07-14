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


vim.lsp.config("clangd", {
	cmd = require"tasks.cmake_utils.cmake_utils".currentClangdArgs(),
	filetypes = {
		"c", "h",
		"cpp", "hpp",
		"cppm",
		"cuda", "objc", "objcpp"
	},
	root_markers = {
		"CMakePresets.json",
		".clangd",
		".clang-tidy",
		".clang-format",
		"compile_commands.json",
		"compile_flags.txt",
		"configure.ac",
		".git"
	},
})
vim.lsp.enable("clangd") -- not managed by mason
require("lsp.clangd_modmap_check").setup()

-- vim.lsp.config("qmlls", {
-- 	cmd = {"qmlls", "-E"}
-- })
