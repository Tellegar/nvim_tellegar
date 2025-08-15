return {
	-- TODO https://chatgpt.com/c/689a9b81-96fc-8331-9a9f-ac5e55eb7ba5
	--      * will need some commands to get current highlight, maybe open it in scratch window
	--      * lua vim.fn.setreg("+", vim.fn.execute("highlight"))
	{	"marko-cerovac/material.nvim",
		main = "material",
		-- lazy = false,
		-- priority = 1000,
		init = function()
			vim.g.material_style = "deep ocean"
		end,
		opts = {
			-- disable = { background = true },
			-- high_visibility = {
			-- * lighter = false, -- Enable higher contrast text for lighter style
			-- * darker = false -- Enable higher contrast text for darker style
			-- },
			custom_colors = function(colors)
				-- vim.fn.setreg("+", vim.inspect(colors)) -- copy `colors` into clipboard

				colors.editor.bg = "#040404"
				colors.backgrounds.non_current_windows = "#070707"
				colors.backgrounds.floating_windows = "#101010"

				colors.editor.selection = "#303030"
				colors.editor.highlight = "#303030"

				colors.backgrounds.bg_blend = "#FF0000"
				colors.backgrounds.sidebars = "#FFFF00"
			end
		},
		config = function(_, opts)
			require("material").setup(opts)
			vim.cmd.colorscheme("material")
			-- local get_hl = vim.api.nvim_get_hl
			local set_hl = vim.api.nvim_set_hl

			set_hl(0, "Removed", { fg = "#d7005f" }) -- gutter removed
			set_hl(0, "Added",   { fg = "#00af5f" }) -- gutter added
			set_hl(0, "Changed", { fg = "#0087d7" }) -- gutter changed

			set_hl(0, "DiffDelete", { fg = "#464b5d" }) -- delete line (using vim.opt.fillchars:get().diff)
			set_hl(0, "DiffAdd",    { bg = "#002a00" }) -- add line
			set_hl(0, "DiffChange", { bg = "#121525" }) -- change line
			set_hl(0, "DiffText",   { bg = "#1a1f34" }) -- change char

			-- set_hl(0, "DiffDelete", { bg = "#2a0000" }) -- delete line
			set_hl(0, "DiffviewDiffAddAsDelete", { bg = "#2a0000" }) -- DiffviewOpen added line (left)

			set_hl(0, "Visual", { bg = "#303030" }) -- visual selection

			set_hl(0, "Whitespace", { fg = "#262b3d" }) -- listchars
		end,
	},
	{	"nvim-lualine/lualine.nvim",
		dependencies = { "nvim-tree/nvim-web-devicons" },
		opts = {},
	},
	{	"catgoose/nvim-colorizer.lua",
		event = "VeryLazy",
		opts = {
			filetypes = { "*" },
			lazy_load = true,
			user_default_options = {
				names = false, -- "Name" codes like Blue or red.  Added from `vim.api.nvim_get_color_map()`
				RGB = false, -- #RGB hex codes
				RGBA = false, -- #RGBA hex codes
				RRGGBB = true, -- #RRGGBB hex codes
				RRGGBBAA = false, -- #RRGGBBAA hex codes
				AARRGGBB = false, -- 0xAARRGGBB hex codes
				mode = "virtualtext",
				virtualtext = " ",
				virtualtext_inline = "before",
				virtualtext_mode = "background",
			},
		},
	},
}
