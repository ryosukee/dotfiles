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
# 外部ファイル（読み書き — このスクリプト自身がキャッシュ/履歴として使用）:
#   - /tmp/claude-code-latest-version
#       最新バージョンのキャッシュ（1時間有効）。
#       ステータスライン表示には不要だが、毎回 GitHub API を叩かないための最適化。
#       削除しても次回実行時に再生成される。
#   - $XDG_STATE_HOME/claude-status/weekly-snapshot.json (デフォルト ~/.local/state/)
#       現 weekly cycle 内の cycle day 別 pp 消費スナップショット。
#       再起動で消えないよう /tmp ではなく state dir に置く。旧 /tmp/claude-status/
#       のスナップショット (v1/v2) はスキーマ非互換のため削除して仕切り直す。
#       スキーマ v3:
#         {
#           "version": 3,
#           "cycle": {
#             "ends_at": 1714089600,          現 cycle の resets_at (検出キー)
#             "day_idx": 3,                   現 cycle day (1..7)
#             "day_start_epoch": 1713657600,  この cycle day スロット開始 epoch
#             "base_pct": 8,                  day_start 時点の weekly used%
#             "last_pct": 20,                 最後に観測した weekly used%
#             "ts_observed": 1713700800       最終観測 epoch
#           },
#           "days": [                         最大 6 件 (最新が先頭)
#             { "day_idx": 2, "pp": 8 },
#             { "day_idx": 1, "pp": 20 }
#           ]
#         }
#       Cycle 整合性: current_resets_at > cycle.ends_at を検出したら cycle 丸ごと
#       クリアして Day 1 から再スタート (sparkline も全クリア)。
#       削除しても次回実行時に再生成される。
#
# 外部ファイル（書き出しのみ — 外部ツール連携用）:
#   - /tmp/claude-status/{session_id}.json
#       ステータスライン情報を JSON で書き出す。
#       ステータスライン情報を利用したいサードパーティツールがあればこのファイルを参照する。
#       ステータスライン表示自体には不要。この書き出しを削除してもステータスラインは正常に動作する。
#
# 出力レイアウト（line1/line2 を │ で区切って並べる）:
#   例:
#     line1: 󰍛 ⣿⣇⣿⣿ 40% │ 󱇹 ⣿⣿⣿⣿ 20% 󰔟4h → 14:30 │ 󰃶 5pp 󰔟18h → 4:50 │ 󰨳 18pp/d ⣿²⁰⣇⁸▸⣇⁸⡀⁰⡀⁰⡀⁰⡀⁰ │ 󰨳 ⣿⣿⣇⣿ 15% 󰔟4d18h → 3/28·21:45
#     line2: ⚡ Opus 4.6 │ NORMAL │  main +3 !2 ?1 ⇡2 │ 📁 ~/ghq_root/github.com/foo/bar │ v2.1.83
#
#   line1（使用量系セクション、budget 専用）:
#     - Ctx Window:   󰍛 ⣿⣇⣿⣿ 40%
#                     icon (nf-md-memory U+F035B) + 4-char Braille (32 レベル解像度、
#                     dim empty、subtle bg)
#     - 5h Rate:      󱇹 ⣿⣿⣿⣿ 20% 󰔟4h → 14:30
#                     icon (nf-md-clock-time-five U+F11F9) + Braille 4-char 使用率 +
#                     5-cell progress block (1h/cell) + 残り時間 + 終了時刻
#     - Today:        󰃶 5pp 󰔟18h → 4:50
#                     T icon (nf-md U+F00F6) + 消費 pp +
#                     6-cell progress block (elapsed/24h 比例) +
#                     残り時間 (nf-md-hourglass + ラベル) + cycle day 終了時刻
#                     pp = percentage points: weekly used% の差分単位
#                     per day 予算は 7d Spark セクションに移動
#     - 7d Spark:     󰨳 18pp/d ⣇₈⣿₂₀󱞩⣇₈⡀₀⡀₀⡀₀⡀₀ (cycle day 3 の例)
#                     icon (nf-md U+F0A33、weekly と共通) + per day 予算 (pp/d) +
#                     weekly cycle (7 日) の cycle day 別 pp 消費 sparkline。
#                     常時 7 本。過去 (day 1..day_idx-1) + 󱞩 + today (day_idx) +
#                     未来 (day_idx+1..7、薄色パディング)。
#                     バー高さは per-day budget (100/7 ≈ 14.3pp) を full bar とした
#                     8 段階 Braille LEGACY (⡀⡄⡆⡇⣇⣧⣷⣿、左列→右列、各列内は下→上)、
#                     各バー直後に subscript 数字で実 pp。
#                     過去・未来は薄色、today は通常色 (色は per-day budget 比で緑/黄/赤)。
#                     󱞩 (nf-md U+F17A9) は today の位置を示すマーカー。
#                     週次リセット検出時は全クリアされて Day 1 からやり直しになる。
#     - Weekly Rate:  󰨳 ⣿⣿⣇⣿ 15% 󰔟4d18h → 3/28·21:45
#                     W icon (nf-md U+F0A33) + Braille 4-char 使用率 +
#                     残り時間 (砂時計アイコン + ラベル) + リセット日
#                     残り時間は最大単位＋次単位で表示 (4d18h / 18h30m / 45m)
#                     Nerd Font アイコン: 󰔟 (U+F051F) 砂時計
#   line2（環境情報系）:
#     - Model:        ⚡ Opus 4.6
#     - Vim:          NORMAL（vim モード有効時のみ）
#     - Git Branch:    main +3 !2 ?1 ⇡2（Nerd Font アイコン付き、git リポジトリ内のみ）
#                      +N=staged, !N=modified, ?N=untracked, ⇡N=ahead, ⇣N=behind（なければ省略）
#     - CWD:          📁 ~/ghq_root/github.com/foo/bar
#     - Version:      v2.1.83（最新時）/ v2.1.81 → 2.1.83（古い時、黄色）
#   端末幅に収まれば line1/line2 を 1 行にまとめて出力、足りなければ 2 行に分ける。
#
# 色分けルール:
#   Ctx Window / 5h Rate / Weekly Rate（使用率ベース）:
#     - 50% 以下: 緑  (\033[92m)
#     - 75% 以下: 黄  (\033[93m)
#     - 75% 超:   赤  (\033[91m)
#   Today / 7d Spark（per day 予算に対する消費率ベース — pp を pp で割るので無次元=%）:
#     - 予算の 50% 以下: 緑  (\033[92m)
#     - 予算の 75% 以下: 黄  (\033[93m)
#     - 予算の 75% 超:   赤  (\033[91m)
#   7d Spark は各バー個別に上記ルールで色付け（1週間の消費ムラが視覚化される）。
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
# Model/Vim は line 2 (右側) の先頭に配置するため、ここでは変数に保持するだけ。
# line 1 は budget 系専用 (Ctx / 5h / Today / Weekly / 7d spark) になる。
# 出力例 (line 2 先頭): ⚡ Opus 4.6 │ NORMAL │ ... (branch 以降が続く)
# -----------------------------------------------------------------------------
left_text=""
left_fmt=""

model_text="⚡ ${model}"
model_fmt=$(printf "\033[96m⚡ %s\033[0m" "$model")

if [ -n "$vim_mode" ] && [ "$vim_mode" != "null" ]; then
  model_text="${model_text} │ ${vim_mode}"
  model_fmt="${model_fmt} \033[2m│\033[0m ${vim_mode}"
fi

# -----------------------------------------------------------------------------
# % バー描画のヘルパ (Ctx 他で共通利用)
# 4-char partial allowed、empty=dim ⣿、bg=\033[48;5;234m (subtle dark gray)
# 色閾値: ≤50% 緑 / ≤75% 黄 / >75% 赤 (現行バーと共通)
#
# 充填順 (0..8 の Level → glyph):
#   LEGACY:       ⠀⡀⡄⡆⡇⣇⣧⣷⣿  左列→右列 (partial char が縦ストライプ状)
#   BOTTOMUP:     ⠀⢀⣀⣄⣤⣴⣶⣾⣿  下段→上段 symmetric (コミュニティ慣習、右下から)
#   BOTTOMUP_L:   ⠀⡀⣀⣄⣤⣦⣶⣷⣿  下段→上段 LEFT-first (左から積む、奇数 level は左側が 1 ドット多い)
#   BLOCK:        ⠀▏▎▍▌▋▊▉█     左→右横充填 (8段階、伝統的プログレスバー外観)
# -----------------------------------------------------------------------------
# 現行: BOTTOMUP_L (bottom-up + LEFT-first) を採用
braille_levels=(⠀ ⡀ ⣀ ⣄ ⣤ ⣦ ⣶ ⣷ ⣿)
BRAILLE_BG='\033[48;5;234m'

# 期日/残り時間系 (Today/5h/Weekly の remaining・end time) 用のマイルドカラー
# italic + 256-103 (muted violet)。dim より明るく section color より控えめ。
SOFT_META='\033[3;38;5;103m'

# セクション識別アイコン用の固定色 (bright green = severity 緑と同色、非 severity な固定色)
# Ctx / 5h / Today / 7d / Weekly のアイコンに共通適用。
SECTION_ICON='\033[92m'

_braille_color_for() {
  local p="$1"
  if [ "$p" -le 50 ]; then printf '\033[92m'
  elif [ "$p" -le 75 ]; then printf '\033[93m'
  else printf '\033[91m'
  fi
}

# 4-char Braille バー。$1=pct。fmt エスケープ (literal \033) を返す。
_render_braille_bar() {
  local pct="$1"
  local color
  color=$(_braille_color_for "$pct")
  local total=32
  local lvl=$(( (pct * total + 50) / 100 ))
  [ "$lvl" -gt 32 ] && lvl=32
  [ "$lvl" -lt 0 ] && lvl=0
  local rem=$lvl out="" i
  for ((i=0; i<4; i++)); do
    local content color_prefix
    if [ "$rem" -ge 8 ]; then
      content="⣿"; color_prefix="$color"
      rem=$(( rem - 8 ))
    elif [ "$rem" -gt 0 ]; then
      content="${braille_levels[$rem]}"; color_prefix="$color"
      rem=0
    else
      content="⣿"; color_prefix='\033[2m'
    fi
    out+="${BRAILLE_BG}${color_prefix}${content}\\033[0m"
  done
  printf '%s' "$out"
}

# -----------------------------------------------------------------------------
# 左側: コンテキストウィンドウ使用率バー (4-char Braille、dim empty、subtle bg)
# 解像度 32 レベル (3.1%/step)。色閾値 ≤50% 緑 / ≤75% 黄 / >75% 赤。
# icon: nf-md-memory (U+F035B 󰍛)。
# 出力例: 󰍛 ⣿⣿⣇⣿ 40%
# -----------------------------------------------------------------------------
if [ -n "$used" ] && [ "$used" != "null" ]; then
  pct=$(printf '%.0f' "$used")
  ctx_bar_fmt=$(_render_braille_bar "$pct")
  ctx_color=$(_braille_color_for "$pct")
  ctx_icon=$'\xf3\xb0\x8d\x9b'  # nf-md-memory (U+F035B)
  # icon は SECTION_ICON (固定色、非 severity)、bar と % のみ severity
  left_text="${left_text} │ ${ctx_icon} ⣿⣿⣿⣿ ${pct}%"
  left_fmt="${left_fmt} \033[2m│\033[0m $(printf '%b%s\033[0m' "$SECTION_ICON" "$ctx_icon") ${ctx_bar_fmt} $(printf '%b%s%%\033[0m' "$ctx_color" "$pct")"
fi

# -----------------------------------------------------------------------------
# 左側: 5時間レートリミット使用率 + remaining icon + リセット時刻
# 形式: 5h:NN% 󰔟Nh → HH:MM
#   - 󰔟Nh        : 残り時間 (nf-md-hourglass + 時間ラベル)
#   - → HH:MM    : cycle 終了時刻 (= five_resets_at の wall clock)
# 依存: jq, date
# -----------------------------------------------------------------------------
session_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
session_reset=""
five_resets_at=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
if [ -n "$five_resets_at" ] && [ "$five_resets_at" != "null" ]; then
  session_reset=$(date -r "${five_resets_at%.*}" "+%H:%M" 2>/dev/null)
fi

if [ -n "$session_pct" ] && [ "$session_pct" != "ERROR" ]; then
  session_pct=$(printf '%.0f' "$session_pct")

  if [ "$session_pct" -le 50 ]; then
    scolor="\033[92m"
  elif [ "$session_pct" -le 75 ]; then
    scolor="\033[93m"
  else
    scolor="\033[91m"
  fi

  five_remaining_str=""
  if [ -n "$five_resets_at" ] && [ "$five_resets_at" != "null" ]; then
    five_cycle_sec=18000  # 5h = 5 * 3600
    five_now=$(date +%s)
    five_rem=$(( ${five_resets_at%.*} - five_now ))
    [ "$five_rem" -lt 0 ] && five_rem=0
    [ "$five_rem" -gt "$five_cycle_sec" ] && five_rem=$five_cycle_sec
    # 残り時間 (Nh / NhMm / Nm)
    fr_h=$(( five_rem / 3600 ))
    fr_m=$(( (five_rem % 3600) / 60 ))
    if [ "$fr_h" -gt 0 ]; then
      five_remaining_str="${fr_h}h"
      [ "$fr_m" -gt 0 ] && five_remaining_str="${five_remaining_str}${fr_m}m"
    else
      five_remaining_str="${fr_m}m"
    fi
  fi

  hourglass_5h=$'\xf3\xb0\x94\x9f'  # nf-md-hourglass (U+F051F)
  five_icon=$'\xf3\xb1\x87\xb9'     # nf-md-clock-time-five (U+F11F9)

  # 使用率を Braille 4-char バーで表示 (Ctx と同じヘルパ)
  # icon は SECTION_ICON (固定色)、bar と % のみ severity
  five_braille=$(_render_braille_bar "$session_pct")
  left_text="${left_text} │ ${five_icon} ⣿⣿⣿⣿ ${session_pct}%"
  left_fmt="${left_fmt} \033[2m│\033[0m $(printf '%b%s\033[0m %s %b%s%%\033[0m' "$SECTION_ICON" "$five_icon" "$five_braille" "$scolor" "$session_pct")"

  if [ -n "$five_remaining_str" ]; then
    left_text="${left_text} ${hourglass_5h}${five_remaining_str}"
    left_fmt="${left_fmt}$(printf ' %b%s%s\033[0m' "$SOFT_META" "$hourglass_5h" "$five_remaining_str")"
  fi

  if [ -n "$session_reset" ]; then
    # 5h のみ arrowhead 左だけスペース (hourglass から離す)、右は詰める
    left_text="${left_text} ➤${session_reset}"
    left_fmt="${left_fmt}$(printf ' %b➤%s\033[0m' "$SOFT_META" "$session_reset")"
  fi

  # ---------------------------------------------------------------------------
  # 左側: 週間レートリミット — 入力のパースと残り時間の計算
  # JSON から使用率・リセット日時を取得し、リセットまでの残り時間を算出する。
  # 残り時間は最大単位＋次単位で表示する（例: 4d18h / 18h30m / 45m）。
  # 依存: jq, date, bc
  # ---------------------------------------------------------------------------
  weekly_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
  weekly_resets_at=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')
  weekly_reset=""          # リセット日時の表示文字列 (例: 3/28·21:45)
  weekly_remaining=""      # 残り時間の表示文字列 (例: 4d18h)
  weekly_remaining_secs=0  # 残り秒数（per day 計算用）
  weekly_per_day=""        # 1日あたりの予算 pp (例: 18)

  if [ -n "$weekly_resets_at" ] && [ "$weekly_resets_at" != "null" ]; then
    weekly_reset=$(date -r "${weekly_resets_at%.*}" "+%-m/%-d·%H:%M" 2>/dev/null)
    weekly_remaining_secs=$(( ${weekly_resets_at%.*} - $(date +%s) ))
    [ "$weekly_remaining_secs" -lt 0 ] && weekly_remaining_secs=0

    # 残り時間を最大単位＋次単位にフォーマットする。
    # 1日以上: XdYh (0h なら Xd)  /  1時間以上: XhYm (0m なら Xh)  /  1時間未満: Xm
    wr_days=$(( weekly_remaining_secs / 86400 ))
    wr_hours=$(( (weekly_remaining_secs % 86400) / 3600 ))
    wr_mins=$(( (weekly_remaining_secs % 3600) / 60 ))
    if [ "$wr_days" -gt 0 ]; then
      weekly_remaining="${wr_days}d"
      [ "$wr_hours" -gt 0 ] && weekly_remaining="${weekly_remaining}${wr_hours}h"
    elif [ "$wr_hours" -gt 0 ]; then
      weekly_remaining="${wr_hours}h"
      [ "$wr_mins" -gt 0 ] && weekly_remaining="${weekly_remaining}${wr_mins}m"
    else
      weekly_remaining="${wr_mins}m"
    fi
  fi

  # ---------------------------------------------------------------------------
  # 左側: 今日の消費ポイント (today セクション) + cycle day 履歴
  # weekly cycle (7 日) 内の 24h スロットを 1 day として扱う。
  # Day 境界は resets_at から逆算した 24h 間隔 (カレンダー 0:00 ではない)。
  # 週次リセット検出 (current_resets_at が snap_ends_at より進む) → cycle 丸ごと
  # クリアし Day 1 からやり直し。sparkline も全クリア。
  # Day 境界検出 (current_day_idx > snap_day_idx) → 旧 day を finalize し days[]
  # に prepend、新 day 開始。
  # 統計情報永続化のため /tmp ではなく $XDG_STATE_HOME/claude-status/ に置く。
  # 旧 /tmp/claude-status/weekly-snapshot.json (v1/v2) があれば破棄して仕切り直し。
  # 依存: jq, date, bc
  # 読み書き: $XDG_STATE_HOME/claude-status/weekly-snapshot.json (v3 スキーマ)
  # 出力例: T:5pp ⏳6h30m 18pp/d
  # ---------------------------------------------------------------------------
  today_used=""            # 今日 (cycle day) の消費 pp
  today_elapsed=""         # cycle day の開始からの経過時間 (例: 6h30m)
  today_history_json="[]"  # sparkline 描画用 (JSON array、newest-first、{day_idx, pp})

  STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/claude-status"
  SNAPSHOT_FILE="${STATE_DIR}/weekly-snapshot.json"
  OLD_SNAPSHOT_FILE="/tmp/claude-status/weekly-snapshot.json"

  if [ -n "$weekly_pct" ] && [ "$weekly_pct" != "" ] \
     && [ -n "$weekly_resets_at" ] && [ "$weekly_resets_at" != "null" ]; then
    weekly_pct_num=$(printf '%.0f' "$weekly_pct")
    now_ts=$(date +%s)
    current_resets_at="${weekly_resets_at%.*}"
    cycle_start=$(( current_resets_at - 7 * 86400 ))

    # day_idx = 1..7 (24h スロット)。7 超えは cycle 側の resets_at 更新で処理される想定。
    current_day_idx=$(( (now_ts - cycle_start) / 86400 + 1 ))
    [ "$current_day_idx" -lt 1 ] && current_day_idx=1
    [ "$current_day_idx" -gt 7 ] && current_day_idx=7
    current_day_start=$(( cycle_start + (current_day_idx - 1) * 86400 ))

    mkdir -p "$STATE_DIR"

    # 旧 /tmp スナップショット (v1/v2) があれば削除 (スキーマ非互換のため仕切り直し)
    if [ -f "$OLD_SNAPSHOT_FILE" ]; then
      rm -f "$OLD_SNAPSHOT_FILE"
    fi

    # スナップショット読み取り (v3 以外は fresh start)
    snap_version=0
    snap_ends_at=""
    snap_day_idx=""
    snap_day_start=""
    snap_base=""
    snap_last=""
    snap_ts_obs=""
    snap_days="[]"
    if [ -f "$SNAPSHOT_FILE" ]; then
      snap_version=$(jq -r '.version // 0' "$SNAPSHOT_FILE" 2>/dev/null)
      if [ "$snap_version" = "3" ]; then
        snap_ends_at=$(jq -r '.cycle.ends_at // empty' "$SNAPSHOT_FILE" 2>/dev/null)
        snap_day_idx=$(jq -r '.cycle.day_idx // empty' "$SNAPSHOT_FILE" 2>/dev/null)
        snap_day_start=$(jq -r '.cycle.day_start_epoch // empty' "$SNAPSHOT_FILE" 2>/dev/null)
        snap_base=$(jq -r '.cycle.base_pct // empty' "$SNAPSHOT_FILE" 2>/dev/null)
        snap_last=$(jq -r '.cycle.last_pct // empty' "$SNAPSHOT_FILE" 2>/dev/null)
        snap_ts_obs=$(jq -r '.cycle.ts_observed // empty' "$SNAPSHOT_FILE" 2>/dev/null)
        snap_days=$(jq -c '.days // []' "$SNAPSHOT_FILE" 2>/dev/null)
      fi
    fi

    # === Cycle 整合性チェック ===
    # 初回 / 週次リセット検出 (current > snap_ends_at) → cycle 全リセット
    # Cycle 開始時の weekly_pct は 0 なので base=0 で統一 (mid-cycle で初回観測した
    # 場合も pre-observation 分は今日に合算される: last - 0 = current_pct)
    if [ -z "$snap_ends_at" ] || [ "$snap_ends_at" = "0" ] \
       || [ "$current_resets_at" -gt "$snap_ends_at" ] 2>/dev/null; then
      snap_ends_at=$current_resets_at
      snap_day_idx=$current_day_idx
      snap_day_start=$current_day_start
      snap_base=0
      snap_last=$weekly_pct_num
      snap_ts_obs=$now_ts
      snap_days="[]"
    # === Day 境界チェック ===
    # cycle 内で day が進んだ → 旧 day を finalize
    elif [ "$current_day_idx" -gt "${snap_day_idx:-0}" ] 2>/dev/null; then
      finalized_pp=$(( ${snap_last%.*} - ${snap_base%.*} ))
      [ "$finalized_pp" -lt 0 ] && finalized_pp=0
      snap_days=$(jq -c \
        --argjson day_idx "${snap_day_idx:-0}" \
        --argjson pp "$finalized_pp" \
        '([{day_idx: $day_idx, pp: $pp}] + .)[:6]' <<< "$snap_days" 2>/dev/null || echo "$snap_days")
      # 新 day を開始 (cycle 内)
      snap_day_idx=$current_day_idx
      snap_day_start=$current_day_start
      snap_base=$weekly_pct_num
      snap_last=$weekly_pct_num
      snap_ts_obs=$now_ts
    else
      # 通常更新 (同 cycle 同 day)
      snap_last=$weekly_pct_num
      snap_ts_obs=$now_ts
      # snap_day_start も current 基準で最新化 (外部 consumer の一貫性確保)
      snap_day_start=$current_day_start
    fi

    # snap_base の並行汚染防御: stored base が現 weekly_pct より大きければ異常なので
    # 現値を採用 (同じ cycle なら base <= last <= current_pct が成立するはず)
    if [ "${snap_base:-0}" -gt "$weekly_pct_num" ] 2>/dev/null; then
      snap_base=$weekly_pct_num
    fi

    # スナップショット書き出し (v3) — tmp 経由の atomic write で並行読取の不整合防止
    SNAPSHOT_TMP="${SNAPSHOT_FILE}.tmp.$$"
    jq -n \
      --argjson ends_at "${snap_ends_at:-0}" \
      --argjson day_idx "${snap_day_idx:-1}" \
      --argjson day_start "${snap_day_start:-0}" \
      --argjson base_pct "${snap_base:-0}" \
      --argjson last_pct "${snap_last:-0}" \
      --argjson ts_obs "${snap_ts_obs:-0}" \
      --argjson days "$snap_days" \
      '{
        version: 3,
        cycle: {
          ends_at: $ends_at,
          day_idx: $day_idx,
          day_start_epoch: $day_start,
          base_pct: $base_pct,
          last_pct: $last_pct,
          ts_observed: $ts_obs
        },
        days: $days
      }' > "$SNAPSHOT_TMP" && mv "$SNAPSHOT_TMP" "$SNAPSHOT_FILE"

    today_history_json="$snap_days"

    # today_used = last - base (cycle day 内の消費)。リセット跨ぎが起きれば上で
    # cycle がリセットされて base=current になるので、ここでの引き算は常に 0 以上。
    today_used=$(( weekly_pct_num - ${snap_base%.*} ))
    [ "$today_used" -lt 0 ] && today_used=0

    # 経過時間は必ず入力由来の current_day_start で算出する (stored snap_day_start は
    # 並行書き込みで陳腐化しうるため信頼しない)
    elapsed_secs=$(( now_ts - current_day_start ))
    [ "$elapsed_secs" -lt 0 ] && elapsed_secs=0
    [ "$elapsed_secs" -gt 86400 ] && elapsed_secs=86400
    el_hours=$(( elapsed_secs / 3600 ))
    el_mins=$(( (elapsed_secs % 3600) / 60 ))
    if [ "$el_hours" -gt 0 ]; then
      today_elapsed="${el_hours}h"
      [ "$el_mins" -gt 0 ] && today_elapsed="${today_elapsed}${el_mins}m"
    else
      today_elapsed="${el_mins}m"
    fi

    # per day 予算の計算: 残り pp ÷ 残り日数（小数）
    if [ "$weekly_remaining_secs" -gt 0 ]; then
      remaining_pct=$(( 100 - weekly_pct_num ))
      [ "$remaining_pct" -lt 0 ] && remaining_pct=0  # weekly_pct > 100 の異常値ガード
      weekly_per_day=$(printf '%.0f' "$(echo "$remaining_pct / ($weekly_remaining_secs / 86400)" | bc -l 2>/dev/null || echo 0)")
    fi

    # today セクションの描画 (remaining icon + 終了時刻)
    # 形式: <T-icon>Npp 󰔟Nh → HH:MM
    #   - <T-icon>Npp  : 今日の消費 (T icon = nf-md U+F00F6)
    #   - 󰔟Nh          : 残り時間 (nf-md-hourglass + 時間ラベル)
    #   - → HH:MM      : cycle day 終了時刻 (wall clock)
    # per day 予算 (pp/d) は 7d Spark セクションの先頭に配置。
    # 色分け: per day 予算比で緑→黄→赤 (Npp に適用)
    if [ -n "$today_used" ]; then
      hourglass=$'\xf3\xb0\x94\x9f'  # nf-md-hourglass (U+F051F)
      today_icon=$'\xf3\xb0\x83\xb6'  # nf-md U+F00F6 (today)

      # 色分け
      tcolor="\033[92m"
      if [ -n "$weekly_per_day" ] && [ "$weekly_per_day" -gt 0 ] 2>/dev/null; then
        today_ratio=$(( today_used * 100 / weekly_per_day ))
        if [ "$today_ratio" -le 50 ]; then
          tcolor="\033[92m"
        elif [ "$today_ratio" -le 75 ]; then
          tcolor="\033[93m"
        else
          tcolor="\033[91m"
        fi
      fi

      # 残り時間と終了時刻
      today_remaining_secs=$(( 86400 - elapsed_secs ))
      [ "$today_remaining_secs" -lt 0 ] && today_remaining_secs=0
      tr_h=$(( today_remaining_secs / 3600 ))
      tr_m=$(( (today_remaining_secs % 3600) / 60 ))
      if [ "$tr_h" -gt 0 ]; then
        today_remaining_str="${tr_h}h"
        [ "$tr_m" -gt 0 ] && today_remaining_str="${today_remaining_str}${tr_m}m"
      else
        today_remaining_str="${tr_m}m"
      fi
      # end time も current_day_start 基準 (stored は信頼しない)
      today_end_epoch=$(( current_day_start + 86400 ))
      today_end_time=$(date -r "$today_end_epoch" "+%-H:%M" 2>/dev/null)

      # T-icon + Npp + remaining + 終了時刻
      # severity color は Npp のみに適用。
      # icon は SECTION_ICON、remaining/end time は SOFT_META。
      t_text="${today_icon} ${today_used}pp ${hourglass}${today_remaining_str} ➤${today_end_time}"
      t_fmt=$(printf '%b%s\033[0m %b%spp\033[0m %b%s%s ➤%s\033[0m' \
        "$SECTION_ICON" "$today_icon" \
        "$tcolor" "$today_used" \
        "$SOFT_META" "$hourglass" "$today_remaining_str" "$today_end_time")

      left_text="${left_text} │ ${t_text}"
      left_fmt="${left_fmt} \033[2m│\033[0m ${t_fmt}"
    fi

    # -------------------------------------------------------------------------
    # 左側: 週間レートリミット (weekly セクション)
    # 使用率を Braille 4-char バー (Ctx/5h と同じヘルパ) で表示。
    # 色分けは使用率で緑→黄→赤（他バーと共通）。
    # 依存: _render_braille_bar, _braille_color_for
    # 出力例: 󰨳 ⣿⣿⣇⣿ 15% 󰔟4d18h → 3/28·21:45
    # -------------------------------------------------------------------------
    weekly_pct=$(printf '%.0f' "$weekly_pct")
    weekly_braille=$(_render_braille_bar "$weekly_pct")
    wcolor=$(_braille_color_for "$weekly_pct")

    hourglass_r=$'\xf3\xb0\x94\x9f'  # nf-md-hourglass (U+F051F)
    week_icon=$'\xf3\xb0\xa8\xb3'    # nf-md U+F0A33 (week)

    # 形式: <W-icon> <Braille 4-char> NN% 󰔟<残り> → <日付>
    # icon は SECTION_ICON (固定色)、bar と % のみ severity
    w_text="${week_icon} ⣿⣿⣿⣿ ${weekly_pct}%"
    w_fmt=$(printf '%b%s\033[0m %s %b%s%%\033[0m' "$SECTION_ICON" "$week_icon" "$weekly_braille" "$wcolor" "$weekly_pct")

    if [ -n "$weekly_remaining" ]; then
      w_text="${w_text} ${hourglass_r}${weekly_remaining}"
      w_fmt="${w_fmt}$(printf ' %b%s%s\033[0m' "$SOFT_META" "$hourglass_r" "$weekly_remaining")"
    fi

    if [ -n "$weekly_reset" ]; then
      w_text="${w_text} ➤${weekly_reset}"
      w_fmt="${w_fmt}$(printf ' %b➤%s\033[0m' "$SOFT_META" "$weekly_reset")"
    fi

    # weekly は 7d sparkline の後に append する (順序: 7d → weekly)
    # ここでは w_text/w_fmt を構築するのみ。append は sparkline 後で行う。

    # -------------------------------------------------------------------------
    # 左側: 7 日 sparkline (weekly cycle の cycle day 別 pp 消費履歴)
    # 常時 7 本。today は cycle day の位置に配置、右側は未来日 (▁⁰ で薄色パディング)。
    # 各バーは per-day budget (100/7 ≈ 14pp) を full bar とした 8 段階 (▁▂▃▄▅▆▇█)。
    # 各バー直後に superscript 数字 (⁰¹²³⁴⁵⁶⁷⁸⁹) で実 pp。
    # 色は per-day budget 比で緑/黄/赤 (過去・未来は薄色、today は通常色)。
    # レイアウト: past bars (day 1..day_idx-1) ▸ today ▁⁰×(7-day_idx)
    # 出力例 (cycle day 3): 7d:█²⁰▅⁸▸▅⁸▁⁰▁⁰▁⁰▁⁰
    # 出力例 (cycle day 7): 7d:█²⁰▅⁸█¹⁹▃⁵█²²█¹⁸▸▅⁸
    # 出力例 (cycle day 1): 7d:▸▁⁰▁⁰▁⁰▁⁰▁⁰▁⁰▁⁰
    # 依存: jq, bash 配列
    # -------------------------------------------------------------------------
    # Braille LEGACY 充填順 (左列→右列、各列内は下→上)
    # 各バーの下に subscript digit で実 pp を併記。
    spark_bars=(⡀ ⡄ ⡆ ⡇ ⣇ ⣧ ⣷ ⣿)
    sub_digits=(₀ ₁ ₂ ₃ ₄ ₅ ₆ ₇ ₈ ₉)
    budget_pp=$(( 100 / 7 ))
    [ "$budget_pp" -lt 1 ] && budget_pp=1

    # pp 数値を subscript 文字列に変換
    spark_to_sub() {
      local n="$1"
      local out=""
      local i c
      for (( i=0; i<${#n}; i++ )); do
        c="${n:$i:1}"
        case "$c" in
          [0-9]) out+="${sub_digits[$c]}" ;;
          *)     out+="$c" ;;
        esac
      done
      printf '%s' "$out"
    }

    # 1 日分のバー (色 + Braille + subscript) を text/fmt に append
    # $1=pp, $2=dim_flag (0=通常色/1=薄色、過去・未来日用)
    spark_append_bar() {
      local pp="$1"
      local dim="${2:-0}"
      local level=$(( pp * 8 / budget_pp ))
      [ "$level" -gt 7 ] && level=7
      [ "$level" -lt 0 ] && level=0
      local bar="${spark_bars[$level]}"
      local sub
      sub=$(spark_to_sub "$pp")
      local color
      if [ "$dim" = "1" ]; then
        color="\033[2m"
      elif [ "$pp" -le $(( budget_pp / 2 )) ]; then
        color="\033[92m"
      elif [ "$pp" -le "$budget_pp" ]; then
        color="\033[93m"
      else
        color="\033[91m"
      fi
      spark_text+="${bar}${pp}"
      spark_fmt+=$(printf '%b%s\033[0m\033[2m%s\033[0m' "$color" "$bar" "$sub")
    }

    # icon: week と同じ nf-md U+F0A33 (󰨳) を使う
    # 並び順: icon + pp/d + sparkline
    # icon は SECTION_ICON (green)、pp/d は別色 (bright cyan) で区別。
    spark_icon=$'\xf3\xb0\xa8\xb3'
    spark_text="${spark_icon} "
    spark_fmt=$(printf '%b%s\033[0m ' "$SECTION_ICON" "$spark_icon")
    if [ -n "$weekly_per_day" ]; then
      spark_text+="${weekly_per_day}pp/d "
      spark_fmt+=$(printf '\033[96m%spp/d\033[0m ' "$weekly_per_day")
    fi

    # days[] から day_idx をキーに pp を配列に展開 (欠損日は 0 のまま)。
    # これにより、例えば days=[{1:10},{2:5}] で current_day_idx=5 のとき、
    # 位置 3, 4 は「日 3, 4 は活動なし」として 0 のままになる。
    pp_by_day=(0 0 0 0 0 0 0)
    while IFS=$'\t' read -r didx pp; do
      [ -z "$didx" ] && continue
      idx=$(( didx - 1 ))
      if [ "$idx" -ge 0 ] && [ "$idx" -lt 7 ]; then
        pp_by_day[$idx]="${pp%.*}"
      fi
    done < <(jq -r '.[] | "\(.day_idx)\t\(.pp)"' <<< "$today_history_json" 2>/dev/null)

    # cycle day 1..7 を順に描画。today は 󱞩 マーカー直後、未来は薄色。
    # today_marker = nf-md U+F17A9 (指さし系)。SOFT_META (italic muted violet) で控えめに目立たせる。
    today_marker=$'\xf3\xb1\x9e\xa9'
    for ((i=1; i<=7; i++)); do
      if [ "$i" -eq "$current_day_idx" ]; then
        # マーカー (SOFT_META 色) + today (通常色)
        spark_text+="${today_marker}"
        spark_fmt+=$(printf '%b%s\033[0m' "$SOFT_META" "$today_marker")
        spark_append_bar "${today_used:-0}" 0
      elif [ "$i" -lt "$current_day_idx" ]; then
        # 過去 day (薄色、データがあればその pp、なければ 0)
        spark_append_bar "${pp_by_day[$((i-1))]}" 1
      else
        # 未来 day (薄色、常に 0)
        spark_append_bar 0 1
      fi
    done

    left_text="${left_text} │ ${spark_text}"
    left_fmt="${left_fmt} \033[2m│\033[0m ${spark_fmt}"

    # --- 7d sparkline の後に weekly セクションを append (順序入れ替え) ---
    left_text="${left_text} │ ${w_text}"
    left_fmt="${left_fmt} \033[2m│\033[0m ${w_fmt}"
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

# Model/Vim を CWD の後に append (Version の前)
right_text="${right_text} │ ${model_text}"
right_fmt="${right_fmt} \033[2m│\033[0m ${model_fmt}"

# -----------------------------------------------------------------------------
# 右側: バージョン情報 (cwd の右に append)
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
    right_text="${right_text} │ v${ver} → v${latest}"
    right_fmt="${right_fmt} \033[2m│\033[0m \033[93mv${ver} → v${latest}\033[0m"
  else
    right_text="${right_text} │ v${ver}"
    right_fmt="${right_fmt} \033[2m│\033[0m \033[2mv${ver}\033[0m"
  fi
fi

# NOTE: Model/Vim は git/cwd ブロック直後 (version の前) に append 済み。
# 旧実装では先頭 prepend だったが、レイアウト変更で中央配置に移行。
# 右側順: Branch │ CWD │ Model [│ Vim] [│ Version]

# left_text は先頭の " │ " を持つ (budget セクションが空の left_text に append した結果)。
# 描画前に 1 段だけ剥がす。left_fmt は printf %b で後から解釈される "\033" リテラル
# を含むので、パターン側も通常の quote で指定する (ANSI-C quote の $'...' にすると
# 本物の ESC バイトになってミスマッチ)。
left_text="${left_text# │ }"
left_fmt_leading=' \033[2m│\033[0m '
# "$var" で quote すると glob 解釈が無効化される ([2m などが char class にならない)
left_fmt="${left_fmt#"$left_fmt_leading"}"

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
    --arg s_remaining "${five_remaining_str:-}" \
    --arg w_pct "${weekly_pct:-}" \
    --arg w_reset "${weekly_reset:-}" \
    --arg w_remaining "${weekly_remaining:-}" \
    --arg w_per_day "${weekly_per_day:-}" \
    --arg t_used "${today_used:-}" \
    --arg t_elapsed "${today_elapsed:-}" \
    --arg t_remaining "${today_remaining_str:-}" \
    --arg t_end "${today_end_time:-}" \
    --arg day_idx "${current_day_idx:-}" \
    --arg cycle_ends "${current_resets_at:-}" \
    --arg ver "${ver:-}" \
    --argjson git_worktree "${git_worktree_raw:-null}" \
    --argjson weekly_history "${today_history_json:-[]}" \
    '{
      model: $model,
      contextWindowPercent: (if $ctx_pct != "" then ($ctx_pct | tonumber) else null end),
      sessionUsagePercent: (if $s_pct != "" and $s_pct != "ERROR" then ($s_pct | tonumber) else null end),
      sessionReset: (if $s_reset != "" then $s_reset else null end),
      sessionRemaining: (if $s_remaining != "" then $s_remaining else null end),
      weeklyUsagePercent: (if $w_pct != "" then ($w_pct | tonumber) else null end),
      weeklyReset: (if $w_reset != "" then $w_reset else null end),
      weeklyRemaining: (if $w_remaining != "" then $w_remaining else null end),
      weeklyPerDay: (if $w_per_day != "" then ($w_per_day | tonumber) else null end),
      weeklyHistory: $weekly_history,
      cycleDayIdx: (if $day_idx != "" then ($day_idx | tonumber) else null end),
      cycleEndsAt: (if $cycle_ends != "" then ($cycle_ends | tonumber) else null end),
      todayUsed: (if $t_used != "" then ($t_used | tonumber) else null end),
      todayElapsed: (if $t_elapsed != "" then $t_elapsed else null end),
      todayRemaining: (if $t_remaining != "" then $t_remaining else null end),
      todayEndTime: (if $t_end != "" then $t_end else null end),
      version: $ver,
      gitWorktree: $git_worktree
    }' > "$TMPFILE" && mv "$TMPFILE" "$TARGET"
fi
