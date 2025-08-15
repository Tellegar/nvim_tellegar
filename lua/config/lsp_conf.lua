-- local autocmd = vim.api.nvim_create_autocmd

-- vim.lsp.config("test", {
-- 	
-- })

-- lua
-- local cmp_lsp = require("cmp_nvim_lsp")
-- local capabilities = vim.tbl_deep_extend(
-- 	"force",
-- 	{},
-- 	vim.lsp.protocol.make_client_capabilities(),
-- 	cmp_lsp.default_capabilities()
-- )
vim.lsp.config("lua_ls", {
	-- capabilities = capabilities,
	-- reuse_client = function(client, config)
	-- 	vim.print("new client")
	-- 	vim.print(config.root_dir)
	-- 	return false
	-- end,
	settings = {
		Lua = {
			runtime = {
				version = "LuaJIT"
			},
			workspace = {
				-- library = {}
				library = vim.api.nvim_get_runtime_file("", true)
			}
		}
	},
})

-- autocmd('LspAttach', {
-- 	callback = function(e)
-- 		local buf = e.buf
-- 		local client_id = e.data.client_id
-- 		local file = e.file
-- 		vim.print("LspAttach")
-- 		-- vim.print(e)
--
-- 		if file == "" then
-- 			file = "nil"
-- 		end
--
-- 		local client = vim.lsp.get_client_by_id(client_id)
-- 		if not client then return end
-- 		vim.print("client.name: " .. client.name)
-- 		vim.print("client.root_dir: " .. tostring(client.root_dir))
-- 		vim.print("file: " .. file)
-- 	end
-- })

-- python
-- vim.lsp.config("ruff", {
-- 	capabilities = {
-- 		general = {
-- 			positionEncodings = { "utf-16" }
-- 		}
-- 	}
-- })

-- Configure ruff (linting)
-- vim.lsp.config("ruff", {
-- 	init_options = {
-- 		settings = {
-- 			-- custom ruff settings if any
-- 		},
-- 	},
-- })
