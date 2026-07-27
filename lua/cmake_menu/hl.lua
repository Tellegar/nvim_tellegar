--- cmake_menu.hl — UI highlight groups, linked to builtins so they follow the
--- colorscheme.
---
--- The first require registers the groups (nvim_set_hl) and a ColorScheme
--- autocmd to re-apply them; later requires just return the cached HL table.

local HL = {
	TabActive      = "TabActive",
	TabInactive    = "TabInactive",
	Value          = "Value",
	Dim            = "Dim",
	Heading        = "Heading",
	Selected       = "Selected",
	SelectedMarker = "SelectedMarker",
	Action         = "Action",
	HiddenCursor   = "HiddenCursor",
}

-- Defined via a function, not a one-shot `do` block: `:colorscheme` runs
-- `:hi clear`, which wipes these groups, and the module is cached so the side
-- effect never re-runs on its own. The ColorScheme autocmd re-applies them.
local function apply()
	local set_hl = function(name, val)
		val.default = true
		vim.api.nvim_set_hl(0, name, val)
	end
	set_hl(HL.TabActive,      { link = "TabLineSel" })
	set_hl(HL.TabInactive,    { link = "Visual" })
	set_hl(HL.Value,          { link = "String" })
	set_hl(HL.Dim,            { link = "Comment" })
	set_hl(HL.Heading,        { link = "Title" })
	set_hl(HL.Selected,       { link = "CursorLine" })
	set_hl(HL.SelectedMarker, { link = "Special" })
	set_hl(HL.Action,         { link = "Function" })
	set_hl(HL.HiddenCursor,   { blend = 100, nocombine = true })
end

apply() -- once at first require

vim.api.nvim_create_autocmd("ColorScheme", {
	group = vim.api.nvim_create_augroup("CMenuHl", { clear = true }),
	callback = apply,
})

return HL
