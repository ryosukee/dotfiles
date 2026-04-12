-- Markdown-related plugin overrides for the LazyVim lang.markdown extra.
--
-- 1. render-markdown.nvim: keep it off by default so normal markdown buffers
--    stay raw. lua/config/markdown_preview.lua uses `buf_enable()` to turn it
--    on per-buffer for the popup's scratch buffer only. The extra already
--    wires `<leader>um` to Snacks.toggle for toggling global rendering on/off.
--
-- 2. iamcco/markdown-preview.nvim: disabled. The extra installs it for a
--    browser-based preview, but the workflow here is vim-internal only
--    (snacks.image for kitty graphics + render-markdown popup for tables).
return {
  {
    "MeanderingProgrammer/render-markdown.nvim",
    opts = {
      enabled = false,
    },
  },
  {
    "iamcco/markdown-preview.nvim",
    enabled = false,
  },
}
