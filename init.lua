-- set leader before anything else
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

-- ".h" is ambiguous C/C++; default is filetype=cpp. This project's convention
-- is .h/.c = C, .hpp/.cpp/.cppm = C++, so flip the default to match.
vim.g.c_syntax_for_h = true

-- dedicated python virtual environment
vim.g.python3_host_prog = vim.fn.expand("~/.config/nvim/.venv/bin/python")
-- put its python3.13 on PATH so Mason's pip-based installers (e.g. cmake-language-server)
-- resolve it instead of the system python, which may be newer than a package supports
vim.env.PATH = vim.fn.expand("~/.config/nvim/.venv/bin") .. ":" .. vim.env.PATH

-- modular require
-- * doesnt exit on fail
-- * instead just notifies of error present in the file
---@param modname string
local function Require(modname)
	local ok, mod = pcall(require, modname)
	if not ok then
		vim.notify("Error loading " .. modname .. ": " .. mod, vim.log.levels.ERROR)
	end
end

-- load core config
Require("config.commands")
Require("config.mappings")
Require("config.callbacks")
Require("config.options")
Require("config.lazy")
Require("config.mappings2")

-- in your init.lua
local ts_indent = vim.fn["nvim_treesitter#indent"]

vim.keymap.set("n", "<leader>sie", function()
	vim.bo.indentexpr = "v:lua.MyIndentExpr()"
end, { desc = "set custom indentexpr" })

function _G.MyIndentExpr()
	local lnum = vim.v.lnum
	local indent = ts_indent(lnum)

	-- DEBUG: dump matched captures
	local parser = vim.treesitter.get_parser(0, "cpp") -- adjust ft
	local tree = parser:parse()[1]
	local root = tree:root()

	local node = root:descendant_for_range(lnum-1, 0, lnum-1, -1)
	if node then
		print("line", lnum, "node", node:type())
	end

	return indent
end
