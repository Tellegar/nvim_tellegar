-- lua_ls reports "unused-function" diagnostics with the whole function
-- statement as the range (LSP DiagnosticTag.Unnecessary), so the built-in
-- strikethrough covers the entire body instead of just the name. Other
-- "unused" diagnostics (e.g. unused-local/unused-parameter) already get a
-- correctly-scoped range by default, so only unused-function is touched here.

local M = {}

local UNNECESSARY = 1 -- lsp.DiagnosticTag.Unnecessary

---@param diag table
---@param bufnr integer
local function shrink(diag, bufnr)
	if diag.code ~= "unused-function" then
		return
	end
	if not (diag.tags and vim.list_contains(diag.tags, UNNECESSARY)) then
		return
	end

	local line = diag.range.start.line
	local text = vim.api.nvim_buf_get_lines(bufnr, line, line + 1, false)[1]
	if not text then
		return
	end

	local name = diag.message:match("`([%w_.]+)`") or text:match("function%s+([%w_.:]+)")
	local s, e
	if name then
		-- word-boundary search, so e.g. `define` doesn't match inside `bi_define`
		local pat = "%f[%w_]" .. name:gsub("%W", "%%%0") .. "%f[^%w_]"
		s, e = text:find(pat)
	end
	if not s then
		-- fallback: at least don't let it span multiple lines
		diag.range["end"].line = line
		diag.range["end"].character = #text
		return
	end

	diag.range["end"].line = line
	diag.range.start.character = s - 1
	diag.range["end"].character = e
end

function M.setup()
	local orig = vim.lsp.handlers["textDocument/publishDiagnostics"]
	vim.lsp.handlers["textDocument/publishDiagnostics"] = function(err, result, ctx, config)
		if result and result.diagnostics then
			local bufnr = vim.uri_to_bufnr(result.uri)
			if vim.api.nvim_buf_is_loaded(bufnr) then
				for _, d in ipairs(result.diagnostics) do
					shrink(d, bufnr)
				end
			end
		end
		return orig(err, result, ctx, config)
	end
end

return M
