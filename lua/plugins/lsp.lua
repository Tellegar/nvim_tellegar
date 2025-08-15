return {
	{	"neovim/nvim-lspconfig",
		dependencies = {
			"williamboman/mason.nvim",
			"williamboman/mason-lspconfig.nvim",
			-- "stevearc/conform.nvim",
			-- "hrsh7th/cmp-nvim-lsp",
			-- "hrsh7th/cmp-buffer",
			-- "hrsh7th/cmp-path",
			-- "hrsh7th/cmp-cmdline",
			-- "L3MON4D3/LuaSnip",
			-- "saadparwaiz1/cmp_luasnip",
			{ "j-hui/fidget.nvim", opts = {} }, -- lsp notifications?
			-- { "folke/lazydev.nvim", ft = "lua", opts = {} },
		},
		config = function()
			require("mason").setup()
			require("mason-lspconfig").setup()
			require("config.lsp_conf")

			-- require("conform").setup{
			-- 	formatters_by_ft = {
			-- 		lua = { "stylua" },
			-- 		python = { "black" },
			-- 		sh = { "shfmt" },
			-- 	}
			-- }

			-- local cmp = require("cmp")
			-- cmp.setup{
			-- 	snippet = {
			-- 		expand = function(args)
			-- 			require("luasnip").lsp_expand(args.body)
			-- 		end
			-- 	},
			-- 	mapping = cmp.mapping.preset.insert{
			-- 		["<S-Tab>"] = cmp.mapping.select_prev_item(),
			-- 		["<Tab>"] = cmp.mapping.select_next_item(),
			-- 		["<CR>"] = cmp.mapping.confirm({ select = true }),
			-- 	},
			-- 	sources = cmp.config.sources{ -- idk what does this change
			-- 		{ name = "nvim_lsp" },
			-- 		{ name = "luasnnip" },
			-- 		{ name = "buffer" },
			-- 		{ name = "path" },
			-- 	}
			-- }

			vim.diagnostic.config{
				-- update_in_insert = true,
				float = {
					-- focusable = false,
					-- style = "minimal",
					-- border = "rounded",
					source = true,
					-- header = "",
					-- prefix = "",
				}
			}
		end
	},
	-- {	"nvimtools/none-ls.nvim",
	-- 	opts = function(_, opts)
	-- 		local null_ls = require("null-ls")
	-- 		opts.root_dir = opts.root_dir
	-- 			or require("null-ls.utils").root_pattern(".null-ls-root", ".neoconf.json", "Makefile", ".git")
	-- 		opts.sources = vim.list_extend(opts.sources or {}, {
	-- 			null_ls.builtins.formatting.stylua,
	-- 			null_ls.builtins.completion.spell,
	-- 			null_ls.builtins.formatting.black
	-- 		})
	-- 	end,
	-- }
	{	"hrsh7th/nvim-cmp",
		dependencies = {
			"hrsh7th/cmp-nvim-lsp",
		},
		config = function()
			local cmp = require("cmp")
			vim.o.completeopt = "menu,menuone,noselect"
			cmp.setup{
				preselect = cmp.PreselectMode.None,
				snippet = { expand = function(_) end }, -- no snippets in layer 1
				mapping = cmp.mapping.preset.insert{
					["<C-Space>"] = cmp.mapping.complete(),
					["<C-e>"]     = cmp.mapping.abort(),
					["<CR>"]      = cmp.mapping.confirm({ select = true }),
					["<Tab>"]     = cmp.mapping.select_next_item(),
					["<S-Tab>"]   = cmp.mapping.select_prev_item(),
				},
				sources = cmp.config.sources{
					{ name = "nvim_lsp" },
				}
			}
		end
	}
}
