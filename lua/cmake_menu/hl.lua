--- cmake_menu.hl — UI highlight groups, linked to builtins so they follow the
--- colorscheme. Required once, for its side effects.

local HL = {
	CMenuTabActive      = "CMenuTabActive",
	CMenuTabInactive    = "CMenuTabInactive",
	CMenuValue          = "CMenuValue",
	CMenuDim            = "CMenuDim",
	CMenuHeading        = "CMenuHeading",
	CMenuSelected       = "CMenuSelected",
	CMenuSelectedMarker = "CMenuSelectedMarker",
	CMenuAction         = "CMenuAction",
	CMenuHiddenCursor   = "CMenuHiddenCursor",
}

-- Defined via a function, not a one-shot `do` block: `:colorscheme` runs
-- `:hi clear`, which wipes these groups, and the module is cached so the side
-- effect never re-runs on its own. The ColorScheme autocmd re-applies them.
local function apply()
	local set_hl = function(name, val)
		val.default = true
		HL[name] = name
		vim.api.nvim_set_hl(0, name, val)
	end
	set_hl(HL.CMenuTabActive,      { link = "TabLineSel" })
	set_hl(HL.CMenuTabInactive,    { link = "Visual" })
	set_hl(HL.CMenuValue,          { link = "String" })
	set_hl(HL.CMenuDim,            { link = "Comment" })
	set_hl(HL.CMenuHeading,        { link = "Title" })
	set_hl(HL.CMenuSelected,       { link = "CursorLine" })
	set_hl(HL.CMenuSelectedMarker, { link = "Special" })
	set_hl(HL.CMenuAction,         { link = "Function" })
	set_hl(HL.CMenuHiddenCursor,   { blend = 100, nocombine = true })
end

apply() -- once at first require

vim.api.nvim_create_autocmd("ColorScheme", {
	group = vim.api.nvim_create_augroup("CMenuHl", { clear = true }),
	callback = apply,
})

return HL
