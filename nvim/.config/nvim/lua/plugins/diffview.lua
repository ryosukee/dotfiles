-- アイコン (最後のマルチバイト文字) の開始バイト位置を返す
local function find_last_icon_pos(text)
  local last_mb_start = 0
  local pos = 1
  while pos <= #text do
    local byte = text:byte(pos)
    if byte >= 0xF0 then last_mb_start = pos; pos = pos + 4
    elseif byte >= 0xE0 then last_mb_start = pos; pos = pos + 3
    elseif byte >= 0xC0 then last_mb_start = pos; pos = pos + 2
    else pos = pos + 1 end
  end
  return last_mb_start > 0 and last_mb_start or (text:find("%S") or 1)
end

-- comp からマーク用のキーを取得 (file と dir_name で取得方法が異なる)
local function get_comp_key(comp)
  if not comp then return nil end
  if comp.name == "file" and comp.context then
    return comp.context.path
  elseif comp.name == "dir_name" and comp.parent and comp.parent.context then
    local ctx = comp.parent.context
    return ctx.path or ctx.name
  end
  return nil
end

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
          ["x"] = function()
            local lib = require("diffview.lib")
            local view = lib.get_current_view()
            if not view then return end

            local line = vim.api.nvim_win_get_cursor(view.panel.winid)[1]
            local comp = view.panel.components
              and view.panel.components.comp
              and view.panel.components.comp:get_comp_on_line(line)
            local key = get_comp_key(comp)
            if not key then return end

            _G._diffview_viewed = _G._diffview_viewed or {}
            if _G._diffview_viewed[key] then
              _G._diffview_viewed[key] = nil
            else
              _G._diffview_viewed[key] = true
            end

            vim.schedule(function()
              _G._diffview_refresh_marks(view)
            end)
          end,
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

      -- ✓ マーク描画
      local ns = vim.api.nvim_create_namespace("diffview_viewed")
      local attached_bufs = {}

      -- パネルバッファの変更を監視して ✓ を付け直す
      local function ensure_buf_attached(view)
        local bufid = view and view.panel and view.panel.bufid
        if not bufid or attached_bufs[bufid] then return end
        attached_bufs[bufid] = true
        vim.api.nvim_buf_attach(bufid, false, {
          on_lines = function()
            vim.schedule(function()
              if _G._diffview_refresh_marks then
                local lib = require("diffview.lib")
                local v = lib.get_current_view()
                if v then _G._diffview_refresh_marks(v) end
              end
            end)
          end,
          on_detach = function()
            attached_bufs[bufid] = nil
          end,
        })
      end

      _G._diffview_refresh_marks = function(view)
        if not _G._diffview_viewed or not next(_G._diffview_viewed) then return end
        local bufid = view and view.panel and view.panel.bufid
        if not bufid or not vim.api.nvim_buf_is_valid(bufid) then return end

        vim.api.nvim_buf_clear_namespace(bufid, ns, 0, -1)
        local line_count = vim.api.nvim_buf_line_count(bufid)
        for i = 1, line_count do
          local comp = view.panel.components
            and view.panel.components.comp
            and view.panel.components.comp:get_comp_on_line(i)
          local key = get_comp_key(comp)
          if key and _G._diffview_viewed[key] then
            local text = vim.api.nvim_buf_get_lines(bufid, i - 1, i, false)[1] or ""
            local col = find_last_icon_pos(text)
            vim.api.nvim_buf_set_extmark(bufid, ns, i - 1, col - 1, {
              virt_text = { { "✓ ", "DiagnosticOk" } },
              virt_text_pos = "inline",
              right_gravity = false,
            })
          end
        end
        ensure_buf_attached(view)
      end
    end,
  },
}
