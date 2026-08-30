--- cmake_menu.keyicon — render an nvim key-notation string (e.g. "<C-S-CR>",
--- "x", "<Tab>") as a short, compact label for the footer's per-item hint.
---
--- Plain unicode only (─ ▌ ● ↵ → ...), no nerd-font/private-use-area glyphs -
--- this user's terminal font doesn't render those (they show as blanks).
---
--- Only `<...>`-wrapped notation is parsed; a bare key (e.g. "x", "j") is
--- returned as-is - plain letters are case-sensitive (x vs X are different
--- keys) so there's nothing to normalize there.

local M = {}

-- Special base-key name -> icon, keyed uppercase (nvim key notation is
-- case-insensitive for these). Covers what this menu actually binds; add to
-- it as new keys show up rather than trying to cover every <...> name nvim
-- understands.
local BASE_ICONS = {
	CR        = "↵",
	NL        = "↵",
	TAB       = "⇥",
	ESC       = "⎋",
	BS        = "⌫",
	DEL       = "⌦",
	SPACE     = "␣",
	UP        = "↑",
	DOWN      = "↓",
	LEFT      = "←",
	RIGHT     = "→",
	HOME      = "⇱",
	["END"]   = "⇲", -- `end` alone is fine as a table key; kept bracketed for visual symmetry with the rest
	PAGEUP    = "⇞",
	PAGEDOWN  = "⇟",
}

-- Modifier prefix -> icon, keyed uppercase. Applied in this fixed order
-- regardless of the order they appeared in the notation, so "<S-C-CR>" and
-- "<C-S-CR>" render identically.
local MODIFIER_ORDER = { "C", "M", "A", "D", "S" }
local MODIFIER_ICONS = {
	C = "⌃", -- Ctrl
	M = "⌥", -- Meta/Alt
	A = "⌥", -- Alt (alias of M in nvim's notation)
	D = "⌘", -- "Super"/Cmd, rare but valid nvim notation
	S = "⇧", -- Shift
}

--- `key` (an nvim keymap lhs) as a short display label.
---@param key string
---@return string
function M.icon(key)
	local inner = key:match("^<(.+)>$")
	if not inner then
		return key
	end

	local parts = vim.split(inner, "-", { plain = true })
	local base = table.remove(parts, #parts)

	local mods = {}
	for _, p in ipairs(parts) do
		mods[p:upper()] = true
	end

	local out = {}
	for _, m in ipairs(MODIFIER_ORDER) do
		if mods[m] then
			out[#out + 1] = MODIFIER_ICONS[m]
		end
	end
	out[#out + 1] = BASE_ICONS[base:upper()] or base

	return table.concat(out)
end

return M
