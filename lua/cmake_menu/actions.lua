-- cmake_menu.actions - per-item key->handler dispatch for a rendered body.
--
-- Actions have a different lifetime than the render that produces them. They're
-- rebuilt every frame, just like the lines are - but the buffer stores the drawn
-- lines for us, whereas nothing stores the action map. And they're consumed
-- *after* render() returns: on the next keypress, by dispatch(), before the next
-- render exists. So this map has to outlive the (transient, render-local) render
-- context that fed it - which is exactly why actions live here and not in render.
--
-- The map keys a selectable-item index (render's layout order, top to bottom) to
-- a list of { key, action } handlers. It's bound to a render context via
-- begin(r) at the top of each render so set() can attach handlers to "the item
-- just closed" without anyone tracking a sel index by hand.
--
--   local acts = actions.new()           -- module-level, persists across renders
--   -- inside render(m):
--   acts:begin(r)                         -- forget last frame, point at this r
--   ... r:item_end()
--   acts:set{ { key="<CR>", action=fn }, { key="x", action=fn } }
--   -- in a key mapping:
--   acts:dispatch(sel, key)               -- r is gone; the map remains

local M = {}

---@class CMenu.Action
---@field key string
---@field action fun(key: string)  -- receives the pressed key (so alt keys can branch)

---@class CMenu.Actions
---@field _r CMenu.Render?          -- current frame's render context (item-index source)
---@field _map table<integer, CMenu.Action[]>
local A = {}
A.__index = A

---@return CMenu.Actions
function M.new()
	return setmetatable({ _r = nil, _map = {} }, A)
end

--- Start a fresh frame: forget the previous map and bind to this render's `r`
--- so set() can read the current item index. Call once, at the top of render().
---@param r CMenu.Render
function A:begin(r)
	self._r = r
	self._map = {}
end

--- Attach handler(s) to the item just closed by r:item_end(). `spec` is one
--- { key, action } or a list of them; multiple set() calls on the same item
--- accumulate.
---@param spec CMenu.Action|CMenu.Action[]
function A:set(spec)
	assert(self._r, "actions:set() called before begin()")
	local list = spec.key and { spec } or spec
	local idx = #self._r.layout
	self._map[idx] = vim.list_extend(self._map[idx] or {}, list)
end

--- Fire the handler bound to `key` on the sel-th item, if there is one. A no-op
--- for items with no matching handler (most items have none).
---@param sel integer
---@param key string
function A:dispatch(sel, key)
	local list = self._map[sel]
	if not list then return end
	for _, a in ipairs(list) do
		if a.key == key then
			a.action(key)
			return
		end
	end
end

return M
