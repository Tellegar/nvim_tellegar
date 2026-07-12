local Path = require("plenary.path")

return {
	{	"Shatur/neovim-tasks",
		dependencies = { "nvim-lua/plenary.nvim" },
		opts = {
			default_params = {
				cmake = {
					cmake_kits_file = "/home/tellegar/.config/nvim/cmake/build_kits.json",
					-- cmake_build_types_file = vim.fn.expand("~/.config/nvim/cmake/build_types.json"),
					build_kit = "clang",

					-- build_dir = tostring(Path:new("{cwd}", "build", "{build_kit}", "{build_type}")),
					build_dir = tostring(Path:new("{cwd}", "build", "{build_kit}-{build_type}")),
					clangd_cmdline = {
						"clangd",
						"--background-index",
						"--clang-tidy",
						"--header-insertion=never",
						"--completion-style=detailed",
						"--offset-encoding=utf-8",
						-- "--experimental-modules-support",
						"-j=16",
						"--pch-storage=memory",
					},
				}
			}
		}
	},
}
