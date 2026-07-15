return {
	{	"bngarren/checkmate.nvim",
		enabled = true,
		ft = "markdown", -- plugin only works on filetype=markdown
		opts = {
			files = {
				"*.md",
			},
			-- checkmate's default list_continuation binds an insert-mode <expr>
			-- <S-CR>. Its handler returns nvim_replace_termcodes("<S-CR>")
			-- (bytes 80 fc 02 0d) while the keymap leaves replace_keycodes at its
			-- true default, so the K_SPECIAL (0x80) byte gets encoded twice ->
			-- a literal <80> is inserted and the input parser is left mid-sequence
			-- (~4 <Esc> to recover). Plain <CR> encodes to 0d, so it's unaffected.
			-- Drop <S-CR> here to avoid the corruption; Shift+Enter then just
			-- falls through to a normal newline.
			list_continuation = {
				keys = {
					["<CR>"] = function()
						require("checkmate").create({
							position = "below",
							indent = false,
						})
					end,
				},
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
