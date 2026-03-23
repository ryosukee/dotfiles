local ok, diffview = pcall(require, "diffview")
if not ok then
  return
end

diffview.setup({
  view = {
    default = { layout = "diff2_horizontal" },
    merge_tool = { layout = "diff3_mixed" },
    file_history = { layout = "diff2_horizontal" },
  },
  hooks = {
    diff_buf_read = function(bufnr)
      vim.opt_local.wrap = true
      vim.opt_local.list = false
      vim.opt_local.relativenumber = false
    end,
  },
  keymaps = {
    view = {
      ["q"] = "<Cmd>DiffviewClose<CR>",
    },
    file_panel = {
      ["q"] = "<Cmd>DiffviewClose<CR>",
    },
    file_history_panel = {
      ["q"] = "<Cmd>DiffviewClose<CR>",
    },
  },
})

-- Keymaps
vim.keymap.set("n", "<leader>do", "<Cmd>DiffviewOpen<CR>", { desc = "Diffview: open" })
vim.keymap.set("n", "<leader>dc", "<Cmd>DiffviewClose<CR>", { desc = "Diffview: close" })
vim.keymap.set("n", "<leader>dh", "<Cmd>DiffviewFileHistory %<CR>", { desc = "Diffview: file history" })
vim.keymap.set("n", "<leader>dH", "<Cmd>DiffviewFileHistory<CR>", { desc = "Diffview: branch history" })
vim.keymap.set("n", "<leader>dr", function()
  local branch = vim.fn.input("Diff against branch: ", "main")
  if branch ~= "" then
    vim.cmd("DiffviewOpen " .. branch)
  end
end, { desc = "Diffview: open against branch" })

-- Better diff highlights
vim.api.nvim_set_hl(0, "DiffAdd", { bg = "#1a3a2a" })
vim.api.nvim_set_hl(0, "DiffDelete", { bg = "#3a1a1a" })
vim.api.nvim_set_hl(0, "DiffChange", { bg = "#1a2a3a" })
vim.api.nvim_set_hl(0, "DiffText", { bg = "#2a4a5a" })
