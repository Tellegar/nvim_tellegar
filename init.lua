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
