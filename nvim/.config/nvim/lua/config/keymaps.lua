-- Keymaps (migrated from init.vim)
-- LazyVim defaults: https://www.lazyvim.org/configuration/keymaps

local map = vim.keymap.set

-- Move by visual lines
map("n", "j", "gj", { desc = "Down (visual line)" })
map("n", "k", "gk", { desc = "Up (visual line)" })

-- Clear search highlighting
map("n", "<ESC><ESC>", "<Cmd>nohlsearch<CR>", { desc = "Clear search highlight" })

-- Toggle wrap
map("n", "<ESC>l", "<Cmd>set nowrap<CR>", { desc = "Disable wrap" })
map("n", "<ESC>h", "<Cmd>set wrap<CR>", { desc = "Enable wrap" })
