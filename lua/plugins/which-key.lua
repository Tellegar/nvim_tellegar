return {
	"folke/which-key.nvim",
	event = "VeryLazy",
	opts = {
		filter = function(mapping)
			return mapping.desc and mapping.desc ~= ""
		end,
		keys = {
			scroll_down = "<C-j>",
			scroll_up = "<C-k>",
		},
	},
	keys = require("config.mappings").plugin_keymap.which_key,
}
