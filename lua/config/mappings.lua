local map = vim.keymap.set
local autocmd = vim.api.nvim_create_autocmd

----------------------------------------------------------------------------------------------


-- map({"n", "x"}, "J", "jzz")
-- map({"n", "x"}, "K", "kzz")
-- map("n", "<C-j>", "<C-d>zz")
-- map("n", "<C-k>", "<C-u>zz")
map("n", "<C-d>", "<Nop>")
map("n", "<C-u>", "<Nop>")

map("n", "L", ":set list!<CR>",             	{ desc = "toggle whitespace visibility" })

map("n", "<Esc>", "<cmd>noh<CR>",           	{ desc = "clear highlights" })

map("n", "<C-s>", "<cmd>w<CR>",             	{ desc = "save file" })
map("n", "<C-y>", "<cmd>%y+<CR>",           	{ desc = "copy whole file (vim clipboard)" })
map("n", "<C-c>", "<cmd>%y+<CR>",           	{ desc = "copy whole file (system clipboard)" })
map("v", "+", '"+y',                        	{ desc = "copy selection (system clipboard)" })

map("n", "<leader>gd", "<cmd>Gitsigns diffthis<CR>",	{ desc = "git diffthis" })

-- map("n", "<C-h>", "<C-w>h")
-- map("n", "<C-l>", "<C-w>l")
-- map("n", "<C-j>", "<C-w>j")
-- map("n", "<C-k>", "<C-w>k")

-- map("n", "q:", "<Nop>")
-- map("n", "q?", "<Nop>")
-- map("n", "q/", "<Nop>")

local plugin_keymap = {}

-- ranger
map("n", "<leader>r", vim.cmd.Ranger,    	{ desc = "open ranger" })

-- telescope
plugin_keymap.telescope = function()
	local builtin = require("telescope.builtin")
	map("n", "<leader>ff", builtin.find_files,  	{ desc = "Telescope find files" })
	map("n", "<leader>fg", builtin.live_grep,   	{ desc = "Telescope live grep" })
	map("n", "<leader>fb", builtin.buffers,     	{ desc = "Telescope buffers" })
	map("n", "gb", builtin.buffers,             	{ desc = "Telescope buffers" })
	map("n", "<leader>fh", builtin.help_tags,   	{ desc = "Telescope help tags" })
end

-- comment
map("n", "<C-/>", function()
	require("Comment.api").toggle.linewise.current()
end, { desc = "Toggle comment line" })
map("x", "<C-/>", function()
	local esc = vim.api.nvim_replace_termcodes("<ESC>", true, false, true)
	vim.api.nvim_feedkeys(esc, "nx", false)
	require("Comment.api").toggle.linewise(vim.fn.visualmode())
end, { desc = "Toggle comment selection" })
map("i", "<C-/>", function()
	require("Comment.api").toggle.linewise.current()
end, { desc = "Toggle comment line" })

-- lsp
_G.e = {}
autocmd('LspAttach', {
	callback = function(e)
		local client = vim.lsp.get_client_by_id(e.data.client_id)
		table.insert(_G.e, e)
		-- local client = vim.lsp.get_client_by_id(e.data.client_id)
		-- vim.print("lsp attached (" .. client.config.name .. ")")

		local function lsp_map(mode, key, func, desc)
			map(mode, key, func, { buffer = e.buf, desc = desc})
		end

		-- TODO i guess gd should always try declaration, as there might be many lsps connected at once to single buffer
		if client.server_capabilities.declarationProvider then
			lsp_map("n", "gd", vim.lsp.buf.declaration)
		else
			lsp_map("n", "gd", vim.lsp.buf.definition)
		end

		lsp_map("n", "gD", vim.lsp.buf.definition,                "vim.lsp.buf.definition")
		lsp_map("n", "J", vim.lsp.buf.hover,                      "vim.lsp.buf.hover")
		lsp_map("n", "K", vim.diagnostic.open_float,              "vim.diagnostic.open_float")
		lsp_map("n", "<leader>vws", vim.lsp.buf.workspace_symbol, "vim.lsp.buf.workspace_symbol")
		lsp_map("n", "<leader>vca", vim.lsp.buf.code_action,      "vim.lsp.buf.code_action")
		lsp_map("n", "<leader>vrr", vim.lsp.buf.references,       "vim.lsp.buf.references")
		lsp_map("n", "<leader>vrn", vim.lsp.buf.rename,           "vim.lsp.buf.rename")
		lsp_map("i", "<C-k>", vim.lsp.buf.signature_help,         "vim.lsp.buf.signature_help")
		-- lsp_map("n", "]d", vim.diagnostic.goto_next)
		-- lsp_map("n", "[d", vim.diagnostic.goto_prev)
		lsp_map("n", "]d", function() vim.diagnostic.jump{count= 1, float=true} end, "jump to next diagnostic")
		lsp_map("n", "[d", function() vim.diagnostic.jump{count=-1, float=true} end, "jump to prev diagnostic")
	end
})

return {
	plugin_keymap = plugin_keymap
}
