-- Highlight groups for the cmake_menu UI.
--
-- M.HL holds every group's name - also what's needed to actually use one
-- (extmark hl_group/line_hl_group, winhighlight, guicursor all key off the
-- name string, nothing else). M.ensure() is what registers them: each
-- default-linked to a canonical group via nvim_set_hl, so a colorscheme can
-- restyle the menu without touching this file.
--
-- Two logical groups within M.HL (blank line between them below):
--   - item-spec content palette (Normal/Low/Glow/Value): what item authors
--     (cpp.lua, scratch.lua, configure.lua) pick from for chunk highlights -
--     a small, generic set of 4 semantic colors, not tied to any one field.
--   - menu-internal (Selected/Rule/Border/Title/HiddenCursor): drawn by
--     menu.lua itself (selection state, dividers, window chrome, cursor
--     hiding), not something an item spec ever chooses.

local M = {}

M.HL = {
	Normal = "CmakeMenuNormal", -- neutral color; also the float window's own background (winhighlight NormalFloat)
	Low    = "CmakeMenuLow",    -- low-contrast color, for de-emphasized content
	Glow   = "CmakeMenuGlow",   -- high-contrast accent color, for content that should draw the eye
	Value  = "CmakeMenuValue",  -- high-contrast color for values (distinct accent from Glow)

	Selected     = "CmakeMenuSelected",     -- line background of the currently selected entry
	Rule         = "CmakeMenuRule",         -- the "─" separator line beside a section header
	Border       = "CmakeMenuBorder",       -- float window border
	Title        = "CmakeMenuTitle",        -- floating window title (winhighlight FloatTitle)
	HiddenCursor = "CmakeMenuHiddenCursor", -- guicursor target while the menu is open, makes the real cursor invisible
}

--- (Re-)defines every CmakeMenu* group, so a colorscheme can override any of
--- them by name and so a colorscheme switch between menu opens is picked up
--- (call this again, it's idempotent and cheap).
function M.ensure()
	local hl = M.HL

	vim.api.nvim_set_hl(0, hl.Normal, { link = "NormalFloat", default = true })
	vim.api.nvim_set_hl(0, hl.Low, { link = "Comment", default = true })
	vim.api.nvim_set_hl(0, hl.Glow, { link = "Special", default = true })
	vim.api.nvim_set_hl(0, hl.Value, { link = "String", default = true })

	vim.api.nvim_set_hl(0, hl.Selected, { link = "CursorLine", default = true })
	vim.api.nvim_set_hl(0, hl.Rule, { link = "NonText", default = true })
	vim.api.nvim_set_hl(0, hl.Border, { link = "FloatBorder", default = true })

	-- Title is text drawn inline in the border row, not buffer content - a
	-- plain link would also pull in FloatTitle's own bg, and many themes set
	-- an explicit guibg on FloatTitle for solid-background floats, which
	-- then mismatches the border's actual bg and shows as a boxed highlight
	-- behind the text. Fg only, bg forced to match the border it sits on
	-- (not the window body) so it blends in instead.
	local title_fg = vim.api.nvim_get_hl(0, { name = "FloatTitle", link = false }).fg
	local border_bg = vim.api.nvim_get_hl(0, { name = "FloatBorder", link = false }).bg
	vim.api.nvim_set_hl(0, hl.Title, { fg = title_fg, bg = border_bg, default = true })

	-- blend = 100 makes the real cursor invisible while it sits in the menu
	-- (the ▌ indicator plays that role instead); not default = true, since
	-- this one must win over anything a colorscheme defines.
	vim.api.nvim_set_hl(0, hl.HiddenCursor, { blend = 100, nocombine = true })
end

return M
