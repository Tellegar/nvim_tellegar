-- clangd silently drops a missing `@foo.modmap` response-file argument instead of
-- erroring, so a not-yet-built module TU gets compiled without -std/-fmodule-file
-- flags and floods the buffer with bogus parse errors. Detect the missing modmap
-- ourselves and replace clangd's noise with one clear diagnostic.
local M = {}

local ns_check = vim.api.nvim_create_namespace("clangd_modmap_check")

local function compile_commands_dir(client)
	for _, arg in ipairs(client.config.cmd or {}) do
		local dir = arg:match("^%-%-compile%-commands%-dir=(.+)$")
		if dir then
			return dir
		end
	end
end

-- Returns the modmap path referenced by this file's compile command, or nil if
-- the file has no compile command or its command has no modmap (not a module TU).
local function find_modmap(cdb_dir, filepath)
	local ok, lines = pcall(vim.fn.readfile, cdb_dir .. "/compile_commands.json")
	if not ok then
		return nil
	end
	local ok2, db = pcall(vim.json.decode, table.concat(lines, "\n"))
	if not ok2 then
		return nil
	end

	for _, entry in ipairs(db) do
		if vim.fs.abspath(entry.file) == filepath then
			local cmd = entry.command or table.concat(entry.arguments or {}, " ")
			local modmap = cmd:match("@([^%s]+%.modmap)")
			if not modmap then
				return nil
			end
			if not modmap:match("^/") then
				modmap = (entry.directory or cdb_dir) .. "/" .. modmap
			end
			return modmap
		end
	end
	return nil
end

local function ninja_target_for(modmap_path)
	return modmap_path:match("([%w_%-]+)%.dir/") or "?"
end

function M.check(bufnr, client)
	local cdb_dir = compile_commands_dir(client)
	if not cdb_dir then
		return
	end

	local filepath = vim.api.nvim_buf_get_name(bufnr)
	local modmap = find_modmap(cdb_dir, filepath)
	local diag_ns = vim.lsp.diagnostic.get_namespace(client.id, false)

	if modmap and vim.fn.filereadable(modmap) == 0 then
		vim.diagnostic.enable(false, { bufnr = bufnr, ns_id = diag_ns })
		vim.diagnostic.set(ns_check, bufnr, {
			{
				lnum = 0,
				col = 0,
				severity = vim.diagnostic.severity.ERROR,
				source = "clangd-modmap-check",
				message = ("module map missing (%s) — target not built yet, run: ninja %s"):format(
					vim.fs.basename(modmap),
					ninja_target_for(modmap)
				),
			},
		})
	else
		vim.diagnostic.enable(true, { bufnr = bufnr, ns_id = diag_ns })
		vim.diagnostic.reset(ns_check, bufnr)
	end
end

function M.setup()
	vim.api.nvim_create_autocmd("LspAttach", {
		group = vim.api.nvim_create_augroup("clangd_modmap_check", { clear = true }),
		callback = function(args)
			local client = vim.lsp.get_client_by_id(args.data.client_id)
			if not client or client.name ~= "clangd" then
				return
			end
			M.check(args.buf, client)
			vim.api.nvim_create_autocmd("BufWritePost", {
				group = "clangd_modmap_check",
				buffer = args.buf,
				callback = function()
					M.check(args.buf, client)
				end,
			})
		end,
	})

	vim.api.nvim_create_user_command("ClangdModmapCheck", function()
		local client = vim.lsp.get_clients({ bufnr = 0, name = "clangd" })[1]
		if not client then
			vim.notify("clangd not attached to this buffer", vim.log.levels.WARN)
			return
		end
		M.check(0, client)
	end, {})
end

return M
