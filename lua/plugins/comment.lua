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
	end,
}
