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
--   dropdown.render(root_dd, r, acts, {
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

--- Render the choice list under an (already-drawn) anchor row, but only while
--- `state.expanded`. Each choice is one selectable item whose <CR> collapses the
--- dropdown and calls on_pick.
---@param state CMenu.DropdownState
---@param r CMenu.Render
---@param acts CMenu.Actions
---@param opts CMenu.DropdownOpts
function M.render(state, r, acts, opts)
	if not state.expanded then return end
	local text = opts.text or tostring
	for _, choice in ipairs(opts.choices()) do
		r:item_begin()
		r:line2{ "  ", { text = text(choice) } }
		r:item_end()
		acts:set{ key = "<CR>", action = function()
			state.expanded = false
			opts.on_pick(choice)
		end }
	end
end

return M
