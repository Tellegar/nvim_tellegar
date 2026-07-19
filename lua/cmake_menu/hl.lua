-- Highlight groups for the cmake_menu UI, split out of menu.lua so other
-- cmake_menu modules (cpp.lua, scratch.lua) that build chunks fed into menu
-- items can reference the group names without depending on the whole
-- rendering module.
--
-- All colors route through CmakeMenu* groups, default-linked so a
-- colorscheme can restyle the menu without touching this file.

local api = vim.api

local M = {}

local PREFIX = "CmakeMenu"

---@enum CMenu.Hl
M.HL = {
	Normal    = PREFIX .. "Normal",    -- float window background (winhighlight NormalFloat)
	Border    = PREFIX .. "Border",    -- float window border
	Selected  = PREFIX .. "Selected",  -- line background of the currently selected entry
	Indicator = PREFIX .. "Indicator", -- the "▌" glyph marking the selected row
	Key       = PREFIX .. "Key",       -- an item's quick-launch key, left column
	Value     = PREFIX .. "Value",     -- default value_hl when an item gives a plain-string value with no override
	Section   = PREFIX .. "Section",   -- section/subsection header text
	Rule      = PREFIX .. "Rule",      -- the "─" separator line under a section header
	Hint      = PREFIX .. "Hint",      -- footer note/description text (both the per-item and global footer lines)
	HintKey   = PREFIX .. "HintKey",   -- the keybind symbol (e.g. "↵") in a footer hint, before its description
	Title     = PREFIX .. "Title",     -- floating window title (winhighlight FloatTitle)
	Label     = PREFIX .. "Label",     -- default label_hl when an item gives no override
}

-- Cursor styling only, never passed as a content highlight - kept out of
-- M.HL (which is content-highlights only) but exposed separately since
-- menu.lua still needs the name.
M.HiddenCursor = PREFIX .. "HiddenCursor"

local HLS = {
	[M.HL.Normal] = "NormalFloat",
	[M.HL.Border] = "FloatBorder",
	[M.HL.Selected] = "CursorLine",
	[M.HL.Indicator] = "Special",
	[M.HL.Key] = "Special",
	[M.HL.Value] = "Comment",
	[M.HL.Section] = "Comment",
	[M.HL.Rule] = "NonText",
	[M.HL.Hint] = "Comment",
	[M.HL.HintKey] = "Special",
}

-- These two sit on top of the window/float background (the title bar, and
-- any label with no label_hl override). A plain `link` would also pull in
-- the target's own bg - and many themes set an explicit guibg on Normal /
-- FloatTitle for solid-background floats - which then mismatches
-- CmakeMenuNormal's bg and shows as a boxed highlight behind the text. Fg-only
-- so the window's own background shows through instead.
local FG_ONLY_HLS = {
	[M.HL.Title] = "FloatTitle",
	[M.HL.Label] = "Normal",
}

--- (Re-)defines every CmakeMenu* group as a default link, so a colorscheme
--- can override any of them by name and so a colorscheme switch between menu
--- opens is picked up (call this again, it's idempotent and cheap).
function M.ensure()
	for name, link in pairs(HLS) do
		api.nvim_set_hl(0, name, { link = link, default = true })
	end
	-- CmakeMenuLabel paints over buffer content, already based to
	-- CmakeMenuNormal (winhighlight), so an unset bg there falls through
	-- correctly. Title is window furniture, not buffer content - an unset bg
	-- on it falls back to the *global* Normal instead of the float's
	-- NormalFloat, so it needs the float's bg spelled out explicitly to
	-- actually match.
	local win_bg = api.nvim_get_hl(0, { name = "NormalFloat", link = false }).bg
	for name, link in pairs(FG_ONLY_HLS) do
		local resolved = api.nvim_get_hl(0, { name = link, link = false })
		api.nvim_set_hl(0, name, { fg = resolved.fg, bg = win_bg, default = true })
	end
	-- blend = 100 makes the real cursor invisible while it sits in the menu
	-- (the ▌ indicator plays that role instead); not default = true, since
	-- this one must win over anything a colorscheme defines.
	api.nvim_set_hl(0, M.HiddenCursor, { blend = 100, nocombine = true })
end

return M
