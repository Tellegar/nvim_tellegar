return {
	{	"neovim/nvim-lspconfig",
		dependencies = {
			{ "williamboman/mason.nvim", opts = {} },
			{ "williamboman/mason-lspconfig.nvim", opts = {} },
			-- "stevearc/conform.nvim",
			-- "hrsh7th/cmp-cmdline",
			-- "L3MON4D3/LuaSnip",
			-- "saadparwaiz1/cmp_luasnip",
			{ "j-hui/fidget.nvim", opts = {} }, -- lsp notifications?
			{ "folke/lazydev.nvim", ft = "lua", opts = {} },
		},
		config = function()
			require("lsp.conf")

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
	{	"hrsh7th/nvim-cmp",
		dependencies = {
			"hrsh7th/cmp-nvim-lsp",
			"hrsh7th/cmp-buffer",
			"hrsh7th/cmp-path",
		},
		event = { "InsertEnter" },
		-- opts = {},
		config = function()
			local cmp = require("cmp")
			local types = require("cmp.types")
			local K     = types.lsp.CompletionItemKind  -- enum table

			local function after_dot()
				local col = vim.fn.col(".") - 1
				if col < 1 then return false end
				local line = vim.api.nvim_get_current_line()
				return line:sub(col, col) == "."
			end

			cmp.setup{
				completion = { completeopt = "menu,menuone,noselect" },
				-- preselect = cmp.PreselectMode.None,
				-- snippet = { expand = function(_) end }, -- no snippets in layer 1
				mapping = cmp.mapping.preset.insert{
					["<C-Space>"] = cmp.mapping.complete(),
					["<CR>"]      = cmp.mapping.confirm({ select = false }),
					["<C-n>"]     = cmp.mapping.select_next_item(),
					["<C-p>"]     = cmp.mapping.select_prev_item(),
					["<C-e>"]     = cmp.mapping.abort(),
					-- Inspect the selected entry’s raw LSP item quickly:
					["<C-i>"]     = function()
						local e = cmp.get_selected_entry()
						if e then vim.notify(vim.inspect(e.completion_item)) end
					end,
				},
				formatting = {
					fields = { "abbr", "menu", "kind" },
					format = function(entry, item)
						local src = ({ nvim_lsp="LSP", buffer="BUF", path="PATH" })[entry.source.name] or entry.source.name
						-- entry:get_kind() returns the numeric enum; item.kind may already be a string
						local kind_num  = entry.get_kind and entry:get_kind() or nil
						local kind_name = kind_num and K[kind_num] or (type(item.kind) == "string" and item.kind) or "?"
						item.menu = string.format("[%s][%s]", src, kind_name)
						return item
					end,
				},
				sorting = {
					priority_weight = 2,
					comparators = {
						cmp.config.compare.exact,
						cmp.config.compare.score,
						cmp.config.compare.recently_used,
						cmp.config.compare.locality,
						cmp.config.compare.kind,
						cmp.config.compare.length,
						cmp.config.compare.order,
					},
				},
				-- sources = cmp.config.sources{
				-- 	{ name = "nvim_lsp" },
				-- },
				sources = cmp.config.sources(
					{
						{
							name = "nvim_lsp",
							entry_filter = function(entry)
								if not after_dot() then return true end
								local k = entry:get_kind()
								return k == K.Method or k == K.Field or k == K.Property or k == K.Function
							end,
						},
					}, {
						{ name = "path",   keyword_length = 3, max_item_count = 10 },
						{ name = "buffer", keyword_length = 4, max_item_count = 8 },
					}
				),
				-- window = {
				-- 	completion    = cmp.config.window.bordered(),
				-- 	documentation = cmp.config.window.bordered(),
				-- },
				experimental = { ghost_text = true },
			}
		end
	}
}
