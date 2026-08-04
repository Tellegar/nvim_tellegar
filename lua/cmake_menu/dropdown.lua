-- cmake_menu.dropdown - the expansion half of a dropdown.
--
-- Deliberately NOT a widget object: the expandable anchor row (the one you press
-- <CR> on) is rendered by the tab itself, in its own render(), along with the
-- action that flips `state.expanded`. This module owns only what appears *below*
-- that row when it's open - the choice list and each choice's pick callback.
--
-- Choices are passed as a function because they depend on current state (e.g. the
-- candidate source roots for the buffer), so they're recomputed every render.
--
--   local root_dd = { expanded = false }         -- module scope, owned by the tab
--   -- in render(m), right after drawing the anchor item + its item_end():
--   acts:set{ key="<CR>", action = function() root_dd.expanded = not root_dd.expanded end }
--   sel = dropdown.render(root_dd, r, acts, sel, {
--     choices = function() return candidates() end,  -- recomputed each render
--     text    = function(c) return c.label end,      -- optional, default tostring
--     on_pick = function(c) ... end,                 -- collapses automatically
--   })

local M = {}

---@class CMenu.DropdownState
---@field expanded boolean

---@class CMenu.DropdownOpts
---@field choices fun(): any[]              -- current choices, recomputed each render
---@field text (fun(c: any): string)?       -- choice -> display text (default tostring)
---@field on_pick fun(c: any)               -- called with the picked choice

--- Render the choice list under an (already-drawn) anchor row while expanded,
--- and auto-collapse when `sel` has moved off the dropdown's span (the anchor
--- row plus its choices) so navigating past an open dropdown closes it without
--- picking. Each choice is one selectable item whose <CR> collapses and picks.
---
--- Pass the current selection index; returns the index to render the selection
--- at. The anchor is the item just closed, so #r.layout is its index and the
--- choices would occupy the `count` slots below it. Moving up out of the span
--- leaves the index unchanged (the choices sit below the anchor); moving down
--- past the last choice shifts it up by `count`, since those rows are collapsed
--- away above the new target and never drawn this frame.
---@param state CMenu.DropdownState
---@param r CMenu.Render
---@param acts CMenu.Actions
---@param sel integer  -- current selection index
---@param opts CMenu.DropdownOpts
---@return integer sel
function M.render(state, r, acts, sel, opts)
	if not state.expanded then return sel end
	local anchor = #r.layout
	local choices = opts.choices()
	local count = #choices
	if sel < anchor then
		state.expanded = false
		return sel
	elseif sel > anchor + count then
		state.expanded = false
		return sel - count
	end
	local text = opts.text or tostring
	for _, choice in ipairs(choices) do
		r:item_begin()
		r:line2{ "  ", { text = text(choice) } }
		r:item_end()
		acts:set{ key = "<CR>", action = function()
			state.expanded = false
			opts.on_pick(choice)
		end }
	end
	return sel
end

return M
