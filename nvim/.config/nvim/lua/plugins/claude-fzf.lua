return {
  {
    "ibhagwan/fzf-lua",
    -- fzf-lua is already included in LazyVim; this extends it for Claude Code
    opts = function(_, opts)
      -- .claude extension as its own filetype
      vim.filetype.add({
        extension = {
          claude = "claude",
        },
      })

      -- In claude filetype, @ triggers fzf file picker
      vim.api.nvim_create_autocmd("FileType", {
        pattern = { "claude" },
        callback = function(ev)
          vim.keymap.set("i", "@", function()
            local fzf = require("fzf-lua")
            local selected_path = nil
            fzf.files({
              file_icons = false,
              git_icons = false,
              actions = {
                ["default"] = function(selected, action_opts)
                  if selected and selected[1] then
                    local file = require("fzf-lua.path").entry_to_file(selected[1], action_opts)
                    selected_path = file and file.path or nil
                  end
                end,
              },
              winopts = {
                on_close = function()
                  vim.schedule(function()
                    if selected_path then
                      vim.api.nvim_put({ "@" .. selected_path .. " " }, "", false, true)
                    else
                      vim.api.nvim_put({ "@" }, "", false, true)
                    end
                    vim.defer_fn(function()
                      vim.cmd("startinsert!")
                    end, 10)
                  end)
                end,
              },
            })
          end, { buffer = ev.buf, noremap = true })
        end,
      })

      return opts
    end,
  },
}
