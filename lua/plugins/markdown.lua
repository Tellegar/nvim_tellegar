return {
	{	"bngarren/checkmate.nvim",
		enabled = true,
		ft = "markdown", -- plugin only works on filetype=markdown
		opts = {
			files = {
				"*.md",
			},
			-- metadata = {
			-- 	url = {
			-- 		key = "<leader>Tmu"
			-- 	},
			-- },
		}
	},
	{	"MeanderingProgrammer/render-markdown.nvim",
		enabled = true,
		-- dependencies = { "nvim-treesitter/nvim-treesitter", "nvim-mini/mini.nvim" }, -- if you use the mini.nvim suite
		-- dependencies = { "nvim-treesitter/nvim-treesitter", "nvim-mini/mini.icons" }, -- if you use standalone mini plugins
		dependencies = { "nvim-treesitter/nvim-treesitter", "nvim-tree/nvim-web-devicons" }, -- if you prefer nvim-web-devicons
		---@module "render-markdown"
		---@type render.md.UserConfig
		opts = {
			bullet = {
				-- icons = { '●', '○', '◆', '◇' },
				icons = { '◇' },
			}
		},
	}
}
