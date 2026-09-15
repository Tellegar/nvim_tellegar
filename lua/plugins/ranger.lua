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
		-- local checkout; skip on machines that don't have it
		cond = vim.uv.fs_stat(vim.fn.expand("~/projects/neovim/ranger_min.nvim")) ~= nil,
		opts = {}
	},
}
