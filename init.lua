-- set leader before anything else
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

-- ".h" is ambiguous C/C++; default is filetype=cpp. This project's convention
-- is .h/.c = C, .hpp/.cpp/.cppm = C++, so flip the default to match.
vim.g.c_syntax_for_h = true

-- dedicated python virtual environment
vim.g.python3_host_prog = vim.fn.expand("~/.config/nvim/.venv/bin/python")
-- vim.g.python3_host_prog = vim.fn.expand("/home/tellegar/.config/nvim/.venv/bin/python")

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
Require("config.options")
Require("config.lazy")
