-- =============================================================================
-- diffview.nvim 設定
--
-- Claude Code のローカルレビューワークフロー用カスタマイズ:
--   - file_panel での `x` トグルで「既読 (✓)」マークを付ける
--   - マーク状態は blob hash 付きで `.git/claude-review/checked.json` に永続化
--     → 同じ内容なら ✓ 復元、内容が変わったら自動で ✓ 消える
--   - `<leader>dM` で working tree を snapshot し `refs/claude-review/head` として保存
--     → 以降の `<leader>do` は前回 mark との差分を表示 (GitHub "Viewed since last review" 相当)
--   - `<leader>dC` で全レビュー状態 (json + ref + in-memory) をクリア
--   - `<leader>do` は ref があれば base 情報を notify し、古い/フル commit 済みなら WARN
--
-- 永続化先:
--   - ✓ 状態:       <git_dir>/claude-review/checked.json
--                   {"version":1,"entries":{"<rel-path>":"<blob-sha>", ...}}
--   - レビュー基準: refs/claude-review/head (dangling commit; `git stash create` の出力)
-- =============================================================================

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

-- comp が通常ファイルを指すか (dir_name は false)。hash 計算可否の判定用
local function comp_is_file(comp)
  return comp and comp.name == "file" and comp.context ~= nil
end

-- =============================================================================
-- レビュー状態 (✓ 永続化 + レビュー基準 ref) ヘルパ
-- =============================================================================

local REVIEW_REF = "refs/claude-review/head"
local STATE_FILE_VERSION = 1

-- git コマンドを同期実行。stderr は捨てる。失敗時 nil、成功時 trim 済み stdout
-- NOTE: blob_hash のような x 連打に乗る処理は blob_hash_async を使うこと。
--       この関数はセットアップ系 (git_dir / repo_root / 基準 ref 操作) のみに使う。
local function git(args)
  local out = vim.fn.system("git " .. args .. " 2>/dev/null")
  if vim.v.shell_error ~= 0 then return nil end
  return vim.fn.trim(out)
end

-- git-dir / repo root は session 中は不変なのでキャッシュする
-- (x 連打のたびに rev-parse を呼ばない)
local cached_git_dir, cached_repo_root
local function git_dir()
  if not cached_git_dir then cached_git_dir = git("rev-parse --git-dir") end
  return cached_git_dir
end
local function repo_root()
  if not cached_repo_root then cached_repo_root = git("rev-parse --show-toplevel") end
  return cached_repo_root
end

-- 状態 JSON のパス。git-dir 配下に置くことで untracked / push 対象外 / worktree 独立
local function state_file()
  local d = git_dir()
  if not d then return nil end
  return d .. "/claude-review/checked.json"
end

-- 単一 path の blob hash を非同期に計算して cb(sha, err) を呼ぶ
-- jobstart なのでプロセス spawn は走るが main thread はブロックしない
local function blob_hash_async(rel_path, cb)
  local root = repo_root()
  if not root then cb(nil, "no repo root") return end
  local abs = root .. "/" .. rel_path
  if vim.fn.filereadable(abs) ~= 1 then cb(nil, "not readable: " .. rel_path) return end
  local stdout_lines, stderr_lines = {}, {}
  vim.fn.jobstart({ "git", "hash-object", abs }, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data) stdout_lines = data end,
    on_stderr = function(_, data) stderr_lines = data end,
    on_exit = function(_, code)
      if code ~= 0 then
        cb(nil, table.concat(stderr_lines, "\n"))
        return
      end
      local sha = vim.fn.trim(table.concat(stdout_lines, "\n"))
      cb(sha ~= "" and sha or nil, sha == "" and "empty hash-object output" or nil)
    end,
  })
end

-- 複数 path の blob hash を 1 プロセスで一括計算 (restore 高速化用)
-- cb(result_table, err)。result_table は { rel_path = sha, ... }
local function blob_hash_batch_async(rel_paths, cb)
  local root = repo_root()
  if not root then cb(nil, "no repo root") return end
  local targets, abs_list = {}, { "git", "hash-object" }
  for _, rel in ipairs(rel_paths) do
    local abs = root .. "/" .. rel
    if vim.fn.filereadable(abs) == 1 then
      table.insert(targets, rel)
      table.insert(abs_list, abs)
    end
  end
  if #targets == 0 then cb({}, nil) return end
  local stdout_lines, stderr_lines = {}, {}
  vim.fn.jobstart(abs_list, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data) stdout_lines = data end,
    on_stderr = function(_, data) stderr_lines = data end,
    on_exit = function(_, code)
      if code ~= 0 then
        cb(nil, table.concat(stderr_lines, "\n"))
        return
      end
      local result = {}
      for i, rel in ipairs(targets) do
        local sha = vim.fn.trim(stdout_lines[i] or "")
        if sha ~= "" then result[rel] = sha end
      end
      cb(result, nil)
    end,
  })
end

-- state JSON を読み出す。壊れていたら空 table を返す
local function read_state()
  local path = state_file()
  if not path or vim.fn.filereadable(path) ~= 1 then
    return { version = STATE_FILE_VERSION, entries = {} }
  end
  local ok, content = pcall(vim.fn.readfile, path)
  if not ok then return { version = STATE_FILE_VERSION, entries = {} } end
  local ok2, data = pcall(vim.fn.json_decode, table.concat(content, "\n"))
  if not ok2 or type(data) ~= "table" then
    return { version = STATE_FILE_VERSION, entries = {} }
  end
  data.version = data.version or STATE_FILE_VERSION
  data.entries = data.entries or {}
  return data
end

-- state JSON を書き出す。dir は mkdirp
local function write_state(data)
  local path = state_file()
  if not path then return false end
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  local ok, encoded = pcall(vim.fn.json_encode, data)
  if not ok then return false end
  vim.fn.writefile(vim.split(encoded, "\n", { plain = true }), path)
  return true
end

-- forward declare: refresh_marks_if_open は後方で定義するが clear_review_state から参照する
local refresh_marks_if_open

-- checked state の全削除 (ファイル / in-memory / ref)
local function clear_review_state(opts)
  opts = opts or {}
  local path = state_file()
  if path and vim.fn.filereadable(path) == 1 then
    vim.fn.delete(path)
  end
  git("update-ref -d " .. REVIEW_REF)
  _G._diffview_viewed = nil
  if opts.refresh then refresh_marks_if_open() end
end

-- 現在の working tree を snapshot し REVIEW_REF として保存
local function mark_review_base()
  local sha = git("stash create")
  if not sha or sha == "" then
    -- 変更なし等で stash create が空を返す場合は HEAD をそのまま使う
    sha = git("rev-parse HEAD")
  end
  if not sha or sha == "" then
    vim.notify("[review] failed to snapshot working tree", vim.log.levels.ERROR)
    return
  end
  local ok = git("update-ref " .. REVIEW_REF .. " " .. sha)
  if ok == nil then
    vim.notify("[review] failed to update " .. REVIEW_REF, vim.log.levels.ERROR)
    return
  end
  vim.notify(("[review] base set to %s"):format(sha:sub(1, 7)))
end

-- REVIEW_REF が存在するか
local function review_ref_exists()
  return git("rev-parse --verify --quiet " .. REVIEW_REF) ~= nil
end

-- 現在の REVIEW_REF の状態を notify (sha / age / HEAD との関係 / tree 一致)
local function notify_review_base()
  if not review_ref_exists() then return end
  local sha = git("rev-parse --short " .. REVIEW_REF) or "?"
  local age = git("log -1 --format=%cr " .. REVIEW_REF) or "?"
  local ahead_raw = git("rev-list --count " .. REVIEW_REF .. "..HEAD")
  local ahead = tonumber(ahead_raw) or 0
  local base_tree = git("rev-parse " .. REVIEW_REF .. "^{tree}")
  local head_tree = git("rev-parse HEAD^{tree}")
  local tree_same = base_tree and head_tree and base_tree == head_tree

  local level = vim.log.levels.INFO
  local note
  if ahead > 0 and tree_same then
    note = ("HEAD is %d commits ahead of base, tree matches (fully committed) — consider :DCR clear"):format(ahead)
    level = vim.log.levels.WARN
  elseif ahead > 0 then
    note = ("HEAD is %d commits ahead of base (stale review base?)"):format(ahead)
    level = vim.log.levels.WARN
  elseif tree_same then
    note = "base matches current HEAD (no pending changes)"
  else
    note = "base captured pre-commit working tree"
  end
  vim.notify(("[review] base=%s (%s) — %s"):format(sha, age, note), level)
end

-- 現 diffview 上のマークを refresh する (非同期から安全に呼ぶためのラッパ)
-- forward-declare 済みの変数に代入する形 (上方の clear_review_state から参照されるため)
refresh_marks_if_open = function()
  if not _G._diffview_refresh_marks then return end
  local ok, lib = pcall(require, "diffview.lib")
  if not ok then return end
  local v = lib.get_current_view()
  if v then _G._diffview_refresh_marks(v) end
end

-- state JSON を読み、blob hash が現在内容と一致する path だけ _G._diffview_viewed に入れる。
-- hash 計算は 1 プロセスで batch 実行 (view_opened に乗るので起動時体感に効く)。
local function restore_viewed_from_state()
  _G._diffview_viewed = {}
  local data = read_state()
  if not data.entries or not next(data.entries) then return end
  local rels = {}
  for p, _ in pairs(data.entries) do table.insert(rels, p) end
  blob_hash_batch_async(rels, function(result, err)
    vim.schedule(function()
      if err then
        vim.notify("[review] restore failed: " .. err, vim.log.levels.WARN)
        return
      end
      _G._diffview_viewed = _G._diffview_viewed or {}
      for rel, sha in pairs(result or {}) do
        if data.entries[rel] == sha then
          _G._diffview_viewed[rel] = true
        end
      end
      refresh_marks_if_open()
    end)
  end)
end

-- x トグル時に state JSON を非同期更新 (ファイルの場合のみ)。
-- in-memory トグルは呼び出し側で済ませておく前提。ここは永続化だけ。
-- エラー時は notify、成功時はサイレント。
local function persist_toggle_async(comp, key, is_now_viewed)
  if not comp_is_file(comp) then return end  -- dir は永続化対象外
  if is_now_viewed then
    -- set: hash を非同期計算してから write
    blob_hash_async(key, function(sha, err)
      vim.schedule(function()
        if err or not sha then
          vim.notify("[review] hash failed for " .. key .. ": " .. (err or "?"), vim.log.levels.ERROR)
          return
        end
        local data = read_state()
        data.entries = data.entries or {}
        data.entries[key] = sha
        if not write_state(data) then
          vim.notify("[review] failed to write state for " .. key, vim.log.levels.ERROR)
        end
      end)
    end)
  else
    -- unset: hash 不要、即 write
    vim.schedule(function()
      local data = read_state()
      data.entries = data.entries or {}
      data.entries[key] = nil
      if not write_state(data) then
        vim.notify("[review] failed to write state for " .. key, vim.log.levels.ERROR)
      end
    end)
  end
end

-- =============================================================================
-- グローバル公開 (keymap や外部から呼ぶため)
-- =============================================================================
_G._review_clear = function() clear_review_state({ refresh = true }) end
_G._review_mark  = mark_review_base
_G._review_open  = function()
  if review_ref_exists() then
    notify_review_base()
    vim.cmd("DiffviewOpen " .. REVIEW_REF)
  else
    vim.cmd("DiffviewOpen")
  end
end

return {
  {
    "sindrets/diffview.nvim",
    cmd = { "DiffviewOpen", "DiffviewClose", "DiffviewFileHistory" },
    keys = {
      { "<leader>do", function() _G._review_open() end, desc = "Diffview: open (review-aware)" },
      { "<leader>dc", "<Cmd>DiffviewClose<CR>", desc = "Diffview: close" },
      { "<leader>dh", "<Cmd>DiffviewFileHistory %<CR>", desc = "Diffview: file history" },
      { "<leader>dH", "<Cmd>DiffviewFileHistory<CR>", desc = "Diffview: branch history" },
      { "<leader>dM", function() _G._review_mark() end, desc = "Diffview: mark current as review base" },
      { "<leader>dC", function() _G._review_clear() end, desc = "Diffview: clear review state (json + ref)" },
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
          -- 永続化済み ✓ を復元 (blob hash が現在内容と一致するパスのみ)。
          -- 内部で jobstart の完了後に refresh_marks_if_open を呼ぶので
          -- ここでの明示 refresh は不要。
          restore_viewed_from_state()
        end,
        -- view_closed では _G._diffview_viewed を消さない (永続化済みなので次回復元される)
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
            local now_viewed
            if _G._diffview_viewed[key] then
              _G._diffview_viewed[key] = nil
              now_viewed = false
            else
              _G._diffview_viewed[key] = true
              now_viewed = true
            end

            -- 1. 描画を先に反映 (in-memory 状態だけで描ける)
            vim.schedule(function()
              _G._diffview_refresh_marks(view)
            end)

            -- 2. 永続化は非同期 (git hash-object spawn が重いため)。エラー時のみ notify。
            persist_toggle_async(comp, key, now_viewed)
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
        local bufid = view and view.panel and view.panel.bufid
        if not bufid or not vim.api.nvim_buf_is_valid(bufid) then return end

        -- 常に既存マークをクリア (viewed が空でもクリアが必要)
        vim.api.nvim_buf_clear_namespace(bufid, ns, 0, -1)

        if not _G._diffview_viewed or not next(_G._diffview_viewed) then return end

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
