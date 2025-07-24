local map = vim.keymap.set

map({"n", "x"}, "J", "jzz", { desc = "shift move - keep centered" })
map({"n", "x"}, "K", "kzz", { desc = "shift move - keep centered" })

map("n", "L", ":set list!<CR>", { desc = "toggle whitespace visibility" })

map("n", "<Esc>", "<cmd>noh<CR>", { desc = "clear highlights" })

map("n", "<C-s>", "<cmd>w<CR>", { desc = "general save file" })
map("n", "<C-c>", "<cmd>%y+<CR>", { desc = "general copy whole file" })

map("v", "+", '"+y', { desc = "copy selection to system clipboard" })

