-- A floating "button list" menu, driven entirely by data. The caller passes a
-- spec of entries; this module owns the window, layout, movement, the hint bar
-- and all key handling, so presentation and content evolve independently.
--
-- Features:
--   - vertically stacked entries grouped under section headers, each entry a
--     label with an optional right-aligned value and a left quick-launch key;
--   - live fields: any text field may be a function, re-resolved on every
--     render so displayed values track external state;
--   - a two-line footer, each line justified with a note flush-left and its
--     keybinds flush-right: line 1 tracks the selected entry (its note +
--     actions), line 2 is menu-global (spec.note + spec.actions + close);
--   - a data-defined keymap - keys come from the actions in the spec, not a
--     fixed set - with j/k movement that skips section headers;
--   - a single floating window that auto-sizes to its widest line (entry or
--     footer) and recenters on the editor when live values change its width.
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
--       Dismisses the menu, restores the cursor and focus, and runs
--       spec.on_close. Also bound to q / <Esc> inside the menu.
--
-- The spec. Every text field is a string, a chunk list ({{text, hl}, ...}
-- where hl is optional per chunk), or a function returning either - plain
-- strings get the field's default highlight.
--   {
--     title    = "Menu",           - window title
--     min_width = 44,              - lower bound on the window width (optional)
--     on_close = function() end,   - called once when the menu closes (optional)
--     note     = <text>,           - left half of the global footer line
--     select_key = "d",           - preselect the item whose `key` matches
--                                    this, instead of the first selectable
--                                    item (optional; falls back silently if
--                                    no item has that key) - for callers that
--                                    rebuild the whole spec (M.open() again)
--                                    and want the selection to stick to a
--                                    known entry rather than reset to the top
--     actions  = { <action>, ... },  - menu-global actions; fire from any entry
--                                      and shadow a per-item action of same key
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
--     note    = <text>,      - left half of the footer line while selected
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

---@alias CMenu.Chunk { [1]: string, [2]: string? } text + optional highlight group
---@alias CMenu.Chunks CMenu.Chunk[]
---@alias CMenu.Text string|CMenu.Chunks

---@class CMenu.Action
---@field key string normal-mode lhs (<CR>, l, <C-s>); pressing it runs `fn`
---@field desc string shown next to `key` in the footer
---@field fn fun(handle: CMenu.Handle) receives the menu handle
---@field close boolean? close the menu before running `fn` (default: stays open and re-renders)
---@field alt_keys string[]? extra lhs's that run the same action but stay out of the footer
---@field hidden boolean? keep `key` itself out of the footer while still mapping it

---@class CMenu.Item
---@field section CMenu.Text|(fun(): CMenu.Text)|nil group header: gap above + text + rule fill (default hl HL.Low); when set, key/label/value are ignored
---@field key string? quick-launch key, shown as a left column
---@field label CMenu.Text|(fun(): CMenu.Text)|nil left-aligned (default hl HL.Normal); "\n" splits it into the label row
---   plus full-width continuation rows below it (still part of this entry: they select/highlight/click as one unit,
---   cursor snaps to the label row)
---@field value CMenu.Text|(fun(): CMenu.Text)|nil right-aligned, label row only (default hl HL.Normal)
---@field note CMenu.Text|(fun(): CMenu.Text)|nil left half of the footer line while this item is selected (default hl HL.Low)
---@field actions CMenu.Action[]? ordered, per-entry; non-nil makes the item selectable

---@class CMenu.Spec
---@field title string? window title
---@field min_width integer? lower bound on the window width
---@field on_close fun()? called once when the menu closes
---@field note CMenu.Text|(fun(): CMenu.Text)|nil left half of the global footer line (default hl HL.Low)
---@field select_key string? preselect the item whose `key` matches this instead of the first selectable item
---@field actions CMenu.Action[]? menu-global actions; fire from any entry, shadow a per-item action of same key
---@field items CMenu.Item[]

local ns = api.nvim_create_namespace("cpp_menu")
local ns_sel = api.nvim_create_namespace("cpp_menu_sel")

local function resolve(v)
	return type(v) == "function" and v() or v
end

local function dw(text)
	return vim.fn.strdisplaywidth(text)
end

local function chunks_width(chunks)
	local w = 0
	for _, c in ipairs(chunks) do
		w = w + dw(c[1])
	end
	return w
end

--- Flattens a chunk list into its concatenated text plus byte-range highlight
--- spans ({start_col, end_col, hl}, 0-based, end-exclusive).
local function flatten(chunks)
	local text, spans = "", {}
	for _, c in ipairs(chunks) do
		if c[2] then
			spans[#spans + 1] = { #text, #text + #c[1], c[2] }
		end
		text = text .. c[1]
	end
	return text, spans
end

--- Normalizes a text field (string | chunks | function returning either) to a
--- chunk list, plain strings taking `default_hl`; nil stays nil.
local function text_chunks(v, default_hl)
	v = resolve(v)
	if v == nil then
		return nil
	end
	if type(v) == "string" then
		return { { v, default_hl } }
	end
	return v
end

--- Splits a chunk list on "\n"s inside chunk text into one chunk list per
--- rendered line (highlights carry across the split).
local function split_chunk_lines(chunks)
	local out = { {} }
	for _, c in ipairs(chunks) do
		for i, part in ipairs(vim.split(c[1], "\n", { plain = true })) do
			if i > 1 then
				out[#out + 1] = {}
			end
			if part ~= "" then
				local line = out[#out]
				line[#line + 1] = { part, c[2] }
			end
		end
	end
	return out
end

-- Pretty forms for action keys in the hint bar; anything else shows verbatim,
-- with <C-x> collapsed to ^x.
local KEY_SYMBOLS = {
	["<CR>"] = "↵",
	["<Right>"] = "→",
	["<Left>"] = "←",
}
-- Modifier prefixes peeled off one at a time (order they appear in the lhs),
-- each rendered as a short glyph prepended to the base key's symbol.
local MOD_SYMBOLS = {
	{ pat = "^<C%-(.+)>$", glyph = "⌃" },
	{ pat = "^<S%-(.+)>$", glyph = "⇧" },
	{ pat = "^<M%-(.+)>$", glyph = "⌥" },
}
local function key_symbol(key)
	if KEY_SYMBOLS[key] then
		return KEY_SYMBOLS[key]
	end
	local prefix = ""
	local rest = key
	while true do
		local matched = false
		for _, mod in ipairs(MOD_SYMBOLS) do
			local inner = rest:match(mod.pat)
			if inner then
				prefix = prefix .. mod.glyph
				rest = "<" .. inner .. ">"
				matched = true
				break
			end
		end
		if not matched then
			break
		end
	end
	if prefix == "" then
		return key
	end
	return prefix .. (KEY_SYMBOLS[rest] or rest:match("^<(.+)>$") or rest)
end

-- Footer: two justified lines, each a note flush-left and its keybinds
-- flush-right with filler between. Line 1 is the selected item's (note +
-- actions); line 2 is the menu-global one (spec.note + spec.actions + close).
local FOOTER_INSET = 1 -- blank columns kept on each side, off the border
local FOOTER_GAP = 3 -- minimum space between the note and the keybinds

--- A source's (item or spec) note as chunks, or empty.
local function note_chunks(source)
	return source and text_chunks(source.note, HL.Low) or {}
end

--- Right-hand keybind chunks: one `key desc` pair per action, close appended
--- when asked (the global line).
local function keys_chunks(actions, with_close)
	local chunks = {}
	local function group(key, desc)
		if #chunks > 0 then
			chunks[#chunks + 1] = { "  " }
		end
		chunks[#chunks + 1] = { key_symbol(key), HL.Glow }
		chunks[#chunks + 1] = { " " .. desc, HL.Low }
	end
	for _, a in ipairs(actions or {}) do
		if not a.hidden then
			group(a.key, a.desc)
		end
	end
	if with_close then
		group("q", "close")
	end
	return chunks
end

--- Minimum window width a footer line with these two halves needs.
local function footer_width(note, keys)
	return 2 * FOOTER_INSET + FOOTER_GAP + chunks_width(note) + chunks_width(keys)
end

--- One justified footer line: inset, note, filler, keys - so the keys land at
--- the right edge (also inset). Width is sized in _build so it never underflows.
local function footer_line(note, keys, width)
	local fill = math.max(FOOTER_GAP, width - 2 * FOOTER_INSET - chunks_width(note) - chunks_width(keys))
	local out = { { string.rep(" ", FOOTER_INSET) } }
	vim.list_extend(out, note)
	out[#out + 1] = { string.rep(" ", fill) }
	vim.list_extend(out, keys)
	return out
end

--- Line 1 (selected item) and line 2 (menu-global) of the footer.
local function item_footer(item, width)
	return footer_line(note_chunks(item), keys_chunks(item and item.actions, false), width)
end
local function global_footer(spec, width)
	return footer_line(note_chunks(spec), keys_chunks(spec.actions, true), width)
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
---@field close fun(self: CMenu.Handle) dismisses the menu, restores cursor/focus, runs spec.on_close
local Menu = {}
Menu.__index = Menu

-- At most one menu at a time; opening a new one closes the previous.
local current

local function selectable(item)
	return item ~= nil and item.actions ~= nil
end

--- Lays the spec out into buffer lines + highlight spans. Width is computed
--- over every item line *and* both footer lines, so nothing ever wraps or
--- truncates as the selection moves.
function Menu:_build()
	local spec = self.spec
	local items = spec.items

	-- Pass 1: resolve every live field once and find the width that fits every
	-- line (entries, continuations and both footers).
	local prep = {} -- per-item resolved fields, indexed like `items`
	local width = math.max(spec.min_width or 44, dw(spec.title or "") + 8)
	for i, it in ipairs(items) do
		local p = {}
		prep[i] = p
		if it.section then
			p.section = text_chunks(it.section, HL.Low)
			width = math.max(width, chunks_width(p.section) + 12)
		else
			local rows = split_chunk_lines(text_chunks(it.label, HL.Normal) or {})
			p.label = table.remove(rows, 1)
			p.extra = rows
			p.left_w = 5 + chunks_width(p.label) -- "  k  " column + label
			p.value = text_chunks(it.value, HL.Normal)
			local w = p.left_w + (p.value and (3 + chunks_width(p.value)) or 0)
			width = math.max(width, w + 2, footer_width(note_chunks(it), keys_chunks(it.actions, false)))
			for _, row in ipairs(rows) do
				width = math.max(width, 5 + chunks_width(row) + 2)
			end
		end
	end
	width = math.max(width, footer_width(note_chunks(spec), keys_chunks(spec.actions, true)))

	-- Pass 2: emit the lines.
	local lines, spans, row_item, item_row, item_rows = {}, {}, {}, {}, {}
	local function push(chunks)
		local text, cols = flatten(chunks)
		for _, s in ipairs(cols) do
			spans[#spans + 1] = { #lines, s[1], s[2], s[3] }
		end
		lines[#lines + 1] = text
		return #lines
	end

	push({ { "" } })
	for i, it in ipairs(items) do
		local p = prep[i]
		local chunks
		if p.section then
			if #lines > 1 then -- separator gap, unless right after the top padding
				push({ { "" } })
			end
			chunks = { { "  " } }
			vim.list_extend(chunks, p.section)
			chunks[#chunks + 1] = { " " }
			chunks[#chunks + 1] = { string.rep("─", math.max(0, width - 5 - chunks_width(p.section))), HL.Rule }
		else
			chunks = {
				{ "  " },
				it.key and { it.key, HL.Glow } or { " " },
				{ "  " },
			}
			vim.list_extend(chunks, p.label)
			if p.value then
				local pad = width - 2 - p.left_w - chunks_width(p.value)
				chunks[#chunks + 1] = { string.rep(" ", math.max(pad, 1)) }
				vim.list_extend(chunks, p.value)
			end
		end
		local row = push(chunks)
		row_item[row], item_row[i] = i, row
		item_rows[i] = { row }
		for _, extra_row in ipairs(p.extra or {}) do
			-- continuation rows: same item for selection/click, but
			-- item_row keeps pointing at the label row above (cursor
			-- always lands there, not mid-block).
			local ln = { { "     " } }
			vim.list_extend(ln, extra_row)
			local ln_row = push(ln)
			row_item[ln_row] = i
			item_rows[i][#item_rows[i] + 1] = ln_row
		end
	end
	push({ { "" } })
	push({ { " " }, { string.rep("─", width - 2), HL.Rule } })
	local item_hint_row = push(item_footer(items[self.sel], width))
	push(global_footer(spec, width))

	return {
		lines = lines,
		spans = spans,
		row_item = row_item,
		item_row = item_row,
		item_rows = item_rows,
		width = width,
		item_hint_row = item_hint_row,
	}
end

--- Moves the selection: cursorline, the ▌ indicator, and the contextual
--- (line 1) footer.
function Menu:_set_sel(i)
	if self.closed then
		return
	end
	self.sel = i
	local layout = self.layout
	local row = layout.item_row[i]

	if row and api.nvim_win_is_valid(self.win) then
		self._syncing = true
		api.nvim_win_set_cursor(self.win, { row, 0 })
		self._syncing = false
	end

	api.nvim_buf_clear_namespace(self.buf, ns_sel, 0, -1)
	-- Highlight every row of the entry (label + any `lines` continuations),
	-- not just the one the real cursor sits on: 'cursorline' only ever lights
	-- up a single row, so the block is painted manually via extmarks instead.
	for _, r in ipairs(layout.item_rows[i] or {}) do
		api.nvim_buf_set_extmark(self.buf, ns_sel, r - 1, 0, {
			line_hl_group = HL.Selected,
		})
	end
	if row then
		api.nvim_buf_set_extmark(self.buf, ns_sel, row - 1, 0, {
			virt_text = { { "▌", HL.Glow } },
			virt_text_pos = "overlay",
		})
	end

	-- Rewrite the contextual footer line for the newly selected item; the
	-- global line below it doesn't depend on the selection, so it stays put.
	local text, spans = flatten(item_footer(self.spec.items[self.sel], layout.width))
	vim.bo[self.buf].modifiable = true
	api.nvim_buf_set_lines(self.buf, layout.item_hint_row - 1, layout.item_hint_row, false, { text })
	vim.bo[self.buf].modifiable = false
	api.nvim_buf_clear_namespace(self.buf, ns, layout.item_hint_row - 1, layout.item_hint_row)
	for _, s in ipairs(spans) do
		api.nvim_buf_set_extmark(self.buf, ns, layout.item_hint_row - 1, s[1], {
			end_col = s[2],
			hl_group = s[3],
		})
	end
end

--- Full re-render: resolves every live field again and resizes/recenters the
--- window if values changed width. Safe to call after the menu closed.
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

	if api.nvim_win_is_valid(self.win) then
		local height = math.min(#layout.lines, vim.o.lines - 4)
		self.win_config.width = layout.width
		self.win_config.height = height
		self.win_config.row = math.floor((vim.o.lines - height) / 2)
		self.win_config.col = math.floor((vim.o.columns - layout.width) / 2)
		api.nvim_win_set_config(self.win, self.win_config)
	end
	self:_set_sel(self.sel)
end

function Menu:_move(delta)
	local items = self.spec.items
	local i = self.sel
	repeat
		i = i + delta
	until not items[i] or selectable(items[i])
	if items[i] then
		self:_set_sel(i)
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
			self:_set_sel(i)
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
	if self.spec.on_close then
		pcall(self.spec.on_close)
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

	-- Actions dispatch through one map per distinct key: a menu-global action
	-- (spec.actions) wins, else the selected item's action bound to that key.
	-- alt_keys are extra aliases for the same action, mapped like any other
	-- key but left out of the footer (keys_chunks only reads a.key).
	local keys = {} -- every lhs any action answers to
	local global_by_key = {} -- lhs -> menu-global action
	local item_by_key = {} -- item index -> lhs -> action
	local function index(actions, by_key)
		for _, a in ipairs(actions or {}) do
			for _, k in ipairs(vim.list_extend({ a.key }, a.alt_keys or {})) do
				keys[k] = true
				by_key[k] = a
			end
		end
	end
	index(spec.actions, global_by_key)
	for i, it in ipairs(spec.items) do
		item_by_key[i] = {}
		index(it.actions, item_by_key[i])
	end
	local function dispatch(key)
		self:_run(global_by_key[key] or item_by_key[self.sel][key], key)
	end
	for key in pairs(keys) do
		map(key, function() dispatch(key) end)
	end
	-- Quick-launch: an item's `key` selects it and runs its <CR> action.
	for i, it in ipairs(spec.items) do
		if it.key and item_by_key[i]["<CR>"] then
			map(it.key, function()
				self:_set_sel(i)
				dispatch("<CR>")
			end)
		end
	end
end

--- Autocommands tied to this menu's buffer: selection snapping under mouse
--- clicks / stray motions, cursor hiding while the menu has focus, and
--- self-closing when the window goes away.
function Menu:_setup_autocmds()
	self.augroup = api.nvim_create_augroup("cpp_menu_" .. self.buf, { clear = true })
	api.nvim_create_autocmd("CursorMoved", {
		group = self.augroup,
		buffer = self.buf,
		callback = function()
			if self._syncing or self.closed then
				return
			end
			-- Snap the cursor to the nearest selectable row.
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
			if i then
				self:_set_sel(i)
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
	vim.bo[self.buf].filetype = "cppmenu"

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
