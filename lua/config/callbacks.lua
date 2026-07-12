local autocmd = vim.api.nvim_create_autocmd
local map = vim.keymap.set

-- every vim.lsp.util.open_floating_preview() window (hover, signature_help, diagnostic
-- float) tags the *window* (not the buffer) with lsp_floating_bufnr; give all of them
-- q/<Esc> to close, overriding the global <Esc> -> :noh mapping only within that float
autocmd("WinEnter", {
	callback = function()
		local winid = vim.api.nvim_get_current_win()
		if not vim.w[winid].lsp_floating_bufnr then
			return
		end
		local bufnr = vim.api.nvim_get_current_buf()
		local function close()
			if vim.api.nvim_win_is_valid(winid) then
				vim.api.nvim_win_close(winid, true)
			end
		end
		map("n", "q",     close, { buffer = bufnr, silent = true, desc = "close floating preview" })
		map("n", "<Esc>", close, { buffer = bufnr, silent = true, desc = "close floating preview" })
	end
})
