_G.my_commands = {}

local function user_cmd(name, command, opts)
	opts = opts or {}
	vim.api.nvim_create_user_command(name, command, opts)
	_G.my_commands[name] = {func=command, desc=opts.desc}
end

user_cmd("MyCommands", function()
	for name, v in pairs(_G.my_commands) do
		if v.desc then
			vim.print(name .. " (" .. v.desc .. ")")
		else
			vim.print(name)
		end
	end
end, { desc = "help" })

-- Make current buffer state the new origin (clears undo, also persistent undo).
user_cmd("ResetUndo", function()
	vim.opt.undolevels = -1
	vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.api.nvim_buf_get_lines(0, 0, -1, false))
	vim.opt.undolevels = 1000
	vim.bo.modified = false
end)

user_cmd("DiffClipboard", function()
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
	local win_scratch = vim.api.nvim_open_win(buf_scratch, false, { split = "right", win=0 })

	-- Set diffmode
	vim.api.nvim_win_call(win, vim.cmd.diffthis)
	vim.api.nvim_win_call(win_scratch, vim.cmd.diffthis)

	-- Copy filetype
	local buf = vim.api.nvim_win_get_buf(win)
	local filetype = vim.api.nvim_get_option_value("filetype", { buf = buf })
	vim.api.nvim_set_option_value("filetype", filetype, { buf = buf_scratch })

	-- Reset [Clipboard] history
	vim.api.nvim_win_call(win_scratch, _G.my_commands.ResetUndo)
end, { desc = "split diff with system clipboard" })

-- TODO arguments, like split direction
user_cmd("Scratch", function()
	-- take note of filetype of focused buf
	local buf_focused_before = vim.api.nvim_get_current_buf()
	local filetype = vim.api.nvim_get_option_value("filetype", { buf = buf_focused_before })

	local buf_scratch = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_name(buf_scratch, "[Scratch]")
	vim.api.nvim_open_win(buf_scratch, true, { split = "left", win=0 })

	vim.api.nvim_set_option_value("filetype", filetype, { buf = buf_scratch })
end, { desc = "opens a scratch buffer" })
	end)

	-- Focus back to original window
	vim.api.nvim_set_current_win(win)
end, {})
