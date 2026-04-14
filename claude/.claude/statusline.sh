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
#   - /tmp/claude-status/weekly-snapshot.json
#       today (当日消費ポイント) 計算用のスナップショット。
#       暦日 0:00 基準で weekly used% のベースラインを記録する。
#       先勝ち方式: 当日の日付が既に記録されていれば上書きしない。
#       フォーマット: { "date": "2026-04-14", "base_pct": 15, "timestamp": 1713052800 }
#       削除しても次回実行時に再生成される（当日分の消費追跡は初期化される）。
#
# 外部ファイル（書き出しのみ — 外部ツール連携用）:
#   - /tmp/claude-status/{session_id}.json
#       ステータスライン情報を JSON で書き出す。
#       ステータスライン情報を利用したいサードパーティツールがあればこのファイルを参照する。
#       ステータスライン表示自体には不要。この書き出しを削除してもステータスラインは正常に動作する。
#
# 出力レイアウト（左側 │ で区切って並べる。右側は端末右端に寄せる）:
#   例:
#     ⚡ Opus 4.6 │ NORMAL │ ████░░░░░░ 40% │ ██░░░░░░░░ 20% → 14:30 │ T:5pp ⏳6h30m 18pp/d │ W:██░░░░░░░░ 15% → 󰇡:3/28 󰔟:4d18h │ v2.1.83
#      main +3 !2 ?1 ⇡2 │ 📁 ~/ghq_root/github.com/foo/bar
#
#   左側（4セクション構成）:
#     - Model:        ⚡ Opus 4.6
#     - Vim:          NORMAL（vim モード有効時のみ）
#     - Ctx Window:   ████░░░░░░ 40%（コンテキストウィンドウ使用率、10段階バー）
#     - 5h Rate:      ██░░░░░░░░ 20% → 14:30（5時間レートリミット使用率 + リセット時刻）
#     - Today:        T:5pp ⏳6h30m 18pp/d
#                     当日消費ポイント (pp) + 経過時間 + per day 予算 (pp/d)
#                     pp = percentage points: weekly used% の差分単位
#                       (weekly 全体に対する割合ではなく「何 pp 増えたか」を表す)
#                     per day = 残り pp ÷ 残り日数（小数）でリアルタイム再計算
#                     Nerd Font アイコン: ⏳ (U+F252) 経過時間 /  (U+F200) per day
#     - Weekly Rate:  W:██░░░░░░░░ 15% → 󰇡:3/28 󰔟:4d18h
#                     10段階バー + 使用率 + リセット日 + 残り時間
#                     残り時間は最大単位＋次単位で表示 (4d18h / 18h30m / 45m)
#                     Nerd Font アイコン: 󰇡 (U+F01E1) カレンダー / 󰔟 (U+F051F) 砂時計
#     - Version:      v2.1.83（最新時）/ v2.1.81 → 2.1.83（古い時、黄色）
#   右側:
#     - Git Branch:    main +3 !2 ?1 ⇡2（Nerd Font アイコン付き、git リポジトリ内のみ）
#                      +N=staged, !N=modified, ?N=untracked, ⇡N=ahead, ⇣N=behind（なければ省略）
#     - CWD:          📁 ~/ghq_root/github.com/foo/bar
#   端末幅に収まれば1行、足りなければ左側・右側を2行に分けて出力する。
#
# 色分けルール:
#   Ctx Window / 5h Rate / Weekly Rate（使用率ベース）:
#     - 50% 以下: 緑  (\033[92m)
#     - 75% 以下: 黄  (\033[93m)
#     - 75% 超:   赤  (\033[91m)
#   Today（per day 予算に対する消費率ベース — pp を pp で割るので無次元=%）:
#     - 予算の 50% 以下: 緑  (\033[92m)
#     - 予算の 75% 以下: 黄  (\033[93m)
#     - 予算の 75% 超:   赤  (\033[91m)
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
  # 左側: 週間レートリミット — 入力のパースと残り時間の計算
  # JSON から使用率・リセット日時を取得し、リセットまでの残り時間を算出する。
  # 残り時間は最大単位＋次単位で表示する（例: 4d18h / 18h30m / 45m）。
  # 依存: jq, date, bc
  # ---------------------------------------------------------------------------
  weekly_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
  weekly_resets_at=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')
  weekly_reset=""          # リセット日時の表示文字列 (例: 3/28)
  weekly_remaining=""      # 残り時間の表示文字列 (例: 4d18h)
  weekly_remaining_secs=0  # 残り秒数（per day 計算用）
  weekly_per_day=""        # 1日あたりの予算 pp (例: 18)

  if [ -n "$weekly_resets_at" ] && [ "$weekly_resets_at" != "null" ]; then
    weekly_reset=$(date -r "${weekly_resets_at%.*}" "+%-m/%-d" 2>/dev/null)
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
  # 左側: 今日の消費ポイント (today セクション)
  # 暦日 0:00 基準でスナップショットを取り、現在の weekly used% との差分を表示する。
  # 差分は「percentage points (pp)」なので表示単位は pp。
  # スナップショットは /tmp/claude-status/weekly-snapshot.json に保存。
  # 先勝ち方式: 当日の日付が既に記録されていれば上書きしない。
  # 経過時間はスナップショット取得からの経過を最大単位＋次単位で表示する。
  # 色分けは per day 予算に対する消費率で緑→黄→赤。
  # 依存: jq, date
  # 読み書き: /tmp/claude-status/weekly-snapshot.json
  # 出力例: T:5pp ⏳6h
  # ---------------------------------------------------------------------------
  today_used=""        # 今日の消費 pp (例: 5)
  today_elapsed=""     # スナップショットからの経過時間 (例: 6h30m)
  SNAPSHOT_FILE="/tmp/claude-status/weekly-snapshot.json"

  if [ -n "$weekly_pct" ] && [ "$weekly_pct" != "" ]; then
    weekly_pct_num=$(printf '%.0f' "$weekly_pct")
    today_date=$(date +%Y-%m-%d)

    # スナップショットの読み取り・更新
    mkdir -p "/tmp/claude-status"
    snap_date=""
    snap_base=""
    snap_ts=""
    if [ -f "$SNAPSHOT_FILE" ]; then
      snap_date=$(jq -r '.date // empty' "$SNAPSHOT_FILE" 2>/dev/null)
      snap_base=$(jq -r '.base_pct // empty' "$SNAPSHOT_FILE" 2>/dev/null)
      snap_ts=$(jq -r '.timestamp // empty' "$SNAPSHOT_FILE" 2>/dev/null)
    fi

    if [ "$snap_date" != "$today_date" ]; then
      # 日付が変わった → 新しいスナップショットを書く
      snap_ts=$(date +%s)
      jq -n \
        --arg date "$today_date" \
        --arg base_pct "$weekly_pct_num" \
        --arg timestamp "$snap_ts" \
        '{date: $date, base_pct: ($base_pct | tonumber), timestamp: ($timestamp | tonumber)}' \
        > "$SNAPSHOT_FILE"
      snap_base="$weekly_pct_num"
    fi

    # 今日の消費 pp = 現在の used% - スナップショットの base% (差分なので pp)
    if [ -n "$snap_base" ]; then
      today_used=$(( weekly_pct_num - ${snap_base%.*} ))
      [ "$today_used" -lt 0 ] && today_used=0

      # スナップショットからの経過時間を最大単位＋次単位でフォーマット
      # XhYm (0m なら Xh)  /  1時間未満: Xm
      if [ -n "$snap_ts" ] && [ "$snap_ts" != "null" ]; then
        elapsed_secs=$(( $(date +%s) - ${snap_ts%.*} ))
        [ "$elapsed_secs" -lt 0 ] && elapsed_secs=0
        el_hours=$(( elapsed_secs / 3600 ))
        el_mins=$(( (elapsed_secs % 3600) / 60 ))
        if [ "$el_hours" -gt 0 ]; then
          today_elapsed="${el_hours}h"
          [ "$el_mins" -gt 0 ] && today_elapsed="${today_elapsed}${el_mins}m"
        else
          today_elapsed="${el_mins}m"
        fi
      fi
    fi

    # per day 予算の計算: 残り pp ÷ 残り日数（小数）
    # 残り秒数を86400で割って小数日を求め、残り pp (= 100 - weekly_pct) を割る。
    if [ "$weekly_remaining_secs" -gt 0 ]; then
      remaining_pct=$(( 100 - weekly_pct_num ))
      weekly_per_day=$(printf '%.0f' "$(echo "$remaining_pct / ($weekly_remaining_secs / 86400)" | bc -l 2>/dev/null || echo 0)")
    fi

    # today セクションの描画
    # T:消費pp + 経過時間 + per day 予算 (pp/d) を1セクションにまとめる。
    # 出力例: T:5pp ⏳6h30m 18pp/d
    if [ -n "$today_used" ] && [ -n "$today_elapsed" ]; then
      hourglass=$'\xef\x89\x92'  # nf-fa-hourglass_half (U+F252)
      pie_chart=$'\xef\x88\x80'  # nf-fa-pie_chart (U+F200)

      # 色分け: per day 予算に対する消費率で緑→黄→赤
      # 予算の 50% 以下: 緑  /  75% 以下: 黄  /  75% 超: 赤
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

      t_text="T:${today_used}pp ${hourglass}${today_elapsed}"
      t_fmt=$(printf '%bT:%spp\033[0m \033[2m%s%s\033[0m' "$tcolor" "$today_used" "$hourglass" "$today_elapsed")

      if [ -n "$weekly_per_day" ]; then
        t_text="${t_text} ${pie_chart}${weekly_per_day}pp/d"
        t_fmt="${t_fmt}$(printf ' \033[2m%s%spp/d\033[0m' "$pie_chart" "$weekly_per_day")"
      fi

      left_text="${left_text} │ ${t_text}"
      left_fmt="${left_fmt} \033[2m│\033[0m ${t_fmt}"
    fi

    # -------------------------------------------------------------------------
    # 左側: 週間レートリミット (weekly セクション)
    # 使用率を10段階バー + パーセンテージで表示し、リセット日・残り時間を
    # Nerd Font アイコン付きで併記する。
    # 色分けは使用率で緑→黄→赤（コンテキストウィンドウ・5h Rate と共通）。
    # アイコン:  (U+F01E1) カレンダー / 󰔟 (U+F051F) 砂時計
    # 依存: bc
    # 出力例: W:██░░░░░░░░ 15% → 󰇡:3/28 󰔟:4d18h
    # -------------------------------------------------------------------------
    weekly_pct=$(printf '%.0f' "$weekly_pct")
    wfilled=$(( weekly_pct / 10 ))
    wbar=""
    for i in $(seq 1 "$wfilled"); do wbar="${wbar}█"; done
    for i in $(seq $((wfilled + 1)) 10); do wbar="${wbar}░"; done

    if [ "$weekly_pct" -le 50 ]; then
      wcolor="\033[92m"
    elif [ "$weekly_pct" -le 75 ]; then
      wcolor="\033[93m"
    else
      wcolor="\033[91m"
    fi

    calendar=$'\xf3\xb0\x87\xa1'     # nf-md-calendar_refresh (U+F01E1)
    hourglass_r=$'\xf3\xb0\x94\x9f'  # nf-md-hourglass (U+F051F)

    # テキスト版（幅計算用）: W:██░░░░░░░░ 15% → 3/28 4d18h
    w_text="W:${wbar} ${weekly_pct}%"
    w_fmt=$(printf '%bW:%s %s%%\033[0m' "$wcolor" "$wbar" "$weekly_pct")

    if [ -n "$weekly_reset" ]; then
      w_text="${w_text} → ${calendar}:${weekly_reset}"
      w_fmt="${w_fmt}$(printf ' \033[2m→ %s:%s\033[0m' "$calendar" "$weekly_reset")"
    fi

    if [ -n "$weekly_remaining" ]; then
      w_text="${w_text} ${hourglass_r}:${weekly_remaining}"
      w_fmt="${w_fmt}$(printf ' \033[2m%s:%s\033[0m' "$hourglass_r" "$weekly_remaining")"
    fi

    left_text="${left_text} │ ${w_text}"
    left_fmt="${left_fmt} \033[2m│\033[0m ${w_fmt}"
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
    --arg w_remaining "${weekly_remaining:-}" \
    --arg w_per_day "${weekly_per_day:-}" \
    --arg t_used "${today_used:-}" \
    --arg t_elapsed "${today_elapsed:-}" \
    --arg ver "${ver:-}" \
    --argjson git_worktree "${git_worktree_raw:-null}" \
    '{
      model: $model,
      contextWindowPercent: (if $ctx_pct != "" then ($ctx_pct | tonumber) else null end),
      sessionUsagePercent: (if $s_pct != "" and $s_pct != "ERROR" then ($s_pct | tonumber) else null end),
      sessionReset: (if $s_reset != "" then $s_reset else null end),
      weeklyUsagePercent: (if $w_pct != "" then ($w_pct | tonumber) else null end),
      weeklyReset: (if $w_reset != "" then $w_reset else null end),
      weeklyRemaining: (if $w_remaining != "" then $w_remaining else null end),
      weeklyPerDay: (if $w_per_day != "" then ($w_per_day | tonumber) else null end),
      todayUsed: (if $t_used != "" then ($t_used | tonumber) else null end),
      todayElapsed: (if $t_elapsed != "" then $t_elapsed else null end),
      version: $ver,
      gitWorktree: $git_worktree
    }' > "$TMPFILE" && mv "$TMPFILE" "$TARGET"
fi
