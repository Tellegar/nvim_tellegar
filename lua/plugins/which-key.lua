return {
	"folke/which-key.nvim",
	event = "VeryLazy",
	opts = {
		filter = function(mapping)
			return mapping.desc and mapping.desc ~= ""
			-- return true
		end,
		keys = {
			scroll_down = "<C-j>",
			scroll_up = "<C-k>",
		},
		disable = {
			ft = { "cmake_menu" }, -- cmake_menu.float: custom TUI, no built-in keybinds apply
		},
	},
	keys = require("config.mappings").plugin_keymap.which_key,
}
