return {
	"numToStr/Comment.nvim",
	config = function()
		-- Setup Comment.nvim with default options but disable default keymaps
		require("Comment").setup({
			mappings = {
				basic = false,
				extra = false,
			},
		})
		
		-- NORMAL mode: Toggle comment on current line
		vim.keymap.set("n", "<C-/>", function()
			require("Comment.api").toggle.linewise.current()
		end, { noremap = true, silent = true, desc = "Toggle comment line" })
		
		-- VISUAL mode: Toggle comment on selected lines
		vim.keymap.set("x", "<C-/>", function()
			local esc = vim.api.nvim_replace_termcodes("<ESC>", true, false, true)
			vim.api.nvim_feedkeys(esc, "nx", false)
			require("Comment.api").toggle.linewise(vim.fn.visualmode())
		end, { noremap = true, silent = true, desc = "Toggle comment selection" })
		
		-- INSERT mode: Toggle comment on current line
		vim.keymap.set("i", "<C-/>", function()
			require("Comment.api").toggle.linewise.current()
		end, { noremap = true, silent = true, desc = "Toggle comment line" })
	end,
}
