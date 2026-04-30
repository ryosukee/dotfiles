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
#       各 cycle day の「朝 (day 境界時) の weekly_pct」のスタック。
#       再起動で消えないよう /tmp ではなく state dir に置く。旧スキーマ (v1/v2/v3)
#       は削除して v4 で仕切り直す。
#       スキーマ v4:
#         {
#           "version": 4,
#           "history": [                     newest-first、最大 7 件
#             { "day_start_ts": 1713657600, "morning_pct": 24 },  // 今日
#             { "day_start_ts": 1713571200, "morning_pct": 18 },  // 昨日
#             ...
#           ]
#         }
#       設計方針: cycle_end (ends_at), day_idx, day_start_epoch, 現 weekly_pct,
#       ts_observed 等は state に持たず、毎回 Claude Code の JSON から derive する。
#       これらを state に持たせると、複数の値を原子的に更新できないので部分的に
#       古いフィールドが残って整合性が崩れる (例: ends_at だけ新 cycle 反映、
#       day_idx は前 cycle の値のまま、といった不整合が発生する)。
#       更新トリガ: (a) 初回、(b) day 進行、(c) cycle 切替 (head が前 cycle 所属)。
#       それ以外は書き込みゼロ。
#       Sparkline の gap 日は空バー、diff は earlier entry に集約して計算。
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
#     line1: NORMAL │ 󰁿 60% │ 󱇹 󰂁 80% 󰔟 4ʰ02ᵐ ➤ 14:30 │ 󱑸 5pp 󰔟 17ʰ59ᵐ ➤ 4:50 │ 󰎷 18pp/d ⣿²⁰⣇⁸▸⣇⁸⡀⁰⡀⁰⡀⁰⡀⁰ │ 󰎸 ⣿⣿⣿⣄ 85% 󰔟 4ᵈ18ʰ ➤ 3/28·21:45
#     line2: ⚡ Opus 4.6 │  main +3 !2 ?1 ⇡2 │ 📁 ~/ghq_root/github.com/foo/bar │ v2.1.83
#
#   line1（vim mode + 使用量系セクション）:
#     - Vim:          NORMAL（vim モード有効時のみ、line1 先頭）
#     - Ctx Window:   󰁿 60%
#                     battery glyph (nf-md-battery-* 10 段階 + alert) + 残量 % で表示。
#                     used 0% → 󰁹 100% / used 100% → 󰂃 0% と inverted mapping。
#                     視覚 (battery) と数値 (残量 %) が一致してスマホ感覚で読める。
#                     memory icon は廃止し、battery 自体が section identifier を兼ねる。
#     - 5h Rate:      󱇹 󰂁 80% 󰔟 4ʰ02ᵐ ➤ 14:30
#                     icon (nf-md-clock-time-five U+F11F9) + battery glyph + 残量 % +
#                     残り時間 (hourglass + superscript 表記 `Nʰ NNᵐ`) + 終了時刻 (➤ + `HH:MM`)
#                     Ctx と同じ battery 表記。clock icon はセクション識別 (SECTION_ICON)、
#                     battery glyph と % は severity 色 (_braille_color_for)。
#                     残り時間は muted cyan、終了時刻は muted amber、icon は dim で色分け
#     - Today:        󱑸 5pp 󰔟 17ʰ59ᵐ ➤ 4:50
#                     T icon (nf-md U+F1478) + 消費 pp +
#                     6-cell progress block (elapsed/24h 比例) +
#                     残り時間 (nf-md-hourglass + ラベル) + cycle day 終了時刻
#                     pp = percentage points: weekly used% の差分単位
#                     per day 予算は 7d Spark セクションに移動
#     - 7d Spark:     󰎷 18pp/d ⣇₈⣿₂₀󱞩⣇₈⡀₀⡀₀⡀₀⡀₀ (cycle day 3 の例)
#                     icon (nf-md U+F03B7、7d 専用) + per day 予算 (pp/d) +
#                     weekly cycle (7 日) の cycle day 別 pp 消費 sparkline。
#                     常時 7 本。過去 (day 1..day_idx-1) + 󱞩 + today (day_idx) +
#                     未来 (day_idx+1..7、薄色パディング)。
#                     バー高さは per-day budget (100/7 ≈ 14.3pp) を full bar とした
#                     8 段階 Braille LEGACY (⡀⡄⡆⡇⣇⣧⣷⣿、左列→右列、各列内は下→上)、
#                     各バー直後に subscript 数字で実 pp。
#                     過去・未来は薄色、today は通常色 (色は per-day budget 比で緑/黄/赤)。
#                     󱞩 (nf-md U+F17A9) は today の位置を示すマーカー。
#                     週次リセット検出時は全クリアされて Day 1 からやり直しになる。
#     - Weekly Rate:  󰎸 ⣿⣿⣿⣄ 85% 󰔟 4ᵈ18ʰ ➤ 3/28·21:45
#                     W icon (nf-md U+F03B8、weekly 専用) + Braille 4-char 残量バー +
#                     残量 % (100 から減る、battery 表記と統一) +
#                     残り時間 (砂時計アイコン + superscript ラベル) + リセット日
#                     bar fill は remaining、色は usage 由来 severity なので
#                     usage 増加でバーが右から減りつつ 緑→黄→赤 と切り替わる。
#                     最大単位＋次単位を superscript で繋ぐ (4ᵈ18ʰ / 18ʰ30ᵐ / 45ᵐ)
#                     分/時は 2 桁 zero-pad で幅を揃える (10ʰ02ᵐ 等)
#                     Nerd Font アイコン: 󰔟 (U+F051F) 砂時計
#   line2（環境情報系）:
#     - Model:        ⚡ Opus 4.6
#     - Git Branch:    main +3 !2 ?1 ⇡2（Nerd Font アイコン付き、git リポジトリ内のみ）
#                      +N=staged, !N=modified, ?N=untracked, ⇡N=ahead, ⇣N=behind（なければ省略）
#     - CWD:          📁 ~/ghq_root/github.com/foo/bar
#     - Version:      v2.1.83（最新時）/ v2.1.81 → 2.1.83（古い時、黄色）
#   端末幅に収まれば line1/line2 を 1 行にまとめて出力、足りなければ 2 行に分ける。
#
# 色分けルール:
#   Ctx Window / 5h Rate（battery 表記、使用率ベース）:
#     - 50% 以下: 緑   (\033[92m)
#     - 75% 以下: 黄   (\033[93m)
#     - 75% 超:   赤   (\033[91m)
#   Weekly Rate（Braille バー、表示は残量だが色は usage ベース severity）:
#     - used 50% 以下: 緑  (\033[92m)
#     - used 75% 以下: 黄  (\033[93m)
#     - used 75% 超:   赤  (\033[91m)
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

# -----------------------------------------------------------------------------
# vim mode 高速キャッシュ: jq を回避し bash regex で vim_mode だけ抽出。
# mode が変わっていればキャッシュの mode 部分を差し替えて即 return。
# キャッシュはセッション単位 (session_id をファイル名に含む)。
# 全セッション共有だと他セッションのメトリクスが混入する。
# -----------------------------------------------------------------------------
_sl_session_id=""
if [[ "$input" =~ \"session_id\":\"([a-f0-9-]+)\" ]]; then
  _sl_session_id="${BASH_REMATCH[1]}"
fi
_SL_CACHE_FILE="/tmp/claude-status/sl-cache-${_sl_session_id:-global}.dat"

_sl_vim_mode=""
if [[ "$input" =~ \"mode\":\"([A-Z ]+)\" ]]; then
  _sl_vim_mode="${BASH_REMATCH[1]}"
fi

if [ -n "$_sl_vim_mode" ] && [ -f "$_SL_CACHE_FILE" ]; then
  IFS=$'\x1f' read -r _cached_vim _cached_line1_body _cached_line2 _cached_line3 < "$_SL_CACHE_FILE"
  if [ "$_cached_vim" != "$_sl_vim_mode" ] && [ -n "$_cached_line3" ]; then
    if [ "$_sl_vim_mode" = "NORMAL" ]; then
      _new_vim_fmt=$(printf "\033[1;30;43m %s \033[0m" "$_sl_vim_mode")
    else
      _new_vim_fmt="$_sl_vim_mode"
    fi
    if [ -n "$_cached_line1_body" ]; then
      printf "%b\n" "${_new_vim_fmt} \033[2m│\033[0m ${_cached_line1_body}"
    else
      printf "%b\n" "${_new_vim_fmt}"
    fi
    [ -n "$_cached_line2" ] && printf "%b\n" "$_cached_line2"
    printf "%b\n" "$_cached_line3"
    printf '%s\x1f%s\x1f%s\x1f%s' "$_sl_vim_mode" "$_cached_line1_body" "$_cached_line2" "$_cached_line3" > "$_SL_CACHE_FILE"
    exit 0
  fi
fi

# 入力 JSON の必要フィールドを 1 回の jq 呼び出しで取り出す。
# jq fork コストが ~24ms あるため個別 call を束ねると数百 ms 短縮できる (Claude
# Code の statusLine タイムアウトで中断されて line 2/3 が消える回避策)。
# 後段で使う rate_limits / current_usage / transcript_path もここで一括取得する。
# git_worktree は object なので compact JSON で別 call。
# 区切りは \x1f (Unit Separator) — \t を IFS にすると bash read が連続 tab を
# 1 つに collapse して空フィールドが詰まり後続変数がずれる。非空白制御文字で回避。
IFS=$'\x1f' read -r \
  session_id model cwd used vim_mode ver \
  session_pct five_resets_at weekly_pct weekly_resets_at \
  cur_in cur_cc cur_cr cur_out total_in total_out transcript_path \
  <<< "$(jq -r '[
    .session_id // "",
    .model.display_name // "",
    .workspace.current_dir // "",
    ((.context_window.used_percentage // "") | tostring),
    .vim.mode // "",
    .version // "",
    ((.rate_limits.five_hour.used_percentage // "") | tostring),
    ((.rate_limits.five_hour.resets_at // "") | tostring),
    ((.rate_limits.seven_day.used_percentage // "") | tostring),
    ((.rate_limits.seven_day.resets_at // "") | tostring),
    ((.context_window.current_usage.input_tokens // 0) | tostring),
    ((.context_window.current_usage.cache_creation_input_tokens // 0) | tostring),
    ((.context_window.current_usage.cache_read_input_tokens // 0) | tostring),
    ((.context_window.current_usage.output_tokens // 0) | tostring),
    ((.context_window.total_input_tokens // 0) | tostring),
    ((.context_window.total_output_tokens // 0) | tostring),
    .transcript_path // ""
  ] | join("\u001f")' <<< "$input")"
cwd="${cwd/#$HOME/~}"

# v2.1.97+ : リンクされた git worktree 内にいる場合に Claude Code 本体が設定する。
# 現状は観測用に JSON 書き出しへ含めるだけで、ステータスライン表示には未使用。
git_worktree_raw=$(jq -c '.workspace.git_worktree // null' <<< "$input")

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
  latest=$(curl -s --connect-timeout 1 --max-time 2 https://api.github.com/repos/anthropics/claude-code/releases/latest | jq -r '.tag_name // empty' | sed 's/^v//')
  [ -n "$latest" ] && echo "$latest" > "$LATEST_CACHE"
fi
[ -f "$LATEST_CACHE" ] && latest=$(cat "$LATEST_CACHE")

# 端末幅の取得（レイアウト判定用）
cols=$(tput cols 2>/dev/null || echo "${COLUMNS:-80}")

# -----------------------------------------------------------------------------
# Model 情報は line 2 (cache セクション) の左端に配置。
# Vim mode は line 1 の先頭に配置 (有効時のみ)。
# 出力レイアウト (3 行):
#   line 1: [NORMAL │] Ctx │ 5h │ Today │ 7d │ Weekly
#   line 2: ⚡ Model │ in·hit │ out │ Σ │ TTL
#   line 3: Branch │ 📁 cwd │ version
# -----------------------------------------------------------------------------
# model の text/fmt は line 2 組み立て時に使うので保持、left は空で start。
left_text=""
left_fmt=""
if [ -n "$model" ] && [ "$model" != "null" ]; then
  model_text="⚡ ${model}"
  model_fmt=$(printf "\033[96m⚡ %s\033[0m" "$model")
else
  model_text=""
  model_fmt=""
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

# 期日/残り時間系のマイルドカラー (Today/5h/Weekly で共通)。
# 数値に色を寄せて icon は dim にするほうが視線誘導しやすいので、
# remaining (Nh Nm) / end time (HH:MM や M/D) / icon (󰔟・➤) で 3 分割する。
META_REMAINING='\033[3;38;5;110m'  # italic + muted cyan (残り時間)
META_ENDTIME='\033[3;38;5;179m'    # italic + muted amber (リセット時刻)
META_ICON='\033[2;38;5;244m'       # dim gray (icon マーカー、矢印 ➤ 用)
# 砂時計 (󰔟) は残り時間 (META_REMAINING) と同系統の 110 を dim で薄くした色。
# 残り時間の数値を主役にしつつ、icon も同じ色系統で「残り時間セクション」
# としての塊感を出す。矢印 ➤ とは別色にして役割を分ける。
META_HOURGLASS='\033[2;38;5;110m'  # dim + muted cyan (残り時間の砂時計)

# 7d sparkline の today マーカー (󱞩) 用。使用量系の meta 色とは別立てで、
# 「現在位置を指すポインタ」として violet italic に残している。
SOFT_META='\033[3;38;5;103m'

# セクション識別アイコン用の固定色 (sky blue #87d7ff、非 severity な固定色)
# Ctx / 5h / Today / 7d / Weekly のアイコンに共通適用。severity 色 (緑/黄/赤)
# とは別系統の色にして、アイコン自体が severity シグナルと誤読されないようにする。
SECTION_ICON='\033[38;5;117m'

# 使用率 (0-100) を battery glyph に変換する。
# Nerd Font Material Design Icons の battery は 0%〜100% を 10 刻みの
# 10 段階 + alert (空) の計 11 段階。used_percentage を 100-used = 残量に
# 反転してマップする。残量 0 (=used 100%) は alert glyph で警告表現。
_battery_for_used() {
  local used="$1"
  if [ "$used" -ge 95 ]; then printf '\xf3\xb0\x82\x83'   # 󰂃 alert (rem 0-5%)
  elif [ "$used" -ge 85 ]; then printf '\xf3\xb0\x81\xba' # 󰁺 10%
  elif [ "$used" -ge 75 ]; then printf '\xf3\xb0\x81\xbb' # 󰁻 20%
  elif [ "$used" -ge 65 ]; then printf '\xf3\xb0\x81\xbc' # 󰁼 30%
  elif [ "$used" -ge 55 ]; then printf '\xf3\xb0\x81\xbd' # 󰁽 40%
  elif [ "$used" -ge 45 ]; then printf '\xf3\xb0\x81\xbe' # 󰁾 50%
  elif [ "$used" -ge 35 ]; then printf '\xf3\xb0\x81\xbf' # 󰁿 60%
  elif [ "$used" -ge 25 ]; then printf '\xf3\xb0\x82\x80' # 󰂀 70%
  elif [ "$used" -ge 15 ]; then printf '\xf3\xb0\x82\x81' # 󰂁 80%
  elif [ "$used" -ge 5 ]; then printf '\xf3\xb0\x82\x82'  # 󰂂 90%
  else printf '\xf3\xb0\x81\xb9'                          # 󰁹 100% (full)
  fi
}

# remaining 文字列を superscript 表記に変換する。
# 例: "4h 29m" → "4ʰ29ᵐ"、"4d 17h" → "4ᵈ17ʰ"、"45m" → "45ᵐ"
# Unicode superscript: ʰ (U+02B0) / ᵐ (U+1D50) / ᵈ (U+1D48)。
# 単位文字を上付きに落として数字主体にすると、`h` / `m` / `d` / space の
# ノイズが減って一瞥で読める。wall clock `HH:MM` とも形が被らない。
_to_superscript() {
  local s="$1"
  s="${s// /}"
  s="${s//h/ʰ}"
  s="${s//m/ᵐ}"
  s="${s//d/ᵈ}"
  printf '%s' "$s"
}

_braille_color_for() {
  local p="$1"
  if [ "$p" -le 50 ]; then printf '\033[92m'
  elif [ "$p" -le 75 ]; then printf '\033[93m'
  else printf '\033[91m'
  fi
}

# 4-char Braille バー。$1=fill_pct、$2=color (optional)。
# color を省略した場合は fill_pct から severity を自動計算する。
# 残量表示したい場合は fill_pct=残量 % + color=used ベースの severity を明示的に渡す
# (severity は usage に基づき、bar は残量で fill したいケース。例: weekly)。
_render_braille_bar() {
  local pct="$1"
  local color="${2:-}"
  [ -z "$color" ] && color=$(_braille_color_for "$pct")
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
  ctx_battery=$(_battery_for_used "$pct")
  ctx_color=$(_braille_color_for "$pct")
  # 数値も battery glyph と揃えて残量 % で表示する。視覚 (battery 残量) と
  # 数値 (残量 %) が一致してスマホ/ノート PC のバッテリー UI と同じ規約になる。
  ctx_remaining=$(( 100 - pct ))
  [ "$ctx_remaining" -lt 0 ] && ctx_remaining=0
  left_text="${left_text} │ ${ctx_battery} ${ctx_remaining}%"
  left_fmt="${left_fmt} \033[2m│\033[0m $(printf '%b%s\033[0m %b%s%%\033[0m' \
    "$ctx_color" "$ctx_battery" "$ctx_color" "$ctx_remaining")"
fi

# -----------------------------------------------------------------------------
# 左側: 5時間レートリミット使用率 + remaining icon + リセット時刻
# 形式: 5h:NN% 󰔟Nh → HH:MM
#   - 󰔟Nh        : 残り時間 (nf-md-hourglass + 時間ラベル)
#   - → HH:MM    : cycle 終了時刻 (= five_resets_at の wall clock)
# 依存: jq, date
# -----------------------------------------------------------------------------
# session_pct / five_resets_at は top-level の一括 jq で取得済み
session_reset=""
if [ -n "$five_resets_at" ] && [ "$five_resets_at" != "null" ]; then
  session_reset=$(date -r "${five_resets_at%.*}" "+%H:%M" 2>/dev/null)
fi

if [ -n "$session_pct" ] && [ "$session_pct" != "ERROR" ]; then
  session_pct=$(printf '%.0f' "$session_pct")
  scolor=$(_braille_color_for "$session_pct")
  five_battery=$(_battery_for_used "$session_pct")
  five_remaining_pct=$(( 100 - session_pct ))
  [ "$five_remaining_pct" -lt 0 ] && five_remaining_pct=0

  five_remaining_str=""
  if [ -n "$five_resets_at" ] && [ "$five_resets_at" != "null" ]; then
    five_cycle_sec=18000  # 5h = 5 * 3600
    five_now=$(date +%s)
    five_rem=$(( ${five_resets_at%.*} - five_now ))
    [ "$five_rem" -lt 0 ] && five_rem=0
    [ "$five_rem" -gt "$five_cycle_sec" ] && five_rem=$five_cycle_sec
    # 残り時間 (Nh / Nh NNm / Nm)。単位間は空白 + 分は zero-pad で幅を揃える。
    fr_h=$(( five_rem / 3600 ))
    fr_m=$(( (five_rem % 3600) / 60 ))
    if [ "$fr_h" -gt 0 ] && [ "$fr_m" -gt 0 ]; then
      five_remaining_str=$(printf '%dh %02dm' "$fr_h" "$fr_m")
    elif [ "$fr_h" -gt 0 ]; then
      five_remaining_str="${fr_h}h"
    else
      five_remaining_str="${fr_m}m"
    fi
  fi

  hourglass_5h=$'\xf3\xb0\x94\x9f'  # nf-md-hourglass (U+F051F)
  five_icon=$'\xf3\xb1\x87\xb9'     # nf-md-clock-time-five (U+F11F9)

  # Ctx と同じ battery 表記 (glyph + 残量 %)。clock icon はセクション識別として残し、
  # battery glyph と % に severity 色 (_braille_color_for) を適用する。
  left_text="${left_text} │ ${five_icon}  ${five_battery} ${five_remaining_pct}%"
  left_fmt="${left_fmt} \033[2m│\033[0m $(printf '%b%s\033[0m  %b%s\033[0m %b%s%%\033[0m' \
    "$SECTION_ICON" "$five_icon" "$scolor" "$five_battery" "$scolor" "$five_remaining_pct")"

  if [ -n "$five_remaining_str" ]; then
    five_remaining_sup=$(_to_superscript "$five_remaining_str")
    left_text="${left_text}  ${hourglass_5h} ${five_remaining_sup}"
    left_fmt="${left_fmt}$(printf '  %b%s\033[0m %b%s\033[0m' \
      "$META_HOURGLASS" "$hourglass_5h" "$META_REMAINING" "$five_remaining_sup")"
  fi

  if [ -n "$session_reset" ]; then
    left_text="${left_text} ➤ ${session_reset}"
    left_fmt="${left_fmt}$(printf ' %b➤\033[0m %b%s\033[0m' \
      "$META_ICON" "$META_ENDTIME" "$session_reset")"
  fi

  # ---------------------------------------------------------------------------
  # 左側: 週間レートリミット — 入力のパースと残り時間の計算
  # JSON から使用率・リセット日時を取得し、リセットまでの残り時間を算出する。
  # 残り時間は最大単位＋次単位で表示する（例: 4d18h / 18h30m / 45m）。
  # 依存: jq, date, bc
  # ---------------------------------------------------------------------------
  # weekly_pct / weekly_resets_at は top-level の一括 jq で取得済み
  weekly_reset=""          # リセット日時の表示文字列 (例: 3/28 21:45)
  weekly_remaining=""      # 残り時間の表示文字列 (例: 4d18h)
  weekly_remaining_secs=0  # 残り秒数（per day 計算用）
  weekly_per_day=""        # 1日あたりの予算 pp (例: 18)

  if [ -n "$weekly_resets_at" ] && [ "$weekly_resets_at" != "null" ]; then
    weekly_reset=$(date -r "${weekly_resets_at%.*}" "+%-m/%-d %H:%M" 2>/dev/null)
    weekly_remaining_secs=$(( ${weekly_resets_at%.*} - $(date +%s) ))
    [ "$weekly_remaining_secs" -lt 0 ] && weekly_remaining_secs=0

    # 残り時間を最大単位＋次単位にフォーマットする。単位間は空白 + 2桁 zero-pad で揃える。
    # 1日以上: `Nd NNh` (0h なら Nd) / 1時間以上: `Nh NNm` (0m なら Nh) / 1時間未満: Nm
    wr_days=$(( weekly_remaining_secs / 86400 ))
    wr_hours=$(( (weekly_remaining_secs % 86400) / 3600 ))
    wr_mins=$(( (weekly_remaining_secs % 3600) / 60 ))
    if [ "$wr_days" -gt 0 ] && [ "$wr_hours" -gt 0 ]; then
      weekly_remaining=$(printf '%dd %02dh' "$wr_days" "$wr_hours")
    elif [ "$wr_days" -gt 0 ]; then
      weekly_remaining="${wr_days}d"
    elif [ "$wr_hours" -gt 0 ] && [ "$wr_mins" -gt 0 ]; then
      weekly_remaining=$(printf '%dh %02dm' "$wr_hours" "$wr_mins")
    elif [ "$wr_hours" -gt 0 ]; then
      weekly_remaining="${wr_hours}h"
    else
      weekly_remaining="${wr_mins}m"
    fi
  fi

  # ---------------------------------------------------------------------------
  # 左側: 今日の消費ポイント (today セクション) + cycle day 履歴
  # weekly cycle (7 日) 内の 24h スロットを 1 day として扱う。
  # Day 境界は resets_at から逆算した 24h 間隔 (カレンダー 0:00 ではない)。
  #
  # === State 設計 (v4) ===
  # 持つべき状態: 各 day の「朝 (= day 境界時) の weekly_pct」のスタックのみ。
  #   history: [{day_start_ts, morning_pct}, ...] newest-first、最大 7 エントリ
  # cycle 情報 (ends_at, day_idx, day_start) や現時点の weekly_pct は JSON から
  # 毎回 derive。これらを state に持たせると複数フィールドを原子的に更新できず、
  # 「ends_at は新 cycle なのに day_idx は前 cycle の値」のような部分更新の不整合が
  # 起きる。毎回 derive なら単一入力 (resets_at) から一貫性が保たれる。
  #
  # === State 更新ルール ===
  # 0. 5h.resets_at < now (= 入力 stale)        → skip (全ルールより先に評価)
  # 1. history 空                               → push 新 entry
  # 2. head.day_start_ts < cycle_start         → 前 cycle 所属。破棄して新 cycle
  #                                              初日として仕切り直し
  # 3. current_day_start > head.day_start_ts   → day 進行 (同 cycle)。push
  # 4. current_day_start < head.day_start_ts   → backward (stale 入力) → skip
  # 5. 同日, 境界 +60s 以内, input_pct > head  → max-update (境界 race 補正)
  # 6. 同日, それ以外                            → skip (書き込みゼロ)
  #
  # ルール 0 の理由: 複数セッション環境で Claude Code 本体は rate_limits を
  # プロセス内にキャッシュし、API 呼び出し時のみ refresh する。アイドル session
  # は古い weekly_pct を送り続けるため、5h cycle が切り替わっても自分の
  # resets_at が更新されない → これを stale signal として使う。
  # ルール 5 の理由: day 境界で stale-low な session が先に push してしまった
  # ケースに対する補正。60s = refresh 2 周期で全 session が 1 回は走る想定。
  # 60s 以降は input pct に今日の成長が乗ってくるので max-update すると
  # morning_pct が膨らんで today_used が消える → 許可しない。
  #
  # Cycle 跨ぎでは旧 cycle の最終日を finalize しない (不正確な値になる)。
  # Sparkline で gap がある日は空バー表示、diff は earlier (古い) entry の使用量
  # として計上 (user 指定動作)。
  #
  # 統計情報永続化のため /tmp ではなく $XDG_STATE_HOME/claude-status/ に置く。
  # 旧 /tmp/claude-status/weekly-snapshot.json (v1/v2) および v3 snap があれば
  # 破棄して v4 で仕切り直し。
  # 依存: jq, date, bc
  # 読み書き: $XDG_STATE_HOME/claude-status/weekly-snapshot.json (v4 スキーマ)
  # 出力例: T:5pp ⏳6h30m 18pp/d
  # ---------------------------------------------------------------------------
  today_used=""            # 今日の消費 pp (= weekly_pct - history[0].morning_pct)
  today_elapsed=""         # cycle day の開始からの経過時間 (例: 6h30m)
  today_history_json="[]"  # JSON 出力用 (per-day pp list、v3 互換形式)

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

    # legacy snapshot 掃除
    [ -f "$OLD_SNAPSHOT_FILE" ] && rm -f "$OLD_SNAPSHOT_FILE"
    # 古い tmp ファイル掃除 (5 分以上放置されてるものは orphan とみなす)
    find "$STATE_DIR" -name "weekly-snapshot.json.tmp.*" -mmin +5 -delete 2>/dev/null || true

    # スナップショット読み取り (v4 のみ、それ以外は fresh start)
    history_json="[]"
    if [ -f "$SNAPSHOT_FILE" ]; then
      snap_version=$(jq -r '.version // 0' "$SNAPSHOT_FILE" 2>/dev/null)
      if [ "$snap_version" = "4" ]; then
        loaded=$(jq -c '.history // []' "$SNAPSHOT_FILE" 2>/dev/null)
        [ -n "$loaded" ] && history_json="$loaded"
      fi
    fi

    # head (newest entry) 取得
    head_day_start=$(jq -r '.[0].day_start_ts // empty' <<< "$history_json" 2>/dev/null)
    head_morning_pct=$(jq -r '.[0].morning_pct // empty' <<< "$history_json" 2>/dev/null)

    # === State 更新判定 ===
    skip_write=false
    new_history="$history_json"

    # Stale 入力ガード: 5h.resets_at が過去 = この session の Claude Code 本体は
    # rate_limits を refresh しておらず、weekly_pct も古い値が固定で来ている。
    # 詳細: アイドルセッション (API 未呼び出し) は rate_limits がプロセス内
    # キャッシュのまま更新されないため、複数セッション環境では古い stale 値が
    # snapshot に push されて morning_pct を壊す。5h cycle が切り替わっても
    # 自分の resets_at が更新されないことを stale signal として使う。
    five_resets_int="${five_resets_at%.*}"
    if [ -n "$five_resets_int" ] && [ "$five_resets_int" != "0" ] \
       && [ "$five_resets_int" -lt "$now_ts" ] 2>/dev/null; then
      skip_write=true
    elif [ -z "$head_day_start" ]; then
      # 初回: 新 entry で start
      new_history=$(jq -n \
        --argjson ts "$current_day_start" \
        --argjson pct "$weekly_pct_num" \
        '[{day_start_ts: $ts, morning_pct: $pct}]')
    elif [ "$head_day_start" -lt "$cycle_start" ] 2>/dev/null; then
      # head が前 cycle 所属 = cycle 切替検知。history 破棄、新 cycle 初日として仕切り直し
      new_history=$(jq -n \
        --argjson ts "$current_day_start" \
        --argjson pct "$weekly_pct_num" \
        '[{day_start_ts: $ts, morning_pct: $pct}]')
    elif [ "$current_day_start" -gt "$head_day_start" ] 2>/dev/null; then
      # 同 cycle 内 day 進行。push + 現 cycle の entry のみ保持 + 7 件まで
      new_history=$(jq -c \
        --argjson ts "$current_day_start" \
        --argjson pct "$weekly_pct_num" \
        --argjson cs "$cycle_start" \
        '([{day_start_ts: $ts, morning_pct: $pct}] + [.[] | select(.day_start_ts >= $cs)])[:7]' \
        <<< "$history_json")
    elif [ "$current_day_start" -lt "$head_day_start" ] 2>/dev/null; then
      # backward: stale 入力 → state 触らずスキップ。次の正常 run で回復
      skip_write=true
    else
      # 同日: 通常は書き込みゼロ。
      # ただし境界直後 60s 以内なら max-update 許可: 14:00 境界での race で
      # stale-low (5h fresh だが weekly が古い session) が先に push してしまった
      # 場合に、同 60s 窓内の他 fresh session が観測した高い pct で head を
      # 上書きする。60s = refresh 2 周期 ≒ 全 session が 1 回は走る時間。
      # 60s 以降は input pct に「今日の成長」が乗ってくるので max-update すると
      # morning_pct が膨らむ → skip。
      elapsed=$(( now_ts - current_day_start ))
      if [ "$elapsed" -ge 0 ] && [ "$elapsed" -le 60 ] \
         && [ "$weekly_pct_num" -gt "${head_morning_pct%.*}" ] 2>/dev/null; then
        new_history=$(jq -c \
          --argjson pct "$weekly_pct_num" \
          '.[0].morning_pct = $pct' \
          <<< "$history_json")
      else
        skip_write=true
      fi
    fi

    # 書き出し (必要なときだけ)
    if [ "$skip_write" != "true" ]; then
      SNAPSHOT_TMP="${SNAPSHOT_FILE}.tmp.$$"
      # trap で tmp をクリーンアップ (jq 成功後 mv 前に process kill された場合の残留防止)
      trap 'rm -f "$SNAPSHOT_TMP" 2>/dev/null' EXIT
      jq -n --argjson history "$new_history" \
        '{version: 4, history: $history}' \
        > "$SNAPSHOT_TMP" && mv "$SNAPSHOT_TMP" "$SNAPSHOT_FILE"
      history_json="$new_history"
    fi

    # === Display 派生 ===
    # today_used = 現 weekly_pct - history[0].morning_pct (clamp 0)
    head_morning_pct_eff=$(jq -r '.[0].morning_pct // "0"' <<< "$history_json" 2>/dev/null)
    today_used=$(( weekly_pct_num - ${head_morning_pct_eff%.*} ))
    [ "$today_used" -lt 0 ] && today_used=0

    # 経過時間
    elapsed_secs=$(( now_ts - current_day_start ))
    [ "$elapsed_secs" -lt 0 ] && elapsed_secs=0
    [ "$elapsed_secs" -gt 86400 ] && elapsed_secs=86400
    el_hours=$(( elapsed_secs / 3600 ))
    el_mins=$(( (elapsed_secs % 3600) / 60 ))
    if [ "$el_hours" -gt 0 ] && [ "$el_mins" -gt 0 ]; then
      today_elapsed=$(printf '%dh %02dm' "$el_hours" "$el_mins")
    elif [ "$el_hours" -gt 0 ]; then
      today_elapsed="${el_hours}h"
    else
      today_elapsed="${el_mins}m"
    fi

    # Per-day pp 配列を history から構築 (sparkline 用)。
    # ルール: 各 entry の pp = 次に newer な entry の morning_pct との差分。
    #   (newest = history[0]) の pp は weekly_pct - morning_pct (= today_used)。
    # gap (day_idx に entry なし) は 0 で空バー表示。
    # JSON output 用に v3 互換の days array も構築。
    declare -A pp_by_day_v4
    declare -A has_data_v4
    for ((i=1; i<=7; i++)); do
      pp_by_day_v4[$i]=0
      has_data_v4[$i]=0
    done

    # history 全 entry を 1 回の jq 呼び出しで `ts pct` 行列に展開する。
    # entry 数 × 2〜3 回の jq fork を避けるため mapfile でまとめて読み込む。
    mapfile -t hist_rows < <(jq -r '.[] | "\(.day_start_ts) \(.morning_pct)"' <<< "$history_json" 2>/dev/null)
    for ((h=0; h<${#hist_rows[@]}; h++)); do
      read -r ent_ts ent_pct <<< "${hist_rows[$h]}"
      # 現 cycle 外の entry は除外 (stale)
      [ "$ent_ts" -lt "$cycle_start" ] 2>/dev/null && continue
      d=$(( (ent_ts - cycle_start) / 86400 + 1 ))
      [ "$d" -lt 1 ] || [ "$d" -gt 7 ] && continue
      if [ "$h" -eq 0 ]; then
        pp=$today_used
      else
        read -r _ prev_pct <<< "${hist_rows[$((h-1))]}"
        pp=$(( ${prev_pct%.*} - ${ent_pct%.*} ))
        [ "$pp" -lt 0 ] && pp=0
      fi
      pp_by_day_v4[$d]=$pp
      has_data_v4[$d]=1
    done

    # v3 互換の days array (JSON output の weeklyHistory 用)。
    # newest-first、今日を除く過去 day のみ (today は todayUsed フィールドにある)。
    # jq で incremental append するのは fork コストが大きいので bash 側で JSON
    # 文字列を組み立てる。pp_by_day_v4 は整数のみなのでエスケープ不要。
    today_history_entries=""
    for ((d=7; d>=1; d--)); do
      if [ "${has_data_v4[$d]}" = "1" ] && [ "$d" -ne "$current_day_idx" ]; then
        [ -n "$today_history_entries" ] && today_history_entries+=","
        today_history_entries+="{\"day_idx\":$d,\"pp\":${pp_by_day_v4[$d]}}"
      fi
    done
    today_history_json="[${today_history_entries}]"

    # per day 予算の計算: head (= 今日の朝) の morning_pct と残り日数から整数除算。
    # pp/d = (100 - head.morning_pct) / (8 - current_day_idx)
    # 日境界で一度確定したら 1 日中安定、翌朝に morning_pct が更新されて再計算。
    # 現在の remaining_pct を remaining_secs/86400 で割る方式にすると小数除算に
    # なって、残り時間 < 1d のときに pp/d > remaining_pct (例: 残り 23% なのに
    # 25pp/d) という直感に反する表示になる。整数除算ベースだと最終日でも
    # pp/d = remaining_pct で収まる。
    days_remaining=$(( 8 - current_day_idx ))
    [ "$days_remaining" -lt 1 ] && days_remaining=1
    morning_for_budget=${head_morning_pct_eff%.*}
    if [ -n "$morning_for_budget" ] && [ "$morning_for_budget" -ge 0 ] 2>/dev/null; then
      budget_remaining=$(( 100 - morning_for_budget ))
      [ "$budget_remaining" -lt 0 ] && budget_remaining=0
      weekly_per_day=$(( budget_remaining / days_remaining ))
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
      today_icon=$'\xf3\xb1\x91\xb8'  # nf-md U+F1478 (today)

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
      if [ "$tr_h" -gt 0 ] && [ "$tr_m" -gt 0 ]; then
        today_remaining_str=$(printf '%dh %02dm' "$tr_h" "$tr_m")
      elif [ "$tr_h" -gt 0 ]; then
        today_remaining_str="${tr_h}h"
      else
        today_remaining_str="${tr_m}m"
      fi
      # end time も current_day_start 基準 (stored は信頼しない)
      today_end_epoch=$(( current_day_start + 86400 ))
      today_end_time=$(date -r "$today_end_epoch" "+%-H:%M" 2>/dev/null)

      # T-icon + Npp + Npp/d + remaining + 終了時刻
      # severity color は Npp のみ。icon は SECTION_ICON、pp/d は bright cyan
      # (今日の消費 pp と per-day 予算を並べて比較できるように today 側に配置)、
      # 󰔟/➤ は META_ICON (dim gray)、残り時間は META_REMAINING (cyan)、
      # 終了時刻は META_ENDTIME (amber) で色分けして数値を主役にする。
      today_remaining_sup=$(_to_superscript "$today_remaining_str")

      # pp/d segment (conditional) — 今日の pp の右に space 区切りで append
      ppd_text=""
      ppd_fmt_content=""
      if [ -n "$weekly_per_day" ]; then
        ppd_text=" ${weekly_per_day}pp/d"
        ppd_fmt_content=" \033[96m${weekly_per_day}pp/d\033[0m"
      fi

      t_text="${today_icon}  ${today_used}pp${ppd_text}  ${hourglass} ${today_remaining_sup} ➤ ${today_end_time}"
      t_fmt=$(printf '%b%s\033[0m  %b%spp\033[0m%b  %b%s\033[0m %b%s\033[0m %b➤\033[0m %b%s\033[0m' \
        "$SECTION_ICON" "$today_icon" \
        "$tcolor" "$today_used" \
        "$ppd_fmt_content" \
        "$META_HOURGLASS" "$hourglass" \
        "$META_REMAINING" "$today_remaining_sup" \
        "$META_ICON" \
        "$META_ENDTIME" "$today_end_time")

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
    weekly_remaining_pct=$(( 100 - weekly_pct ))
    [ "$weekly_remaining_pct" -lt 0 ] && weekly_remaining_pct=0
    wcolor=$(_braille_color_for "$weekly_pct")
    # bar は残量で fill (100% 始まりで usage 増で減る、battery と同じ減衰感)。
    # 色は usage ベースの severity を維持するので _render_braille_bar の 2nd arg で上書き。
    weekly_braille=$(_render_braille_bar "$weekly_remaining_pct" "$wcolor")

    hourglass_r=$'\xf3\xb0\x94\x9f'  # nf-md-hourglass (U+F051F)
    week_icon=$'\xf3\xb0\x8e\xb8'    # nf-md U+F03B8 (weekly)

    # 形式: <W-icon> <Braille 4-char> NN% 󰔟<残り> → <日付>
    # icon は SECTION_ICON (固定色)、bar と % は残量表示だが色は usage 由来 severity
    w_text="${week_icon}  ⣿⣿⣿⣿ ${weekly_remaining_pct}%"
    w_fmt=$(printf '%b%s\033[0m  %s %b%s%%\033[0m' "$SECTION_ICON" "$week_icon" "$weekly_braille" "$wcolor" "$weekly_remaining_pct")

    if [ -n "$weekly_remaining" ]; then
      weekly_remaining_sup=$(_to_superscript "$weekly_remaining")
      w_text="${w_text}  ${hourglass_r} ${weekly_remaining_sup}"
      w_fmt="${w_fmt}$(printf '  %b%s\033[0m %b%s\033[0m' \
        "$META_HOURGLASS" "$hourglass_r" "$META_REMAINING" "$weekly_remaining_sup")"
    fi

    if [ -n "$weekly_reset" ]; then
      w_text="${w_text} ➤ ${weekly_reset}"
      w_fmt="${w_fmt}$(printf ' %b➤\033[0m %b%s\033[0m' \
        "$META_ICON" "$META_ENDTIME" "$weekly_reset")"
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

    # icon: nf-md U+F03B7 (7d 専用、weekly とは別グリフで視覚的に区別)
    # 並び順: icon + sparkline (pp/d は today セクションに移動済み)
    spark_icon=$'\xf3\xb0\x8e\xb7'
    spark_text="${spark_icon}  "
    spark_fmt=$(printf '%b%s\033[0m  ' "$SECTION_ICON" "$spark_icon")

    # cycle day 1..7 を順に描画。today は 󱞩 マーカー直後、未来は薄色。
    # pp_by_day_v4 は state 更新セクションで既に構築済み (history から derive)。
    # gap day (has_data_v4[d]=0) は pp=0 で空バー表示 (user 指定動作)。
    # today_marker = nf-md U+F17A9 (指さし系)。SOFT_META (italic muted violet) で控えめに目立たせる。
    today_marker=$'\xf3\xb1\x9e\xa9'
    for ((i=1; i<=7; i++)); do
      if [ "$i" -eq "$current_day_idx" ]; then
        # マーカー (SOFT_META 色) + today (通常色)
        spark_text+="${today_marker}"
        spark_fmt+=$(printf '%b%s\033[0m' "$SOFT_META" "$today_marker")
        spark_append_bar "${today_used:-0}" 0
      elif [ "$i" -lt "$current_day_idx" ]; then
        # 過去 day (薄色、データあれば pp、なければ 0 = 空バー)
        spark_append_bar "${pp_by_day_v4[$i]:-0}" 1
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
# line 2: 直近 5 ターンの cache metrics (digits + graph) + Σ + TTL
#
# レイアウト (左=新、右=古):
#   ⚡ Model │ digits (最新 2 ターン) │ in·hit graph (3 ターン) │ out graph (3 ターン)
#            │ Σ (累積) │ TTL
#
# Claude Code の context_window.current_usage から 1 ターン分の
#   - input_tokens                (uncached = キャッシュに乗らなかった input)
#   - cache_creation_input_tokens (cache 新規書き込み)
#   - cache_read_input_tokens     (cache 読出し)
#   - output_tokens
# を受け取る。hit rate = cache_read / (input + cc + cache_read)。
# output はキャッシュ対象外 (モデルが毎回新規生成) なので hit rate 計算には不使用。
#
# === State: per-session ファイルに分離 ===
# Claude Code は複数セッションが並列で走る (別 tmux pane 等) 。state file を
# 全セッションで共有するとターン粒度の race で履歴が壊れる。ファイル名に
# session_id を入れることで各セッション独立に書き込めるようにし、race を回避。
# 配置は /tmp/claude-status/ (既に session JSON export が使っている場所)。
# /tmp は OS が定期掃除する (macOS: /etc/periodic/daily/110.clean-tmps で atime
# 3 日超を削除 / Linux: systemd-tmpfiles で ~10 日) ので終了セッションの残骸も
# 自動で片付く。
#
# State ファイル: /tmp/claude-status/turn-history-<session_id>.json
#   schema: { version: 1, last_sig: "i-cc-cr-o", turns: [{i,cc,cr,o}, ...] }
#   turns は newest-first、最大 5 件 (digits 2 + graph 3)。
# Update trigger: (cur_in, cur_cc, cur_cr, cur_out) の signature 変化 = 新ターン完了。
#   statusline は毎回走るが signature 同じなら書かない (= 1 ターン 1 push)。
#
# === TTL の anchor ===
# Claude Code は会話イベント (user msg / assistant / tool result) で
# transcript_path (.jsonl) に append するため、その mtime ≒ 最後に API が
# キャッシュに触れた時刻。transcript は session ごとに別ファイルなので共有
# state 問題はない。prompt cache のデフォルト TTL は 5 分 (Anthropic API 仕様)。
#
# 依存: jq, date, stat (macOS -f %m / Linux -c %Y)
# 出力例:
#   ⚡ Opus 4.7 │ in·hit out 200·98% 80  300·97% 100 │ ⣤⣷ ⣦⣷ ⣧⣇ │ ⣤ ⣶ ⣇ │ Σ in 32K, out 12K │ TTL 59:48
#
# digits セクション (最新 2 ターン):
#   label `in·hit out` + turn ごとに `{in}·{hit}% {out}` を 2 スペース区切り。
#   now (左) は通常色、t-1 (右) は同色ベースの dim で視線誘導。
# graph セクション (3 ターン):
#   in·hit pair bar と out 単色 bar を別セクションで描画 (subscript なし)。
#   ターン間は 1 スペース区切り、左=新・右=古。
#   in·hit pair は 1 ターン = [in-bar][hit-bar] の 2 Braille cells。
#   色: in=cyan / hit=severity (90+=緑/70+=黄/<70=赤) / out=magenta。
#
# per-turn metrics の定義:
#   in  = cur_in + cur_cc  (今ターンで新規に積んだ input。cur_in はほぼ常に 1 で
#         breakpoint 外の構造トークン。user 発言/tool 結果 etc. の実体は cc 側に入る。
#         cache TTL 切れで全 prefix が miss すると cc が膨れて in が急騰する)
#   out = cur_out          (今ターンの output)
#   hit = cur_cr / (cur_in + cur_cc + cur_cr)  (このターンの cache 活用率)
#
# cur_in + cur_cc + cur_cr は「今ターン時点の累積 context サイズ」で、
# context_window.used_percentage と同じ概念なので turn 単位の値としては使わない。
# -----------------------------------------------------------------------------
# cur_in / cur_cc / cur_cr / cur_out / total_in / total_out / transcript_path は
# top-level の一括 jq で取得済み。ここではデフォルト値 (0 や空文字) へ補完する。
cur_in="${cur_in:-0}"
cur_cc="${cur_cc:-0}"
cur_cr="${cur_cr:-0}"
cur_out="${cur_out:-0}"
total_in="${total_in:-0}"
total_out="${total_out:-0}"
cur_sig="${cur_in}-${cur_cc}-${cur_cr}-${cur_out}"

# --- 数値フォーマット: 1000 未満はそのまま、以上は K / M で短縮 ---
_fmt_k() {
  local n="$1"
  if [ "$n" -lt 1000 ] 2>/dev/null; then printf '%d' "$n"
  elif [ "$n" -lt 10000 ] 2>/dev/null; then printf '%d.%dK' $(( n / 1000 )) $(( (n % 1000) / 100 ))
  elif [ "$n" -lt 1000000 ] 2>/dev/null; then printf '%dK' $(( n / 1000 ))
  else printf '%d.%dM' $(( n / 1000000 )) $(( (n % 1000000) / 100000 ))
  fi
}

# --- per-session state read ---
TURN_HISTORY_FILE=""
turns_json="[]"
last_sig=""
sum_fresh_in=0
sum_out=0
if [ -n "$session_id" ] && [ "$session_id" != "null" ]; then
  mkdir -p /tmp/claude-status 2>/dev/null
  TURN_HISTORY_FILE="/tmp/claude-status/turn-history-${session_id}.json"
  if [ -f "$TURN_HISTORY_FILE" ]; then
    _sv=$(jq -r '.version // 0' "$TURN_HISTORY_FILE" 2>/dev/null)
    if [ "$_sv" = "2" ]; then
      last_sig=$(jq -r '.last_sig // empty' "$TURN_HISTORY_FILE" 2>/dev/null)
      loaded=$(jq -c '.turns // []' "$TURN_HISTORY_FILE" 2>/dev/null)
      [ -n "$loaded" ] && turns_json="$loaded"
      sum_fresh_in=$(jq -r '.sum_fresh_in // 0' "$TURN_HISTORY_FILE" 2>/dev/null)
      sum_out=$(jq -r '.sum_out // 0' "$TURN_HISTORY_FILE" 2>/dev/null)
    elif [ "$_sv" = "1" ]; then
      last_sig=$(jq -r '.last_sig // empty' "$TURN_HISTORY_FILE" 2>/dev/null)
      loaded=$(jq -c '.turns // []' "$TURN_HISTORY_FILE" 2>/dev/null)
      [ -n "$loaded" ] && turns_json="$loaded"
      sum_fresh_in=$(jq -r '[.turns[]? | (.i // 0) + (.cc // 0)] | add // 0' "$TURN_HISTORY_FILE" 2>/dev/null)
      sum_out=$(jq -r '[.turns[]? | .o // 0] | add // 0' "$TURN_HISTORY_FILE" 2>/dev/null)
    fi
  fi
fi

# --- signature 変化 → 新ターン push (+ state write) ---
if [ -n "$TURN_HISTORY_FILE" ] && [ "$cur_sig" != "$last_sig" ]; then
  sum_fresh_in=$(( sum_fresh_in + cur_in + cur_cc ))
  sum_out=$(( sum_out + cur_out ))
  turns_json=$(jq -c \
    --argjson i "$cur_in" --argjson cc "$cur_cc" \
    --argjson cr "$cur_cr" --argjson o "$cur_out" \
    '([{i: $i, cc: $cc, cr: $cr, o: $o}] + .)[:4]' <<< "$turns_json")
  TH_TMP="${TURN_HISTORY_FILE}.tmp.$$"
  if jq -n --arg sig "$cur_sig" --argjson turns "$turns_json" \
      --argjson sfi "$sum_fresh_in" --argjson so "$sum_out" \
      '{version: 2, last_sig: $sig, turns: $turns, sum_fresh_in: $sfi, sum_out: $so}' \
      > "$TH_TMP" 2>/dev/null; then
    mv "$TH_TMP" "$TURN_HISTORY_FILE"
  else
    rm -f "$TH_TMP" 2>/dev/null
  fi
fi

# --- per-turn metrics (current) ---
# in = cur_in + cur_cc (今ターンで新規に積んだ input。cache 切れで急騰する)。
# hit = 今ターンの cache 活用率 (in spike と冗長だが TTL 観察用)。
cur_fresh_in=$(( cur_in + cur_cc ))
cur_total=$(( cur_in + cur_cc + cur_cr ))
cur_hit=0
[ "$cur_total" -gt 0 ] && cur_hit=$(( cur_cr * 100 / cur_total ))
_hit_color_for() {
  local p="$1"
  if [ "$p" -ge 90 ]; then printf '\033[92m'
  elif [ "$p" -ge 70 ]; then printf '\033[93m'
  else printf '\033[91m'
  fi
}
cur_hit_color=$(_hit_color_for "$cur_hit")

cur_in_str=$(_fmt_k "$cur_fresh_in")
cur_out_str=$(_fmt_k "$cur_out")
tot_in_str=$(_fmt_k "$sum_fresh_in")
tot_out_str=$(_fmt_k "$sum_out")

# --- turn rows の読み込み ---
# turns_json は newest-first: [0]=now, [1]=t-1, [2..4]=graph (t-2/t-3/t-4)
mapfile -t turn_rows < <(jq -r '.[] | "\(.i) \(.cc) \(.cr) \(.o)"' <<< "$turns_json" 2>/dev/null)
n_turns=${#turn_rows[@]}

# --- digits section: 最新 2 ターン (now / t-1) ---
# 形式: `in·hit out {in}·{hit}% {out}  {in}·{hit}% {out}` (左=新、2 スペース区切り)
# now は通常色、t-1 は同色ベースの dim (\033[2;9Xm)。
# データ不足は `—·—% —` の dim placeholder で埋める。
_hit_color_for_dim() {
  local p="$1"
  if [ "$p" -ge 90 ]; then printf '\033[2;92m'
  elif [ "$p" -ge 70 ]; then printf '\033[2;93m'
  else printf '\033[2;91m'
  fi
}

digits_text=""
digits_fmt=""
# ターン間のセパレータ: ` › ` (U+203A)。dim 色で視覚的に控えめにし、
# 左=新・右=古の時系列順であることを示唆する。
sep_turn_text=" › "
sep_turn_fmt=$(printf ' \033[2m›\033[0m ')
for ((idx=0; idx<4; idx++)); do
  # idx=0 (now) は `in N hit N% out N` の label inline 形式で凡例を兼ねる。
  # idx>=1 (過去ターン) は `N·N% N` のコンパクト形式 + 同色 dim で視線誘導。
  if [ "$idx" -eq 0 ]; then sep_text=""; sep_fmt=""; else sep_text="$sep_turn_text"; sep_fmt="$sep_turn_fmt"; fi
  if [ "$idx" -ge "$n_turns" ]; then
    if [ "$idx" -eq 0 ]; then
      # label は subscript (ᵢₙ ₕᵢₜ ₒᵤₜ) で視覚的に縮小。dim + subscript の二重控えめ
      digits_text+="${sep_text}ᵢₙ — ₕᵢₜ —% ₒᵤₜ —"
      digits_fmt+=$(printf '%s\033[2mᵢₙ — ₕᵢₜ —%% ₒᵤₜ —\033[0m' "$sep_fmt")
    else
      digits_text+="${sep_text}—·—% —"
      digits_fmt+=$(printf '%s\033[2m—·—%% —\033[0m' "$sep_fmt")
    fi
    continue
  fi
  read -r _ti _tcc _tcr _to <<< "${turn_rows[$idx]}"
  _fresh=$(( _ti + _tcc ))
  _total=$(( _ti + _tcc + _tcr ))
  _hit=0
  [ "$_total" -gt 0 ] && _hit=$(( _tcr * 100 / _total ))
  _in_s=$(_fmt_k "$_fresh")
  _out_s=$(_fmt_k "$_to")

  if [ "$idx" -eq 0 ]; then
    _hc=$(_hit_color_for "$_hit")
    # label は subscript (ᵢₙ ₕᵢₜ ₒᵤₜ) で視覚的に縮小。値は通常サイズの bright 色で主役に
    digits_text+="${sep_text}ᵢₙ ${_in_s} ₕᵢₜ ${_hit}% ₒᵤₜ ${_out_s}"
    digits_fmt+=$(printf '%s\033[2mᵢₙ\033[0m \033[96m%s\033[0m \033[2mₕᵢₜ\033[0m %b%s%%\033[0m \033[2mₒᵤₜ\033[0m \033[95m%s\033[0m' \
      "$sep_fmt" "$_in_s" "$_hc" "$_hit" "$_out_s")
  else
    _hc=$(_hit_color_for_dim "$_hit")
    digits_text+="${sep_text}${_in_s}·${_hit}% ${_out_s}"
    digits_fmt+=$(printf '%s\033[2;96m%s\033[0m\033[2m·\033[0m%b%s%%\033[0m \033[2;95m%s\033[0m' \
      "$sep_fmt" "$_in_s" "$_hc" "$_hit" "$_out_s")
  fi
done

# グラフは廃止 (見づらいため)。過去ターンは digits section に dim で並べる。

# --- TTL: 1 時間 countdown ---
# Claude Code CLI の default cache TTL は 1 時間 (extended cache)。
# Anthropic 公式 docs は「default = 5min ephemeral」だが、実機観測により
# Claude Code CLI は内部で 1h extended cache を使っている (Issue #46829 の
# 1h → 5min regression 話とも整合、現 2.1.114 では 1h が効いている)。
# 経過時間 = now - transcript mtime (= 最後の API コール時刻のプロキシ)。
ttl_text=""; ttl_fmt=""
if [ -n "$transcript_path" ] && [ -f "$transcript_path" ]; then
  last_api_ts=$(stat -f %m "$transcript_path" 2>/dev/null || stat -c %Y "$transcript_path" 2>/dev/null || echo 0)
  if [ "$last_api_ts" -gt 0 ] 2>/dev/null; then
    ttl_elapsed=$(( $(date +%s) - last_api_ts ))
    [ "$ttl_elapsed" -lt 0 ] && ttl_elapsed=0
    ttl_rem=$(( 3600 - ttl_elapsed ))
    if [ "$ttl_rem" -le 0 ]; then
      ttl_text="TTL expired"
      ttl_fmt=$(printf '\033[2mTTL\033[0m \033[2mexpired\033[0m')
    else
      ttl_m=$(( ttl_rem / 60 ))
      ttl_s=$(( ttl_rem % 60 ))
      ttl_text=$(printf 'TTL %d:%02d' "$ttl_m" "$ttl_s")
      if [ "$ttl_rem" -gt 1800 ]; then ttl_color='\033[92m'
      elif [ "$ttl_rem" -gt 900 ]; then ttl_color='\033[93m'
      else ttl_color='\033[91m'
      fi
      ttl_fmt=$(printf '\033[2mTTL\033[0m %b%d:%02d\033[0m' "$ttl_color" "$ttl_m" "$ttl_s")
    fi
  fi
fi

# --- 組み立て ---
# Model │ digits (4 turns) │ Σ │ TTL
cache_text="${digits_text} │ Σ in ${tot_in_str}, out ${tot_out_str}"
cache_fmt="${digits_fmt} \033[2m│\033[0m $(printf '\033[2mΣ\033[0m in \033[96m%s\033[0m\033[2m,\033[0m out \033[95m%s\033[0m' "$tot_in_str" "$tot_out_str")"

# Model を line 2 の先頭に prepend
if [ -n "$model_text" ]; then
  cache_text="${model_text} │ ${cache_text}"
  cache_fmt="${model_fmt} \033[2m│\033[0m ${cache_fmt}"
fi

if [ -n "$ttl_text" ]; then
  cache_text="${cache_text} │ ${ttl_text}"
  cache_fmt="${cache_fmt} \033[2m│\033[0m ${ttl_fmt}"
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

# NOTE: Model は line 2 左端 (cache_text) に配置済み、Vim は line 1 先頭に prepend 済み。
# 右側順 (line 3): Branch │ CWD [│ Version]

# left_text は先頭の " │ " を持つ (budget セクションが空の left_text に append した結果)。
# 描画前に 1 段だけ剥がす。left_fmt は printf %b で後から解釈される "\033" リテラル
# を含むので、パターン側も通常の quote で指定する (ANSI-C quote の $'...' にすると
# 本物の ESC バイトになってミスマッチ)。
left_text="${left_text# │ }"
left_fmt_leading=' \033[2m│\033[0m '
# "$var" で quote すると glob 解釈が無効化される ([2m などが char class にならない)
left_fmt="${left_fmt#"$left_fmt_leading"}"

# vim mode を line 1 先頭に prepend
if [ -n "$vim_mode" ] && [ "$vim_mode" != "null" ]; then
  if [ "$vim_mode" = "NORMAL" ]; then
    vim_mode_fmt=$(printf "\033[1;30;43m %s \033[0m" "$vim_mode")
  else
    vim_mode_fmt="$vim_mode"
  fi
  if [ -n "$left_text" ]; then
    left_text="${vim_mode} │ ${left_text}"
    left_fmt="${vim_mode_fmt} \033[2m│\033[0m ${left_fmt}"
  else
    left_text="${vim_mode}"
    left_fmt="${vim_mode_fmt}"
  fi
fi

# -----------------------------------------------------------------------------
# 3 行固定レイアウト:
#   line 1: [NORMAL │] Ctx │ 5h │ Today │ 7d │ Weekly
#   line 2: ⚡ Model │ in·hit │ out │ Σ │ TTL
#   line 3: Branch │ 📁 cwd │ version
# セッション開始直後は rate_limits / context_window がまだ届かず left_fmt が
# 空になるため、placeholder を出して 3 行構成を保つ (空 printf だと 1 行目が
# 丸ごと空白行になり「消えた」ように見える)。
# -----------------------------------------------------------------------------
if [ -z "$left_fmt" ]; then
  left_fmt=$'\033[2m— budget: awaiting first API call\033[0m'
fi
printf "%b\n" "$left_fmt"
[ -n "$cache_fmt" ] && printf "%b\n" "$cache_fmt"
printf "%b\n" "$right_fmt"

# vim mode 高速キャッシュ書き出し (line1 の vim mode 以外の本体を保存)
mkdir -p /tmp/claude-status 2>/dev/null
_sl_line1_body="$left_fmt"
if [ -n "$vim_mode" ] && [ "$vim_mode" != "null" ] && [ -n "$_sl_line1_body" ]; then
  _sl_vim_prefix="${vim_mode_fmt} \033[2m│\033[0m "
  _sl_line1_body="${_sl_line1_body#"$_sl_vim_prefix"}"
fi
printf '%s\x1f%s\x1f%s\x1f%s' "$vim_mode" "$_sl_line1_body" "$cache_fmt" "$right_fmt" > "$_SL_CACHE_FILE"

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
