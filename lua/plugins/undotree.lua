return {
	"mbbill/undotree",
	keys = require("config.mappings").plugin_keymap.undotree,
	init = function()
		vim.g.undotree_WindowLayout = 3
	end
}
