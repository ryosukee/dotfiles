-- Keymaps (migrated from init.vim)
-- LazyVim defaults: https://www.lazyvim.org/configuration/keymaps

local map = vim.keymap.set

-- Move by visual lines
map("n", "j", "gj", { desc = "Down (visual line)" })
map("n", "k", "gk", { desc = "Up (visual line)" })

-- Toggle wrap
map("n", "<ESC>l", "<Cmd>set nowrap<CR>", { desc = "Disable wrap" })
map("n", "<ESC>h", "<Cmd>set wrap<CR>", { desc = "Enable wrap" })

-- Restore native 's' (delete char and insert), overriding flash.nvim
map({ "n", "x" }, "s", "s")

-- Context menu (カーソル位置にコンパクト表示 + 右側にツールチップ)
local context_menu_items = {
  { label = "Go to Definition", desc = "シンボルの定義元にジャンプ", action = vim.lsp.buf.definition },
  { label = "Find References", desc = "シンボルの参照箇所を一覧表示", action = vim.lsp.buf.references },
  { label = "Rename", desc = "シンボル名を一括リネーム", action = vim.lsp.buf.rename },
  { label = "Code Action", desc = "LSP の修正・リファクタ候補を表示", action = vim.lsp.buf.code_action },
  { label = "Open in GitHub", desc = "現在のファイル+行をブラウザで開く", action = function() Snacks.gitbrowse({ what = "file" }) end },
  { label = "Open Permalink", desc = "コミット固定 URL でブラウザを開く", action = function() Snacks.gitbrowse({ what = "permalink" }) end },
  { label = "Copy GitHub URL", desc = "Permalink をクリップボードにコピー", action = function()
    Snacks.gitbrowse({ what = "permalink", open = function(url)
      vim.fn.setreg("+", url)
      vim.notify("Copied: " .. url)
    end })
  end },
}

local function open_context_menu()
  local NuiMenu = require("nui.menu")
  local NuiPopup = require("nui.popup")

  local lines = {}
  local max_label = 0
  for _, item in ipairs(context_menu_items) do
    if #item.label > max_label then max_label = #item.label end
  end

  for _, item in ipairs(context_menu_items) do
    table.insert(lines, NuiMenu.item(item.label, { desc = item.desc, action = item.action }))
  end

  local tooltip = NuiPopup({
    border = { style = "rounded", text = { top = " Hint ", top_align = "center" } },
    win_options = { winblend = 0, winhighlight = "Normal:NormalFloat,FloatBorder:FloatBorder" },
    relative = "editor",
    position = { row = 0, col = 0 },
    size = { width = 40, height = 1 },
    zindex = 60,
  })

  local menu
  menu = NuiMenu({
    border = { style = "rounded", text = { top = " Context Menu ", top_align = "center" } },
    win_options = { winblend = 10, winhighlight = "Normal:NormalFloat,FloatBorder:FloatBorder,CursorLine:PmenuSel" },
    relative = "cursor",
    position = { row = 1, col = 0 },
    size = { width = max_label + 4 },
    zindex = 50,
  }, {
    lines = lines,
    keymap = {
      focus_next = { "j", "<Down>", "<Tab>" },
      focus_prev = { "k", "<Up>", "<S-Tab>" },
      close = { "<Esc>", "q" },
      submit = { "<CR>", "l" },
    },
    on_change = function(item)
      if not tooltip.winid or not vim.api.nvim_win_is_valid(tooltip.winid) then return end
      local buf = tooltip.bufnr
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { " " .. (item.desc or "") .. " " })
      -- ツールチップをメニューの右隣に配置
      local menu_pos = vim.api.nvim_win_get_position(menu.winid)
      local menu_w = vim.api.nvim_win_get_width(menu.winid)
      vim.api.nvim_win_set_config(tooltip.winid, {
        relative = "editor",
        row = menu_pos[1],
        col = menu_pos[2] + menu_w + 1,
        width = math.max(#(item.desc or "") + 4, 10),
        height = 1,
        border = "rounded",
      })
    end,
    on_submit = function(item)
      tooltip:unmount()
      if item.action then
        vim.schedule(item.action)
      end
    end,
    on_close = function()
      tooltip:unmount()
    end,
  })

  menu:mount()
  tooltip:mount()

  -- 初期表示: 最初の項目の説明を表示
  local first = context_menu_items[1]
  if first then
    vim.api.nvim_buf_set_lines(tooltip.bufnr, 0, -1, false, { " " .. (first.desc or "") .. " " })
    vim.schedule(function()
      if menu.winid and vim.api.nvim_win_is_valid(menu.winid) then
        local menu_pos = vim.api.nvim_win_get_position(menu.winid)
        local menu_w = vim.api.nvim_win_get_width(menu.winid)
        vim.api.nvim_win_set_config(tooltip.winid, {
          relative = "editor",
          row = menu_pos[1],
          col = menu_pos[2] + menu_w + 1,
          width = math.max(#(first.desc or "") + 4, 10),
          height = 1,
          border = "rounded",
        })
      end
    end)
  end
end

map({ "n", "v" }, "<leader>a", open_context_menu, { desc = "Context menu" })
