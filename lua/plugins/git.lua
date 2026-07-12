return {
	{	"lewis6991/gitsigns.nvim",
		event = { "BufReadPre", "BufNewFile" },
		opts = {
			attach_to_untracked = false,
			on_attach = function(buf)
				-- local fidget = require("fidget")
				-- fidget.notify("buffer attached", nil, { annote = "GitSigns" })
			-- 	local gs = package.loaded.gitsigns
			-- 	local map = function(m, l, r, d) vim.keymap.set(m, l, r, { buffer = buf, desc = d }) end
			-- 	map("n", "]h", gs.next_hunk, "Next hunk")
			-- 	map("n", "[h", gs.prev_hunk, "Prev hunk")
			-- 	map("n", "<leader>hs", gs.stage_hunk, "Stage hunk")
			-- 	map("n", "<leader>hr", gs.reset_hunk, "Reset hunk")
			-- 	map("n", "<leader>hp", gs.preview_hunk, "Preview hunk")
			-- 	map("n", "<leader>hb", gs.toggle_current_line_blame, "Toggle blame")
			-- 	map("n", "<leader>hd", function() gs.diffthis("~") end, "Diff vs HEAD")
			end,
		},
	},
	{	"sindrets/diffview.nvim",
		cmd = { "DiffviewOpen", "DiffviewFileHistory" },
		opts = {
			enhanced_diff_hl=true,
		},
	},
	{
		"NeogitOrg/neogit",
		dependencies = { "nvim-lua/plenary.nvim", "sindrets/diffview.nvim" },
		keys = {
			{ "<leader>gs", function() require("neogit").open({ kind = "vsplit", width = 40 }) end,
				desc = "Git status (sidebar)" },
			{ "<leader>gc", "<cmd>Neogit commit<cr>", desc = "Git commit (popup)" }, -- reliable commit opener
		},
		opts = {
			integrations = { diffview = true },
		},
	},
}
