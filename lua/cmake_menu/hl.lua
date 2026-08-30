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
	-- deliberately not plain "Error": that's a builtin group, and set_hl's
	-- default=true would leave ours a no-op alias of it
	Error          = "MenuError",
	HiddenCursor   = "HiddenCursor",
	FooterBg       = "FooterBg", -- winhighlight target, not a text hl - see float.lua's footer pane
}

--- `base_group`'s bg, nudged by `delta` per channel (negative = darker,
--- positive = lighter) - so the footer reads as "the same surface, slightly
--- off" rather than an unrelated color. nil if `base_group` has no bg
--- (transparent background colorschemes).
---@param base_group string
---@param delta integer
---@return integer?
local function shift_bg(base_group, delta)
	local bg = vim.api.nvim_get_hl(0, { name = base_group, link = false }).bg
	if not bg then
		return nil
	end
	local r = math.floor(bg / 65536) % 256
	local g = math.floor(bg / 256) % 256
	local b = bg % 256
	local function clamp(v) return math.max(0, math.min(255, v)) end
	r, g, b = clamp(r + delta), clamp(g + delta), clamp(b + delta)
	return r * 65536 + g * 256 + b
end

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
	set_hl(HL.Error,          { link = "ErrorMsg" })
	set_hl(HL.HiddenCursor,   { blend = 100, nocombine = true })

	local footer_bg = shift_bg("NormalFloat", -4)
	set_hl(HL.FooterBg, footer_bg and { bg = footer_bg } or { link = "NormalFloat" })
end

apply() -- once at first require

vim.api.nvim_create_autocmd("ColorScheme", {
	group = vim.api.nvim_create_augroup("CMenuHl", { clear = true }),
	callback = apply,
})

return HL
