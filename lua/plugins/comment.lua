return {
	"numToStr/Comment.nvim",
	opts = {
		padding = false,
		mappings = {
			basic = false,
			extra = false,
		},
	},
	init = function()
		require("config.mappings").plugin_keymap.comment()
	end
}
