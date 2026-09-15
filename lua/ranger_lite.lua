-- ranger_lite - a small ranger look-alike file browser that runs inside nvim.
--
-- ranger in :terminal is painfully slow on Windows (MSYS2 python behind
-- ConPTY behind nvim's terminal emulator), so this draws ranger's three
-- Miller columns (parent | current | preview) as floating windows instead.
-- Scope is deliberately small: navigate, open, and a few file operations.
--
--   require("ranger_lite").setup{ command = "Ranger", replace_netrw = true }
--
-- keys (in the browser):
--   j/k, gg/G, <C-d>/<C-u>, /   normal buffer motions and search
--   l, <CR>, <Right>            enter directory / open file
--   h, <BS>, <Left>             go to parent directory
--   oh / ov / ot                open file in split / vsplit / new tab
--   <Space>                     toggle mark on the current entry (and move down)
--   v                           invert marks in the current directory
--   zh, .                       toggle hidden (dot) files
--   ~                           go to home directory
--   R                           re-read directories
--   <Insert> / <F7>             :Touch / :Mkdir prompt
--   A <F2> / a / I i            :Rename name, cursor at end / before extension /
--                               at start; with marked entries, the rename editor
--   ?                           list these keys (which-key popup)
--   q, <Esc>                    close
--
--   yy / dd                     copy / cut marked entries (or the current one)
--   pp                          paste: copy (name_1.ext on conflict) or move them here
--   yp / yd / yn / y.           put path / directory / name / name without
--                               extension into the clipboard (+ and ")
--   dD                          :Delete marked entries (or the current one)
--
-- commands (browser buffer only):
--   :Cd [dir]          go to dir (home without argument)
--   :Mkdir {dir}       create directory, parents included
--   :Touch {file}      create empty file, parents included
--   :Rename [name]     marked entries (or the current one) in an edit buffer;
--                      closing it applies the new names, emptying it cancels.
--                      With a name, renames the single current entry directly
--   :Delete [names]    delete marked entries (or the current one, or names), asks first
-- Paths are relative to the browser's directory and tab-complete against it.

local M = {}

local api = vim.api
local uv = vim.uv

local config = {
	command = "RangerLite",
	replace_netrw = false, -- open directories (`nvim .`, `:e dir`) in ranger_lite
	show_hidden = false,
	ratios = { 1, 3, 4 }, -- parent : current : preview column widths
	preview_bytes = 64 * 1024,
}

local ns = api.nvim_create_namespace("ranger_lite")

-- last selected entry per directory, kept across opens (ranger does the same)
local remembered = {}

-- paths copied (`yy`) or cut (`dd`), waiting for `pp`; kept across opens like
-- ranger's copy buffer
---@type { mode: "copy"|"cut"|nil, paths: string[] }
local clip = { mode = nil, paths = {} }

-- the open browser, nil while closed
---@type table?
local state = nil

----------------------------------------------------------------------------------------------------
-- filesystem

---@param path string
---@return string
local function normalize(path)
	path = vim.fs.normalize(path)
	if path:match("^%a:$") then
		path = path .. "/" -- "C:" means the drive's cwd, "C:/" its root
	end
	return path
end

-- nvim resolves links in buffer names, so a file opened through cwd/scripts
-- (a link elsewhere) is named by its target. Map it back under the link so the
-- browser starts where the user actually is.
---@param path string
---@return string
local function via_cwd_link(path)
	local cwd = normalize(uv.cwd())
	local handle = uv.fs_scandir(cwd)
	if not handle then
		return path
	end
	local win = vim.fn.has("win32") == 1
	local cmp_path = win and path:lower() or path
	while true do
		local name, kind = uv.fs_scandir_next(handle)
		if not name then
			break
		end
		if kind == "link" then
			local link = vim.fs.joinpath(cwd, name)
			local target = uv.fs_realpath(link)
			if target then
				target = normalize(target)
				local cmp_target = win and target:lower() or target
				if cmp_path == cmp_target or vim.startswith(cmp_path, cmp_target .. "/") then
					return link .. path:sub(#target + 1)
				end
			end
		end
	end
	return path
end

local is_windows = vim.fn.has("win32") == 1

-- comparison key for paths/names: Windows filesystems are case-insensitive
---@param s string
---@return string
local function casefold(s)
	return is_windows and s:lower() or s
end

-- user input -> absolute normalized path; relative to `base`, `~` is home
---@param input string
---@param base string
---@return string
local function resolve_path(input, base)
	input = vim.trim(input)
	if input == "~" or input:match("^~[/\\]") then
		input = uv.os_homedir() .. input:sub(2)
	end
	local absolute = input:match("^[/\\]") or input:match("^%a:[/\\]")
	local path = absolute and input or vim.fs.joinpath(base, input)
	return normalize(vim.fn.simplify(path))
end

---@param dir string
---@return string? parent nil at a filesystem root
local function parent_of(dir)
	local parent = normalize(vim.fs.dirname(dir))
	return parent ~= dir and parent or nil
end

-- "file10" sorts after "file9"
---@param name string
---@return string
local function natural_key(name)
	return (name:lower():gsub("%d+", function(d)
		return ("%012d"):format(tonumber(d) or 0)
	end))
end

---@class RangerLiteEntry
---@field name string
---@field path string
---@field is_dir boolean
---@field is_link boolean
---@field size integer?
---@field mtime integer?
---@field key string

---@param dir string
---@return { entries: RangerLiteEntry[], err: string? }
local function read_dir(dir)
	local cached = state and state.cache[dir]
	if cached then
		return cached
	end

	local entries = {}
	local handle, err = uv.fs_scandir(dir)
	if handle then
		while true do
			local name, kind = uv.fs_scandir_next(handle)
			if not name then
				break
			end
			local path = vim.fs.joinpath(dir, name)
			local stat = uv.fs_stat(path) -- follows links and junctions; nil if broken
			entries[#entries + 1] = {
				name = name,
				path = path,
				is_dir = (stat and stat.type == "directory") or (not stat and kind == "directory"),
				is_link = kind == "link",
				size = stat and stat.size,
				mtime = stat and stat.mtime.sec,
				key = natural_key(name),
			}
		end
		table.sort(entries, function(a, b)
			if a.is_dir ~= b.is_dir then
				return a.is_dir
			end
			return a.key < b.key
		end)
	end

	local result = { entries = entries, err = not handle and err or nil }
	if state then
		state.cache[dir] = result
	end
	return result
end

---@param entries RangerLiteEntry[]
---@param keep string? name to show even if hidden (the dir we came from)
---@return RangerLiteEntry[]
local function visible(entries, keep)
	if config.show_hidden then
		return entries
	end
	return vim.tbl_filter(function(e)
		return e.name:sub(1, 1) ~= "." or e.name == keep
	end, entries)
end

---@param n integer?
---@return string
local function human_size(n)
	if not n then
		return ""
	end
	local units = { "B", "K", "M", "G", "T" }
	local i = 1
	while n >= 1024 and i < #units do
		n = n / 1024
		i = i + 1
	end
	return i == 1 and ("%d B"):format(n) or ("%.1f %s"):format(n, units[i])
end

----------------------------------------------------------------------------------------------------
-- drawing

---@param buf integer
---@param lines string[]
local function set_lines(buf, lines)
	vim.bo[buf].modifiable = true
	api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false
	api.nvim_buf_clear_namespace(buf, ns, 0, -1)
end

---@param buf integer
---@param row integer 0-based
---@param col integer
---@param end_col integer
---@param group string
local function hl(buf, row, col, end_col, group)
	api.nvim_buf_set_extmark(buf, ns, row, col, { end_col = end_col, hl_group = group })
end

-- plain text in the preview column, e.g. "empty" or an error
---@param buf integer
---@param text string
local function set_message(buf, text)
	set_lines(buf, { " " .. text })
	hl(buf, 0, 0, #text + 1, "RangerLiteMessage")
end

---@param buf integer
---@param listing { entries: RangerLiteEntry[], err: string? }
---@param entries RangerLiteEntry[]
---@param with_sizes boolean
---@param marked table<string, true>? marked paths to highlight
local function draw_list(buf, listing, entries, with_sizes, marked)
	if listing.err then
		return set_message(buf, listing.err)
	elseif #entries == 0 then
		return set_message(buf, "empty")
	end

	local lines = {}
	for i, e in ipairs(entries) do
		lines[i] = " " .. e.name
	end
	set_lines(buf, lines)

	for i, e in ipairs(entries) do
		local is_marked = marked and marked[e.path]
		local group = is_marked and "RangerLiteMarked"
			or vim.tbl_contains(clip.paths, e.path) and (clip.mode == "cut" and "RangerLiteCut" or "RangerLiteCopied")
			or e.is_link and "RangerLiteLink"
			or e.is_dir and "RangerLiteDir"
			or "RangerLiteFile"
		api.nvim_buf_set_extmark(buf, ns, i - 1, 0, {
			end_col = #lines[i],
			hl_group = group,
			virt_text = with_sizes and not e.is_dir and { { human_size(e.size) .. " ", "RangerLiteSize" } } or nil,
			virt_text_pos = "right_align",
		})
		if is_marked then
			-- a bar in the leading blank column, like ranger's mark indicator
			api.nvim_buf_set_extmark(buf, ns, i - 1, 0, {
				virt_text = { { "▌", "RangerLiteMarked" } },
				virt_text_pos = "overlay",
			})
		end
	end
end

---@param buf integer
local function stop_highlighting(buf)
	pcall(vim.treesitter.stop, buf)
	vim.bo[buf].syntax = ""
end

-- Highlight the preview without setting 'filetype': that would fire FileType
-- autocmds (LSP attach, parser installs) for a throwaway buffer.
---@param buf integer
---@param path string
local function highlight_preview(buf, path)
	local ok, ft = pcall(vim.filetype.match, { filename = path })
	if not ok or not ft then
		return
	end
	local lang = vim.treesitter.language.get_lang(ft)
	if lang then
		local added, loaded = pcall(vim.treesitter.language.add, lang)
		if added and loaded and pcall(vim.treesitter.start, buf, lang) then
			return
		end
	end
	vim.bo[buf].syntax = ft
end

---@param buf integer
---@param entry RangerLiteEntry
---@param height integer
local function preview_file(buf, entry, height)
	if not entry.size then
		return set_message(buf, "broken link")
	end
	local fd = io.open(entry.path, "rb")
	if not fd then
		return set_message(buf, "cannot read file")
	end
	local data = fd:read(config.preview_bytes) or ""
	fd:close()
	if data:find("\0", 1, true) then
		return set_message(buf, "binary file")
	end

	local lines = {}
	for line in (data .. "\n"):gmatch("(.-)\r?\n") do
		lines[#lines + 1] = line
		if #lines >= height then
			break
		end
	end
	set_lines(buf, lines)
	highlight_preview(buf, entry.path)
end

---@param buf integer
---@param text string
---@param width integer
---@param right string
local function set_bar(buf, text, width, right)
	local pad = math.max(width - vim.fn.strdisplaywidth(text) - vim.fn.strdisplaywidth(right), 1)
	set_lines(buf, { text .. (" "):rep(pad) .. right })
end

----------------------------------------------------------------------------------------------------
-- browser

local function layout()
	local width = vim.o.columns
	local height = math.max(vim.o.lines - vim.o.cmdheight, 3)
	local body = height - 2 -- header on top, status at the bottom
	local gap = 1
	local r = config.ratios
	local total = math.max(width - 2 * gap, 3)
	local w1 = math.max(math.floor(total * r[1] / (r[1] + r[2] + r[3])), 1)
	local w2 = math.max(math.floor(total * r[2] / (r[1] + r[2] + r[3])), 1)
	local w3 = math.max(total - w1 - w2, 1)
	return {
		backdrop = { row = 0, col = 0, width = width, height = height, zindex = 45 },
		header = { row = 0, col = 0, width = width, height = 1, zindex = 46 },
		parent = { row = 1, col = 0, width = w1, height = body, zindex = 46 },
		current = { row = 1, col = w1 + gap, width = w2, height = body, zindex = 46 },
		preview = { row = 1, col = w1 + w2 + 2 * gap, width = w3, height = body, zindex = 46 },
		status = { row = height - 1, col = 0, width = width, height = 1, zindex = 46 },
	}
end

---@return RangerLiteEntry?, integer
local function selected()
	local row = api.nvim_win_get_cursor(state.wins.current)[1]
	return state.entries[row], row
end

-- redraw everything that depends on the selected entry
---@param force boolean?
local function draw_selection(force)
	local st = state
	if not st then
		return
	end
	local entry, row = selected()
	local key = table.concat({ st.dir, row, st.generation }, "\0")
	if key == st.drawn and not force then
		return
	end
	st.drawn = key

	local geo = layout()
	local dir_text = st.dir:sub(-1) == "/" and st.dir or st.dir .. "/"

	-- header: path/selected
	local name = entry and entry.name or ""
	set_lines(st.bufs.header, { " " .. dir_text .. name })
	hl(st.bufs.header, 0, 1, 1 + #dir_text, "RangerLitePath")
	hl(st.bufs.header, 0, 1 + #dir_text, 1 + #dir_text + #name, "RangerLiteName")

	-- status: size, mtime, link target | position
	local info = ""
	if entry then
		local parts = {}
		if not entry.is_dir then
			parts[#parts + 1] = human_size(entry.size)
		end
		if entry.mtime then
			parts[#parts + 1] = os.date("%Y-%m-%d %H:%M", entry.mtime)
		end
		if entry.is_link then
			parts[#parts + 1] = "-> " .. (uv.fs_readlink(entry.path) or "?")
		end
		info = " " .. table.concat(parts, "  ")
	end
	local pos = #st.entries > 0 and ("%d/%d"):format(row, #st.entries) or "0/0"
	local hidden = config.show_hidden and "hidden  " or ""
	local n_marked = 0
	for _, e in ipairs(st.entries) do
		if st.marked[e.path] then
			n_marked = n_marked + 1
		end
	end
	local marks = (#clip.paths > 0 and ("%d %s  "):format(#clip.paths, clip.mode == "cut" and "cut" or "copied") or "")
		.. (n_marked > 0 and ("%d marked  "):format(n_marked) or "")
	set_bar(st.bufs.status, info, geo.status.width, marks .. hidden .. pos .. " ")
	hl(st.bufs.status, 0, 0, #api.nvim_buf_get_lines(st.bufs.status, 0, 1, false)[1], "RangerLiteStatus")

	-- preview
	local pbuf = st.bufs.preview
	stop_highlighting(pbuf)
	if not entry then
		set_lines(pbuf, {})
	elseif entry.is_dir then
		local listing = read_dir(entry.path)
		draw_list(pbuf, listing, visible(listing.entries), false)
	else
		preview_file(pbuf, entry, geo.preview.height)
	end
	if api.nvim_win_is_valid(st.wins.preview) then
		api.nvim_win_set_cursor(st.wins.preview, { 1, 0 })
	end

	if entry then
		remembered[st.dir] = entry.name
	end
end

---@param dir string
---@param select string? entry name to put the cursor on
local function show_dir(dir, select)
	local st = state
	st.dir = dir
	st.generation = st.generation + 1

	local listing = read_dir(dir)
	st.entries = visible(listing.entries)
	draw_list(st.bufs.current, listing, st.entries, true, st.marked)

	local target = select or remembered[dir]
	local row = 1
	for i, e in ipairs(st.entries) do
		if e.name == target then
			row = i
			break
		end
	end
	api.nvim_win_set_cursor(st.wins.current, { row, 0 })

	local parent = parent_of(dir)
	if parent then
		local plisting = read_dir(parent)
		local here = vim.fs.basename(dir)
		local pentries = visible(plisting.entries, here)
		draw_list(st.bufs.parent, plisting, pentries, false)
		for i, e in ipairs(pentries) do
			if e.name == here then
				api.nvim_win_set_cursor(st.wins.parent, { i, 0 })
				break
			end
		end
	else
		set_lines(st.bufs.parent, {})
	end

	draw_selection()
end

-- hide the real cursor while the browser has focus (only the selection line
-- shows where you are), same trick as cmake_menu.float
local saved_guicursor = nil

local function hide_cursor()
	if saved_guicursor == nil then
		saved_guicursor = vim.go.guicursor
		vim.go.guicursor = "a:RangerLiteHiddenCursor"
	end
end

local function restore_cursor()
	if saved_guicursor ~= nil then
		local saved = saved_guicursor
		saved_guicursor = nil
		-- transitional "a:" forces a cursor refresh even if `saved` is empty
		vim.go.guicursor = "a:"
		if saved ~= "" then
			vim.go.guicursor = saved
		end
	end
end

function M.close()
	local st = state
	if not st then
		return
	end
	state = nil
	restore_cursor()
	pcall(api.nvim_del_augroup_by_id, st.augroup)
	for _, win in pairs(st.wins) do
		if api.nvim_win_is_valid(win) then
			pcall(api.nvim_win_close, win, true)
		end
	end
	if api.nvim_win_is_valid(st.prev_win) then
		api.nvim_set_current_win(st.prev_win)
	end
end

-- after close(): a directory placeholder left in the window becomes an empty buffer
local function drop_directory_buffer()
	local buf = api.nvim_get_current_buf()
	local name = api.nvim_buf_get_name(buf)
	if name ~= "" and vim.fn.isdirectory(name) == 1 and vim.bo[buf].buftype == "" then
		vim.cmd("enew")
		if api.nvim_buf_is_valid(buf) then
			pcall(api.nvim_buf_delete, buf, { force = true })
		end
	end
end

---@param cmd string? "edit" (default), "split", "vsplit" or "tabedit"
local function open_selected(cmd)
	local entry = selected()
	if not entry then
		return
	end
	if entry.is_dir then
		return show_dir(entry.path)
	end
	M.close()
	vim.cmd((cmd or "edit") .. " " .. vim.fn.fnameescape(entry.path))
end

local function go_parent()
	local parent = parent_of(state.dir)
	if parent then
		show_dir(parent, vim.fs.basename(state.dir))
	end
end

---@param reread boolean? drop cached listings first
---@param select string? entry to select instead of the current one
local function redraw(reread, select)
	local entry = selected()
	if reread then
		state.cache = {}
	end
	show_dir(state.dir, select or (entry and entry.name))
end

----------------------------------------------------------------------------------------------------
-- marks

-- redraw only the current column (marks changed), keeping the cursor
local function redraw_marks()
	local st = state
	local row = api.nvim_win_get_cursor(st.wins.current)[1]
	draw_list(st.bufs.current, read_dir(st.dir), st.entries, true, st.marked)
	api.nvim_win_set_cursor(st.wins.current, { math.min(row, math.max(#st.entries, 1)), 0 })
	draw_selection(true)
end

local function toggle_mark()
	local st = state
	local entry, row = selected()
	if not entry then
		return
	end
	st.marked[entry.path] = not st.marked[entry.path] or nil
	redraw_marks()
	-- move on like ranger does, so repeated <Space> marks a run of entries
	if row < #st.entries then
		api.nvim_win_set_cursor(st.wins.current, { row + 1, 0 })
	end
end

local function invert_marks()
	local st = state
	for _, e in ipairs(st.entries) do
		st.marked[e.path] = not st.marked[e.path] or nil
	end
	redraw_marks()
end

-- what an operation acts on: marked entries of this directory, else the current one
---@return RangerLiteEntry[]
local function targets()
	local st = state
	local list = vim.tbl_filter(function(e) return st.marked[e.path] end, st.entries)
	if #list == 0 then
		local entry = selected()
		list = entry and { entry } or {}
	end
	return list
end

----------------------------------------------------------------------------------------------------
-- file operations

---@param msg string
---@param level integer?
local function notify(msg, level)
	vim.notify("ranger_lite: " .. msg, level or vim.log.levels.INFO)
end

-- first path component of user input, to select what was just created
---@param input string
---@return string?
local function first_component(input)
	if input:match("^[/\\~]") or input:match("^%a:[/\\]") then
		return nil
	end
	return input:match("^[^/\\]+")
end

---@param input string
local function cmd_cd(input)
	local st = state
	local path = resolve_path(input ~= "" and input or "~", st.dir)
	local stat = uv.fs_stat(path)
	if not stat then
		return notify("no such directory: " .. path, vim.log.levels.ERROR)
	end
	if stat.type == "directory" then
		show_dir(path)
	else
		show_dir(normalize(vim.fs.dirname(path)), vim.fs.basename(path))
	end
end

---@param input string
local function cmd_mkdir(input)
	local path = resolve_path(input, state.dir)
	if uv.fs_stat(path) then
		return notify("already exists: " .. path, vim.log.levels.ERROR)
	end
	local ok, err = pcall(vim.fn.mkdir, path, "p")
	if not ok then
		return notify(tostring(err), vim.log.levels.ERROR)
	end
	redraw(true, first_component(input))
end

---@param input string
local function cmd_touch(input)
	local path = resolve_path(input, state.dir)
	if uv.fs_stat(path) then
		return notify("already exists: " .. path, vim.log.levels.ERROR)
	end
	pcall(vim.fn.mkdir, vim.fs.dirname(path), "p")
	local fd, err = io.open(path, "ab")
	if not fd then
		return notify(tostring(err), vim.log.levels.ERROR)
	end
	fd:close()
	redraw(true, first_component(input))
end

-- Remove one path. Links and junctions are removed as links: their target
-- (e.g. a junction into a game's save folder) is never touched.
---@param path string
---@return boolean ok, string? err
local function delete_path(path)
	local lstat = uv.fs_lstat(path)
	if not lstat then
		return false, "not found"
	end
	if lstat.type == "link" then
		local ok, err = uv.fs_unlink(path)
		if not ok then
			ok, err = uv.fs_rmdir(path) -- directory symlinks and junctions on Windows
		end
		return ok ~= nil, err
	end
	if lstat.type == "directory" then
		-- delete(), "rf" removes nested links as links too, without following them
		return vim.fn.delete(path, "rf") == 0, "could not delete directory"
	end
	local ok, err = uv.fs_unlink(path)
	return ok ~= nil, err
end

-- One-keypress question on the command line, like ranger's console: y or <CR>
-- confirms (default yes, [Y/n]); n, <Esc> or anything else cancels. Kept to a
-- single line: a multi-line message would end in a "Press ENTER" prompt.
---@param question string
---@return boolean
local function ask_yes(question)
	local suffix = " [Y/n] "
	local room = vim.o.columns - vim.fn.strdisplaywidth(suffix) - 2
	if vim.fn.strdisplaywidth(question) > room then
		question = vim.fn.strcharpart(question, 0, room - 1) .. "…"
	end
	vim.cmd.redraw()
	api.nvim_echo({ { question .. suffix, "Question" } }, false, {})
	local ok, key = pcall(vim.fn.getcharstr)
	api.nvim_echo({ { "" } }, false, {})
	return ok and (key == "y" or key == "Y" or key == "\r")
end

---@param names string[] explicit names/paths; targets() when empty
local function cmd_delete(names)
	local st = state
	local paths = {}
	if #names > 0 then
		for _, name in ipairs(names) do
			paths[#paths + 1] = resolve_path(name, st.dir)
		end
	else
		for _, e in ipairs(targets()) do
			paths[#paths + 1] = e.path
		end
	end
	if #paths == 0 then
		return
	end

	local shown = vim.tbl_map(function(p)
		return vim.startswith(casefold(p), casefold(st.dir) .. "/") and p:sub(#st.dir + 2) or p
	end, paths)
	local question = #paths == 1 and ("Delete %s?"):format(shown[1])
		or ("Delete %d items: %s?"):format(#paths, table.concat(shown, ", "))
	if not ask_yes(question) then
		return
	end

	local errors = {}
	for _, p in ipairs(paths) do
		local ok, err = delete_path(p)
		if ok then
			st.marked[p] = nil
		else
			errors[#errors + 1] = p .. ": " .. tostring(err)
		end
	end
	if #errors > 0 then
		notify("delete failed:\n" .. table.concat(errors, "\n"), vim.log.levels.ERROR)
	end
	redraw(true)
end

-- Apply the rename buffer: line i is the new name of entries[i].
---@param dir string
---@param entries RangerLiteEntry[]
---@param lines string[]
local function apply_renames(dir, entries, lines)
	while #lines > 0 and vim.trim(lines[#lines]) == "" do
		table.remove(lines)
	end
	if #lines == 0 then
		return notify("rename cancelled")
	end
	if #lines ~= #entries then
		return notify(("rename: %d names for %d entries, nothing renamed"):format(#lines, #entries), vim.log.levels.ERROR)
	end

	local plan, sources, seen = {}, {}, {}
	for i, e in ipairs(entries) do
		local name = vim.trim(lines[i])
		if name == "" then
			return notify(("rename: line %d is empty, nothing renamed"):format(i), vim.log.levels.ERROR)
		end
		if name ~= e.name then
			local dst = resolve_path(name, dir)
			if seen[casefold(dst)] then
				return notify("rename: duplicate name " .. name .. ", nothing renamed", vim.log.levels.ERROR)
			end
			seen[casefold(dst)] = true
			sources[casefold(e.path)] = true
			plan[#plan + 1] = { src = e.path, dst = dst, name = name }
		end
	end
	if #plan == 0 then
		return
	end
	for _, p in ipairs(plan) do
		-- taken by something that isn't itself being renamed away (swaps are fine)
		if uv.fs_lstat(p.dst) and not sources[casefold(p.dst)] then
			return notify("rename: " .. p.dst .. " already exists, nothing renamed", vim.log.levels.ERROR)
		end
	end

	-- two phases so swaps and case-only changes (a -> A on Windows) work
	local errors = {}
	for i, p in ipairs(plan) do
		p.tmp = ("%s.ranger_lite_tmp%d"):format(p.src, i)
		local ok, err = uv.fs_rename(p.src, p.tmp)
		if not ok then
			errors[#errors + 1] = p.src .. ": " .. tostring(err)
			p.tmp = nil
		end
	end
	for _, p in ipairs(plan) do
		if p.tmp then
			pcall(vim.fn.mkdir, vim.fs.dirname(p.dst), "p")
			local ok, err = uv.fs_rename(p.tmp, p.dst)
			if ok then
				state.marked[p.src] = nil
			else
				errors[#errors + 1] = p.src .. " -> " .. p.dst .. ": " .. tostring(err)
				uv.fs_rename(p.tmp, p.src) -- put it back
			end
		end
	end
	if #errors > 0 then
		notify("rename failed:\n" .. table.concat(errors, "\n"), vim.log.levels.ERROR)
	end
	redraw(true, first_component(plan[1].name))
end

-- `yy` / `dd`: remember what to copy or move; nothing changes on disk until `pp`
---@param mode "copy"|"cut"
local function clip_targets(mode)
	local st = state
	clip = { mode = mode, paths = {} }
	for _, e in ipairs(targets()) do
		clip.paths[#clip.paths + 1] = e.path
		st.marked[e.path] = nil
	end
	if #clip.paths > 0 then
		notify(("%d %s, paste with pp"):format(#clip.paths, mode == "cut" and "cut" or "copied"))
	end
	redraw_marks()
end

-- first free "name", "name_1.ext", "name_2.ext", ... in dir
---@param dir string
---@param name string
---@return string path, string name
local function unique_path(dir, name)
	local path = vim.fs.joinpath(dir, name)
	if not uv.fs_lstat(path) then
		return path, name
	end
	local base, ext = name:match("^(.+)(%.[^.]+)$")
	if not base then
		base, ext = name, ""
	end
	for i = 1, 9999 do
		local candidate = ("%s_%d%s"):format(base, i, ext)
		path = vim.fs.joinpath(dir, candidate)
		if not uv.fs_lstat(path) then
			return path, candidate
		end
	end
	return path, name
end

-- Recursive copy. Links and junctions are copied as links, never followed
-- (like cp -R), so copying a folder with a junction doesn't copy its target.
---@param src string
---@param dst string
---@return boolean ok, string? err
local function copy_path(src, dst)
	local lstat = uv.fs_lstat(src)
	if not lstat then
		return false, src .. ": not found"
	end
	if lstat.type == "link" then
		local target = uv.fs_readlink(src)
		if not target then
			return false, src .. ": cannot read link"
		end
		local stat = uv.fs_stat(src)
		local is_dir = stat and stat.type == "directory" or false
		local ok, err = uv.fs_symlink(target, dst, { dir = is_dir, junction = is_dir })
		return ok == true, not ok and (src .. ": " .. tostring(err)) or nil
	elseif lstat.type == "directory" then
		local ok, err = uv.fs_mkdir(dst, tonumber("755", 8))
		if not ok then
			return false, dst .. ": " .. tostring(err)
		end
		local handle = uv.fs_scandir(src)
		while handle do
			local name = uv.fs_scandir_next(handle)
			if not name then
				break
			end
			local child_ok, child_err = copy_path(vim.fs.joinpath(src, name), vim.fs.joinpath(dst, name))
			if not child_ok then
				return false, child_err
			end
		end
		return true
	end
	local ok, err = uv.fs_copyfile(src, dst, { excl = true })
	return ok == true, not ok and (src .. ": " .. tostring(err)) or nil
end

-- `pp`: copy or move the clipped paths into the browser's directory
local function paste()
	local st = state
	if #clip.paths == 0 then
		return notify("nothing to paste, use yy or dd first")
	end
	local errors, pasted = {}, {}
	for _, src in ipairs(clip.paths) do
		local name = vim.fs.basename(src)
		local here = casefold(normalize(vim.fs.dirname(src))) == casefold(st.dir)
		if vim.startswith(casefold(st.dir) .. "/", casefold(src) .. "/") then
			errors[#errors + 1] = src .. ": cannot paste a directory into itself"
		elseif clip.mode == "cut" then
			if not here then
				local dst = vim.fs.joinpath(st.dir, name)
				if uv.fs_lstat(dst) then
					errors[#errors + 1] = dst .. ": already exists"
				else
					local ok, err = uv.fs_rename(src, dst)
					if ok then
						pasted[#pasted + 1] = name
					else
						-- e.g. EXDEV: a move across drives would need copy + delete
						errors[#errors + 1] = src .. ": " .. tostring(err)
					end
				end
			end
		else
			local dst, new_name = unique_path(st.dir, name)
			local ok, err = copy_path(src, dst)
			if ok then
				pasted[#pasted + 1] = new_name
			else
				errors[#errors + 1] = err
			end
		end
	end
	-- a copy can be pasted again elsewhere; a move is done
	if clip.mode == "cut" then
		clip = { mode = nil, paths = {} }
	end
	if #errors > 0 then
		notify("paste failed:\n" .. table.concat(errors, "\n"), vim.log.levels.ERROR)
	end
	redraw(true, pasted[1])
end

-- `yp` and friends: text about the targets into the " and + registers
---@param what string
---@param fn fun(e: RangerLiteEntry): string
local function yank_text(what, fn)
	local list = targets()
	if #list == 0 then
		return
	end
	local text = table.concat(vim.tbl_map(fn, list), "\n")
	vim.fn.setreg('"', text)
	pcall(vim.fn.setreg, "+", text)
	notify(("copied %s: %s"):format(what, #list == 1 and text or (#list .. " entries")))
end

local rename_serial = 0

-- Edit names in a float; closing it (:q, :wq, ZZ) applies them.
local function open_rename_editor()
	local st = state
	local list = targets()
	if #list == 0 then
		return
	end
	local dir = st.dir

	rename_serial = rename_serial + 1
	local buf = api.nvim_create_buf(false, true)
	vim.bo[buf].buftype = "acwrite" -- :w / :wq work (BufWriteCmd below), nothing is written
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false
	api.nvim_buf_set_name(buf, "ranger_lite://rename/" .. rename_serial)
	local names = vim.tbl_map(function(e) return e.name end, list)
	api.nvim_buf_set_lines(buf, 0, -1, false, names)
	vim.bo[buf].modified = false

	local longest = 0
	for _, n in ipairs(names) do
		longest = math.max(longest, vim.fn.strdisplaywidth(n))
	end
	local width = math.min(math.max(longest + 4, 50), vim.o.columns - 8)
	local height = math.min(#names, math.max(vim.o.lines - 8, 1))

	st.editing = true -- keep the browser open while focus is in the editor
	local win = api.nvim_open_win(buf, true, {
		relative = "editor",
		row = math.floor((vim.o.lines - height) / 2) - 1,
		col = math.floor((vim.o.columns - width) / 2),
		width = width,
		height = height,
		border = "rounded",
		title = " Rename: close to apply, empty to cancel ",
		title_pos = "center",
		zindex = 60,
	})
	vim.wo[win].wrap = false

	-- never "modified": plain :q closes (and applies) without E37
	api.nvim_create_autocmd({ "BufWriteCmd", "TextChanged", "TextChangedI" }, {
		buffer = buf,
		callback = function() vim.bo[buf].modified = false end,
	})
	api.nvim_create_autocmd("WinClosed", {
		pattern = tostring(win),
		once = true,
		callback = function()
			local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
			vim.schedule(function()
				st.editing = false
				if state ~= st then
					return
				end
				if api.nvim_win_is_valid(st.wins.current) then
					api.nvim_set_current_win(st.wins.current)
				end
				apply_renames(dir, list, lines)
			end)
		end,
	})
end

-- text for the command line, applied from inside cmdline mode by fill_cmdline()
---@type { text: string, pos: integer }?
local pending_cmdline = nil

function M._fill_cmdline()
	if pending_cmdline then
		vim.fn.setcmdline(pending_cmdline.text, pending_cmdline.pos)
		pending_cmdline = nil
	end
end

-- Open ":" with `text` and the cursor at byte `pos` (1-based). setcmdline()
-- instead of feeding the text as keys, so names with "<", "|" or K_SPECIAL
-- bytes arrive intact.
---@param text string
---@param pos integer
local function prompt_cmdline(text, pos)
	pending_cmdline = { text = text, pos = pos }
	local keys = ":<Cmd>lua require('ranger_lite')._fill_cmdline()<CR>"
	api.nvim_feedkeys(api.nvim_replace_termcodes(keys, true, false, true), "n", false)
end

-- Rename keys: marked entries go straight to the editor (:Rename<CR>); a single
-- entry gets ":Rename name" with the cursor where ranger puts it.
---@param cursor "start"|"end"|"ext"
local function rename_key(cursor)
	local st = state
	for _, e in ipairs(st.entries) do
		if st.marked[e.path] then
			return open_rename_editor()
		end
	end
	local entry = selected()
	if not entry then
		return
	end
	local prefix = "Rename "
	local text = prefix .. entry.name
	local pos = #text + 1
	if cursor == "start" then
		pos = #prefix + 1
	elseif cursor == "ext" and not entry.is_dir then
		local base = entry.name:match("^(.+)%.[^.]+$")
		if base then
			pos = #prefix + #base + 1
		end
	end
	prompt_cmdline(text, pos)
end

---@param input string
local function cmd_rename(input)
	if input == "" then
		return open_rename_editor()
	end
	local entry = selected()
	if entry then
		apply_renames(state.dir, { entry }, { input })
	end
end

----------------------------------------------------------------------------------------------------
-- commands

-- Complete paths relative to the browser's directory. Spaces come back
-- escaped (`\ `) so a name with spaces stays one argument.
---@param dirs_only boolean
---@return fun(arglead: string): string[]
local function path_completer(dirs_only)
	return function(arglead)
		local st = state
		if not st then
			return {}
		end
		local typed = arglead:gsub("\\ ", " ")
		local head = typed:match("^(.*[/\\])") or ""
		local tail = typed:sub(#head + 1)
		local dir = head == "" and st.dir or resolve_path(head, st.dir)
		local prefix = casefold(tail)
		local out = {}
		for _, e in ipairs(read_dir(dir).entries) do
			local shown = config.show_hidden or e.name:sub(1, 1) ~= "." or tail:sub(1, 1) == "."
			if shown and (e.is_dir or not dirs_only) and vim.startswith(casefold(e.name), prefix) then
				local item = head .. e.name .. (e.is_dir and "/" or "")
				out[#out + 1] = (item:gsub(" ", "\\ "))
			end
		end
		return out
	end
end

---@param buf integer
local function set_commands(buf)
	local function arg(args)
		return (args.args:gsub("\\ ", " "))
	end
	local commands = {
		{ "Cd", function(a) cmd_cd(arg(a)) end, { nargs = "?", complete = path_completer(true), desc = "go to directory" } },
		{ "Mkdir", function(a) cmd_mkdir(arg(a)) end, { nargs = 1, complete = path_completer(true), desc = "create directory" } },
		{ "Touch", function(a) cmd_touch(arg(a)) end, { nargs = 1, complete = path_completer(false), desc = "create file" } },
		{ "Rename", function(a) cmd_rename(arg(a)) end, {
			nargs = "?",
			desc = "rename marked/current entries",
			complete = function(arglead)
				local entry = state and selected()
				return entry and vim.startswith(entry.name, arglead) and { (entry.name:gsub(" ", "\\ ")) } or {}
			end,
		} },
		{ "Delete", function(a) cmd_delete(a.fargs) end, { nargs = "*", complete = path_completer(false), desc = "delete marked/current entries" } },
	}
	for _, c in ipairs(commands) do
		api.nvim_buf_create_user_command(buf, c[1], c[2], c[3])
	end
end

-- Blank-slate keymap surface, same approach as cmake_menu.float: every key is
-- a no-op on the browser buffer, so insert/visual/edit commands and global
-- mappings can't act on it. Only what set_keymaps() adds below does anything.
---@param buf integer
local function clear_keymaps(buf)
	local function nop(lhs)
		vim.keymap.set("n", lhs, "<Nop>", { buffer = buf, nowait = true, silent = true })
	end
	for b = 32, 126 do
		local c = string.char(b)
		nop(c)
		nop("<C-" .. c .. ">")
	end
	for _, k in ipairs({
		"<CR>", "<C-CR>", "<S-CR>", "<BS>", "<Tab>", "<S-Tab>", "<Del>", "<Esc>",
		"<Up>", "<Down>", "<Left>", "<Right>",
		"<Home>", "<End>", "<PageUp>", "<PageDown>", "<Insert>",
		"<F1>", "<F2>", "<F3>", "<F4>", "<F5>", "<F6>",
		"<F7>", "<F8>", "<F9>", "<F10>", "<F11>", "<F12>",
		"<LeftMouse>", "<2-LeftMouse>", "<RightMouse>", "<MiddleMouse>",
	}) do
		nop(k)
	end
end

-- `?`: list the browser's own keymaps. which-key's show{ global = false }
-- reads exactly this buffer's mappings; its desc filter hides the <Nop>
-- blanket and the undescribed aliases. Without which-key, echo the same list.
---@param buf integer
local function show_help(buf)
	-- which-key finishes its setup only after VeryLazy (lazy-loaded); before
	-- that show() errors, so check its config reports loaded
	local ok, wk_config = pcall(require, "which-key.config")
	if ok and wk_config.loaded then
		-- The <Esc> that dismisses the popup still reaches this buffer's <Esc>
		-- mapping afterwards. show() blocks until the popup is gone and leftover
		-- keys run before the next scheduled callback, so mute <Esc> until then.
		local st = state
		st.help_open = true
		require("which-key").show({ global = false })
		vim.schedule(function() st.help_open = false end)
		return
	end
	local chunks = {}
	for _, km in ipairs(api.nvim_buf_get_keymap(buf, "n")) do
		if km.desc and km.desc ~= "" then
			chunks[#chunks + 1] = { ("%-6s %s\n"):format(vim.fn.keytrans(km.lhsraw or km.lhs), km.desc) }
		end
	end
	table.sort(chunks, function(a, b) return a[1] < b[1] end)
	api.nvim_echo(chunks, false, {})
end

---@param buf integer
local function set_keymaps(buf)
	clear_keymaps(buf)

	-- desc nil: works, but stays out of the `?` list (aliases, passthroughs)
	---@param desc string?
	local function map(lhs, rhs, desc, opts)
		vim.keymap.set("n", lhs, rhs, vim.tbl_extend("force", {
			buffer = buf,
			nowait = true,
			silent = true,
			desc = desc,
		}, opts or {}))
		-- a nowait <Nop> on the first key would swallow multi-key maps (gg, zh, oh)
		if #lhs == 2 and not lhs:find("<", 1, true) then
			vim.keymap.set("n", lhs:sub(1, 1), "<Nop>", { buffer = buf, silent = true })
		end
	end

	-- motions and search, passed through to the builtins (keymap.set is noremap)
	map("j", "j", "down")
	map("k", "k", "up")
	map("gg", "gg", "first entry")
	map("G", "G", "last entry")
	map("<C-d>", "<C-d>", "half page down")
	map("<C-u>", "<C-u>", "half page up")
	map("/", "/", "search", { silent = false })
	map("n", "n", "next match")
	map("N", "N", "previous match")
	map(":", ":", nil, { silent = false })
	for _, lhs in ipairs({ "<C-f>", "<C-b>", "<Down>", "<Up>", "<PageDown>", "<PageUp>",
		"<Home>", "<End>", "<ScrollWheelDown>", "<ScrollWheelUp>" }) do
		map(lhs, lhs)
	end
	for d = 1, 9 do
		map(tostring(d), tostring(d))
	end

	local function open() open_selected() end
	map("l", open, "open / enter directory")
	map("<CR>", open)
	map("<Right>", open)
	map("h", go_parent, "parent directory")
	map("<BS>", go_parent)
	map("<Left>", go_parent)
	map("oh", function() open_selected("split") end, "open in split")
	map("ov", function() open_selected("vsplit") end, "open in vsplit")
	map("ot", function() open_selected("tabedit") end, "open in tab")

	local function toggle_hidden()
		config.show_hidden = not config.show_hidden
		redraw()
	end
	map("zh", toggle_hidden, "toggle hidden files")
	map(".", toggle_hidden)
	map("<Space>", toggle_mark, "toggle mark")
	map("v", invert_marks, "invert marks")
	map("yy", function() clip_targets("copy") end, "copy")
	map("dd", function() clip_targets("cut") end, "cut")
	map("pp", paste, "paste (copy / move here)")
	map("dD", function() cmd_delete({}) end, "delete")
	map("yp", function() yank_text("path", function(e) return e.path end) end, "copy path")
	map("yd", function() yank_text("directory", function(e) return normalize(vim.fs.dirname(e.path)) end) end, "copy directory")
	map("yn", function() yank_text("name", function(e) return e.name end) end, "copy name")
	map("y.", function()
		yank_text("name without extension", function(e) return e.name:match("^(.+)%.[^.]+$") or e.name end)
	end, "copy name without extension")
	map("~", function() show_dir(normalize(uv.os_homedir())) end, "home directory")
	map("R", function() redraw(true) end, "re-read directories")
	map("?", function() show_help(buf) end, "help")

	local function quit()
		M.close()
		drop_directory_buffer()
	end
	map("q", quit, "close")
	map("<Esc>", function()
		if not state.help_open then -- the key that closed the `?` popup
			quit()
		end
	end)

	map("<Insert>", ":Touch ", "create file (:Touch)", { silent = false })
	map("<F7>", ":Mkdir ", "create directory (:Mkdir)", { silent = false })

	map("A", function() rename_key("end") end, "rename (cursor at end)")
	map("<F2>", function() rename_key("end") end)
	map("a", function() rename_key("ext") end, "rename (cursor before extension)")
	map("I", function() rename_key("start") end, "rename (cursor at start)")
	map("i", function() rename_key("start") end)
end

---@param path string? file or directory to start at; defaults to the current buffer
function M.open(path)
	if state then
		return
	end

	path = path or api.nvim_buf_get_name(0)
	local stat = path ~= "" and uv.fs_stat(path) or nil
	if stat then
		path = via_cwd_link(normalize(path))
	end
	local dir, select
	if stat and stat.type == "directory" then
		dir = normalize(path)
	elseif stat then
		dir, select = normalize(vim.fs.dirname(path)), vim.fs.basename(path)
	else
		dir = normalize(uv.cwd())
	end

	local st = {
		prev_win = api.nvim_get_current_win(),
		bufs = {},
		wins = {},
		cache = {},
		entries = {},
		marked = {}, -- path -> true
		editing = false, -- rename editor open: focus leaving the browser is expected
		generation = 0,
		augroup = api.nvim_create_augroup("ranger_lite", { clear = true }),
	}
	state = st

	local geo = layout()
	for _, name in ipairs({ "backdrop", "header", "parent", "current", "preview", "status" }) do
		local buf = api.nvim_create_buf(false, true)
		vim.bo[buf].bufhidden = "wipe"
		st.bufs[name] = buf
		local focus = name == "current"
		local win = api.nvim_open_win(buf, focus, vim.tbl_extend("force", geo[name], {
			relative = "editor",
			style = "minimal",
			focusable = focus,
			noautocmd = true,
		}))
		st.wins[name] = win
		local wo = vim.wo[win]
		wo.wrap = false
		wo.foldenable = false
		wo.winfixbuf = true
		wo.cursorline = name == "current" or name == "parent"
		wo.winhighlight = "NormalFloat:Normal,CursorLine:"
			.. (name == "current" and "RangerLiteSelection" or "RangerLiteParentSelection")
	end
	vim.wo[st.wins.current].scrolloff = 3
	set_keymaps(st.bufs.current)
	set_commands(st.bufs.current)

	local cur = st.bufs.current
	hide_cursor()
	api.nvim_create_autocmd("BufEnter", {
		group = st.augroup,
		buffer = cur,
		callback = hide_cursor,
	})
	api.nvim_create_autocmd("BufLeave", {
		group = st.augroup,
		buffer = cur,
		callback = restore_cursor,
	})
	api.nvim_create_autocmd("CursorMoved", {
		group = st.augroup,
		buffer = cur,
		callback = function() draw_selection() end,
	})
	-- leaving the browser (<C-w>w, a picker, :q on the float) closes all of it
	api.nvim_create_autocmd({ "WinLeave", "BufWipeout" }, {
		group = st.augroup,
		buffer = cur,
		callback = function()
			vim.schedule(function()
				if state == st and not st.editing and api.nvim_get_current_win() ~= st.wins.current then
					M.close()
				end
			end)
		end,
	})
	api.nvim_create_autocmd("VimResized", {
		group = st.augroup,
		callback = function()
			local g = layout()
			for name, win in pairs(st.wins) do
				if api.nvim_win_is_valid(win) then
					api.nvim_win_set_config(win, vim.tbl_extend("force", g[name], { relative = "editor" }))
				end
			end
			st.generation = st.generation + 1
			draw_selection(true)
		end,
	})

	show_dir(dir, select)
end

function M.toggle()
	if state then
		M.close()
	else
		M.open()
	end
end

local function set_highlights()
	local links = {
		RangerLiteDir = "Directory",
		RangerLiteLink = "Special",
		RangerLiteFile = "Normal",
		RangerLiteSize = "Comment",
		RangerLitePath = "Directory",
		RangerLiteName = "Title",
		RangerLiteStatus = "Comment",
		RangerLiteMessage = "Comment",
		RangerLiteSelection = "Visual",
		RangerLiteParentSelection = "CursorLine",
		RangerLiteMarked = "DiagnosticWarn",
		RangerLiteCut = "Comment",
		RangerLiteCopied = "DiagnosticOk",
	}
	for group, link in pairs(links) do
		api.nvim_set_hl(0, group, { link = link, default = true })
	end
	api.nvim_set_hl(0, "RangerLiteHiddenCursor", { blend = 100, nocombine = true })
end

-- Take over directory buffers (`nvim .`, `:e some/dir`) instead of netrw.
-- The directory buffer is only a placeholder: it wipes itself once a file
-- replaces it, and quitting the browser leaves an empty buffer in its place.
local function replace_netrw()
	vim.g.loaded_netrw = 1
	vim.g.loaded_netrwPlugin = 1

	local function take_over(buf)
		local name = api.nvim_buf_get_name(buf)
		-- handled once: close() refocuses this buffer, which must not reopen the browser
		if name == "" or vim.b[buf].ranger_lite_dir or vim.fn.isdirectory(name) ~= 1 or vim.bo[buf].buftype ~= "" then
			return
		end
		vim.b[buf].ranger_lite_dir = true
		vim.bo[buf].bufhidden = "wipe"
		vim.bo[buf].buflisted = false
		M.close()
		M.open(name)
	end

	api.nvim_create_autocmd("BufEnter", {
		group = api.nvim_create_augroup("ranger_lite_netrw", { clear = true }),
		callback = function(args)
			if vim.v.vim_did_enter == 1 then
				take_over(args.buf)
			else
				-- `nvim .`: wait for the UI so the layout gets the real size
				api.nvim_create_autocmd("VimEnter", {
					once = true,
					callback = function()
						if api.nvim_buf_is_valid(args.buf) and api.nvim_get_current_buf() == args.buf then
							take_over(args.buf)
						end
					end,
				})
			end
		end,
	})
end

---@param opts table?
function M.setup(opts)
	config = vim.tbl_deep_extend("force", config, opts or {})
	if config.replace_netrw then
		replace_netrw()
	end
	set_highlights()
	api.nvim_create_autocmd("ColorScheme", {
		group = api.nvim_create_augroup("ranger_lite_hl", { clear = true }),
		callback = set_highlights,
	})
	api.nvim_create_user_command(config.command, function(args)
		if args.args ~= "" then
			M.close()
			M.open(vim.fn.expand(args.args))
		else
			M.toggle()
		end
	end, { nargs = "?", complete = "file", desc = "ranger_lite file browser" })
end

return M
