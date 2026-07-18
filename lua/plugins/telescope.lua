
return {
	"nvim-telescope/telescope.nvim",
	dependencies = { 'nvim-lua/plenary.nvim' },
	opts = {
		defaults = {
			-- search box on top, best match directly under it (top-down list).
			sorting_strategy = "ascending",
			layout_config = { prompt_position = "top" },
		},
	},
	init = function()
		require("config.mappings").plugin_keymap.telescope()
	end
}
