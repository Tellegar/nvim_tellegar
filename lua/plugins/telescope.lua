
return {
	"nvim-telescope/telescope.nvim",
	dependencies = { 'nvim-lua/plenary.nvim' },
	opts = {},
	init = function()
		require("config.mappings").plugin_keymap.telescope()
	end
}
