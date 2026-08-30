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
-- Collapse has three triggers:
--   * navigating off the span   -> render() sets state[open]=false
--   * <CR> on the anchor (toggle)-> the tab's own action flips state[open]
--   * a choice's callback calling ctx.close() (see below)
--
-- What a callback leaves selected is the *caller's* decision, not this
-- module's. The obvious default ("a pick closes and returns to the anchor")
-- is only right for a terminal pick; a delete instead wants to stay put so the
-- next entry slides under the cursor (or step back by one when there's no
-- next entry to slide up - see cmake_menu.tab_project's config_on_delete).
-- Rather than grow flags for each, every callback receives a `ctx` describing
-- where it sits and holding the two moves worth naming:
--
--   ctx.anchor    -- selectable index of the anchor row this list hangs under
--   ctx.index     -- 1-based index of this choice within the list
--   ctx.count     -- number of choices this frame
--   ctx.close()   -- collapse, and put the selection back on the anchor
--   ctx.focus(i)  -- stay open, select the i-th choice (0 = the anchor row)
--
-- Doing nothing keeps the dropdown open with the selection where it was -
-- which, after a delete, is the row that shifted up into the deleted slot.
--
--   local state = { sel = 1, dd_root = false }     -- module scope, owned by the tab
--   -- in render(m), right after drawing the anchor item + its item_end():
--   acts:set{ key="<CR>", action = function() state.dd_root = not state.dd_root end }
--   dropdown.render{
--     state   = state,
--     open    = "dd_root",                          -- key in state for this flag
--     choices = function() return candidates() end, -- recomputed each render
--     text    = function(c) return c.label end,     -- optional, default tostring
--     on_pick = function(c, ctx) pick(c); ctx.close() end,
--   }

local render_mod = require("cmake_menu.render")
local actions = require("cmake_menu.actions")
local HL = require("cmake_menu.hl")

local M = {}

---@class CMenu.DropdownArgs
---@field state table                        -- tab state; dropdown r/w state.sel and state[open]
---@field open string                        -- key in `state` holding this dropdown's expanded bool
---@field choices fun(): any[]               -- current choices, recomputed each render
---@field text (fun(c: any): string)?        -- choice -> display text (default tostring)
---@field tag (fun(c: any): string?)?        -- choice -> right-aligned dim label (e.g. its source), nil to omit
---@field on_pick fun(c: any, ctx: CMenu.DropdownCtx)    -- picks the choice; decides what stays selected via ctx (see the header)
---@field deletable (fun(c: any): boolean)?              -- choice -> whether "x" applies to it (e.g. false for a cmake preset, which isn't a stored entry); required alongside on_delete, otherwise ignored
---@field on_delete (fun(c: any, ctx: CMenu.DropdownCtx))? -- deletes the choice's saved entry; only bound to "x" where deletable(c) is true

--- Where a choice sits, and the selection moves worth naming. Handed to
--- on_pick/on_delete so the caller - not this module - decides what the
--- dropdown leaves selected. Doing nothing with it keeps the list open and the
--- selection unmoved.
---@class CMenu.DropdownCtx
---@field anchor integer            -- selectable index of the anchor row this list hangs under
---@field index integer             -- 1-based index of this choice within the list
---@field count integer             -- number of choices rendered this frame
---@field close fun()               -- collapse the list, selection back on the anchor
---@field focus fun(i: integer)     -- keep it open, select the i-th choice (0 = the anchor)

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
--- frame. ctx.close() adjusts the same way, and for the same reason.
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
	for i, choice in ipairs(choices) do
		r:item_begin()
		local tag = o.tag and o.tag(choice)
		if tag then
			r:line2{ "  ", { text = text(choice) }, { fill = true }, { text = tag, hl = HL.Dim } }
		else
			r:line2{ "  ", { text = text(choice) } }
		end
		r:item_end()
		---@type CMenu.DropdownCtx
		local ctx = {
			anchor = anchor,
			index = i,
			count = count,
			close = function()
				state[o.open] = false
				state.sel = anchor
			end,
			focus = function(n)
				state.sel = anchor + n
			end,
		}
		acts:set{ key = "<CR>", desc = "select", action = function() o.on_pick(choice, ctx) end }
		if o.on_delete and (not o.deletable or o.deletable(choice)) then
			acts:set{ key = "x", desc = "delete", action = function() o.on_delete(choice, ctx) end }
		end
	end
end

return M
