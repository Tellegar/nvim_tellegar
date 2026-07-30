--- cmake_menu.render — stateful body-rendering context shared by tabs.
---
--- Accumulates a pane's lines/highlights/selectable-item layout by hand, then
--- flushes them in one shot. Mirrors the float.Pane contract (set_lines then
--- hl) but adds margin bookkeeping and a "selectable item" concept so tabs
--- stop hand-rolling line()/mark()/item_begin()/item_end() closures.
---
--- Usage, inside a tab's render(m):
---   r.target = m.body
---   r.margin = "  "
---   r:reset()
---   r:item_begin()
---   local row = r:line("hello")
---   r:mark(nil, 0, { end_col = 5, hl_group = HL.Value })
---   r:item_end()
---   r:render()
---   r:render_selection(sel)
---
--- render() only flushes lines+marks; render_selection(sel) is a separate,
--- optional step for tabs that track a `layout` of selectable items (a tab
--- with no selection concept just never calls it).
---
--- For a line built from several differently-highlighted spans, r:line2(segments)
--- is an alternative to hand-tracking column offsets across line()/mark() calls.

local HL = require("cmake_menu.hl")

local M = {}

---@class CMenu.Render
---@field target CMenu.Pane?      -- pane to flush into; set before reset()/line()/mark()
---@field margin string           -- prefix applied by line(); default ""
---@field lines string[]
---@field marks table[]           -- { row, col, opts }
---@field layout table[]          -- layout[i] = row-list of the i-th selectable item
local R = {}
R.__index = R

---@return CMenu.Render
function M.new()
	return setmetatable({
		target = nil,
		margin = "",
		lines = {},
		marks = {},
		layout = {},
		_item_start = nil, -- row `lines` was at when item_begin() ran; nil if not mid-item
	}, R)
end

--- Clear accumulated state for a fresh build against `self.target`.
--- Call once per render(m) pass, after (re)assigning `self.target`.
function R:reset()
	self.lines = {}
	self.marks = {}
	self.layout = {}
	self._item_start = nil
end

--- Accumulate one line, margin-prefixed. Returns its 0-based row.
---@param text string
---@return integer row
function R:line(text)
	self.lines[#self.lines + 1] = self.margin .. text
	return #self.lines - 1
end

--- Queue a highlight, margin-adjusted, applied on render(). `row` defaults to
--- the last line pushed.
--- ```
--- ...
--- r:text(...)
--- r:mark(nil, col, opts)
--- ```
---@param row integer?
---@param col integer
---@param opts table  -- must carry hl_group / end_col etc, per Pane:hl
function R:mark(row, col, opts)
	row = row or (#self.lines - 1)
	opts = vim.tbl_extend("force", {}, opts) -- don't mutate caller's table
	opts.end_col = opts.end_col + #self.margin
	self.marks[#self.marks + 1] = { row, col + #self.margin, opts }
end

---@alias CMenu.Segment string | { text: string, hl: string|table } | { fill: true|string }

--- Build one line from segments (plain string = unhighlighted; {text, hl} =
--- highlighted span). Concatenates segment text for the line; for any
--- segment carrying `hl`, queues a mark whose col/end_col are inferred from
--- that segment's position in the concatenation (0-based, pre-margin same as
--- line()/mark()). `hl` as a string is shorthand for `{ hl_group = hl }`; as
--- a table it's the full mark opts, with `end_col` computed and always
--- overwriting whatever the caller passed (col/end_col are not the caller's
--- to set here).
---
--- At most one segment may be `{ fill = true|string }` -- an expanding
--- spacer. At the end, it's replaced with however much padding (the fill
--- string repeated, default a single space) is needed to stretch the line to
--- `self.target:width() - 2*#self.margin`; marks after the fill segment
--- shift right by the inserted padding.
---@param segments CMenu.Segment[]
---@return integer row
function R:line2(segments)
	local text = ""
	local pending = {} -- { col, end_col, opts }
	local fill_pos, fill_char, fill_mark_idx
	for _, seg in ipairs(segments) do
		if type(seg) == "table" and seg.fill then
			assert(fill_pos == nil, "line2(): at most one fill segment is allowed")
			fill_pos = #text
			fill_mark_idx = #pending
			fill_char = seg.fill == true and " " or seg.fill
			if fill_char == "" then fill_char = " " end
		else
			local seg_text = type(seg) == "string" and seg or seg.text
			if type(seg) == "table" and seg.hl then
				local opts = type(seg.hl) == "string"
					and { hl_group = seg.hl }
					or vim.tbl_extend("force", {}, seg.hl)
				pending[#pending + 1] = { col = #text, end_col = #text + #seg_text, opts = opts }
			end
			text = text .. seg_text
		end
	end

	if fill_pos then
		local target_width = self.target:width() - 2 * #self.margin
		local pad_len = math.max(0, target_width - #text)
		---@cast fill_char string
		local pad = string.rep(fill_char, math.ceil(pad_len / #fill_char)):sub(1, pad_len)
		text = text:sub(1, fill_pos) .. pad .. text:sub(fill_pos + 1)
		for i = fill_mark_idx + 1, #pending do
			pending[i].col = pending[i].col + pad_len
			pending[i].end_col = pending[i].end_col + pad_len
		end
	end

	local row = self:line(text)
	for _, p in ipairs(pending) do
		p.opts.end_col = p.end_col
		self:mark(row, p.col, p.opts)
	end
	return row
end

--- Open a selectable item: rows pushed between this and the matching
--- item_end() become one entry in `self.layout`.
function R:item_begin()
	assert(self._item_start == nil, "item_begin() called without a matching item_end()")
	self._item_start = #self.lines
end

--- Close the selectable item opened by the last item_begin().
function R:item_end()
	assert(self._item_start ~= nil, "item_end() must follow item_begin()")
	local rows = {}
	for r = self._item_start, #self.lines - 1 do
		rows[#rows + 1] = r
	end
	self.layout[#self.layout + 1] = rows
	self._item_start = nil
end

--- Flush accumulated lines + marks to self.target. Does NOT touch selection
--- highlighting -- call render_selection() after, if this pane has one.
function R:render()
	assert(self.target, "render.target must be set before render()")
	self.target:set_lines(self.lines)
	for _, k in ipairs(self.marks) do
		self.target:hl(k[1], k[2], k[3])
	end
end

--- Highlight every row of the sel-th selectable item (1-based, clamped to
--- #self.layout). Call after render(): set_lines() would otherwise wipe it.
---@param sel integer
---@return integer clamped
function R:render_selection(sel)
	assert(self.target, "render.target must be set before render_selection()")
	sel = math.max(1, math.min(sel, #self.layout))
	local rows = self.layout[sel]
	if rows then
		for _, r in ipairs(rows) do
			self.target:hl(r, 0, {
				line_hl_group = HL.Selected,
				virt_text = { { "▌", HL.SelectedMarker } },
				virt_text_pos = "overlay",
			})
		end
	end
	return sel
end

return M
