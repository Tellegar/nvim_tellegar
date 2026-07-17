local o = vim.opt
local g = vim.g
local autocmd = vim.api.nvim_create_autocmd

----------------------------------------------------------------------------------------------------

o.listchars = 'tab:──╴,space:⋅,trail:~,extends:>,precedes:<'
o.list = true

-- indentdation
o.tabstop = 4
o.shiftwidth = 0
o.expandtab = false

o.cindent = false

-- line numbers
o.number = true

-- search behaviour
o.ignorecase = true
o.smartcase = true

-- diff
o.fillchars:append({ diff = "╱" }) -- ╱╲╳ -- ██

-- folding
o.foldmethod = "expr"
o.foldexpr = "v:lua.vim.treesitter.foldexpr()"
o.foldlevelstart = 99

-- do not continue comments (e.g. in normal mode pressing o/O won't insert comment)
local grp = vim.api.nvim_create_augroup("no_auto_comment", { clear = true })
autocmd({ "FileType" }, {
	group = grp,
	pattern = "*",
	callback = function()
		vim.opt_local.formatoptions:remove({ "o" })
	end,
})

autocmd("TextYankPost", {
	desc = "Highlight when yanking text",
	group = vim.api.nvim_create_augroup("highlight-yank", { clear = true }),
	callback = function()
		vim.hl.on_yank()
	end
})

g.python_recommended_style = 0
