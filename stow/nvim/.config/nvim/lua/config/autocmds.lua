-- Disable format-on-save for markdown. The LazyVim lang.markdown extra pulls
-- in prettier (+ markdownlint-cli2 auto-fix and markdown-toc) as conform.nvim
-- formatters. Existing docs predate this setup, so running them on every
-- save would rewrite large chunks of text. Lint diagnostics (via nvim-lint
-- running markdownlint-cli2) stay active so new markdown still gets feedback.
--
-- `<leader>cf` still formats on demand because it bypasses the autoformat
-- gate and calls conform directly.
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "markdown", "markdown.mdx" },
  callback = function()
    vim.b.autoformat = false
  end,
})
