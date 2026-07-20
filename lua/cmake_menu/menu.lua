-- A floating "button list" menu, driven entirely by data. The caller passes a
-- spec of entries; this module owns the window, layout, movement, the hint bar
-- and all key handling, so presentation and content evolve independently.
--
-- Features:
--   - vertically stacked entries grouped under section headers, each entry a
--     label with an optional right-aligned value and a left quick-launch key;
--   - live fields: any text field may be a function, re-resolved on every
--     render so displayed values track external state;
--   - a footer line, justified: spec.note flush-left, the selected entry's
--     keybinds plus "q close" flush-right;
--   - a data-defined keymap - keys come from the actions in the spec, not a
--     fixed set - with j/k movement that skips non-selectable rows;
--   - a single floating window that auto-sizes to its widest line (entry or
--     footer, for any possible selection) and recenters on the editor when
--     live values change its width.
--
-- Deliberately no nerd-font glyphs anywhere: only unicode that every monospace
-- font ships (─ ▌ ● ↵ →), for terminals that don't render private-use icons.
--
-- Usage:
--   local menu = require("cmake_menu.menu")
--   local handle = menu.open(spec)   -- see the spec shape below
--   -- later, from an action callback or elsewhere:
--   handle:render()                  -- refresh values in place
--   handle:close()                   -- dismiss the menu
--
-- API:
--   M.open(spec) -> handle
--       Opens the menu (closing any menu already open - only one exists at a
--       time) and returns a handle. Focus moves into the floating window.
--   handle:render()
--       Re-resolves every live field, repaints, and resizes/recenters the
--       window if widths changed. Call it after an action mutates displayed
--       state. Safe to call after the menu closed - it's then a no-op, so
--       stale async callbacks are harmless.
--   handle:close()
--       Dismisses the menu and restores the cursor and focus. Also bound to
--       q / <Esc> inside the menu.
--
-- The spec. Every text field is a string, a chunk ({text=, highlight=?}), a
-- chunk list, or a function returning any of those. Text without a highlight -
-- a plain string, or a chunk that omits `highlight` - takes the field's
-- default highlight.
--   {
--     title    = "Menu",     - window title
--     min_width = 44,        - lower bound on the window width (optional)
--     note     = <text>,     - left half of the footer line (default HL.Low)
--     select_key = "d",      - preselect the item whose `key` matches this,
--                              instead of the first selectable item (optional;
--                              falls back silently if no item has that key) -
--                              for callers that rebuild the whole spec
--                              (M.open() again) and want the selection to
--                              stick to a known entry rather than reset
--     items    = { <item>, ... },
--   }
--
-- An <item> is one shape; how it renders follows from which fields are set:
--   {
--     section = "build",     - group header: gap above, then the text plus a
--                              "─" rule filling the rest of the line. Default
--                              hl HL.Low. When set, key/label/value are ignored.
--     key     = "b",         - quick-launch key, shown as a left column;
--                              pressing it anywhere selects this entry and
--                              runs its <CR> action
--     label   = "Build",     - left-aligned, default hl HL.Normal. "\n"s split
--                              it into the label row plus full-width
--                              continuation rows below it, still part of THIS
--                              entry: they select/highlight/click as one unit
--                              (the cursor snaps back to the label row), for
--                              entries whose content doesn't fit one line
--     value   = "no target", - right-aligned on the label row, default hl
--                              HL.Normal
--     actions = { <action>, ... },  - ordered; per-entry. An item with actions
--                              is selectable; one without is skipped over
--                              (headers, spacers, static text)
--   }
--
-- An <action> is
-- { key = "<CR>", desc = "build", fn = ..., close = false?, alt_keys = {}?, hidden = false? }:
-- `key` is a normal-mode lhs (<CR>, l, <C-s>); pressing it runs fn(handle). The
-- action stays open and re-renders unless close = true, which closes the menu
-- first so follow-up work lands in the origin window. <CR> is the default
-- action - the quick-launch keys trigger it. q / <Esc> always close.
-- `alt_keys` are extra lhs's that run the same action but stay out of the
-- footer - aliases for muscle memory (old bindings, mnemonics) without
-- cluttering the hint bar.
-- `hidden = true` keeps the action itself (its `key`, not an alias) out of
-- the footer - still mapped and functional, just not advertised, for
-- nice-to-have shortcuts that aren't worth cluttering the hint bar over.
--
-- Action callbacks receive the menu handle; async callbacks (vim.ui.select)
-- should call handle:render() to refresh values in place - render() is a
-- no-op once the menu is closed, so stale callbacks are harmless.

local api = vim.api

-- Just the group-name table; M.open() requires cmake_menu.hl again directly
-- where it actually needs to call .ensure().
local HL = require("cmake_menu.hl").HL

local M = {}

---@class CMenu.TextChunk
---@field text string
---@field highlight string? highlight group; falls back to the field's default

---@alias CMenu.Text string|CMenu.TextChunk|CMenu.TextChunk[]
---@alias CMenu.TextIsh CMenu.Text|fun(): CMenu.Text

---@class CMenu.Action
---@field key string normal-mode lhs (<CR>, l, <C-s>); pressing it runs `fn`
---@field desc string shown next to `key` in the footer
---@field fn fun(handle: CMenu.Handle) receives the menu handle
---@field close boolean? close the menu before running `fn` (default: stays open and re-renders)
---@field alt_keys string[]? extra lhs's that run the same action but stay out of the footer
---@field hidden boolean? keep `key` itself out of the footer while still mapping it

---@class CMenu.Item
---@field section CMenu.TextIsh? group header: gap above + text + rule fill (default hl HL.Low); when set, key/label/value are ignored
---@field key string? quick-launch key, shown as a left column
---@field label CMenu.TextIsh? left-aligned (default hl HL.Normal); "\n" splits it into the label row
---   plus full-width continuation rows below it (still part of this entry: they select/highlight/click as one unit,
---   cursor snaps to the label row)
---@field value CMenu.TextIsh? right-aligned, label row only (default hl HL.Normal)
---@field actions CMenu.Action[]? ordered, per-entry; non-nil makes the item selectable

---@class CMenu.Spec
---@field title string? window title
---@field min_width integer? lower bound on the window width
---@field note CMenu.TextIsh? left half of the footer line (default hl HL.Low)
---@field select_key string? preselect the item whose `key` matches this instead of the first selectable item
---@field items CMenu.Item[]

local ns = api.nvim_create_namespace("cmake_menu")

--- Normalizes a text field to a chunk list with every highlight filled in:
--- a function is called first, a plain string and any chunk missing its own
--- `highlight` take `default_highlight`. Chunks are copied, never mutated, so
--- the same table can back two fields with different defaults. Chunks without
--- `text` are skipped. Not nil-tolerant: guard optional fields at the caller.
---@param default_highlight string
---@param text CMenu.TextIsh
---@return CMenu.TextChunk[]
local function resolve_text(default_highlight, text)
	-- case - fun(): CMenu.Text
	if type(text) == "function" then
		text = text()
	end

	-- case - string
	if type(text) == "string" then
		return { { text = text, highlight = default_highlight } }
	end

	-- case - CMenu.TextChunk
	---@cast text CMenu.TextChunk|CMenu.TextChunk[]
	if text.text then
		return { {
			text = text.text,
			highlight = text.highlight or default_highlight,
		} }
	end

	-- case - CMenu.TextChunk[]
	local out = {} ---@type CMenu.TextChunk[]
	for _, chunk in ipairs(text) do
		if chunk.text then -- skip nil text's
			out[#out + 1] = {
				text = chunk.text,
				highlight = chunk.highlight or default_highlight,
			}
		end
	end

	return out
end

local function dw(text)
	return vim.fn.strdisplaywidth(text)
end

local function chunks_width(chunks)
	local w = 0
	for _, c in ipairs(chunks) do
		w = w + dw(c.text)
	end
	return w
end

--- Concatenates chunk lists into a new one.
local function cat(...)
	local out = {}
	for _, chunks in ipairs({ ... }) do
		vim.list_extend(out, chunks)
	end
	return out
end

--- Flattens a chunk list into its concatenated text plus byte-range highlight
--- spans ({start_col, end_col, hl}, 0-based, end-exclusive).
local function flatten(chunks)
	local text, spans = "", {}
	for _, c in ipairs(chunks) do
		if c.highlight then
			spans[#spans + 1] = { #text, #text + #c.text, c.highlight }
		end
		text = text .. c.text
	end
	return text, spans
end

--- Splits a chunk list on "\n"s inside chunk text into one chunk list per
--- rendered line (highlights carry across the split).
local function split_chunk_lines(chunks)
	local out = { {} }
	for _, c in ipairs(chunks) do
		for i, part in ipairs(vim.split(c.text, "\n", { plain = true })) do
			if i > 1 then
				out[#out + 1] = {}
			end
			if part ~= "" then
				local line = out[#out]
				line[#line + 1] = { text = part, highlight = c.highlight }
			end
		end
	end
	return out
end

-- Pretty forms for action keys in the hint bar: named keys get a glyph,
-- modifiers become prefix glyphs (<C-s> -> ⌃s); anything else shows verbatim.
local KEY_SYMBOLS = { CR = "↵", Right = "→", Left = "←" }
local MOD_SYMBOLS = { C = "⌃", S = "⇧", M = "⌥" }
local function key_symbol(key)
	local inner = key:match("^<(.+)>$")
	if not inner then
		return key
	end
	local mods = ""
	local base = inner:gsub("([CSM])%-", function(m)
		mods = mods .. MOD_SYMBOLS[m]
		return ""
	end)
	return mods .. (KEY_SYMBOLS[base] or base)
end

--- Footer keybind chunks: one `key desc` pair per non-hidden action, with
--- "q close" always appended.
local function keys_chunks(actions)
	local chunks = {}
	local function group(key, desc)
		if #chunks > 0 then
			chunks[#chunks + 1] = { text = "  " }
		end
		chunks[#chunks + 1] = { text = key_symbol(key), highlight = HL.Glow }
		chunks[#chunks + 1] = { text = " " .. desc, highlight = HL.Low }
	end
	for _, a in ipairs(actions or {}) do
		if not a.hidden then
			group(a.key, a.desc)
		end
	end
	group("q", "close")
	return chunks
end

------------------------------------------------------------------------------
-- Row model. Every rendered line is the same shape:
--   { left = chunks, right = chunks?, fill = chunk?, item = integer? }
-- `left` sits flush-left; when `right` is present it lands flush against the
-- right margin, the space between filled by repeating `fill` (spaces by
-- default, a "─" chunk for section rules and the divider). `item` ties the
-- row to its spec item for selection/click handling.
------------------------------------------------------------------------------

local MARGIN = 2 -- blank columns kept at the right edge
local GAP = 3 -- minimum fill between a row's left and right halves

local RULE = { text = "─", highlight = HL.Rule }
local BLANK = { left = {} }

--- Minimum window width this row needs to render without truncating.
local function row_min_width(row)
	local w = chunks_width(row.left) + MARGIN
	if row.right then
		w = w + GAP + chunks_width(row.right)
	end
	return w
end

--- The row's final chunk list at the given window width.
local function row_chunks(row, width)
	if not row.right then
		return row.left
	end
	local fill = row.fill or { text = " " }
	local n = math.max(0, width - MARGIN - chunks_width(row.left) - chunks_width(row.right))
	return cat(row.left, { { text = string.rep(fill.text, n), highlight = fill.highlight } }, row.right)
end

--- The footer row for `item` being selected: spec.note left, keybinds right.
local function footer_row(spec, item)
	return {
		left = cat({ { text = " " } }, spec.note and resolve_text(HL.Low, spec.note) or {}),
		right = keys_chunks(item and item.actions),
	}
end

---@class CMenu.Handle
---@field spec CMenu.Spec the spec this menu was opened with
---@field sel integer index into spec.items of the currently selected entry
---@field buf integer menu buffer handle
---@field win integer menu floating-window handle
---@field win_config table nvim_win_get_config-shaped table kept in sync on render
---@field layout table last layout built by :_build() (lines/spans/row<->item maps/width)
---@field closed boolean? true once :close() has run
---@field augroup integer autocommand group tied to this menu's buffer
---@field saved_guicursor string? guicursor value saved while the real cursor is hidden
---@field dispatched_key string? the lhs that triggered the action currently running (set just before `fn` runs)
---@field render fun(self: CMenu.Handle) re-resolves every live field and repaints, resizing/recentering if widths changed
---@field close fun(self: CMenu.Handle) dismisses the menu, restores cursor/focus
local Menu = {}
Menu.__index = Menu

-- At most one menu at a time; opening a new one closes the previous.
local current

local function selectable(item)
	return item ~= nil and item.actions ~= nil
end

--- Resolves the spec into the full list of rows: padding, items (sections
--- with a gap above, entries with continuation rows), divider, footer.
function Menu:_rows()
	local spec = self.spec
	local rows = { BLANK }
	for i, it in ipairs(spec.items) do
		if it.section then
			if i > 1 then
				rows[#rows + 1] = BLANK
			end
			local sec = resolve_text(HL.Low, it.section)
			rows[#rows + 1] = {
				item = i,
				left = cat({ { text = "  " } }, sec, { { text = " " } }),
				right = {},
				fill = RULE,
			}
		else
			local lines = split_chunk_lines(it.label and resolve_text(HL.Normal, it.label) or {})
			rows[#rows + 1] = {
				item = i,
				left = cat({
					{ text = "  " },
					it.key and { text = it.key, highlight = HL.Glow } or { text = " " },
					{ text = "  " },
				}, lines[1]),
				right = it.value and resolve_text(HL.Normal, it.value) or nil,
			}
			for j = 2, #lines do
				rows[#rows + 1] = { item = i, left = cat({ { text = "     " } }, lines[j]) }
			end
		end
	end
	rows[#rows + 1] = BLANK
	rows[#rows + 1] = { left = { { text = " " } }, right = {}, fill = RULE }
	rows[#rows + 1] = footer_row(spec, spec.items[self.sel])
	return rows
end

--- Lays the spec out into buffer lines + highlight spans. Width is sized so
--- every row fits - including the footer for *any* possible selection, so
--- nothing wraps or resizes as the selection moves.
function Menu:_build()
	local spec = self.spec
	local rows = self:_rows()

	local width = math.max(spec.min_width or 44, dw(spec.title or "") + 8)
	for _, row in ipairs(rows) do
		width = math.max(width, row_min_width(row))
	end
	for _, it in ipairs(spec.items) do
		if selectable(it) then
			width = math.max(width, row_min_width(footer_row(spec, it)))
		end
	end

	local lines, spans, row_item, item_row, item_rows = {}, {}, {}, {}, {}
	for _, row in ipairs(rows) do
		local text, cols = flatten(row_chunks(row, width))
		for _, s in ipairs(cols) do
			spans[#spans + 1] = { #lines, s[1], s[2], s[3] }
		end
		lines[#lines + 1] = text
		local i = row.item
		if i then
			-- First row of an item is its anchor (where the cursor sits);
			-- continuation rows still select/click as the same item.
			row_item[#lines] = i
			item_row[i] = item_row[i] or #lines
			item_rows[i] = item_rows[i] or {}
			table.insert(item_rows[i], #lines)
		end
	end

	return {
		lines = lines,
		spans = spans,
		row_item = row_item,
		item_row = item_row,
		item_rows = item_rows,
		width = width,
	}
end

--- Full repaint: resolves every live field, rewrites the buffer, resizes and
--- recenters the window, and paints the selection (block highlight, the ▌
--- indicator, cursor position). Safe to call after the menu closed.
function Menu:render()
	if self.closed or not (self.buf and api.nvim_buf_is_valid(self.buf)) then
		return
	end
	local layout = self:_build()
	self.layout = layout

	vim.bo[self.buf].modifiable = true
	api.nvim_buf_set_lines(self.buf, 0, -1, false, layout.lines)
	vim.bo[self.buf].modifiable = false

	api.nvim_buf_clear_namespace(self.buf, ns, 0, -1)
	for _, s in ipairs(layout.spans) do
		api.nvim_buf_set_extmark(self.buf, ns, s[1], s[2], { end_col = s[3], hl_group = s[4] })
	end
	-- 'cursorline' only ever lights up a single row; the whole entry (label +
	-- continuation rows) is painted via extmarks instead.
	for _, r in ipairs(layout.item_rows[self.sel] or {}) do
		api.nvim_buf_set_extmark(self.buf, ns, r - 1, 0, { line_hl_group = HL.Selected })
	end
	local row = layout.item_row[self.sel]
	if row then
		api.nvim_buf_set_extmark(self.buf, ns, row - 1, 0, {
			virt_text = { { "▌", HL.Glow } },
			virt_text_pos = "overlay",
		})
	end

	if api.nvim_win_is_valid(self.win) then
		local height = math.min(#layout.lines, vim.o.lines - 4)
		self.win_config.width = layout.width
		self.win_config.height = height
		self.win_config.row = math.floor((vim.o.lines - height) / 2)
		self.win_config.col = math.floor((vim.o.columns - layout.width) / 2)
		api.nvim_win_set_config(self.win, self.win_config)
		if row then
			self:_snap(row)
		end
	end
end

--- Puts the real cursor on `row` without the CursorMoved autocmd reacting.
function Menu:_snap(row)
	self._syncing = true
	api.nvim_win_set_cursor(self.win, { row, 0 })
	self._syncing = false
end

--- Selects item `i` and repaints. Movement is a full render: live fields are
--- cheap and item counts are small, so one code path beats an incremental one.
function Menu:_select(i)
	self.sel = i
	self:render()
end

function Menu:_move(delta)
	local items = self.spec.items
	local i = self.sel
	repeat
		i = i + delta
	until not items[i] or selectable(items[i])
	if items[i] then
		self:_select(i)
	end
end

function Menu:_edge(last)
	local items = self.spec.items
	local from, to, step = 1, #items, 1
	if last then
		from, to, step = #items, 1, -1
	end
	for i = from, to, step do
		if selectable(items[i]) then
			self:_select(i)
			return
		end
	end
end

--- Runs an action. Actions with close = true close the menu first (so tasks
--- land in the origin window); the rest stay open and re-render in place.
--- @param key string? the lhs that triggered `action` (its `key` or one of its
--- `alt_keys`); exposed to `action.fn` as `self.dispatched_key`.
function Menu:_run(action, key)
	if not action then
		return
	end
	self.dispatched_key = key
	if action.close then
		self:close()
		action.fn(self)
	else
		action.fn(self)
		self:render()
	end
end

function Menu:_hide_cursor()
	if self.saved_guicursor == nil then
		self.saved_guicursor = vim.go.guicursor
		vim.go.guicursor = "a:" .. HL.HiddenCursor
	end
end

function Menu:_restore_cursor()
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

function Menu:close()
	if self.closed then
		return
	end
	self.closed = true
	self:_restore_cursor()
	pcall(api.nvim_del_augroup_by_id, self.augroup)
	-- self.win may still be unset if this handle never finished M.open() (an
	-- error partway through construction, e.g. a bad spec field, leaves
	-- `current` pointing at a half-built menu) - closing it must still be a
	-- safe no-op so the next M.open() doesn't crash trying to clean it up.
	if self.win and api.nvim_win_is_valid(self.win) then
		api.nvim_win_close(self.win, true)
	end
	if current == self then
		current = nil
	end
end

--- Buffer-local keymaps: movement, close, insert-blockers, the data-defined
--- action keys, and the quick-launch keys.
function Menu:_setup_keymaps()
	local spec = self.spec
	local opts = { buffer = self.buf, nowait = true, silent = true }
	local function map(lhs, fn)
		vim.keymap.set("n", lhs, fn, opts)
	end
	local function map_all(lhss, fn)
		for _, lhs in ipairs(lhss) do
			map(lhs, fn)
		end
	end

	map_all({ "j", "<Down>", "<Tab>" }, function() self:_move(1) end)
	map_all({ "k", "<Up>", "<S-Tab>" }, function() self:_move(-1) end)
	map("gg", function() self:_edge(false) end)
	map("G", function() self:_edge(true) end)
	map_all({ "q", "<Esc>" }, function() self:close() end)
	-- Swallow keys that would edit the buffer or beep; the action maps below
	-- override any of these a spec actually uses.
	map_all({ "i", "I", "a", "A", "o", "O", "<CR>", "<S-CR>", "<M-CR>" }, function() end)

	-- One map per distinct action key, dispatching to the selected item's
	-- action bound to it. alt_keys are extra aliases for the same action,
	-- mapped like any other key but left out of the footer.
	local keys = {} -- every lhs any action answers to
	local item_by_key = {} -- item index -> lhs -> action
	for i, it in ipairs(spec.items) do
		local by_key = {}
		item_by_key[i] = by_key
		for _, a in ipairs(it.actions or {}) do
			for _, k in ipairs(vim.list_extend({ a.key }, a.alt_keys or {})) do
				keys[k] = true
				by_key[k] = a
			end
		end
	end
	local function dispatch(key)
		self:_run(item_by_key[self.sel][key], key)
	end
	for key in pairs(keys) do
		map(key, function() dispatch(key) end)
	end
	-- Quick-launch: an item's `key` selects it and runs its <CR> action.
	for i, it in ipairs(spec.items) do
		if it.key and item_by_key[i]["<CR>"] then
			map(it.key, function()
				self:_select(i)
				dispatch("<CR>")
			end)
		end
	end
end

--- Autocommands tied to this menu's buffer: selection snapping under mouse
--- clicks / stray motions, cursor hiding while the menu has focus, and
--- self-closing when the window goes away.
function Menu:_setup_autocmds()
	self.augroup = api.nvim_create_augroup("cmake_menu_" .. self.buf, { clear = true })
	api.nvim_create_autocmd("CursorMoved", {
		group = self.augroup,
		buffer = self.buf,
		callback = function()
			if self._syncing or self.closed then
				return
			end
			-- Snap to the nearest selectable item's row.
			local items = self.spec.items
			local row = api.nvim_win_get_cursor(self.win)[1]
			local i = self.layout.row_item[row]
			if not (i and selectable(items[i])) then
				local best, best_dist
				for item_i, item_row in pairs(self.layout.item_row) do
					local dist = math.abs(item_row - row)
					if selectable(items[item_i]) and (not best_dist or dist < best_dist) then
						best, best_dist = item_i, dist
					end
				end
				i = best
			end
			if i and i ~= self.sel then
				self:_select(i)
			elseif i then
				self:_snap(self.layout.item_row[i])
			end
		end,
	})
	-- The hidden real cursor must come back whenever focus leaves the menu
	-- (pickers opened from actions, or the menu closing).
	api.nvim_create_autocmd("BufEnter", {
		group = self.augroup,
		buffer = self.buf,
		callback = function() self:_hide_cursor() end,
	})
	api.nvim_create_autocmd("BufLeave", {
		group = self.augroup,
		buffer = self.buf,
		callback = function() self:_restore_cursor() end,
	})
	api.nvim_create_autocmd("WinClosed", {
		group = self.augroup,
		pattern = tostring(self.win),
		callback = function() self:close() end,
	})
end

---@param spec CMenu.Spec
---@return CMenu.Handle handle
function M.open(spec)
	require("cmake_menu.hl").ensure()
	if current then
		current:close()
	end

	local self = setmetatable({ spec = spec, sel = 1 }, Menu)
	current = self
	local first_selectable, matched
	for i, it in ipairs(spec.items) do
		if selectable(it) then
			first_selectable = first_selectable or i
			if spec.select_key and it.key == spec.select_key then
				matched = i
			end
		end
	end
	self.sel = matched or first_selectable or 1

	self.buf = api.nvim_create_buf(false, true)
	vim.bo[self.buf].buftype = "nofile"
	vim.bo[self.buf].bufhidden = "wipe"
	vim.bo[self.buf].swapfile = false

	-- Real geometry comes from the first :render() below; nvim_open_win just
	-- needs something valid to start from.
	self.win_config = {
		relative = "editor",
		width = 1,
		height = 1,
		row = 0,
		col = 0,
		style = "minimal",
		border = "rounded",
		title = spec.title,
		title_pos = spec.title and "left" or nil,
	}
	self.win = api.nvim_open_win(self.buf, true, self.win_config)
	vim.wo[self.win].winhighlight = table.concat({
		"NormalFloat:" .. HL.Normal,
		"FloatBorder:" .. HL.Border,
		"FloatTitle:" .. HL.Title,
	}, ",")
	vim.wo[self.win].wrap = false
	vim.wo[self.win].scrolloff = 2

	self:render()
	self:_setup_keymaps()
	self:_setup_autocmds()
	self:_hide_cursor()

	return self
end

return M
-- TODO explore editable fields
