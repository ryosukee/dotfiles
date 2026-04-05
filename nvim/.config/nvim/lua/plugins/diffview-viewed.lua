-- diffview file tree に ✓ マークを付ける機能
-- x キーでトグル、diffview 終了時にリセット
-- 不要になったらこのファイルを削除するだけで無効化できる

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

return {
  {
    "sindrets/diffview.nvim",
    opts = {
      keymaps = {
        file_panel = {
          ["x"] = function()
            local lib = require("diffview.lib")
            local view = lib.get_current_view()
            if not view then return end
            local item = view.panel:get_item_at_cursor()
            if not item or not item.path then return end

            _G._diffview_viewed = _G._diffview_viewed or {}
            if _G._diffview_viewed[item.path] then
              _G._diffview_viewed[item.path] = nil
            else
              _G._diffview_viewed[item.path] = true
            end

            _G._diffview_refresh_marks(view)
          end,
        },
      },
    },
  },
}
