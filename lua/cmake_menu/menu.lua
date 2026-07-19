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
--   local menu = require("cpp.menu")
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
-- The spec (all text fields accept a value or a function returning one):
--   {
--     title    = "Menu",           - window title
--     min_width = 44,              - lower bound on the window width (optional)
--     on_close = function() end,   - called once when the menu closes (optional)
--     note     = "text" | function() return {{text, hl}, ...} end,
--                                  - left half of the global footer line
--     select_key = "d",           - preselect the item whose `key` matches
--                                    this, instead of the first selectable
--                                    item (optional; falls back silently if
--                                    no item has that key) - for callers that
--                                    rebuild the whole spec (M.open() again)
--                                    and want the selection to stick to a
--                                    known entry rather than reset to the top
--     actions  = { <action>, ... },  - menu-global actions; fire from any entry
--                                      and shadow a per-item action of same key
--     items    = {
--       { section = "build" },     - group header line, gap above + rule
--       { subsection = "flags" },  - lighter-weight header: no gap above, no
--                                    rule, for subdividing within a section
--       {
--         key      = "b",          - quick-launch key, shown as a left column;
--                                    pressing it anywhere selects this entry and
--                                    runs its <CR> action
--         label    = "Build",
--         value    = "no target" | {{text, hl}, ...},  - right-aligned
--         value_hl = "String",     - hl for plain-string values
--         note     = function() return {{text, hl}, ...} end,
--                                  - left half of the footer line while selected
--         actions  = { <action>, ... },  - ordered; per-entry
--                                  - "\n" in `label` splits it into the label
--                                    row plus full-width continuation rows
--                                    below it, still part of THIS entry: they
--                                    select/highlight/click as one unit (the
--                                    cursor snaps back to the label row), for
--                                    entries whose content doesn't fit one line
--       },
--     },
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

---@alias Cpp.MenuChunk { [1]: string, [2]: string? } text + optional highlight group
---@alias Cpp.MenuChunks Cpp.MenuChunk[]
---@alias Cpp.MenuText string|Cpp.MenuChunks

---@class Cpp.MenuAction
---@field key string normal-mode lhs (<CR>, l, <C-s>); pressing it runs `fn`
---@field desc string shown next to `key` in the footer
---@field fn fun(handle: Cpp.MenuHandle) receives the menu handle
---@field close boolean? close the menu before running `fn` (default: stays open and re-renders)
---@field alt_keys string[]? extra lhs's that run the same action but stay out of the footer
---@field hidden boolean? keep `key` itself out of the footer while still mapping it

---@class CMenu.Item
---@field section string? group header line (gap above + rule); not selectable
---@field subsection string? lighter-weight header (no gap, no rule); not selectable
---@field key string? quick-launch key, shown as a left column
---@field label string|(fun(): string)|nil "\n" splits it into the label row plus full-width continuation
---   rows below it (still part of this entry: they select/highlight/click as one unit, cursor snaps to the label row)
---@field label_hl string|(fun(): string)|nil hl group for `label`, applied to every line it splits into
---@field value Cpp.MenuText|(fun(): Cpp.MenuText)|nil right-aligned, label row only
---@field value_hl string|(fun(): string)|nil hl group used when `value` resolves to a plain string
---@field note Cpp.MenuChunks|(fun(): Cpp.MenuChunks)|nil left half of the footer line while this item is selected
---@field actions Cpp.MenuAction[]? ordered, per-entry

---@class Cpp.MenuSpec
---@field title string? window title
---@field min_width integer? lower bound on the window width
---@field on_close fun()? called once when the menu closes
---@field note Cpp.MenuChunks|(fun(): Cpp.MenuChunks)|nil left half of the global footer line
---@field select_key string? preselect the item whose `key` matches this instead of the first selectable item
---@field actions Cpp.MenuAction[]? menu-global actions; fire from any entry, shadow a per-item action of same key
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

--- Normalizes an item's `value` to a chunk list ({{text, hl}, ...}) or nil.
local function value_chunks(item)
	local v = resolve(item.value)
	if v == nil then
		return nil
	end
	if type(v) == "string" then
		return { { v, resolve(item.value_hl) or HL.Value } }
	end
	return v
end

-- Footer: two justified lines, each a note flush-left and its keybinds
-- flush-right with filler between. Line 1 is the selected item's (note +
-- actions); line 2 is the menu-global one (spec.note + spec.actions + close).
local FOOTER_INSET = 1 -- blank columns kept on each side, off the border
local FOOTER_GAP = 3 -- minimum space between the note and the keybinds

--- A source's (item or spec) note as chunks, or empty.
local function note_chunks(source)
	if not (source and source.note) then
		return {}
	end
	local v = resolve(source.note)
	if type(v) == "string" then
		return { { v, HL.Hint } }
	end
	return v
end

--- Right-hand keybind chunks: one `key desc` pair per action, close appended
--- when asked (the global line).
local function keys_chunks(actions, with_close)
	local chunks = {}
	local function group(key, desc)
		if #chunks > 0 then
			chunks[#chunks + 1] = { "  " }
		end
		chunks[#chunks + 1] = { key_symbol(key), HL.HintKey }
		chunks[#chunks + 1] = { " " .. desc, HL.Hint }
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

---@class Cpp.MenuHandle
---@field spec Cpp.MenuSpec the spec this menu was opened with
---@field sel integer index into spec.items of the currently selected entry
---@field buf integer menu buffer handle
---@field win integer menu floating-window handle
---@field win_config table nvim_win_get_config-shaped table kept in sync on render
---@field layout table last layout built by :_build() (lines/spans/row<->item maps/width)
---@field closed boolean? true once :close() has run
---@field augroup integer autocommand group tied to this menu's buffer
---@field saved_guicursor string? guicursor value saved while the real cursor is hidden
---@field dispatched_key string? the lhs that triggered the action currently running (set just before `fn` runs)
---@field render fun(self: Cpp.MenuHandle) re-resolves every live field and repaints, resizing/recentering if widths changed
---@field close fun(self: Cpp.MenuHandle) dismisses the menu, restores cursor/focus, runs spec.on_close
local Menu = {}
Menu.__index = Menu

-- At most one menu at a time; opening a new one closes the previous.
local current

local function selectable(item)
	return item and not item.section and item.actions ~= nil and #item.actions > 0
end

--- Splits a resolved label on "\n" into its first (label-row) line and any
--- continuation lines, the latter pre-wrapped as full-width chunk rows
--- indented to align under the label column.
local function label_lines(it)
	local text = resolve(it.label) or ""
	local split = vim.split(text, "\n", { plain = true })
	local label_hl = resolve(it.label_hl) or HL.Label
	local extra = {}
	for i = 2, #split do
		extra[#extra + 1] = { { "     " }, { split[i], label_hl } }
	end
	return split[1], label_hl, extra
end

--- Lays the spec out into buffer lines + highlight spans. Width is computed
--- over every item line *and* both footer lines, so nothing ever wraps or
--- truncates as the selection moves.
function Menu:_build()
	local items = self.spec.items

	local lefts, values, firsts, first_hls, extras = {}, {}, {}, {}, {}
	local width = math.max(self.spec.min_width or 44, dw(self.spec.title or "") + 8)
	for i, it in ipairs(items) do
		if it.section then
			width = math.max(width, dw(it.section) + 12)
		elseif it.subsection then
			width = math.max(width, dw(it.subsection) + 4)
		else
			local first, hl, extra = label_lines(it)
			firsts[i], first_hls[i], extras[i] = first, hl, extra
			lefts[i] = "  " .. (it.key or " ") .. "  " .. first
			values[i] = value_chunks(it)
			local w = dw(lefts[i]) + (values[i] and (3 + chunks_width(values[i])) or 0)
			width = math.max(width, w + 2, footer_width(note_chunks(it), keys_chunks(it.actions, false)))
			for _, chunks in ipairs(extra) do
				width = math.max(width, chunks_width(chunks) + 2)
			end
		end
	end
	width = math.max(width, footer_width(note_chunks(self.spec), keys_chunks(self.spec.actions, true)))

	local lines, spans, row_item, item_row, item_rows = {}, {}, {}, {}, {}
	local function push(chunks)
		local row, text = #lines, ""
		for _, c in ipairs(chunks) do
			if c[2] then
				spans[#spans + 1] = { row, #text, #text + #c[1], c[2] }
			end
			text = text .. c[1]
		end
		lines[#lines + 1] = text
		return #lines
	end

	push({ { "" } })
	for i, it in ipairs(items) do
		if it.section then
			if #lines > 1 then -- separator gap, unless right after the top padding
				push({ { "" } })
			end
			local rule = string.rep("─", math.max(0, width - 5 - dw(it.section)))
			push({ { "  " }, { it.section, HL.Section }, { " " }, { rule, HL.Rule } })
		elseif it.subsection then
			push({ { "  " }, { it.subsection, HL.Section } })
		else
			local chunks = {
				{ "  " },
				it.key and { it.key, HL.Key } or { " " },
				{ "  " },
				{ firsts[i], first_hls[i] },
			}
			if values[i] then
				local pad = width - 2 - dw(lefts[i]) - chunks_width(values[i])
				chunks[#chunks + 1] = { string.rep(" ", math.max(pad, 1)) }
				vim.list_extend(chunks, values[i])
			end
			local row = push(chunks)
			row_item[row], item_row[i] = i, row
			item_rows[i] = { row }
			for _, ln_chunks in ipairs(extras[i] or {}) do
				-- continuation rows: same item for selection/click, but
				-- item_row keeps pointing at the label row above (cursor
				-- always lands there, not mid-block).
				local ln_row = push(ln_chunks)
				row_item[ln_row] = i
				item_rows[i][#item_rows[i] + 1] = ln_row
			end
		end
	end
	push({ { "" } })
	push({ { " " }, { string.rep("─", width - 2), HL.Rule } })
	local item_hint_row = push(item_footer(items[self.sel], width))
	local global_hint_row = push(global_footer(self.spec, width))

	return {
		lines = lines,
		spans = spans,
		row_item = row_item,
		item_row = item_row,
		item_rows = item_rows,
		width = width,
		item_hint_row = item_hint_row,
		global_hint_row = global_hint_row,
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
			virt_text = { { "▌", HL.Indicator } },
			virt_text_pos = "overlay",
		})
	end

	-- Rewrite the contextual footer line for the newly selected item; the
	-- global line below it doesn't depend on the selection, so it stays put.
	local chunks = item_footer(self.spec.items[self.sel], layout.width)
	local text, spans = "", {}
	for _, c in ipairs(chunks) do
		if c[2] then
			spans[#spans + 1] = { #text, #text + #c[1], c[2] }
		end
		text = text .. c[1]
	end
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
		vim.go.guicursor = "a:" .. require("cmake_menu.hl").HiddenCursor
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

---@param spec Cpp.MenuSpec
---@return Cpp.MenuHandle handle
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

	self.layout = self:_build()
	local height = math.min(#self.layout.lines, vim.o.lines - 4)
	self.win_config = {
		relative = "editor",
		width = self.layout.width,
		height = height,
		row = math.floor((vim.o.lines - height) / 2),
		col = math.floor((vim.o.columns - self.layout.width) / 2),
		style = "minimal",
		border = "rounded",
		title = spec.title,
		title_pos = "left",
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

	local opts = { buffer = self.buf, nowait = true, silent = true }
	local function map(lhs, fn)
		vim.keymap.set("n", lhs, fn, opts)
	end
	map("j", function() self:_move(1) end)
	map("<Down>", function() self:_move(1) end)
	map("<Tab>", function() self:_move(1) end)
	map("k", function() self:_move(-1) end)
	map("<Up>", function() self:_move(-1) end)
	map("<S-Tab>", function() self:_move(-1) end)
	map("gg", function() self:_edge(false) end)
	map("G", function() self:_edge(true) end)
	map("q", function() self:close() end)
	map("<Esc>", function() self:close() end)
	for _, lhs in ipairs({
		"i", "I", "a", "A", "o", "O",
		"<CR>", "<S-CR>", "<M-CR>"
	}) do
		map(lhs, function() end)
	end

	-- Actions dispatch through one map per distinct key: a menu-global action
	-- (spec.actions) wins, else the selected item's action bound to that key.
	-- alt_keys are extra aliases for the same action, mapped like any other
	-- key but left out of the footer (keys_chunks only reads a.key).
	local function action_keys(a)
		return a.alt_keys and vim.list_extend({ a.key }, a.alt_keys) or { a.key }
	end
	local global_by_key = {}
	for _, a in ipairs(spec.actions or {}) do
		for _, k in ipairs(action_keys(a)) do
			global_by_key[k] = a
		end
	end
	local function item_action(it, key)
		for _, a in ipairs(it and it.actions or {}) do
			for _, k in ipairs(action_keys(a)) do
				if k == key then
					return a
				end
			end
		end
	end
	local function dispatch(key)
		self:_run(global_by_key[key] or item_action(spec.items[self.sel], key), key)
	end
	local keys = {}
	for _, a in ipairs(spec.actions or {}) do
		for _, k in ipairs(action_keys(a)) do
			keys[k] = true
		end
	end
	for _, it in ipairs(spec.items) do
		for _, a in ipairs(it.actions or {}) do
			for _, k in ipairs(action_keys(a)) do
				keys[k] = true
			end
		end
	end
	for key in pairs(keys) do
		map(key, function() dispatch(key) end)
	end
-- Quick-launch: an item's `key` selects it and runs its <CR> action.
	for i, it in ipairs(spec.items) do
		if it.key and item_action(it, "<CR>") then
			map(it.key, function()
				self:_set_sel(i)
				dispatch("<CR>")
			end)
		end
	end

	self.augroup = api.nvim_create_augroup("cpp_menu_" .. self.buf, { clear = true })
	-- Keep selection consistent under mouse clicks / stray motions: snap the
	-- cursor to the nearest selectable row.
	api.nvim_create_autocmd("CursorMoved", {
		group = self.augroup,
		buffer = self.buf,
		callback = function()
			if self._syncing or self.closed then
				return
			end
			local row = api.nvim_win_get_cursor(self.win)[1]
			local i = self.layout.row_item[row]
			if not (i and selectable(spec.items[i])) then
				local best, best_dist
				for item_i, item_row in pairs(self.layout.item_row) do
					local dist = math.abs(item_row - row)
					if selectable(spec.items[item_i]) and (not best_dist or dist < best_dist) then
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
	-- (pickers opened from `expand`, or the menu closing).
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
	self:_hide_cursor()

	return self
end

return M
-- TODO explore editable fields
