return {
	{	"nvim-treesitter/nvim-treesitter",
		enabled = true,
		branch = "main",
		lazy = false,
		build = ":TSUpdate",
		config = function()
			-- `main` is a full rewrite: no more `nvim-treesitter.configs`,
			-- `ensure_installed`/`auto_install`/`highlight`/`indent`/
			-- `incremental_selection` options. Highlighting, indent, and
			-- lazy parser install are now our job, wired up by hand below.
			-- See https://github.com/nvim-treesitter/nvim-treesitter (main
			-- branch README, "Setup"/"Supported features" sections).
			require("nvim-treesitter").setup{}

			local parsers = require("nvim-treesitter.parsers")
			local max_filesize = 100 * 1024 -- 100 KB

			vim.api.nvim_create_autocmd("FileType", {
				group = vim.api.nvim_create_augroup("user_treesitter", { clear = true }),
				callback = function(ev)
					local lang = vim.treesitter.language.get_lang(ev.match) or ev.match
					if not parsers[lang] then
						return
					end

					if not vim.list_contains(require("nvim-treesitter").get_installed(), lang) then
						require("nvim-treesitter").install(lang):wait(120000)
					end

					local ok, stats = pcall(vim.uv.fs_stat, vim.api.nvim_buf_get_name(ev.buf))
					if ok and stats and stats.size > max_filesize then
						return
					end

					vim.treesitter.start(ev.buf, lang)
					vim.bo[ev.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
				end,
			})
		end,
	},
	{	"nvim-treesitter/nvim-treesitter-context",
		config = function()
			require"treesitter-context".setup{
				enable = true, -- Enable this plugin (Can be enabled/disabled later via commands)
				multiwindow = false, -- Enable multiwindow support.
				max_lines = 0, -- How many lines the window should span. Values <= 0 mean no limit.
				min_window_height = 0, -- Minimum editor window height to enable context. Values <= 0 mean no limit.
				line_numbers = true,
				multiline_threshold = 20, -- Maximum number of lines to show for a single context
				trim_scope = "outer", -- Which context lines to discard if `max_lines` is exceeded. Choices: "inner", "outer"
				mode = "cursor",  -- Line used to calculate context. Choices: "cursor", "topline"
				-- Separator between context and content. Should be a single character string, like "-".
				-- When separator is set, the context will only show up when there are at least 2 lines above cursorline.
				separator = nil,
				zindex = 20, -- The Z-index of the context window
				on_attach = nil, -- (fun(buf: integer): boolean) return false to disable attaching
			}
		end,
	},
	{	dir = "~/projects/neovim/namespace-hint.nvim",
		name = "namespace-hint",
		ft = "cpp",
		opts = {}
		-- config = function()
		-- 	require("namespace-hint").setup()
		-- end,
	},
}
