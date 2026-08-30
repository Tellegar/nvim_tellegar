--- cmake_menu.float — three borderless floats presented as one window.
---
--- From the caller's standpoint this is a single surface; it knows nothing about
--- its contents. Its whole job is to manage the three real windows underneath.
--- Responsibilities, and nothing more:
---   1. window creation      three borderless floats stacked as [header, body,
---                           footer]; singleton — reopening closes the old set.
---   2. mapping registration  base keys (q/Esc close, debug copy) at open();
---                           callers layer their own on top via Float:map()
---   3. a render step         set_lines + set_extmarks, per pane
---   4. cursor visibility     the real cursor is hidden while the body has
---                           focus, restored on BufLeave/close
---
--- There is no content model. A caller ("tab") supplies spec.render(float) and
--- builds each pane by hand via float.header / float.body / float.footer:
---   pane:set_lines(lines); pane:hl(row, col, opts); pane:width().
---
--- The body is the only focusable window; header and footer immediately bounce
--- focus back to it, acting as a border extension of the body. Mappings are
--- therefore set on the body alone. Closing any one window closes all three.

local M = {}
local ns = vim.api.nvim_create_namespace("cmake_menu")
local HL = require("cmake_menu.hl")

--- A single window+buffer the caller renders into by hand.
---@class CMenu.Pane
---@field buf integer
---@field win integer
local Pane = {}
Pane.__index = Pane

--- Current inner width of the pane, for right-aligning values.
function Pane:width()
	return vim.api.nvim_win_get_width(self.win)
end

--- Replace the whole pane with `lines` and clear its old highlights.
---@param lines string[]
function Pane:set_lines(lines)
	vim.bo[self.buf].modifiable = true
	vim.api.nvim_buf_set_lines(self.buf, 0, -1, false, lines)
	vim.bo[self.buf].modifiable = false
	vim.api.nvim_buf_clear_namespace(self.buf, ns, 0, -1)
end

--- Add one highlight. `opts` is passed straight to nvim_buf_set_extmark and must
--- carry hl_group (plus end_col / hl_eol / priority as needed). Call after
--- set_lines, which clears the namespace.
---@param row integer   -- 0-based line
---@param col integer   -- 0-based byte column
---@param opts table
function Pane:hl(row, col, opts)
	vim.api.nvim_buf_set_extmark(self.buf, ns, row, col, opts)
end

---@class CMenu.Spec
---@field render fun(float: CMenu.Float)  -- build the panes by hand
---@field header_height integer?          -- default 1
---@field footer_height integer?          -- default 1

---@class CMenu.Float
---@field header CMenu.Pane
---@field body CMenu.Pane
---@field footer CMenu.Pane
---@field spec CMenu.Spec
---@field augroup integer?
---@field closing boolean?
---@field saved_guicursor string?  -- guicursor before _hide_cursor, nil while restored
local Float = {}
Float.__index = Float

---@type CMenu.Float
local self

local function close()
	if self.closing then return end
	self.closing = true
	self:_restore_cursor()
	if self.augroup then
		pcall(vim.api.nvim_del_augroup_by_id, self.augroup)
		self.augroup = nil
	end
	for _, p in ipairs({ self.header, self.body, self.footer }) do
		if p and p.win and vim.api.nvim_win_is_valid(p.win) then
			pcall(vim.api.nvim_win_close, p.win, true) -- bufhidden=wipe deletes the buffer
		end
	end
	self.header, self.body, self.footer = nil, nil, nil
	self.closing = false
end

local function setup_window()
	close()

	local width  = 80
	local height = 24
	local hh = self.spec.header_height or 1
	local fh = self.spec.footer_height or 1
	local bh = height - hh - fh
	local col = math.floor((vim.o.columns - width) / 2)
	local top = math.floor((vim.o.lines - height) / 2) - 1

	local function pane(row, h, enter, winhighlight)
		local buf = vim.api.nvim_create_buf(false, true)
		vim.bo[buf].bufhidden = "wipe"
		vim.bo[buf].filetype = "cmake_menu" -- see which-key.lua: disable.ft
		local win = vim.api.nvim_open_win(buf, enter or false, {
			relative = "editor",
			width    = width,
			height   = h,
			row      = row,
			col      = col,
			style    = "minimal",
			border   = "none",
		})
		if winhighlight then
			-- append, don't replace: style="minimal" already sets its own
			-- winhighlight (EndOfBuffer:..., hiding the `~` tildes) - clobbering
			-- it would bring those back on a pane shorter than its window.
			local existing = vim.wo[win].winhighlight
			vim.wo[win].winhighlight = existing ~= "" and (existing .. "," .. winhighlight) or winhighlight
		end
		return setmetatable({ buf = buf, win = win }, Pane)
	end

	self.header = pane(top,           hh, false)
	self.body   = pane(top + hh,      bh, true) -- focus starts on the body
	-- footer bg set a shade off the body's via HL.FooterBg (see cmake_menu.hl)
	self.footer = pane(top + hh + bh, fh, false, "NormalFloat:" .. HL.FooterBg)
end

local function setup_autocmds()
	self.augroup = vim.api.nvim_create_augroup("CMenu", { clear = true })

	-- closing any of the three windows closes the other two
	for _, p in ipairs({ self.header, self.body, self.footer }) do
		vim.api.nvim_create_autocmd("WinClosed", {
			group = self.augroup,
			pattern = tostring(p.win),
			callback = function() close() end,
		})
	end

	-- header/footer are display-only: entering either bounces focus back to the
	-- body. WinEnter can't be scoped to a window by pattern (its pattern matches
	-- the buffer name, not the window id), so we register one autocmd and filter
	-- to just those two windows in the callback -- the body never rebounces.
	local rebounce = { [self.header.win] = true, [self.footer.win] = true }
	vim.api.nvim_create_autocmd("WinEnter", {
		group = self.augroup,
		callback = function()
			if not self.body or not vim.api.nvim_win_is_valid(self.body.win) then return end
			if rebounce[vim.api.nvim_get_current_win()] then
				vim.api.nvim_set_current_win(self.body.win)
			end
		end,
	})

	vim.api.nvim_create_autocmd("BufEnter", {
		group = self.augroup,
		buffer = self.body.buf,
		callback = function() self:_hide_cursor() end,
	})
	vim.api.nvim_create_autocmd("BufLeave", {
		group = self.augroup,
		buffer = self.body.buf,
		callback = function() self:_restore_cursor() end,
	})
end

-- Debug: yank all three panes, top to bottom, as one blob to the + clipboard.
-- Each pane is padded with blank lines to fill its window, so the copy reflects
-- the full virtual window (>= 24 lines); a body longer than its window keeps all
-- its lines.
local function copy_all()
	local out = {}
	for _, p in ipairs({ self.header, self.body, self.footer }) do
		if p and vim.api.nvim_buf_is_valid(p.buf) then
			local lines = vim.api.nvim_buf_get_lines(p.buf, 0, -1, false)
			vim.list_extend(out, lines)
			for _ = #lines + 1, vim.api.nvim_win_get_height(p.win) do
				out[#out + 1] = ""
			end
		end
	end
	vim.fn.setreg("+", table.concat(out, "\n"))
	vim.notify("cmake_menu: copied " .. #out .. " lines to +")
end

-- disable all keybinds (probably not complete)
local function setup_mappings_clear()
	local function set(modes, lhs, rhs, opts)
		opts = opts or {}
		opts.buffer = self.body.buf
		if opts.nowait == nil then opts.nowait = true end
		if opts.silent == nil then opts.silent = true end
		vim.keymap.set(modes, lhs, rhs, opts)
	end

	for b = 32, 126 do
		local c = string.char(b)
		set("n", c, "<Nop>")
		set("n", "<C-"..c..">", "<Nop>")
	end

	local named_keys = {
		"<CR>", "<C-CR>", "<S-CR>", "<BS>", "<Tab>", "<Del>", "<Esc>",
		"<Up>", "<Down>", "<Left>", "<Right>",
		"<Home>", "<End>", "<PageUp>", "<PageDown>",
		"<F1>", "<F2>", "<F3>", "<F4>", "<F5>", "<F6>",
		"<F7>", "<F8>", "<F9>", "<F10>", "<F11>", "<F12>",
	}
	for _, k in ipairs(named_keys) do
		set("n", k, "<Nop>")
	end

	-- don't move the cursor
	set("n", "<LeftMouse>", "<Nop>")

	-- keep commands
	set("n", ":", ":", { silent = false })
end
-- Mappings live only on the body: it is the sole focusable window (header and
-- footer immediately bounce focus back), so it's the only place keys can land.
local function setup_mappings()
	local function set(modes, lhs, rhs, opts)
		opts = opts or {}
		opts.buffer = self.body.buf
		if opts.nowait == nil then opts.nowait = true end
		if opts.silent == nil then opts.silent = true end
		vim.keymap.set(modes, lhs, rhs, opts)
	end

	set("n", "q", function() close() end)
	set("n", "<Esc>", function() close() end)

	-- for debug
	set("n", "<C-c>", copy_all)
end

--- Rebuild every pane from the spec's render callback.
function Float:render()
	self.spec.render(self)
end

---@class CMenu.Mapping
---@field modes? string|string[]
---@field lhs string
---@field rhs string|function
---@field opts? vim.keymap.set.Opts

--- Register additional buffer-local keymaps on the body, layered on top of
--- the base q/Esc/close and debug bindings set up by open(). Call once per
--- open() (the body buffer -- and any keymaps on it -- is wiped and recreated
--- on every open(), so this doesn't survive a tab switch); call as many times
--- as convenient, e.g. once per group of mappings.
---@param mapping CMenu.Mapping|CMenu.Mapping[]
function Float:map(mapping)
	local mappings = mapping.lhs and { mapping } or mapping
	for _, m in ipairs(mappings) do
		vim.keymap.set(m.modes or "n", m.lhs, m.rhs, {
			buffer = self.body.buf,
			nowait = true,
			silent = true,
		})
	end
end

function Float:_hide_cursor()
	if self.saved_guicursor == nil then
		self.saved_guicursor = vim.go.guicursor
		vim.go.guicursor = "a:" .. HL.HiddenCursor
	end
end

function Float:_restore_cursor()
	if self.saved_guicursor ~= nil then
		local saved = self.saved_guicursor
		self.saved_guicursor = nil
		-- Transitional "a:" forces a cursor refresh even if `saved` is empty.
		vim.go.guicursor = "a:"
		if saved ~= "" then
			vim.go.guicursor = saved
		end
	end
end

function Float:close()
	close()
end

---@param spec CMenu.Spec?
---@return CMenu.Float
function M.open(spec)
	self = self or setmetatable({}, Float)
	self.spec = spec or self.spec

	setup_window()
	self:_hide_cursor()
	setup_autocmds()
	setup_mappings_clear()
	setup_mappings()
	self:render()

	return self
end

return M
