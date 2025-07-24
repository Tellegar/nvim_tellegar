vim.api.nvim_create_user_command("DiffClipboard", function()
	local clipboard_text = vim.fn.getreg("+") -- prints warning on empty clipboard
	if clipboard_text == "" then
		return
	end
	clipboard_text = vim.fn.getreg("+"):gsub("\n$", "")
	if clipboard_text == "" then
		vim.notify("Clipboard only contains a newline character", vim.log.levels.WARN)
		return
	end

	local win = vim.api.nvim_get_current_win()

	-- Create a scratch buffer
	local buf_scratch = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_name(buf_scratch, "[Clipboard]")
	vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf_scratch })

	-- Paste the clipboard content into the scratch buffer
	local lines = vim.split(clipboard_text, "\n")
	vim.api.nvim_buf_set_lines(buf_scratch, 0, -1, false, lines)

	-- Create scratch window and attach buffer
	vim.api.nvim_command("rightbelow vsplit")
	local win_scratch = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(win_scratch, buf_scratch)

	-- Set diffmode
	vim.api.nvim_win_call(win, function()
		vim.cmd("diffthis")
	end)
	vim.api.nvim_win_call(win_scratch, function()
		vim.cmd("diffthis")
	end)

	-- Focus back to original window
	vim.api.nvim_set_current_win(win)
end, {})
