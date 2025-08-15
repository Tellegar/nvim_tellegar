local o = vim.opt
local g = vim.g
local autocmd = vim.api.nvim_create_autocmd

----------------------------------------------------------------------------------------------------

o.listchars = 'tab:──╴,space:⋅,trail:~,extends:>,precedes:<'
o.list = true

-- intendation
o.tabstop = 4
o.shiftwidth = 0
o.expandtab = false

-- line numbers
o.number = true

-- search behaviour
o.ignorecase = true
o.smartcase = true

-- diff
o.fillchars:append({ diff = "╱" }) -- ╱╲╳ -- ██

-- do not continue comments (e.g. in normal mode pressing o/O won't insert comment)
local grp = vim.api.nvim_create_augroup("no_auto_comment", { clear = true })
autocmd({ "FileType" }, {
	group = grp,
	pattern = "*",
	callback = function()
		vim.opt_local.formatoptions:remove({ "o" })
	end,
})
