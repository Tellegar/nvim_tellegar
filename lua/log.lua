-- log - an append-only log file for this config, at
-- stdpath("state")/tellegar.log (~/.local/state/nvim/tellegar.log).
--
-- nvim has no general-purpose log a Lua config can write to: $NVIM_LOG_FILE
-- belongs to the C core, and vim.lsp.log is the LSP client's own (lsp.log,
-- WARN and up by default). So this is its own file. It's opened and closed
-- per line - fine at config volume, and a crash never loses a buffered tail.
--
--   local log = require("log").scope("cpp_modules")
--   log.info("loaded %d modules in %.1fms", n, ms)

local M = {}

M.path = vim.fs.joinpath(vim.fn.stdpath("state"), "tellegar.log")

---@param level string
---@param scope string
---@param fmt string
local function write(level, scope, fmt, ...)
	local f = io.open(M.path, "a")
	if not f then
		return
	end
	f:write(string.format("%s %-5s %s: %s\n", os.date("%Y-%m-%d %H:%M:%S"), level, scope, fmt:format(...)))
	f:close()
end

---@class Log.Scoped
---@field info fun(fmt: string, ...)
---@field warn fun(fmt: string, ...)
---@field error fun(fmt: string, ...)

--- A logger whose lines are all tagged with `scope`.
---@param scope string
---@return Log.Scoped
function M.scope(scope)
	return {
		info = function(fmt, ...) write("INFO", scope, fmt, ...) end,
		warn = function(fmt, ...) write("WARN", scope, fmt, ...) end,
		error = function(fmt, ...) write("ERROR", scope, fmt, ...) end,
	}
end

return M
