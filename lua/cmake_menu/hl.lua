--- cmake_menu.hl — UI highlight groups, linked to builtins so they follow the
--- colorscheme. Required once, for its side effects.

-- Defined via a function, not a one-shot `do` block: `:colorscheme` runs
-- `:hi clear`, which wipes these groups, and the module is cached so the side
-- effect never re-runs on its own. The ColorScheme autocmd re-applies them.
local function apply()
	local set_hl = function(name, val)
		val.default = true
		vim.api.nvim_set_hl(0, name, val)
	end
	set_hl("CMenuTabActive",   { link = "TabLineSel" })
	set_hl("CMenuTabInactive", { link = "Visual" })
	set_hl("CMenuValue",       { link = "String" })
	set_hl("CMenuDim",         { link = "Comment" })
	set_hl("CMenuHeading",     { link = "Title" })
	set_hl("CMenuSelected",    { link = "CursorLine" })
	set_hl("CMenuAction",      { link = "Function" })
	set_hl("CMenuMarker",      { link = "Special" })
end

apply()

vim.api.nvim_create_autocmd("ColorScheme", {
	group = vim.api.nvim_create_augroup("CMenuHl", { clear = true }),
	callback = apply,
})

return {}
