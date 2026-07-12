-- -- lua/lsp/min.lua  (or anywhere you load early)
--
-- -- Define the default config for a server
-- vim.lsp.config('lua_ls', {
--   cmd = { 'lua-language-server' },              -- Arch package: lua-language-server
--   filetypes = { 'lua' },
--   root_markers = { '.luarc.json', '.luarc.jsonc', '.git' },
--   settings = { Lua = { runtime = { version = 'LuaJIT' } } },
-- })
--
-- -- Auto-start it when a matching buffer opens
-- vim.lsp.enable('lua_ls')
--

vim.api.nvim_create_user_command("LspInfo", function()
	vim.cmd("checkhealth vim.lsp")
end, {})

vim.api.nvim_create_user_command("LspStop", function(opts)
	local arg = opts.args

	-- Helper to stop one or many clients
	local function stop_clients(clients)
		for _, client in ipairs(clients) do
			-- for _, buf in ipairs(vim.api.nvim_list_bufs()) do
			-- 	if vim.lsp.buf_is_attached(buf, client.id) then
			-- 		vim.lsp.buf_detach_client(buf, client.id)
			-- 	end
			-- end
			vim.lsp.stop_client(client.id, true)
		end
	end

	if arg == "" then
		-- No args → ask before stopping everything
		vim.ui.input({ prompt = "Stop ALL LSP clients? [Y/n]: " }, function(input)
			if input and input:lower() == "n" then
				vim.notify(" Canceled", vim.log.levels.INFO)
			else
				stop_clients(vim.lsp.get_clients())
			end
		end)

	elseif arg == "all" then
		-- Explicit 'all' → stop without asking
		stop_clients(vim.lsp.get_clients())

	else
		-- Treat arg as client name
		local clients = vim.lsp.get_clients({ name = arg })
		if #clients == 0 then
			vim.notify("No active LSP client named " .. arg, vim.log.levels.WARN)
		else
			stop_clients(clients)
		end
	end
end, {
		nargs = "?",
		complete = function()
			local names = {}
			for _, client in ipairs(vim.lsp.get_clients()) do
				names[client.name] = true
			end
			local list = vim.tbl_keys(names)
			table.insert(list, "all")
			return list
		end,
	})

vim.api.nvim_create_user_command("LspStart", function(opts)
	local arg = opts.args
	if arg == "lua" then
		vim.lsp.start({
			name = "lua_ls",
			cmd = { "lua-language-server" },
			-- root_dir = vim.fs.root(0, { ".git", ".luarc.json", ".luarc.jsonc" })
			-- 	or vim.fs.dirname(vim.api.nvim_buf_get_name(0)),
		})
	else
		vim.notify("Unknown LSP: " .. arg, vim.log.levels.ERROR)
	end
end, {
		nargs = 1,
		complete = function()
			return { "lua" }
		end,
	}
)

-- vim.api.nvim_create_autocmd("FileType", {
-- 	pattern = "c,cpp",
-- 	callback = function()
-- 		vim.print("hello world [c,cpp]")
-- 	end
-- })
--
-- vim.api.nvim_create_autocmd("FileType", {
-- 	pattern = "python",
-- 	callback = function()
-- 		vim.print("hello world [python]")
-- 	end
-- })
--
-- vim.api.nvim_create_autocmd("FileType", {
-- 	pattern = "lua",
-- 	callback = function()
-- 		vim.print("hello world [lua]")
-- 	end
-- })
