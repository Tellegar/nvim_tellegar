local map = vim.keymap.set

----------------------------------------------------------------------------------------------

map("n", "<C-Space>", function()
	vim.print("hello world")
end)

map("n", "<leader><leader>x", "<cmd>source %<CR>", { desc = "source current file" })
map("n", "<leader>x", ":.lua<CR>", { desc = "source current line" })
map("v", "<leader>x", ":lua<CR>",  { desc = "source current selection" })

-- map({"n", "x"}, "J", "jzz")
-- map({"n", "x"}, "K", "kzz")
-- map("n", "<C-j>", "<C-d>zz")
-- map("n", "<C-k>", "<C-u>zz")
map("n", "<C-d>", "<Nop>")
map("n", "<C-u>", "<Nop>")

map("n", "L", ":set list!<CR>",             	{ desc = "toggle whitespace visibility" })

map("n", "<Esc>", "<cmd>noh<CR>",           	{ desc = "clear highlights" })

-- map("n", "<C-s>", "<cmd>w<CR>",             	{ desc = "save file" })
map("n", "<C-y>", "<cmd>%y<CR>",            	{ desc = "copy whole file (vim clipboard)" })
map("n", "<C-c>", "<cmd>%y+<CR>",           	{ desc = "copy whole file (system clipboard)" })
map("v", "+", '"+y',                        	{ desc = "copy selection (system clipboard)" })

map("n", "<C-a>", "maGVgg",                 	{ desc = "select all lines" })
-- map("n", "<C-a>", [[:<C-u>normal! m`ggVG``<CR>]], { desc = "select all lines" })

map("n", "<leader>gdt", "<cmd>Gitsigns diffthis<CR>",	{ desc = "git diffthis" })

map("t", "<S-Esc>", [[<C-\><C-n>]], { noremap = true })

-- map("n", "<C-h>", "<C-w>h")
-- map("n", "<C-l>", "<C-w>l")
-- map("n", "<C-j>", "<C-w>j")
-- map("n", "<C-k>", "<C-w>k")

-- annoying missclick of :q
map("n", "q:", "<Nop>")
map("n", "q?", "<Nop>")
map("n", "q/", "<Nop>")

local plugin_keymap = {}

-- comment
plugin_keymap.comment = function()
	local comment_api = require("Comment.api")
	local esc = vim.api.nvim_replace_termcodes("<ESC>", true, false, true)
	map("n", "<C-/>", function()
		comment_api.toggle.linewise.current()
	end, { desc = "Toggle comment line" })
	map("x", "<C-/>", function()
		vim.api.nvim_feedkeys(esc, "nx", false)
		local mode = vim.fn.visualmode()
		if mode == "v" then
			comment_api.toggle.blockwise(mode)
		else
			comment_api.toggle.linewise(mode)
			-- TODO "^V" selection to work as multiple "v" selections
		end
	end, { desc = "Toggle comment selection" })
	map("i", "<C-/>", function()
		comment_api.toggle.linewise.current()
	end, { desc = "Toggle comment line" })
end

-- TODO git

-- lsp
map("n", "J", vim.diagnostic.open_float, { desc = "vim.diagnostic.open_float" })
map("n", "K", vim.lsp.buf.hover,         { desc = "vim.lsp.buf.hover" })

-- goto family: capability checked at call time across all attached clients,
-- so it's not tied to whichever single client happened to fire LspAttach last.
-- Only take the fallback when it's actually supported and the primary isn't -
-- otherwise call the primary anyway, so an unsupported buffer errors with the
-- method you actually asked for instead of a confusing fallback-method error.
local function goto_with_fallback(primary_method, primary_fn, fallback_method, fallback_fn)
	return function()
		local has_primary  = #vim.lsp.get_clients({ bufnr = 0, method = primary_method })  > 0
		local has_fallback = #vim.lsp.get_clients({ bufnr = 0, method = fallback_method }) > 0
		if has_fallback and not has_primary then
			fallback_fn()
		else
			primary_fn()
		end
	end
end

local function in_split(fn)
	return function()
		vim.cmd("rightbelow vsplit")
		fn()
		vim.cmd("wincmd h")
	end
end

-- d is simpler than D: gd (declaration) answers "what is this", gD (definition) "how is it built"
local goto_declaration = goto_with_fallback("textDocument/declaration", vim.lsp.buf.declaration, "textDocument/definition",  vim.lsp.buf.definition)
local goto_definition  = goto_with_fallback("textDocument/definition",  vim.lsp.buf.definition,  "textDocument/declaration", vim.lsp.buf.declaration)

map("n", "gd",         goto_declaration,          { desc = "goto declaration (fallback: definition)" })
map("n", "<leader>gd", in_split(goto_declaration), { desc = "split and goto declaration" })
map("n", "gD",         goto_definition,           { desc = "goto definition (fallback: declaration)" })
map("n", "<leader>gD", in_split(goto_definition),  { desc = "split and goto definition" })
map("n", "gt", vim.lsp.buf.type_definition, { desc = "vim.lsp.buf.type_definition" })
map("n", "gI", vim.lsp.buf.implementation,  { desc = "vim.lsp.buf.implementation" })

map("n", "<leader>vf",  function() vim.lsp.buf.format({ async = true }) end, { desc = "vim.lsp.buf.format" })
map("n", "<leader>vds", vim.lsp.buf.document_symbol, { desc = "vim.lsp.buf.document_symbol" })
map("n", "<leader>vd",  function()
	vim.diagnostic.setqflist()
	vim.cmd.copen()
end, { desc = "diagnostics to quickfix" })

map("n", "<leader>vws", vim.lsp.buf.workspace_symbol, { desc = "vim.lsp.buf.workspace_symbol" })
map("n", "<leader>vca", vim.lsp.buf.code_action,      { desc = "vim.lsp.buf.code_action" })
map("n", "<leader>vrr", vim.lsp.buf.references,       { desc = "vim.lsp.buf.references" })
map("n", "<leader>vrn", vim.lsp.buf.rename,           { desc = "vim.lsp.buf.rename" })
map("n", "<C-k>", vim.lsp.buf.signature_help, { desc = "vim.lsp.buf.signature_help" })
map("i", "<C-k>", vim.lsp.buf.signature_help, { desc = "vim.lsp.buf.signature_help" })
map("n", "]d", function() vim.diagnostic.jump{count= 1, float=true} end, { desc = "jump to next diagnostic" })
map("n", "[d", function() vim.diagnostic.jump{count=-1, float=true} end, { desc = "jump to prev diagnostic" })

-- global + one-shot: bufstates falls back to globalstate via metatable, so this
-- covers buffers whose LSP client attaches later too - no need for a per-attach call.
vim.lsp.inlay_hint.enable()

-- ranger
plugin_keymap.ranger = function()
	map("n", "<leader>r", vim.cmd.Ranger,    	{ desc = "open ranger" })
end

-- telescope
plugin_keymap.telescope = function()
	local builtin = require("telescope.builtin")
	map("n", "<leader>ff", builtin.find_files,  	{ desc = "Telescope find files" })
	map("n", "<leader>fg", builtin.live_grep,   	{ desc = "Telescope live grep" })
	map("n", "<leader>fb", builtin.buffers,     	{ desc = "Telescope buffers" })
	map("n", "gb", builtin.buffers,             	{ desc = "Telescope buffers" })
	map("n", "<leader>fh", builtin.help_tags,   	{ desc = "Telescope help tags" })
end

-- undotree
plugin_keymap.undotree = {
	{
		"<C-u>",
		function()
			vim.cmd.UndotreeToggle()
			vim.cmd.UndotreeFocus()
		end,
		desc = "Toggle undotree"
	},
}
vim.keymap.set("n", "<C-u>", function()
	vim.cmd.UndotreeToggle()
	vim.cmd.UndotreeFocus()
end)

-- which-key
plugin_keymap.which_key = {
	{
		".",
		function()
			require("which-key").show({
				global = false,
				loop = true,
			})
		end,
		desc = "show this menu"
	},
	{
		"?",
		function()
			require("which-key").show({
				global = true,
				loop = true,
			})
		end,
		desc = "show this menu"
	},
}

return {
	plugin_keymap = plugin_keymap
}
