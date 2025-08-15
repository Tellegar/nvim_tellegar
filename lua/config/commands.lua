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


local output_buf = -1
local output_win = -1

-- Open bottom floating output panel
local function OpenLuaOutputWindow(buf)
	local width = vim.o.columns -- full width
	local height = 20           -- fixed height (you can adjust this)
	local row = vim.o.lines - height - 2 -- position above command line
	local col = 0

	local opts = {
		style = "minimal",
		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = col,
		border = "single", -- or "rounded" / "none"
	}

	return vim.api.nvim_open_win(buf, false, opts) -- false = don't focus the window
end

-- Run entire buffer as Lua
user_cmd("RunLuaBuffer", function()
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	local code = table.concat(lines, "\n")

	-- Capture print output
	local output = {}
	local function capture_print(...)
		local parts = {}
		for i = 1, select("#", ...) do
			parts[#parts + 1] = tostring(select(i, ...))
		end
		for s in table.concat(parts, "\t"):gmatch("[^\n]+") do
			table.insert(output, s)
		end
	end

	local old_print = print
	print = capture_print

	local ok, err = pcall(function()
		local chunk, load_err = load(code)
		if not chunk then
			error(load_err)
		end
		chunk()
	end)

	print = old_print

	if not ok then
		output = { "Error: " .. err }
	elseif #output == 0 then
		output = { "No output (ran successfully)" }
	end

	-- Create output buffer if needed
	if not vim.api.nvim_buf_is_valid(output_buf) then
		output_buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_name(output_buf, "LuaOutput")
	end
	vim.api.nvim_buf_set_lines(output_buf, 0, -1, false, output)

	-- Create output window if not visible
	if not vim.api.nvim_win_is_valid(output_win) then
		output_win = OpenLuaOutputWindow(output_buf)
	else
		vim.api.nvim_win_set_buf(output_win, output_buf)
	end

	-- Keybindings to close output window
	vim.keymap.set("n", "q", function()
		if vim.api.nvim_win_is_valid(output_win) then
			vim.api.nvim_win_close(output_win, true)
			output_win = -1
		end
	end, { buffer = output_buf, silent = true, desc = "close this buffer" })

	vim.keymap.set("n", "<Esc>", function()
		if vim.api.nvim_win_is_valid(output_win) then
			vim.api.nvim_win_close(output_win, true)
			output_win = -1
		end
	end, { buffer = output_buf, silent = true, desc = "close this buffer" })
end, { desc = "run current buffer as nvim lua code" })
