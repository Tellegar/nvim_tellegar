-- Floating "button list" menu for :Cpp - rendering and interaction only.
-- cpp.lua describes entries (label / value / actions); this module owns the
-- window, layout, movement, quick-launch keys and the hint bar, so the two
-- concerns can evolve independently.
--
-- Deliberately no nerd-font glyphs anywhere: only unicode that every
-- monospace font ships (─ ▌ ● ↵ →), since the terminal font here doesn't
-- render private-use-area icons.
--
-- Item spec (text fields accept either a value or a function returning one,
-- so re-renders pick up live state):
--   { section = "build" }                        - group header line
--   {
--     key      = "b",              - quick-launch key, shown as a left column;
--                                    pressing it anywhere triggers `primary`
--     label    = "Build",
--     value    = "no target" | {{text, hl}, ...},  - right-aligned
--     value_hl = "String",         - hl for plain-string values
--     note     = function() return {{text, hl}, ...} end,
--                                  - status chunks prefixed to the hint bar
--     primary  = { desc = "build", fn = ..., close = false? },
--                                  - <CR> / quick key; closes the menu first
--                                    unless close = false
--     expand   = { desc = "pick target", fn = ... },  - l / <Right>, stays open
--     save     = { desc = "save", fn = ... },         - <C-s>, stays open
--   }
-- Action callbacks receive the menu handle; async callbacks (vim.ui.select)
-- should call handle:render() to refresh values in place - render() is a
-- no-op once the menu is closed, so stale callbacks are harmless.

local api = vim.api

local M = {}

local ns = api.nvim_create_namespace("cpp_menu")
local ns_sel = api.nvim_create_namespace("cpp_menu_sel")

-- All colors route through CppMenu* groups, default-linked so a colorscheme
-- can restyle the menu without touching this file.
local HLS = {
	CppMenuNormal = "NormalFloat",
	CppMenuBorder = "FloatBorder",
	CppMenuTitle = "FloatTitle",
	CppMenuSelected = "CursorLine",
	CppMenuIndicator = "Special",
	CppMenuKey = "Special",
	CppMenuLabel = "Normal",
	CppMenuValue = "Comment",
	CppMenuSection = "Comment",
	CppMenuRule = "NonText",
	CppMenuHint = "Comment",
	CppMenuHintKey = "Special",
}

local function ensure_hl()
	for name, link in pairs(HLS) do
		api.nvim_set_hl(0, name, { link = link, default = true })
	end
	-- blend = 100 makes the real cursor invisible while it sits in the menu
	-- (the ▌ indicator plays that role instead); not default = true, since
	-- this one must win over anything a colorscheme defines.
	api.nvim_set_hl(0, "CppMenuHiddenCursor", { blend = 100, nocombine = true })
end

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

--- Normalizes an item's `value` to a chunk list ({{text, hl}, ...}) or nil.
local function value_chunks(item)
	local v = resolve(item.value)
	if v == nil then
		return nil
	end
	if type(v) == "string" then
		return { { v, resolve(item.value_hl) or "CppMenuValue" } }
	end
	return v
end

--- Hint-bar chunks for an item: its note, then one `key action` pair per
--- available action, then the ever-present close hint.
local function hint_chunks(item)
	local chunks = {}
	local function push(text, hl)
		chunks[#chunks + 1] = { text, hl }
	end
	local function gap()
		if #chunks > 0 then
			push("   ")
		end
	end
	if item and item.note then
		vim.list_extend(chunks, resolve(item.note))
	end
	local function action(sym, a)
		if a then
			gap()
			push(sym, "CppMenuHintKey")
			push(" " .. a.desc, "CppMenuHint")
		end
	end
	if item then
		action("↵", item.primary)
		action("→", item.expand)
		action("^s", item.save)
	end
	gap()
	push("q", "CppMenuHintKey")
	push(" close", "CppMenuHint")
	return chunks
end

local Menu = {}
Menu.__index = Menu

-- At most one menu at a time; opening a new one closes the previous.
local current

local function selectable(item)
	return item and not item.section and (item.primary or item.expand or item.save) ~= nil
end

function Menu:_hint_line(width)
	local chunks = hint_chunks(self.spec.items[self.sel])
	local pad = math.max(1, math.floor((width - chunks_width(chunks)) / 2))
	local out = { { string.rep(" ", pad) } }
	vim.list_extend(out, chunks)
	return out
end

--- Lays the spec out into buffer lines + highlight spans. Width is computed
--- over every item line *and* every item's hint bar, so neither ever wraps
--- or truncates as the selection moves.
function Menu:_build()
	local items = self.spec.items

	local lefts, values = {}, {}
	local width = math.max(self.spec.min_width or 44, dw(self.spec.title or "") + 8)
	for i, it in ipairs(items) do
		if it.section then
			width = math.max(width, dw(it.section) + 12)
		else
			lefts[i] = "  " .. (it.key or " ") .. "  " .. resolve(it.label)
			values[i] = value_chunks(it)
			local w = dw(lefts[i]) + (values[i] and (3 + chunks_width(values[i])) or 0)
			width = math.max(width, w + 2, chunks_width(hint_chunks(it)) + 4)
		end
	end
	width = math.max(width, chunks_width(hint_chunks(nil)) + 4)

	local lines, spans, row_item, item_row = {}, {}, {}, {}
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
			push({ { "" } })
			local rule = string.rep("─", math.max(0, width - 5 - dw(it.section)))
			push({ { "  " }, { it.section, "CppMenuSection" }, { " " }, { rule, "CppMenuRule" } })
		else
			local chunks = {
				{ "  " },
				it.key and { it.key, "CppMenuKey" } or { " " },
				{ "  " },
				{ resolve(it.label), resolve(it.label_hl) or "CppMenuLabel" },
			}
			if values[i] then
				local pad = width - 2 - dw(lefts[i]) - chunks_width(values[i])
				chunks[#chunks + 1] = { string.rep(" ", math.max(pad, 1)) }
				vim.list_extend(chunks, values[i])
			end
			local row = push(chunks)
			row_item[row], item_row[i] = i, row
		end
	end
	push({ { "" } })
	push({ { " " }, { string.rep("─", width - 2), "CppMenuRule" } })
	local hint_row = push(self:_hint_line(width))

	return {
		lines = lines,
		spans = spans,
		row_item = row_item,
		item_row = item_row,
		width = width,
		hint_row = hint_row,
	}
end

--- Moves the selection: cursorline, the ▌ indicator, and the hint bar.
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
	if row then
		api.nvim_buf_set_extmark(self.buf, ns_sel, row - 1, 0, {
			virt_text = { { "▌", "CppMenuIndicator" } },
			virt_text_pos = "overlay",
		})
	end

	-- Rewrite the hint bar for the newly selected item.
	local chunks = self:_hint_line(layout.width)
	local text, spans = "", {}
	for _, c in ipairs(chunks) do
		if c[2] then
			spans[#spans + 1] = { #text, #text + #c[1], c[2] }
		end
		text = text .. c[1]
	end
	vim.bo[self.buf].modifiable = true
	api.nvim_buf_set_lines(self.buf, layout.hint_row - 1, layout.hint_row, false, { text })
	vim.bo[self.buf].modifiable = false
	api.nvim_buf_clear_namespace(self.buf, ns, layout.hint_row - 1, layout.hint_row)
	for _, s in ipairs(spans) do
		api.nvim_buf_set_extmark(self.buf, ns, layout.hint_row - 1, s[1], {
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

--- Runs one of an item's actions. Primary actions close the menu first (so
--- tasks land in the origin window) unless the action opts out.
function Menu:_run(action, default_close)
	if not action then
		return
	end
	local close = action.close
	if close == nil then
		close = default_close
	end
	if close then
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
		vim.go.guicursor = "a:CppMenuHiddenCursor"
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
	if api.nvim_win_is_valid(self.win) then
		api.nvim_win_close(self.win, true)
	end
	if current == self then
		current = nil
	end
	if self.spec.on_close then
		pcall(self.spec.on_close)
	end
end

---@param spec { title: string, items: table[], min_width: integer?, on_close: fun()? }
---@return table handle  with :close() and :render()
function M.open(spec)
	ensure_hl()
	if current then
		current:close()
	end

	local self = setmetatable({ spec = spec, sel = 1 }, Menu)
	current = self
	for i, it in ipairs(spec.items) do
		if selectable(it) then
			self.sel = i
			break
		end
	end

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
		"NormalFloat:CppMenuNormal",
		"FloatBorder:CppMenuBorder",
		"FloatTitle:CppMenuTitle",
		"CursorLine:CppMenuSelected",
	}, ",")
	vim.wo[self.win].cursorline = true
	vim.wo[self.win].wrap = false
	vim.wo[self.win].scrolloff = 0

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
	map("<CR>", function() self:_run(spec.items[self.sel].primary, true) end)
	map("l", function() self:_run(spec.items[self.sel].expand, false) end)
	map("<Right>", function() self:_run(spec.items[self.sel].expand, false) end)
	map("<C-s>", function() self:_run(spec.items[self.sel].save, false) end)
	map("q", function() self:close() end)
	map("<Esc>", function() self:close() end)
	for _, lhs in ipairs({ "i", "I", "a", "A", "o", "O" }) do
		map(lhs, function() end)
	end
	for i, it in ipairs(spec.items) do
		if it.key and it.primary then
			map(it.key, function()
				self:_set_sel(i)
				self:_run(it.primary, true)
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
