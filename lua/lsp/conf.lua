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


require("lsp.lua_ls-shrink_unnecessary").setup()
require("cpp_project.clangd").setup()

-- neocmakelsp (mason-installed, auto-enabled by mason-lspconfig) ships its own
-- lint: command case plus "[C0301] Line too long". The server has no per-rule
-- switch (only lint.enable wholesale, or .neocmakelint.toml's line_max_words),
-- so C0301 is dropped here instead, client-side, leaving the rest of the lint on.
vim.lsp.config("neocmakelsp", {
	handlers = {
		["textDocument/publishDiagnostics"] = function(err, result, ctx, config)
			if result and result.diagnostics then
				result.diagnostics = vim.tbl_filter(function(d)
					return d.code ~= "C0301"
						and not (d.message or ""):find("[C0301]", 1, true)
				end, result.diagnostics)
			end
			return vim.lsp.handlers["textDocument/publishDiagnostics"](err, result, ctx, config)
		end,
	},
})

-- vim.lsp.config("qmlls", {
-- 	cmd = {"qmlls", "-E"}
-- })
