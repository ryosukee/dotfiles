-- cc-ask-dotfiles floating UI
-- Opens a markdown-rendered popup backed by the ~/.local/bin/cc-ask-dotfiles script.
-- Each popup session pins a new UUID so follow-up questions stay in the same fork.

local M = {}

local state = {
  session_uuid = nil,
  buf = nil,
  win = nil,
  busy = false,
}

local function gen_uuid()
  local f = io.popen("uuidgen | tr '[:upper:]' '[:lower:]'")
  if not f then return nil end
  local uuid = f:read("*l")
  f:close()
  return uuid
end

local function buf_valid()
  return state.buf and vim.api.nvim_buf_is_valid(state.buf)
end

local function win_valid()
  return state.win and vim.api.nvim_win_is_valid(state.win)
end

local function close()
  if win_valid() then
    vim.api.nvim_win_close(state.win, true)
  end
  if buf_valid() then
    vim.api.nvim_buf_delete(state.buf, { force = true })
  end
  state.win = nil
  state.buf = nil
  state.session_uuid = nil
  state.busy = false
end

local function append(lines)
  if not buf_valid() then return end
  vim.bo[state.buf].modifiable = true
  local current = vim.api.nvim_buf_line_count(state.buf)
  -- If the buffer is "empty" (single empty line), overwrite it instead of appending.
  if current == 1 and vim.api.nvim_buf_get_lines(state.buf, 0, 1, false)[1] == "" then
    vim.api.nvim_buf_set_lines(state.buf, 0, 1, false, lines)
  else
    vim.api.nvim_buf_set_lines(state.buf, current, -1, false, lines)
  end
  vim.bo[state.buf].modifiable = false
  if win_valid() then
    local last = vim.api.nvim_buf_line_count(state.buf)
    pcall(vim.api.nvim_win_set_cursor, state.win, { last, 0 })
  end
end

local function remove_last_lines(n)
  if not buf_valid() then return end
  vim.bo[state.buf].modifiable = true
  local count = vim.api.nvim_buf_line_count(state.buf)
  vim.api.nvim_buf_set_lines(state.buf, math.max(0, count - n), count, false, {})
  vim.bo[state.buf].modifiable = false
end

local function run_query(question)
  if state.busy then
    vim.notify("cc-ask-dotfiles: still waiting for previous answer", vim.log.levels.WARN)
    return
  end
  state.busy = true
  append({ "", "## > " .. question, "", "_thinking…_", "" })

  local cmd = { "cc-ask-dotfiles", "--session", state.session_uuid, question }
  local has_indicator = true -- initial "thinking…" is showing
  local rebuild_done = false

  vim.system(cmd, {
    text = true,
    -- Stream stderr so rebuild progress appears in real-time instead of
    -- blocking for 20-30 seconds with no feedback.
    stderr = function(_, data)
      if not data or not data:match("%S") then return end
      vim.schedule(function()
        if not buf_valid() then return end
        if has_indicator then
          remove_last_lines(2)
        end
        for _, line in ipairs(vim.split(data, "\n", { plain = true })) do
          if line:match("%S") then
            append({ "_" .. line .. "_" })
            if line:match("ready") then
              rebuild_done = true
            end
          end
        end
        local indicator = rebuild_done and "_thinking…_" or "_building…_"
        append({ "", indicator, "" })
        has_indicator = true
      end)
    end,
  }, function(result)
    vim.schedule(function()
      if not buf_valid() then
        state.busy = false
        return
      end
      if has_indicator then
        remove_last_lines(2)
      end
      local stdout = result.stdout or ""
      if stdout:match("%S") then
        if rebuild_shown then append({ "" }) end
        append(vim.split(stdout, "\n", { plain = true }))
      elseif result.code ~= 0 then
        append({ "**Error (exit " .. result.code .. ")**" })
      end
      append({ "", "---", "" })
      state.busy = false
    end)
  end)
end

local function prompt()
  if state.busy then
    vim.notify("cc-ask-dotfiles: still waiting for previous answer", vim.log.levels.WARN)
    return
  end
  vim.ui.input({ prompt = "cc-ask-dotfiles > " }, function(q)
    if not q or q == "" then return end
    run_query(q)
  end)
end

local function set_keymaps()
  local opts = { buffer = state.buf, silent = true, nowait = true }
  vim.keymap.set("n", "q", close, opts)
  vim.keymap.set("n", "<Esc>", close, opts)
  vim.keymap.set("n", "i", prompt, vim.tbl_extend("force", opts, { desc = "Ask follow-up" }))
  vim.keymap.set("n", "a", prompt, opts)
  vim.keymap.set("n", "o", prompt, opts)
end

function M.open()
  if win_valid() then
    vim.api.nvim_set_current_win(state.win)
    return
  end

  state.session_uuid = gen_uuid()
  if not state.session_uuid then
    vim.notify("cc-ask-dotfiles: failed to generate UUID (uuidgen missing?)", vim.log.levels.ERROR)
    return
  end

  state.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.buf].filetype = "markdown"
  vim.bo[state.buf].buftype = "nofile"
  vim.bo[state.buf].bufhidden = "wipe"
  vim.bo[state.buf].modifiable = false

  local width = math.floor(vim.o.columns * 0.8)
  local height = math.floor(vim.o.lines * 0.8)
  state.win = vim.api.nvim_open_win(state.buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    border = "rounded",
    title = " cc-ask-dotfiles  (i: follow-up / q: close) ",
    title_pos = "center",
    style = "minimal",
  })
  vim.wo[state.win].wrap = true
  vim.wo[state.win].linebreak = true
  vim.wo[state.win].conceallevel = 2
  vim.wo[state.win].cursorline = false

  set_keymaps()
  prompt()
end

return M
