return {
  {
    "sindrets/diffview.nvim",
    cmd = { "DiffviewOpen", "DiffviewClose", "DiffviewFileHistory" },
    keys = {
      { "<leader>do", "<Cmd>DiffviewOpen<CR>", desc = "Diffview: open" },
      { "<leader>dc", "<Cmd>DiffviewClose<CR>", desc = "Diffview: close" },
      { "<leader>dh", "<Cmd>DiffviewFileHistory %<CR>", desc = "Diffview: file history" },
      { "<leader>dH", "<Cmd>DiffviewFileHistory<CR>", desc = "Diffview: branch history" },
      {
        "<leader>dr",
        function()
          local branch = vim.fn.input("Diff against branch: ", "main")
          if branch ~= "" then
            vim.cmd("DiffviewOpen " .. branch)
          end
        end,
        desc = "Diffview: open against branch",
      },
    },
    opts = {
      view = {
        default = { layout = "diff2_horizontal" },
        merge_tool = { layout = "diff3_mixed" },
        file_history = { layout = "diff2_horizontal" },
      },
      hooks = {
        diff_buf_read = function()
          vim.opt_local.wrap = true
          vim.opt_local.list = false
          vim.opt_local.relativenumber = false
        end,
        view_opened = function()
          _G._diffview_saved_showtabline = vim.o.showtabline
          vim.schedule(function()
            vim.o.showtabline = 0
          end)
        end,
        view_enter = function()
          vim.schedule(function()
            vim.o.showtabline = 0
          end)
        end,
        view_leave = function()
          vim.schedule(function()
            vim.o.showtabline = _G._diffview_saved_showtabline or 2
          end)
        end,
        view_closed = function()
          _G._diffview_viewed = nil
          vim.schedule(function()
            vim.o.showtabline = _G._diffview_saved_showtabline or 2
            _G._diffview_saved_showtabline = nil
          end)
        end,
      },
      keymaps = {
        view = { ["q"] = "<Cmd>DiffviewClose<CR>" },
        file_panel = {
          ["q"] = "<Cmd>DiffviewClose<CR>",
          ["X"] = false, -- restore file from index を無効化
        },
        file_history_panel = { ["q"] = "<Cmd>DiffviewClose<CR>" },
      },
    },
    config = function(_, opts)
      require("diffview").setup(opts)

      -- Custom diff highlight colors
      vim.api.nvim_set_hl(0, "DiffAdd", { bg = "#1a3a2a" })
      vim.api.nvim_set_hl(0, "DiffDelete", { bg = "#3a1a1a" })
      vim.api.nvim_set_hl(0, "DiffChange", { bg = "#1a2a3a" })
      vim.api.nvim_set_hl(0, "DiffText", { bg = "#2a4a5a" })
    end,
  },
}
