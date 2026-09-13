-- Disable auto-completion in prose filetypes (markdown, text, etc.)
return {
  "saghen/blink.cmp",
  opts = {
    enabled = function()
      local disabled_filetypes = { markdown = true, text = true, gitcommit = true }
      return not disabled_filetypes[vim.bo.filetype]
    end,
  },
}
