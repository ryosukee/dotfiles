-- diffview file tree に ✓ マークを付ける描画ロジック
-- キーマップは diffview.lua の file_panel["x"] で定義
-- 不要になったらこのファイルを削除し、diffview.lua から x キーマップも消す

local ns = vim.api.nvim_create_namespace("diffview_viewed")
local augroup = vim.api.nvim_create_augroup("diffview_viewed", { clear = true })

_G._diffview_refresh_marks = function(view)
  if not _G._diffview_viewed then return end
  local bufid = view and view.panel and view.panel.bufid
  if not bufid or not vim.api.nvim_buf_is_valid(bufid) then return end

  vim.api.nvim_buf_clear_namespace(bufid, ns, 0, -1)
  local lines = vim.api.nvim_buf_get_lines(bufid, 0, -1, false)
  for i, line in ipairs(lines) do
    for path, _ in pairs(_G._diffview_viewed) do
      -- 親ディレクトリ/ファイル名で結合マッチ (同名ファイルの誤マッチを防ぐ)
      local filename = vim.fn.fnamemodify(path, ":t")
      local parent = vim.fn.fnamemodify(path, ":h:t")
      local needle = parent == "." and filename or (parent .. "/" .. filename)
      local col_start = line:find(filename, 1, true)
      if col_start and line:find(needle, 1, true) then
        vim.api.nvim_buf_set_extmark(bufid, ns, i - 1, col_start - 1, {
          virt_text = { { "✓ ", "DiagnosticOk" } },
          virt_text_pos = "inline",
          right_gravity = false,
        })
      end
    end
  end
end

vim.api.nvim_create_autocmd("BufWinEnter", {
  group = augroup,
  callback = function(ev)
    if vim.bo[ev.buf].filetype == "DiffviewFiles" then
      vim.schedule(function()
        local lib = require("diffview.lib")
        local view = lib.get_current_view()
        _G._diffview_refresh_marks(view)
      end)
    end
  end,
})

return {}
