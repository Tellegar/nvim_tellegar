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

--- `path` written relative to `base` when it's a descendant of it, otherwise
--- `path` unchanged. For display only: it shortens a path that is already
--- rooted under a directory the UI is showing anyway, and deliberately never
--- produces a leading "../.." - a path outside `base` stays absolute rather
--- than being expressed as a climb out of it.
---@param base string?
---@param path string
---@return string
function M.relative_to(base, path)
	if not base then
		return path
	end
	local prefix = vim.fs.normalize(base):gsub("/+$", "") .. "/"
	local norm = vim.fs.normalize(path)
	if norm:sub(1, #prefix) == prefix then
		return norm:sub(#prefix + 1)
	end
	return path
end

--- Renders `value` as a Lua-ish string. Tables become `{ k=v, ... }`, nested
--- tables recurse. Single line by default; pass `multiline=true` for an
--- indented layout.
---@param value any
---@param opts? { multiline?: boolean, indent?: string }
---@return string
function M.inspect(value, opts)
	opts = opts or {}
	if type(value) ~= "table" then
		return type(value) == "string" and string.format("%q", value) or tostring(value)
	end

	local multiline = opts.multiline
	local indent = opts.indent or ""
	local child = indent .. "\t"

	local parts = {}
	for k, v in pairs(value) do
		local key = (type(k) == "string" and k:match("^[%a_][%w_]*$")) and k or "[" .. M.inspect(k) .. "]"
		local nested = multiline and { multiline = true, indent = child } or nil
		parts[#parts + 1] = key .. "=" .. M.inspect(v, nested)
	end

	if #parts == 0 then
		return "{}"
	end
	if multiline then
		return "{\n" .. child .. table.concat(parts, ",\n" .. child) .. "\n" .. indent .. "}"
	end
	return "{ " .. table.concat(parts, ", ") .. " }"
end

return M
