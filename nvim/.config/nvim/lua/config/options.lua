-- Options (migrated from init.vim)
-- LazyVim defaults: https://www.lazyvim.org/configuration/general

local opt = vim.opt

opt.tabstop = 4
opt.shiftwidth = 4

opt.showmatch = true

-- Visible whitespace
opt.list = true
opt.listchars = { tab = "»-", trail = "-", extends = "»", precedes = "«", nbsp = "%" }

-- Disable conceal (LazyVim defaults to 3)
opt.conceallevel = 0

-- Search
opt.wrapscan = true

-- Match pairs
opt.matchpairs:append("<:>")
