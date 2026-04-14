-- 画像/mermaid プレビュー関数 (keymaps.lua のコンテキストメニューからも呼ばれる)
local function image_preview()
  Snacks.image.doc.at_cursor(function(src)
    if not src then
      vim.notify("No image/mermaid at cursor")
      return
    end
    local win = Snacks.win(Snacks.win.resolve(Snacks.image.config.doc, "snacks_image", {
      show = false,
      enter = false,
      backdrop = false,
      focusable = true,
      wo = { winblend = 0 },
    }))
    win:open_buf()

    local img_src = src
    local keymaps_set = false

    local force_size = nil -- { w, h } を設定するとウィンドウサイズを強制
    local is_full = false
    local saved_full = { w = nil, h = nil, pos = nil }

    local function make_opts(w, h)
      return Snacks.config.merge({}, Snacks.image.config.doc, {
        width = w,
        height = h,
        max_width = w,
        max_height = h,
        on_update_pre = function()
          if win._snacks_img then
            local loc = win._snacks_img:state().loc
            if force_size then
              win.opts.width = force_size[1]
              win.opts.height = force_size[2]
            else
              win.opts.width = loc.width
              win.opts.height = loc.height
            end
            win:show()
            if force_size and win.win and vim.api.nvim_win_is_valid(win.win) then
              vim.api.nvim_win_set_config(win.win, { width = force_size[1], height = force_size[2] })
            end
            if not keymaps_set then
              keymaps_set = true
              local wid = win.win
              local function move(dr, dc)
                local pos = vim.api.nvim_win_get_position(wid)
                vim.api.nvim_win_set_config(wid, {
                  relative = "editor",
                  row = pos[1] + dr,
                  col = pos[2] + dc,
                })
              end
              local cur_w = vim.api.nvim_win_get_width(wid)
              local cur_h = vim.api.nvim_win_get_height(wid)
              local function do_resize(dw, dh)
                if not win._snacks_img then return end
                cur_w = math.max(10, cur_w + dw)
                cur_h = math.max(5, cur_h + dh)
                local saved_pos = vim.api.nvim_win_get_position(wid)
                keymaps_set = false
                win._snacks_img:close()
                win._snacks_img = Snacks.image.placement.new(win.buf, img_src, make_opts(cur_w, cur_h))
                vim.defer_fn(function()
                  if vim.api.nvim_win_is_valid(wid) then
                    vim.api.nvim_win_set_config(wid, {
                      relative = "editor",
                      row = saved_pos[1],
                      col = saved_pos[2],
                    })
                  end
                end, 50)
              end
              local bopts = { buffer = win.buf, nowait = true }
              vim.keymap.set("n", "q", function() win:close() end, bopts)
              vim.keymap.set("n", "<Up>", function() move(-2, 0) end, bopts)
              vim.keymap.set("n", "<Down>", function() move(2, 0) end, bopts)
              vim.keymap.set("n", "<Left>", function() move(0, -4) end, bopts)
              vim.keymap.set("n", "<Right>", function() move(0, 4) end, bopts)
              vim.keymap.set("n", "k", function() move(-2, 0) end, bopts)
              vim.keymap.set("n", "j", function() move(2, 0) end, bopts)
              vim.keymap.set("n", "h", function() move(0, -4) end, bopts)
              vim.keymap.set("n", "l", function() move(0, 4) end, bopts)
              vim.keymap.set("n", "+", function() do_resize(4, 2) end, bopts)
              vim.keymap.set("n", "-", function() do_resize(-4, -2) end, bopts)
              vim.keymap.set("n", "<S-Right>", function() do_resize(4, 0) end, bopts)
              vim.keymap.set("n", "<S-Left>", function() do_resize(-4, 0) end, bopts)
              vim.keymap.set("n", "<S-Down>", function() do_resize(0, 2) end, bopts)
              vim.keymap.set("n", "<S-Up>", function() do_resize(0, -2) end, bopts)
              -- macOS Preview で開く
              vim.keymap.set("n", "o", function()
                local cache = vim.fn.glob(vim.fn.stdpath("cache") .. "/snacks/image/*" .. vim.fn.fnamemodify(img_src, ":t:r") .. "*.png")
                local target = cache ~= "" and vim.split(cache, "\n")[1] or img_src
                vim.fn.system({ "open", "-a", "Preview", target })
              end, bopts)
              -- フルスクリーントグル
              vim.keymap.set("n", "f", function()
                if not win._snacks_img then return end
                local current_pos = vim.api.nvim_win_get_position(wid)
                if is_full then
                  -- 元サイズに戻す
                  force_size = nil
                  cur_w = saved_full.w
                  cur_h = saved_full.h
                  keymaps_set = false
                  win._snacks_img:close()
                  win._snacks_img = Snacks.image.placement.new(win.buf, img_src, make_opts(cur_w, cur_h))
                  vim.defer_fn(function()
                    if vim.api.nvim_win_is_valid(wid) then
                      vim.api.nvim_win_set_config(wid, {
                        relative = "editor", row = saved_full.pos[1], col = saved_full.pos[2],
                      })
                    end
                  end, 50)
                else
                  -- フルスクリーン: ウィンドウサイズを画面全体に強制
                  saved_full.w = cur_w
                  saved_full.h = cur_h
                  saved_full.pos = current_pos
                  cur_w = vim.o.columns - 2
                  cur_h = vim.o.lines - 2
                  force_size = { cur_w, cur_h }
                  keymaps_set = false
                  win._snacks_img:close()
                  win._snacks_img = Snacks.image.placement.new(win.buf, img_src, make_opts(cur_w, cur_h))
                  vim.defer_fn(function()
                    if vim.api.nvim_win_is_valid(wid) then
                      vim.api.nvim_win_set_config(wid, {
                        relative = "editor", row = 0, col = 0,
                      })
                    end
                  end, 50)
                end
                is_full = not is_full
              end, bopts)
            end
          end
        end,
        inline = false,
      })
    end

    local init_w = math.floor(vim.o.columns * 0.8)
    local init_h = math.floor(vim.o.lines * 0.8)
    local o = make_opts(init_w, init_h)
    win._snacks_img = Snacks.image.placement.new(win.buf, img_src, o)
  end)
end

-- グローバルに公開 (コンテキストメニューから呼ぶため)
_G._snacks_image_preview = image_preview

return {
  {
    "snacks.nvim",
    keys = {
      { "<leader>go", function() Snacks.gitbrowse({ what = "file" }) end, desc = "Open in GitHub", mode = { "n", "v" } },
      { "<leader>gO", function() Snacks.gitbrowse({ what = "permalink" }) end, desc = "Open in GitHub (permalink)", mode = { "n", "v" } },
      -- <leader>ip is wired in lua/config/keymaps.lua to a dispatcher that
      -- covers image/mermaid AND markdown tables with a single entry point.
    },
    opts = {
      image = {
        enabled = true,
        backend = "kitty",
        convert = {
          mermaid = function()
            local theme = vim.o.background == "light" and "neutral" or "dark"
            return { "-i", "{src}", "-o", "{file}", "-b", "transparent", "-t", theme, "-s", "4" }
          end,
        },
        doc = {
          enabled = false,
          inline = true,
          float = true,
        },
      },
      dashboard = {
        preset = {
          -- stylua: ignore
          keys = {
            { icon = " ", key = "f", desc = "Find File", action = ":lua Snacks.dashboard.pick('files')" },
            { icon = " ", key = "n", desc = "New File", action = ":ene | startinsert" },
            { icon = " ", key = "/", desc = "Find Text", action = ":lua Snacks.dashboard.pick('live_grep')" },
            { icon = " ", key = "r", desc = "Recent Files", action = ":lua Snacks.dashboard.pick('oldfiles')" },
            { icon = " ", key = "c", desc = "Config", action = ":lua Snacks.dashboard.pick('files', {cwd = vim.fn.stdpath('config')})" },
            { icon = " ", key = "s", desc = "Restore Session", section = "session" },
            { icon = " ", key = "x", desc = "Lazy Extras", action = ":LazyExtras" },
            { icon = "󰒲 ", key = "l", desc = "Lazy", action = ":Lazy" },
            { icon = " ", key = "q", desc = "Quit", action = ":qa" },
          },
        },
        -- 1-pane 縦一列: header → keys → Recent Files → Projects → startup
        -- snacks docs の 'files' example ベース。Recent Files と Projects を
        -- dashboard に直接表示する (`r` キーは picker 起動、section は一覧表示)。
        sections = {
          { section = "header" },
          { section = "keys", gap = 1, padding = 1 },
          { icon = " ", title = "Recent Files", section = "recent_files", indent = 2, padding = { 2, 2 } },
          { icon = " ", title = "Projects", section = "projects", indent = 2, padding = 2 },
          { section = "startup" },
        },
      },
    },
  },
}
