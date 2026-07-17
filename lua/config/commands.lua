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
end, { desc = "shows this list" })

-- Make current buffer state the new origin (clears undo, also persistent undo).
user_cmd("ResetUndo", function()
	vim.opt.undolevels = -1
	vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.api.nvim_buf_get_lines(0, 0, -1, false))
	vim.opt.undolevels = 1000
	vim.bo.modified = false
end, { desc = "clears undo history" })


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
	local buf_clip = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_name(buf_clip, "[Clipboard]")
	vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf_clip })

	-- Paste the clipboard content into the scratch buffer
	local lines = vim.split(clipboard_text, "\n")
	vim.api.nvim_buf_set_lines(buf_clip, 0, -1, false, lines)

	-- Create scratch window and attach buffer
	local win_scratch = vim.api.nvim_open_win(buf_clip, false, { split = "right", win=0 })

	-- Set diffmode
	vim.api.nvim_win_call(win, vim.cmd.diffthis)
	vim.api.nvim_win_call(win_scratch, vim.cmd.diffthis)

	-- Copy filetype
	local buf = vim.api.nvim_win_get_buf(win)
	local filetype = vim.api.nvim_get_option_value("filetype", { buf = buf })
	vim.api.nvim_set_option_value("filetype", filetype, { buf = buf_clip })

	-- Reset [Clipboard] history
	vim.api.nvim_win_call(win_scratch, _G.my_commands.ResetUndo.func)
end, { desc = "split diff with system clipboard" })


-- -- TODO arguments, like split direction
-- user_cmd("Scratch", function()
-- 	-- take note of filetype of focused buf
-- 	local buf_focused_before = vim.api.nvim_get_current_buf()
-- 	local filetype = vim.api.nvim_get_option_value("filetype", { buf = buf_focused_before })
--
-- 	local buf_scratch = vim.api.nvim_create_buf(false, true)
-- 	vim.api.nvim_buf_set_name(buf_scratch, "[Scratch]")
-- 	vim.api.nvim_open_win(buf_scratch, true, { split = "left", win=0 })
--
-- 	vim.api.nvim_set_option_value("filetype", filetype, { buf = buf_scratch })
-- end, { desc = "opens a scratch buffer" })

local buf_scratch = nil
user_cmd("Scratch", function(opts)
	-- take note of filetype of focused buffer
	local buf_focused_before = vim.api.nvim_get_current_buf()
	local filetype = vim.api.nvim_get_option_value("filetype", { buf = buf_focused_before })

	-- direction (default/invalid: left)
	local dir_spec = {
		left = "left",
		right = "right",
		up = "above",
		above = "above",
		down = "below",
		below = "below",
	}
	local direction = dir_spec[opts.fargs[1]] or "left"

	-- BUG: same E95 issue as RunLuaBuffer below - running RunLuaBuffer on this file
	-- redefines this command with a fresh `buf_scratch = nil` upvalue, orphaning the
	-- previous "[Scratch]" buffer, then colliding with it on name when recreating.

	-- optionaly create Scratch buffer
	if buf_scratch == nil then
		buf_scratch = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_name(buf_scratch, "[Scratch]")
	end

	-- open window in specified direction
	vim.api.nvim_open_win(buf_scratch, true, { split=direction, win=0 })

	-- copy filetype from prev buffer
	vim.api.nvim_set_option_value("filetype", filetype, { buf = buf_scratch })
end, {
		desc = "opens a scratch buffer",
		nargs="*",
		complete = function()
			return { "left", "right", "up", "down" }
		end
	})


local output_buf = -1
local output_win = -1

-- Open bottom output panel for `buf`
local function OpenOutputWindow(buf)
	local before_win = vim.api.nvim_get_current_win()

	-- create split window
	local height = 10
	vim.cmd(string.format("belowright %dsplit", height))
	vim.api.nvim_set_current_buf(buf)
	local win = vim.api.nvim_get_current_win()

	-- restore focus
	vim.api.nvim_set_current_win(before_win)

	return win
end

-- Run entire buffer as Lua
user_cmd("RunLuaBuffer", function(opts)
	local silent = opts.fargs[1] == "silent"

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

	if silent then
		if not ok then
			vim.notify("RunLuaBuffer: " .. err, vim.log.levels.ERROR)
		end
		return
	end

	if not ok then
		output = { "Error: " .. err }
	elseif #output == 0 then
		output = { "No output (ran successfully)" }
	end

	-- TODO output win+buf (w reuse) into single create output panel window

	-- BUG: running RunLuaBuffer on this file (commands.lua) re-executes the whole
	-- chunk, which redefines this command with a fresh `output_buf = -1` upvalue
	-- and orphans the previous "LuaOutput" buffer. The next invocation then tries
	-- to create another buffer with that same name -> E95. Repeats on every run
	-- after the first. Same issue applies to `buf_scratch` above.

	-- Create output buffer if needed
	if not vim.api.nvim_buf_is_valid(output_buf) then
		output_buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_name(output_buf, "LuaOutput")
	end
	vim.api.nvim_buf_set_lines(output_buf, 0, -1, false, output)

	-- Create output window if not visible
	if not vim.api.nvim_win_is_valid(output_win) then
		output_win = OpenOutputWindow(output_buf)
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
end, {
	desc = "run current buffer as nvim lua code",
	nargs = "?",
	complete = function()
		return { "silent" }
	end,
})

user_cmd("ToggleInlayHints", function()
	vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled({0}),{0})
end, { desc = "toggle inlay hints" })
