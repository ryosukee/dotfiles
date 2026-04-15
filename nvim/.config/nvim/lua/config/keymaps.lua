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

  -- 静的メニュー項目 + カーソル位置に応じた動的項目を構築
  local items = vim.deepcopy(context_menu_items)

  -- カーソル位置に URL がある場合に項目を追加
  -- (markdown の [text](url) も vim.ui._get_urls が解決する。PopUp.Open\ in\ web\ browser と同じ仕組み)
  local ok_ui, ui = pcall(require, "vim.ui")
  if ok_ui and ui._get_urls then
    local urls = ui._get_urls()
    local url = urls and urls[1]
    if url and vim.startswith(url, "http") then
      table.insert(items, { label = "Open in web browser", desc = "カーソル位置の URL / Markdown リンクをブラウザで開く", action = function()
        vim.ui.open(url)
      end })
    end
  end

  -- カーソル位置に画像/mermaid がある場合に項目を追加
  local has_image = false
  local image_src = nil
  if pcall(require, "snacks") and Snacks.image and Snacks.image.doc then
    -- 同期的に判定するため find を使う
    local done = false
    Snacks.image.doc.find(vim.api.nvim_get_current_buf(), function(imgs)
      local cursor = vim.api.nvim_win_get_cursor(0)
      for _, img in ipairs(imgs) do
        local range = img.range
        if range then
          if (range[1] == range[3] and cursor[2] >= range[2] and cursor[2] <= range[4])
            or (range[1] ~= range[3] and cursor[1] >= range[1] and cursor[1] <= range[3]) then
            has_image = true
            image_src = img.src
            break
          end
        end
      end
      done = true
    end, { from = vim.api.nvim_win_get_cursor(0)[1], to = vim.api.nvim_win_get_cursor(0)[1] + 1 })
    vim.wait(100, function() return done end)
  end

  if has_image then
    table.insert(items, { label = "Preview here", desc = "フローティングで画像/mermaidをプレビュー (hjkl移動, q閉じ)", action = function()
      if _G._snacks_image_preview then _G._snacks_image_preview() end
    end })
    table.insert(items, { label = "Open in Preview.app", desc = "macOS Preview で画像を開く (ズーム自由)", action = function()
      Snacks.image.doc.at_cursor(function(src)
        if src then
          -- mermaid/latex 等は変換後のキャッシュ画像を開く
          local cache = vim.fn.glob(vim.fn.stdpath("cache") .. "/snacks/image/*" .. vim.fn.fnamemodify(src, ":t:r") .. "*.png")
          local target = cache ~= "" and vim.split(cache, "\n")[1] or src
          vim.fn.system({ "open", "-a", "Preview", target })
        end
      end)
    end })
  end

  local lines = {}
  local max_label = 0
  for _, item in ipairs(items) do
    if #item.label > max_label then max_label = #item.label end
  end

  for _, item in ipairs(items) do
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

-- Ask dotfiles (Claude) — floating popup backed by ~/.local/bin/cc-ask-dotfiles
map("n", "<leader>Ca", function()
  require("config.ask_dotfiles").open()
end, { desc = "Ask dotfiles (Claude)" })

-- Preview at cursor (image / mermaid / markdown table).
-- Dispatches to the right handler based on what's under the cursor:
--   - markdown table -> render-markdown popup on a scratch buffer
--   - image / mermaid -> snacks.image popup (kitty graphics)
-- The popup inside either variant shares the same movement / resize / f keys.
map("n", "<leader>ip", function()
  require("config.markdown_preview").dispatch()
end, { desc = "Preview at cursor (image/mermaid/table)" })

-- Markdown split preview: left = raw, right = rendered.
-- Toggle: press again to close the preview split.
-- um = inline toggle (LazyVim extra), uM = split preview toggle.
map("n", "<leader>uM", function()
  require("config.markdown_preview").split_preview()
end, { desc = "Markdown Split Preview" })
