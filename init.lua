-- Set leader before anything else
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

-- Load core config
require("config.commands")
require("config.mappings")
require("config.options")
require("config.lazy") -- Lazy plugin manager
