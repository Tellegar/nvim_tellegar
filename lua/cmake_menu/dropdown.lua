-- cmake_menu.dropdown - the expansion half of a dropdown.
--
-- Deliberately NOT a widget object: the expandable anchor row (the one you press
-- <CR> on) is rendered by the tab itself, in its own render(), along with the
-- action that flips the `open` flag. This module owns only what appears *below*
-- that row when it's open - the choice list and each choice's pick callback.
--
-- One flat args table carries the whole call: the two required references into
-- tab state (`open`, `sel`) alongside the option fields (choices/text/on_pick).
-- The render context and action map aren't passed - they're read from their
-- module singletons (render.current, actions.current), which the tab has already
-- initialised this frame. `choices` is a function because the choices depend on
-- current state (e.g. the candidate roots for the buffer), recomputed each render.
--
-- `open` is a plain bool the tab owns, passed in and returned back (a value, so
-- the dropdown can't write it across a later keypress). Collapse has three
-- triggers, each closed by whoever can reach the flag at that moment:
--   * navigating off the span   -> render() returns open=false
--   * <CR> on the anchor (toggle)-> the tab's own action flips its `open` local
--   * <CR> on a choice (pick)    -> the tab's on_pick closes over `open`, so it
--                                   does the pick AND sets open=false
--
--   local root_open = false                       -- module scope, owned by the tab
--   -- in render(m), right after drawing the anchor item + its item_end():
--   acts:set{ key="<CR>", action = function() root_open = not root_open end }
--   root_open, sel = dropdown.render{
--     open    = root_open,
--     sel     = sel,
--     choices = function() return candidates() end,  -- recomputed each render
--     text    = function(c) return c.label end,      -- optional, default tostring
--     on_pick = function(c) pick(c); root_open = false end,  -- pick AND close
--   }

local render_mod = require("cmake_menu.render")
local actions = require("cmake_menu.actions")

local M = {}

---@class CMenu.DropdownArgs
---@field open boolean                       -- whether the dropdown is expanded
---@field sel integer                        -- current selection index
---@field choices fun(): any[]               -- current choices, recomputed each render
---@field text (fun(c: any): string)?        -- choice -> display text (default tostring)
---@field on_pick fun(c: any)                -- picks the choice; should also close (open=false)

--- Render the choice list under an (already-drawn) anchor row while `open`, and
--- auto-collapse when `sel` has moved off the dropdown's span (the anchor row
--- plus its choices) so navigating past an open dropdown closes it without
--- picking. Each choice is one selectable item whose <CR> calls on_pick.
---
--- Reads the frame's render context and action map from render.current /
--- actions.current. Returns the (possibly-collapsed) open flag and the index to
--- render the selection at. The anchor is the item just closed, so #r.layout is
--- its index and the choices would occupy the `count` slots below it. Moving up
--- out of the span leaves the index unchanged (the choices sit below the anchor);
--- moving down past the last choice shifts it up by `count`, since those rows are
--- collapsed away above the new target and never drawn this frame.
---@param o CMenu.DropdownArgs
---@return boolean open, integer sel
function M.render(o)
	local sel = o.sel
	if not o.open then return false, sel end
	local r = assert(render_mod.current, "dropdown.render(): no active render frame")
	local acts = assert(actions.current, "dropdown.render(): no active action map")
	local anchor = #r.layout
	local choices = o.choices()
	local count = #choices
	if sel < anchor then
		return false, sel
	elseif sel > anchor + count then
		return false, sel - count
	end
	local text = o.text or tostring
	for _, choice in ipairs(choices) do
		r:item_begin()
		r:line2{ "  ", { text = text(choice) } }
		r:item_end()
		acts:set{ key = "<CR>", action = function() o.on_pick(choice) end }
	end
	return true, sel
end

return M
