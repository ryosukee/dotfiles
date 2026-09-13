-- Markdown element popup preview.
-- Renders the element under cursor (currently: tables) in a floating window
-- using render-markdown.nvim's per-buffer enable API on a scratch buffer.
-- The source buffer is never touched and global render state is never changed.
--
-- Exposes `dispatch()` which unifies the preview entry point:
--   1. If cursor is on a markdown table -> popup-render the table
--   2. Otherwise -> delegate to the existing image/mermaid preview (snacks)
-- The movement / resize / fullscreen interface inside the popup matches the
-- image preview popup in lua/plugins/snacks.lua so both share one mental model.

local M = {}

local function get_lines(buf, range)
  return vim.api.nvim_buf_get_lines(buf, range.start - 1, range.stop, false)
end

-- Contiguous lines starting with "|" form a markdown table block.
-- Returns { start, stop } (1-indexed, inclusive) or nil.
local function find_table_range(buf, row)
  local total = vim.api.nvim_buf_line_count(buf)
  local function is_table_line(lineno)
    if lineno < 1 or lineno > total then return false end
    local line = vim.api.nvim_buf_get_lines(buf, lineno - 1, lineno, false)[1]
    return line ~= nil and line:match("^%s*|") ~= nil
  end

  if not is_table_line(row) then return nil end

  local start_row = row
  while start_row > 1 and is_table_line(start_row - 1) do
    start_row = start_row - 1
  end
  local stop_row = row
  while stop_row < total and is_table_line(stop_row + 1) do
    stop_row = stop_row + 1
  end
  return { start = start_row, stop = stop_row }
end

-- Attach the shared popup navigation keymaps (matches image_preview).
local function attach_popup_keys(win, buf, initial_width, initial_height)
  local function valid()
    return vim.api.nvim_win_is_valid(win)
  end

  local function close()
    if valid() then vim.api.nvim_win_close(win, true) end
  end

  local function move(dr, dc)
    if not valid() then return end
    local pos = vim.api.nvim_win_get_position(win)
    vim.api.nvim_win_set_config(win, {
      relative = "editor",
      row = pos[1] + dr,
      col = pos[2] + dc,
    })
  end

  local function resize(dw, dh)
    if not valid() then return end
    local pos = vim.api.nvim_win_get_position(win)
    local cur_w = vim.api.nvim_win_get_width(win)
    local cur_h = vim.api.nvim_win_get_height(win)
    vim.api.nvim_win_set_config(win, {
      relative = "editor",
      row = pos[1],
      col = pos[2],
      width = math.max(10, cur_w + dw),
      height = math.max(3, cur_h + dh),
    })
  end

  local is_full = false
  local saved = { width = initial_width, height = initial_height, row = nil, col = nil }
  local function toggle_full()
    if not valid() then return end
    if is_full then
      vim.api.nvim_win_set_config(win, {
        relative = "editor",
        row = saved.row,
        col = saved.col,
        width = saved.width,
        height = saved.height,
      })
    else
      local pos = vim.api.nvim_win_get_position(win)
      saved.width = vim.api.nvim_win_get_width(win)
      saved.height = vim.api.nvim_win_get_height(win)
      saved.row = pos[1]
      saved.col = pos[2]
      vim.api.nvim_win_set_config(win, {
        relative = "editor",
        row = 0,
        col = 0,
        width = vim.o.columns - 2,
        height = vim.o.lines - 2,
      })
    end
    is_full = not is_full
  end

  local opts = { buffer = buf, silent = true, nowait = true }
  vim.keymap.set("n", "q", close, opts)
  vim.keymap.set("n", "<Esc>", close, opts)
  vim.keymap.set("n", "h", function() move(0, -4) end, opts)
  vim.keymap.set("n", "j", function() move(2, 0) end, opts)
  vim.keymap.set("n", "k", function() move(-2, 0) end, opts)
  vim.keymap.set("n", "l", function() move(0, 4) end, opts)
  vim.keymap.set("n", "<Left>", function() move(0, -4) end, opts)
  vim.keymap.set("n", "<Down>", function() move(2, 0) end, opts)
  vim.keymap.set("n", "<Up>", function() move(-2, 0) end, opts)
  vim.keymap.set("n", "<Right>", function() move(0, 4) end, opts)
  vim.keymap.set("n", "+", function() resize(4, 2) end, opts)
  vim.keymap.set("n", "-", function() resize(-4, -2) end, opts)
  vim.keymap.set("n", "<S-Left>", function() resize(-4, 0) end, opts)
  vim.keymap.set("n", "<S-Right>", function() resize(4, 0) end, opts)
  vim.keymap.set("n", "<S-Up>", function() resize(0, -2) end, opts)
  vim.keymap.set("n", "<S-Down>", function() resize(0, 2) end, opts)
  vim.keymap.set("n", "f", toggle_full, opts)
end

-- Core popup: takes a list of markdown lines and shows them in a floating
-- window with render-markdown.nvim enabled for that scratch buffer only.
local function popup_markdown(lines, title)
  if not lines or #lines == 0 then return end

  -- render-markdown renders the top border of a table / heading as a
  -- virtual line ATTACHED ABOVE the first content line. If that line is
  -- buffer row 1, the virtual line can collide with the popup's own
  -- rounded border and effectively vanish. Pad with one blank line at
  -- the top (and one at the bottom for symmetry) so the virtual borders
  -- have somewhere to sit.
  local padded = { "" }
  for _, l in ipairs(lines) do padded[#padded + 1] = l end
  padded[#padded + 1] = ""

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, padded)
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].modifiable = false

  local max_width = 1
  for _, line in ipairs(padded) do
    local w = vim.fn.strdisplaywidth(line)
    if w > max_width then max_width = w end
  end
  local width = math.min(vim.o.columns - 4, max_width + 4)
  local height = math.min(vim.o.lines - 4, #padded + 2)

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    border = "rounded",
    title = title and (" " .. title .. " ") or nil,
    title_pos = title and "center" or nil,
    style = "minimal",
  })
  vim.wo[win].wrap = false
  vim.wo[win].conceallevel = 3
  vim.wo[win].concealcursor = "nvic"
  vim.wo[win].cursorline = false
  vim.wo[win].spell = false

  -- Per-buffer enable: rendering applies only to this scratch buffer and
  -- does not change the global render-markdown state, so other markdown
  -- buffers remain raw. After enabling, disable anti-conceal so the cursor
  -- line stays fully rendered — this is a read-only popup, not an editor,
  -- so the "reveal raw markdown under cursor" behavior isn't useful here.
  pcall(function()
    local rm = require("render-markdown")
    rm.buf_enable()
    local cfg = require("render-markdown.state").get(buf)
    if cfg and cfg.anti_conceal then
      cfg.anti_conceal.enabled = false
    end
    -- Force a re-render now that the config changed.
    local ui = require("render-markdown.core.ui")
    local env = require("render-markdown.lib.env")
    ui.update(buf, env.buf.win(buf), "Force", true)
  end)

  -- Now that render-markdown has placed its virtual text, the rendered
  -- display width can be substantially wider than the raw markdown
  -- (cell padding for column alignment, box drawing chars, etc.).
  -- Compute the true rendered width per row and resize the window.
  --
  -- Subtlety: extmark `col` is a BYTE index, while strdisplaywidth is in
  -- display cells. With CJK content the two differ, so we must convert
  -- byte col -> display col before doing any width math for overlays.
  vim.schedule(function()
    if not vim.api.nvim_win_is_valid(win) or not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    local ns
    for name, id in pairs(vim.api.nvim_get_namespaces()) do
      if name:match("render.markdown") then
        ns = id
        break
      end
    end
    if not ns then return end

    local total_rows = vim.api.nvim_buf_line_count(buf)
    local max_rendered = 0
    for row = 0, total_rows - 1 do
      local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
      local raw_display = vim.fn.strdisplaywidth(line)
      local inline_sum = 0
      local overlay_max = 0
      local marks = vim.api.nvim_buf_get_extmarks(buf, ns, { row, 0 }, { row, -1 }, { details = true })
      for _, m in ipairs(marks) do
        local byte_col = m[3]
        local details = m[4] or {}
        if details.virt_text and (details.virt_text_pos == "inline" or details.virt_text_pos == "overlay") then
          local w = 0
          for _, chunk in ipairs(details.virt_text) do
            w = w + vim.fn.strdisplaywidth(chunk[1])
          end
          if details.virt_text_pos == "inline" then
            inline_sum = inline_sum + w
          else -- overlay
            -- Convert byte col to display col by measuring the prefix.
            local display_col = vim.fn.strdisplaywidth(line:sub(1, byte_col))
            local end_display = display_col + w
            if end_display > overlay_max then
              overlay_max = end_display
            end
          end
        end
      end
      local effective = math.max(raw_display + inline_sum, overlay_max)
      if effective > max_rendered then
        max_rendered = effective
      end
    end

    local new_width = math.min(vim.o.columns - 4, max_rendered + 4)
    if new_width > width then
      vim.api.nvim_win_set_config(win, {
        relative = "editor",
        width = new_width,
        height = height,
        row = math.floor((vim.o.lines - height) / 2),
        col = math.floor((vim.o.columns - new_width) / 2),
      })
    end
  end)

  attach_popup_keys(win, buf, width, height)
end

function M.preview_table()
  local buf = vim.api.nvim_get_current_buf()
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local range = find_table_range(buf, row)
  if not range then
    vim.notify("No markdown table at cursor", vim.log.levels.WARN)
    return
  end
  popup_markdown(get_lines(buf, range), "Table Preview")
end

-- Unified preview dispatch bound to <leader>ip.
-- Priority: markdown table > image/mermaid. If neither, falls through to
-- the existing image_preview which notifies its own "not found" message.
function M.dispatch()
  local buf = vim.api.nvim_get_current_buf()
  local row = vim.api.nvim_win_get_cursor(0)[1]
  if find_table_range(buf, row) then
    M.preview_table()
    return
  end
  if _G._snacks_image_preview then
    _G._snacks_image_preview()
  else
    vim.notify("No image/mermaid/table at cursor", vim.log.levels.WARN)
  end
end

-- Split preview: left = raw markdown, right = rendered.
-- render-markdown.nvim's built-in preview expects the buffer to be
-- enabled first. With our global opts.enabled = false, the scratch
-- buffer would also stay raw. This wrapper enables the source buffer,
-- opens the preview (which disables source and renders the copy),
-- then force-enables the scratch buffer.
function M.split_preview()
  local rm = require("render-markdown")
  local manager = require("render-markdown.core.manager")
  local preview = require("render-markdown.core.preview")
  local state = require("render-markdown.state")

  local src = vim.api.nvim_get_current_buf()

  -- If preview is already open, toggle it off.
  if preview.buffers[src] then
    rm.preview()
    return
  end

  -- Enable source so preview() passes the attached+enabled check.
  rm.buf_enable()

  -- Open the split (disables source, creates rendered scratch copy).
  rm.preview()

  -- Force-enable the scratch buffer (global enabled=false means it
  -- attached but didn't render).
  local dst = preview.buffers[src]
  if dst and manager.attached(dst) then
    manager.set_buf(dst, true)
  end

  -- LazyVim's markdown FileType autocmd re-enables spell on the scratch
  -- buffer's window. Turn it off so SpellBad underlines don't appear on
  -- proper nouns (Auth0, UserInfo, ...) in the rendered view.
  if dst then
    local src_win = vim.api.nvim_get_current_win()
    vim.wo[src_win].scrollbind = true
    vim.wo[src_win].cursorbind = true
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_buf(win) == dst then
        vim.wo[win].spell = false
        vim.wo[win].scrollbind = true
        vim.wo[win].cursorbind = true
      end
    end
  end
end

return M
