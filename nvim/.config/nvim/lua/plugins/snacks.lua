return {
  {
    "snacks.nvim",
    keys = {
      { "<leader>go", function() Snacks.gitbrowse({ what = "file" }) end, desc = "Open in GitHub", mode = { "n", "v" } },
      { "<leader>gO", function() Snacks.gitbrowse({ what = "permalink" }) end, desc = "Open in GitHub (permalink)", mode = { "n", "v" } },
      { "<leader>ip", function()
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
          local o = Snacks.config.merge({}, Snacks.image.config.doc, {
            on_update_pre = function()
              if win._snacks_img then
                local loc = win._snacks_img:state().loc
                win.opts.width = loc.width
                win.opts.height = loc.height
                win:show()
                -- 表示後に移動・閉じるキーマップを設定
                local wid = win.win
                local function move(dr, dc)
                  local cfg = vim.api.nvim_win_get_config(wid)
                  cfg.row = cfg.row + dr
                  cfg.col = cfg.col + dc
                  vim.api.nvim_win_set_config(wid, cfg)
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
              end
            end,
            inline = false,
          })
          win._snacks_img = Snacks.image.placement.new(win.buf, src, o)
        end)
      end, desc = "Preview image/mermaid at cursor" },
    },
    opts = {
      image = {
        enabled = true,
        backend = "kitty",
        doc = {
          enabled = false, -- 自動表示 OFF、トグルで表示
          inline = true,
          float = true,
          max_width = 60,
          max_height = 20,
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
      },
    },
  },
}
