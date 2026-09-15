require("config.mappings").plugin_keymap.ranger()

-- ranger in :terminal is far too slow on Windows (MSYS2 python behind ConPTY),
-- so :Ranger is the in-nvim look-alike there instead
local is_windows = vim.fn.has("win32") == 1
if is_windows then
	require("ranger_lite").setup{ command = "Ranger", replace_netrw = true }
end

return {
	{	"Tellegar/ranger.nvim",
		-- dir = "~/projects/ranger_min.nvim",
		name = "ranger.nvim",
		cond = not is_windows,
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
