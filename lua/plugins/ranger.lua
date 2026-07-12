require("config.mappings").plugin_keymap.ranger()

return {
	{	"Tellegar/ranger.nvim",
		-- dir = "~/projects/ranger_min.nvim",
		name = "ranger.nvim",
		opts = {
			enable_cmds = true,
			replace_netrw = true,
		},
	},
	{
		dir = "~/projects/neovim/ranger_min.nvim",
		name = "ranger2.nvim",
		opts = {}
	},
}
