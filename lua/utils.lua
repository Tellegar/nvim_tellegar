local M = {}

--- Concatenates `arrays` into a new array, in order.
---@param arrays table[][]
---@return table[]
function M.concat(arrays)
	local out = {}
	for _, arr in ipairs(arrays) do
		vim.list_extend(out, arr)
	end
	return out
end

-- POSIX-shell quoting (sh/bash/zsh single-quote escaping) - not Windows-safe.
-- {a}'{b} splits on the first ' into a and b, each escaped separately by
-- recursing back into this same function - so a safe half (e.g. "it" in
-- "it's") comes back bare, with no quotes wrapping it at all - and rejoined
-- with a literal \'.
function M.shell_escape(str)
	if str == "" then
		return "''"
	end
	if str:match("^[%w%-%.,_/:=+~]+$") then
		return str
	end

	str = "'" .. str:gsub("'", "'\\''") .. "'"
	str = str:gsub("^''", ""):gsub("\\'''", "\\'")

	return str
end

return M
