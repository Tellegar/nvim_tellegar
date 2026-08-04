-- cmake_menu.dropdown - the expansion half of a dropdown.
--
-- Deliberately NOT a widget object: the expandable anchor row (the one you press
-- <CR> on) is rendered by the tab itself, in its own render(), along with the
-- action that flips the open flag. This module owns only what appears *below*
-- that row when it's open - the choice list and each choice's pick callback.
--
-- One flat args table carries the whole call. `state` is the tab's own state
-- table, passed by reference: the dropdown reads and writes `state.sel` (the
-- selection index) and `state[open]` (this dropdown's expanded bool, named by
-- the `open` key) directly, the way a C function mutates a struct through a
-- pointer - so nothing is threaded back through return values. The remaining
-- fields are options (choices/text/on_pick). The render context and action map
-- aren't passed either - they're read from their module singletons
-- (render.current, actions.current), which the tab has already initialised this
-- frame. `choices` is a function because the choices depend on current state
-- (e.g. the candidate roots for the buffer), recomputed each render.
--
-- Collapse has three triggers, each closing the flag directly:
--   * navigating off the span   -> render() sets state[open]=false
--   * <CR> on the anchor (toggle)-> the tab's own action flips state[open]
--   * <CR> on a choice (pick)    -> the tab's on_pick sets state[open]=false, so
--                                   it does the pick AND closes
--
--   local state = { sel = 1, dd_root = false }     -- module scope, owned by the tab
--   -- in render(m), right after drawing the anchor item + its item_end():
--   acts:set{ key="<CR>", action = function() state.dd_root = not state.dd_root end }
--   dropdown.render{
--     state   = state,
--     open    = "dd_root",                          -- key in state for this flag
--     choices = function() return candidates() end, -- recomputed each render
--     text    = function(c) return c.label end,     -- optional, default tostring
--     on_pick = function(c) pick(c); state.dd_root = false end,  -- pick AND close
--   }

local render_mod = require("cmake_menu.render")
local actions = require("cmake_menu.actions")

local M = {}

---@class CMenu.DropdownArgs
---@field state table                        -- tab state; dropdown r/w state.sel and state[open]
---@field open string                        -- key in `state` holding this dropdown's expanded bool
---@field choices fun(): any[]               -- current choices, recomputed each render
---@field text (fun(c: any): string)?        -- choice -> display text (default tostring)
---@field on_pick fun(c: any)                -- picks the choice; should also close (state[open]=false)

--- Render the choice list under an (already-drawn) anchor row while open, and
--- auto-collapse when `state.sel` has moved off the dropdown's span (the anchor
--- row plus its choices) so navigating past an open dropdown closes it without
--- picking. Each choice is one selectable item whose <CR> calls on_pick.
---
--- Reads the frame's render context and action map from render.current /
--- actions.current. Writes the (possibly-collapsed) open flag and the adjusted
--- selection back into `state` directly. The anchor is the item just closed, so
--- #r.layout is its index and the choices would occupy the `count` slots below
--- it. Moving up out of the span leaves the index unchanged (the choices sit
--- below the anchor); moving down past the last choice shifts it up by `count`,
--- since those rows are collapsed away above the new target and never drawn this
--- frame. Picking returns focus to the anchor for the same reason.
---@param o CMenu.DropdownArgs
function M.render(o)
	local state = o.state
	if not state[o.open] then return end
	local r = assert(render_mod.current, "dropdown.render(): no active render frame")
	local acts = assert(actions.current, "dropdown.render(): no active action map")
	local anchor = #r.layout
	local choices = o.choices()
	local count = #choices
	if state.sel < anchor then
		state[o.open] = false
		return
	elseif state.sel > anchor + count then
		state[o.open] = false
		state.sel = state.sel - count
		return
	end
	local text = o.text or tostring
	for _, choice in ipairs(choices) do
		r:item_begin()
		r:line2{ "  ", { text = text(choice) } }
		r:item_end()
		-- picking returns focus to the anchor row (its choices are about to
		-- collapse away, so leaving sel on the choice would land it elsewhere)
		acts:set{ key = "<CR>", action = function() o.on_pick(choice); state.sel = anchor end }
	end
end

return M
