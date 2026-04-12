#!/bin/bash
# =============================================================================
# Claude Code ステータスライン
# =============================================================================
#
# 概要:
#   Claude Code の statusLine 設定から呼び出されるスクリプト。
#   stdin で Claude Code 本体から JSON を受け取り、整形した文字列を stdout に返す。
#   stdout の出力がそのままステータスラインとして描画される。
#
# 設定方法 (~/.claude/settings.json に追加):
#   "statusLine": {
#     "type": "command",
#     "command": "bash ~/.claude/statusline.sh"
#   }
#
# 依存ツール:
#   - jq     (必須) JSON パース・ステータス JSON 書き出し
#   - bc     (必須) 浮動小数点の演算・比較（バー描画の計算）
#   - curl   (任意) GitHub API から最新バージョンを取得。失敗時はスキップ
#   - git    (任意) ブランチ名取得。git リポジトリ外ではスキップ
#   - tput   (任意) 端末幅の取得。失敗時は $COLUMNS → 80 にフォールバック
#   - stat   (必須) キャッシュファイルの更新時刻取得（macOS -f %m / Linux -c %Y 両対応）
#   - Nerd Font (任意) git ブランチアイコン (\uf418) の表示に必要
#
# 外部ファイル（読み書き — このスクリプト自身がキャッシュとして使用）:
#   - /tmp/claude-code-latest-version
#       最新バージョンのキャッシュ（1時間有効）。
#       ステータスライン表示には不要だが、毎回 GitHub API を叩かないための最適化。
#       削除しても次回実行時に再生成される。
#
# 外部ファイル（書き出しのみ — 外部ツール連携用）:
#   - /tmp/claude-status/{session_id}.json
#       ステータスライン情報を JSON で書き出す。
#       ステータスライン情報を利用したいサードパーティツールがあればこのファイルを参照する。
#       ステータスライン表示自体には不要。この書き出しを削除してもステータスラインは正常に動作する。
#
# 出力レイアウト（左側 │ で区切って並べる。右側は端末右端に寄せる）:
#   例:
#     ⚡ Opus 4.6 │ NORMAL │ ████░░░░░░ 40% │ ██░░░░░░░░ 20% → 14:30 │ W:15% │ v2.1.83
#      main +3 !2 ?1 ⇡2 │ 📁 ~/ghq_root/github.com/foo/bar
#
#   左側:
#     - Model:        ⚡ Opus 4.6
#     - Vim:          NORMAL（vim モード有効時のみ）
#     - Ctx Window:   ████░░░░░░ 40%（コンテキストウィンドウ使用率、10段階バー）
#     - 5h Rate:      ██░░░░░░░░ 20% → 14:30（5時間レートリミット使用率 + リセット時刻）
#     - Weekly Rate:  W:15% → 3/28,09:00（週間レートリミット使用率 + リセット日時）
#     - Version:      v2.1.83（最新時）/ v2.1.81 → 2.1.83（古い時、黄色）
#   右側:
#     - Git Branch:    main +3 !2 ?1 ⇡2（Nerd Font アイコン付き、git リポジトリ内のみ）
#                      +N=staged, !N=modified, ?N=untracked, ⇡N=ahead, ⇣N=behind（なければ省略）
#     - CWD:          📁 ~/ghq_root/github.com/foo/bar
#   端末幅に収まれば1行、足りなければ左側・右側を2行に分けて出力する。
#
# 色分けルール（Ctx Window / 5h Rate / Weekly Rate 共通）:
#   - 50% 以下: 緑  (\033[92m)
#   - 75% 以下: 黄  (\033[93m)
#   - 75% 超:   赤  (\033[91m)
# =============================================================================

# -----------------------------------------------------------------------------
# 入力 JSON のパース
# Claude Code 本体が stdin に渡す JSON から各フィールドを取得する。
# 依存: jq
# -----------------------------------------------------------------------------
input=$(cat)

session_id=$(echo "$input" | jq -r '.session_id // empty')
model=$(echo "$input" | jq -r '.model.display_name // empty')
cwd=$(echo "$input" | jq -r '.workspace.current_dir // empty')
cwd="${cwd/#$HOME/~}"
# v2.1.97+ : リンクされた git worktree 内にいる場合に Claude Code 本体が設定する。
# 現状は観測用に JSON 書き出しへ含めるだけで、ステータスライン表示には未使用。
git_worktree_raw=$(echo "$input" | jq -c '.workspace.git_worktree // null')
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
vim_mode=$(echo "$input" | jq -r '.vim.mode // empty')
ver=$(echo "$input" | jq -r '.version // empty')

# -----------------------------------------------------------------------------
# 最新バージョンの取得（1時間キャッシュ）
# GitHub API から Claude Code の最新リリースタグを取得し、/tmp にキャッシュする。
# キャッシュが存在し1時間以内であれば API コールをスキップする。
# 依存: curl, jq, stat, sed
# 読み書き: /tmp/claude-code-latest-version
# -----------------------------------------------------------------------------
LATEST_CACHE="/tmp/claude-code-latest-version"
CACHE_MAX_AGE=3600
latest=""
if [ ! -f "$LATEST_CACHE" ] || [ $(($(date +%s) - $(stat -f %m "$LATEST_CACHE" 2>/dev/null || stat -c %Y "$LATEST_CACHE" 2>/dev/null || echo 0))) -gt $CACHE_MAX_AGE ]; then
  latest=$(curl -s https://api.github.com/repos/anthropics/claude-code/releases/latest | jq -r '.tag_name // empty' | sed 's/^v//')
  [ -n "$latest" ] && echo "$latest" > "$LATEST_CACHE"
fi
[ -f "$LATEST_CACHE" ] && latest=$(cat "$LATEST_CACHE")

# 端末幅の取得（レイアウト判定用）
cols=$(tput cols 2>/dev/null || echo "${COLUMNS:-80}")

# -----------------------------------------------------------------------------
# 左側: モデル名
# 出力例: ⚡ Opus 4.6
# -----------------------------------------------------------------------------
left_text="⚡ ${model}"
left_fmt=$(printf "\033[96m⚡ %s\033[0m" "$model")

# -----------------------------------------------------------------------------
# 左側: Vim モード（有効時のみ）
# 出力例: ⚡ Opus 4.6 │ NORMAL
# -----------------------------------------------------------------------------
if [ -n "$vim_mode" ] && [ "$vim_mode" != "null" ]; then
  left_text="${left_text} │ ${vim_mode}"
  left_fmt="${left_fmt} \033[2m│\033[0m ${vim_mode}"
fi

# -----------------------------------------------------------------------------
# 左側: コンテキストウィンドウ使用率バー
# 使用率を10段階のブロックバーで表示する。色は使用率に応じて緑→黄→赤。
# 依存: bc
# 出力例: ████░░░░░░ 40%
# -----------------------------------------------------------------------------
if [ -n "$used" ] && [ "$used" != "null" ]; then
  filled=$(printf '%.0f' "$(echo "$used/10" | bc -l 2>/dev/null || echo 0)")
  bar=""
  for i in $(seq 1 "$filled"); do bar="${bar}█"; done
  for i in $(seq $((filled + 1)) 10); do bar="${bar}░"; done

  if (( $(echo "$used < 50" | bc -l 2>/dev/null || echo 0) )); then
    color="\033[92m"
  elif (( $(echo "$used < 75" | bc -l 2>/dev/null || echo 0) )); then
    color="\033[93m"
  else
    color="\033[91m"
  fi

  pct=$(printf '%.0f' "$used")
  left_text="${left_text} │ ${bar} ${pct}%"
  left_fmt="${left_fmt} \033[2m│\033[0m $(printf '%b%s\033[0m %b%s%%\033[0m' "$color" "$bar" "$color" "$pct")"
fi

# -----------------------------------------------------------------------------
# 左側: 5時間レートリミット使用率バー + リセット時刻
# JSON からパースし、コンテキストウィンドウと同様の10段階バーで描画する。
# リセット時刻があれば末尾に表示。(v2.1.80+ で利用可能)
# 依存: jq, date
# 出力例: ██░░░░░░░░ 20% → 14:30
# -----------------------------------------------------------------------------
session_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
session_reset=""
five_resets_at=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
if [ -n "$five_resets_at" ] && [ "$five_resets_at" != "null" ]; then
  session_reset=$(date -r "${five_resets_at%.*}" "+%H:%M" 2>/dev/null)
fi

if [ -n "$session_pct" ] && [ "$session_pct" != "ERROR" ]; then
  session_pct=$(printf '%.0f' "$session_pct")
  sfilled=$(( session_pct / 10 ))
  sbar=""
  for i in $(seq 1 "$sfilled"); do sbar="${sbar}█"; done
  for i in $(seq $((sfilled + 1)) 10); do sbar="${sbar}░"; done

  if [ "$session_pct" -le 50 ]; then
    scolor="\033[92m"
  elif [ "$session_pct" -le 75 ]; then
    scolor="\033[93m"
  else
    scolor="\033[91m"
  fi

  slabel="${sbar} ${session_pct}%"
  left_text="${left_text} │ ${slabel}"
  left_fmt="${left_fmt} \033[2m│\033[0m $(printf '%b%s\033[0m %b%s%%\033[0m' "$scolor" "$sbar" "$scolor" "$session_pct")"

  if [ -n "$session_reset" ]; then
    left_text="${left_text} → ${session_reset}"
    left_fmt="${left_fmt}$(printf ' \033[2m→ %s\033[0m' "$session_reset")"
  fi

  # ---------------------------------------------------------------------------
  # 左側: 週間レートリミット使用率 + リセット日時
  # JSON からパースし、パーセンテージのみ表示（バーは省略）。リセット日時があれば併記。
  # 依存: jq, date
  # 出力例: W:15% → 3/28,09:00
  # ---------------------------------------------------------------------------
  weekly_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
  weekly_reset=""
  weekly_resets_at=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')
  if [ -n "$weekly_resets_at" ] && [ "$weekly_resets_at" != "null" ]; then
    weekly_reset=$(date -r "${weekly_resets_at%.*}" "+%-m/%-d,%H:%M" 2>/dev/null)
  fi

  if [ -n "$weekly_pct" ] && [ "$weekly_pct" != "" ]; then
    weekly_pct=$(printf '%.0f' "$weekly_pct")
    if [ "$weekly_pct" -le 50 ]; then
      wcolor="\033[92m"
    elif [ "$weekly_pct" -le 75 ]; then
      wcolor="\033[93m"
    else
      wcolor="\033[91m"
    fi
    if [ -n "$weekly_reset" ]; then
      left_text="${left_text} │ W:${weekly_pct}% → ${weekly_reset}"
      left_fmt="${left_fmt} \033[2m│\033[0m $(printf '%bW:%s%% → %s\033[0m' "$wcolor" "$weekly_pct" "$weekly_reset")"
    else
      left_text="${left_text} │ W:${weekly_pct}%"
      left_fmt="${left_fmt} \033[2m│\033[0m $(printf '%bW:%s%%\033[0m' "$wcolor" "$weekly_pct")"
    fi
  fi
fi

# -----------------------------------------------------------------------------
# 左側: バージョン情報
# 現在バージョンと最新バージョンを比較し、差分があれば黄色で更新先を表示する。
# 最新であれば薄い色でバージョンのみ表示。
# 出力例（最新）: v2.1.83
# 出力例（古い）: v2.1.81 → 2.1.83（黄色）
# -----------------------------------------------------------------------------
if [ -n "$ver" ] && [ "$ver" != "null" ]; then
  # latest > ver の場合のみ更新表示（バージョン文字列をドット区切りで数値比較）
  update_available=false
  if [ -n "$latest" ] && [ "$ver" != "$latest" ]; then
    IFS='.' read -r v1 v2 v3 <<< "$ver"
    IFS='.' read -r l1 l2 l3 <<< "$latest"
    if [ "${l1:-0}" -gt "${v1:-0}" ] 2>/dev/null ||
       { [ "${l1:-0}" -eq "${v1:-0}" ] && [ "${l2:-0}" -gt "${v2:-0}" ]; } 2>/dev/null ||
       { [ "${l1:-0}" -eq "${v1:-0}" ] && [ "${l2:-0}" -eq "${v2:-0}" ] && [ "${l3:-0}" -gt "${v3:-0}" ]; } 2>/dev/null; then
      update_available=true
    fi
  fi

  if [ "$update_available" = true ]; then
    left_text="${left_text} │ v${ver} → v${latest}"
    left_fmt="${left_fmt} \033[2m│\033[0m \033[93mv${ver} → v${latest}\033[0m"
  else
    left_text="${left_text} │ v${ver}"
    left_fmt="${left_fmt} \033[2m│\033[0m \033[2mv${ver}\033[0m"
  fi
fi

# -----------------------------------------------------------------------------
# 右側: Git ブランチ + ステータス + 作業ディレクトリ
# cwd が git リポジトリ内であればブランチ名を Nerd Font アイコン付きで表示。
# さらに git status から staged/modified/untracked と ahead/behind のカウントを表示する。
# GIT_OPTIONAL_LOCKS=0 でロックファイル取得をスキップし、ブロッキングを回避する。
# 依存: git (任意), Nerd Font (アイコン表示)
# 出力例（git あり）:  main +3 !2 ?1 ⇡2 │ 📁 ~/ghq_root/github.com/foo/bar
# 出力例（変更なし）:  main │ 📁 ~/ghq_root/github.com/foo/bar
# 出力例（git なし）: 📁 ~/projects/something
# 記号凡例: +N=staged, !N=modified, ?N=untracked, ⇡N=ahead, ⇣N=behind
# 参考: fish shell の starship prompt (~/.config/starship.toml) の [git_status] 設定
# -----------------------------------------------------------------------------
git_branch=""
git_status_text=""
git_status_fmt=""
if [ -n "$cwd" ] && [ "$cwd" != "null" ]; then
  abs_cwd="${cwd/#\~/$HOME}"
  git_branch=$(GIT_OPTIONAL_LOCKS=0 git -C "$abs_cwd" symbolic-ref --short HEAD 2>/dev/null)
  if [ -n "$git_branch" ]; then
    porcelain=$(GIT_OPTIONAL_LOCKS=0 git -C "$abs_cwd" status --porcelain 2>/dev/null)
    if [ -n "$porcelain" ]; then
      staged=$(echo "$porcelain" | grep -c '^[MADRC]')
      modified=$(echo "$porcelain" | grep -c '^.[MADRC]')
      untracked=$(echo "$porcelain" | grep -c '^??')
      [ "$staged" -gt 0 ] && { git_status_text="${git_status_text} +${staged}"; git_status_fmt="${git_status_fmt}$(printf ' \033[93m+%s\033[0m' "$staged")"; }
      [ "$modified" -gt 0 ] && { git_status_text="${git_status_text} !${modified}"; git_status_fmt="${git_status_fmt}$(printf ' \033[93m!%s\033[0m' "$modified")"; }
      [ "$untracked" -gt 0 ] && { git_status_text="${git_status_text} ?${untracked}"; git_status_fmt="${git_status_fmt}$(printf ' \033[93m?%s\033[0m' "$untracked")"; }
    fi
    ahead_behind=$(GIT_OPTIONAL_LOCKS=0 git -C "$abs_cwd" rev-list --left-right --count HEAD...@{upstream} 2>/dev/null)
    if [ -n "$ahead_behind" ]; then
      ahead=$(echo "$ahead_behind" | awk '{print $1}')
      behind=$(echo "$ahead_behind" | awk '{print $2}')
      [ "$ahead" -gt 0 ] && { git_status_text="${git_status_text} ⇡${ahead}"; git_status_fmt="${git_status_fmt}$(printf ' \033[92m⇡%s\033[0m' "$ahead")"; }
      [ "$behind" -gt 0 ] && { git_status_text="${git_status_text} ⇣${behind}"; git_status_fmt="${git_status_fmt}$(printf ' \033[91m⇣%s\033[0m' "$behind")"; }
    fi
  fi
fi

if [ -n "$git_branch" ]; then
  branch_icon=$'\uf418'
  # linked git worktree 内なら nf-fa-tree (U+F1BB) をブランチ名の後ろに付ける。
  # 値そのもの（.git/worktrees/<name> の name）は cwd と重複しがちなので表示しない。
  wt_marker=""
  wt_marker_fmt=""
  if [ -n "$git_worktree_raw" ] && [ "$git_worktree_raw" != "null" ]; then
    wt_icon=$'\uf1bb'
    wt_marker=" ${wt_icon}"
    wt_marker_fmt=$(printf ' \033[32m%s\033[0m' "$wt_icon")
  fi
  right_text="${branch_icon} ${git_branch}${wt_marker}${git_status_text} │ 📁 ${cwd}"
  right_fmt=$(printf "\033[35m%s %s\033[0m%b%b \033[2m│\033[0m \033[94m📁 %s\033[0m" "$branch_icon" "$git_branch" "$wt_marker_fmt" "$git_status_fmt" "$cwd")
else
  right_text="📁 ${cwd}"
  right_fmt=$(printf "\033[94m📁 %s\033[0m" "$cwd")
fi

# -----------------------------------------------------------------------------
# レイアウト: 端末幅に応じて1行 or 2行で出力
# left_text + right_text が端末幅に収まれば1行（間をスペースで埋める）。
# 収まらなければ左側・右側を別の行に分けて出力する。
# -----------------------------------------------------------------------------
total=$((${#left_text} + 3 + ${#right_text}))

if [ "$total" -le "$cols" ]; then
  pad=$((cols - ${#left_text} - ${#right_text}))
  printf "%b%*s%b\n" "$left_fmt" "$pad" "" "$right_fmt"
else
  printf "%b\n" "$left_fmt"
  printf "%b\n" "$right_fmt"
fi

# -----------------------------------------------------------------------------
# ステータスライン情報の JSON 書き出し（ステータスライン表示には不要）
# ステータスライン情報を利用したいサードパーティツールがあればこのファイルを参照する。
# このセクションを丸ごと削除しても、ステータスラインの表示には一切影響しない。
# tmp ファイル経由の atomic write で、読み取り中でも不整合を防ぐ。
# 依存: jq
# 書き出し: /tmp/claude-status/{session_id}.json
# -----------------------------------------------------------------------------
if [ -n "$session_id" ] && [ "$session_id" != "null" ]; then
  STATUS_DIR="/tmp/claude-status"
  mkdir -p "$STATUS_DIR"
  TARGET="$STATUS_DIR/$session_id.json"
  TMPFILE="$TARGET.tmp.$$"

  jq -n \
    --arg model "$model" \
    --arg ctx_pct "${used:-}" \
    --arg s_pct "${session_pct:-}" \
    --arg s_reset "${session_reset:-}" \
    --arg w_pct "${weekly_pct:-}" \
    --arg w_reset "${weekly_reset:-}" \
    --arg ver "${ver:-}" \
    --argjson git_worktree "${git_worktree_raw:-null}" \
    '{
      model: $model,
      contextWindowPercent: (if $ctx_pct != "" then ($ctx_pct | tonumber) else null end),
      sessionUsagePercent: (if $s_pct != "" and $s_pct != "ERROR" then ($s_pct | tonumber) else null end),
      sessionReset: (if $s_reset != "" then $s_reset else null end),
      weeklyUsagePercent: (if $w_pct != "" then ($w_pct | tonumber) else null end),
      weeklyReset: (if $w_reset != "" then $w_reset else null end),
      version: $ver,
      gitWorktree: $git_worktree
    }' > "$TMPFILE" && mv "$TMPFILE" "$TARGET"
fi
