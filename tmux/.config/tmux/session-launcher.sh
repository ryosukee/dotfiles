#!/usr/bin/env bash
# prefix + S から呼ばれる session launcher。
#
# 仕組み:
#   - `_launcher` という専用 session を一度だけ生成し、その中でこのスクリプト
#     自身を `--loop` 付きで再実行することで fzf を while ループで常駐させる。
#   - エントリモード (引数なし) は `switch-client -t _launcher` するだけ。
#     launcher 側の fzf はスタンバイ状態なので即座に UI が出る。
#   - fzf で enter を押すと選んだ window の session に switch-client して
#     select-window。q / esc で元の session (`switch-client -l`) に戻る。
#
# サブコマンド:
#   --loop     launcher session の中で fzf ループを回す
#   --list     window 一覧をツリー形式で生成 (fzf に食わせる)
#   --preview  指定 target の preview を生成する (fzf --preview から呼ばれる)

set -u

LAUNCHER_SESSION="_launcher"
SELF="$HOME/.config/tmux/session-launcher.sh"

# ---- list: window 単位のツリー表示 ----
# 出力フォーマット: "<session>:<window_index>\t<tree-display>"
# fzf 側は --delimiter=$'\t' --with-nth=2.. で 2 列目以降だけ表示し、
# 選択時には 1 列目 (session:index) がそのまま返る。
gen_list() {
  tmux list-windows -a \
    -F '#{session_name}	#{window_index}	#{window_name}	#{pane_current_command}' \
    | grep -vx "$(printf '%s\t.*' "$LAUNCHER_SESSION")" \
    | awk -F'\t' -v DIM=$'\033[38;5;244m' -v RST=$'\033[0m' -v SESS=$'\033[1;36m' '
      {
        sess[NR]=$1; idx[NR]=$2; wname[NR]=$3; cmd[NR]=$4
        if (length($1) > maxw) maxw = length($1)
      }
      END {
        for (i=1; i<=NR; i++) {
          first = (i==1 || sess[i-1]!=sess[i])
          last  = (i==NR || sess[i+1]!=sess[i])
          branch = last ? "└─ " : "├─ "
          if (first) {
            # 先頭 window 行に session 名を inline
            printf "%s:%s\t%s%-*s%s %s%s%s%s: %s%s %s(%s)%s\n", \
              sess[i], idx[i], SESS, maxw, sess[i], RST, \
              DIM, branch, RST, idx[i], wname[i], RST, DIM, cmd[i], RST
          } else {
            # 2 本目以降は session 名をスペースでパディング
            printf "%s:%s\t%-*s %s%s%s%s: %s%s %s(%s)%s\n", \
              sess[i], idx[i], maxw, "", \
              DIM, branch, RST, idx[i], wname[i], RST, DIM, cmd[i], RST
          }
        }
      }
    '
}

# ---- preview: ANSI を保ちつつ可視幅で truncate ----
# choose-tree は対象 pane のグリッドを preview 欄の幅でクリップしているだけ
# なので、同じことを capture-pane + 可視幅 truncate で再現する。
# $FZF_PREVIEW_COLUMNS は fzf が preview プロセスに渡す現在の preview 幅。
_truncate_ansi() {
  # 1 pass で以下をまとめて処理する (複数 perl を直列に繋ぐより高速):
  #   a. underline color / 複合 SGR 内の underline パラメータを除去
  #   b. 各行の bg 状態を追跡して、bg を持たない行は前行の bg を prepend
  #   c. 可視幅 (CJK 考慮) で truncate し、残りセルを空白で pad
  #   d. 各行の先頭と末尾に individual attribute reset を付与
  perl -CSD -ne '
    BEGIN {
      $w = $ENV{PREVIEW_WIDTH} || 80;
      $last_bg = "";
      $reset = "\e[22m\e[23m\e[24m\e[25m\e[27m\e[28m\e[29m\e[39m\e[49m\e[59m";
      # East Asian Wide / Fullwidth の簡易判定 (wcwidth 相当)
      sub cwidth {
        my $c = ord($_[0]);
        return 0 if $c < 0x20 || ($c >= 0x7F && $c < 0xA0);
        return 2 if $c >= 0x1100 && $c <= 0x115F;
        return 2 if $c >= 0x2E80 && $c <= 0x303E;
        return 2 if $c >= 0x3041 && $c <= 0x33FF;
        return 2 if $c >= 0x3400 && $c <= 0x4DBF;
        return 2 if $c >= 0x4E00 && $c <= 0x9FFF;
        return 2 if $c >= 0xA000 && $c <= 0xA4CF;
        return 2 if $c >= 0xAC00 && $c <= 0xD7A3;
        return 2 if $c >= 0xF900 && $c <= 0xFAFF;
        return 2 if $c >= 0xFE30 && $c <= 0xFE4F;
        return 2 if $c >= 0xFF00 && $c <= 0xFF60;
        return 2 if $c >= 0xFFE0 && $c <= 0xFFE6;
        return 1;
      }
      # SGR パラメータから underline 系 (4 / 21 / 4:N) を除去して
      # クリーンな SGR 文字列に組み直す。
      sub clean_sgr {
        my @p = split /;/, $_[0];
        my @kept;
        for (my $i = 0; $i < @p; $i++) {
          my $v = $p[$i];
          next if $v eq "4" || $v eq "21" || $v =~ /^4:/;
          if ($v eq "38" || $v eq "48") {
            push @kept, $v;
            if ($i+1 < @p && ($p[$i+1] eq "5" || $p[$i+1] eq "2")) {
              my $n = $p[$i+1] eq "5" ? 1 : 3;
              push @kept, $p[$i+1];
              for (my $j = 0; $j < $n && $i+2+$j < @p; $j++) {
                push @kept, $p[$i+2+$j];
              }
              $i += 1 + $n;
            }
            next;
          }
          push @kept, $v;
        }
        return "\e[" . join(";", @kept) . "m";
      }
    }

    chomp;
    # 先に underline color 系を削除 (他のパラメータと混ざらない形式なので regex で済む)
    s/\e\[58[;:][0-9;:]*m//g;
    s/\e\[59m//g;

    my ($out, $vis) = ("", 0);
    my $line_last_bg = "";

    while (/\G(\e\[([0-9;:]*)m|\e\[[0-9;:?]*[ -\/]*[@-~]|\e\][^\a]*\a|.)/gcs) {
      my $tok = $1;
      my $params = $2;
      if (defined $params) {
        # SGR シーケンス: underline 除去 + bg 追跡
        my $cleaned = clean_sgr($params);
        $out .= $cleaned;
        if ($cleaned =~ /\e\[(?:[0-9;:]*;)?(48[;:]\d+(?:[;:]\d+)*|49)m/) {
          $line_last_bg = "\e[$1m";
        }
      } elsif ($tok =~ /^\e/) {
        # その他の escape (CSI 非 SGR, OSC)
        $out .= $tok;
      } else {
        my $cw = cwidth($tok);
        if ($vis + $cw <= $w) {
          $out .= $tok;
          $vis += $cw;
        }
      }
    }

    # bg carry: この行に bg が無ければ前行の bg を流用
    my $prepend = $line_last_bg ? "" : $last_bg;
    $last_bg = $line_last_bg || $last_bg;

    my $remaining = $w - $vis;
    my $pad = $remaining > 0 ? " " x $remaining : "";
    print "$reset$prepend$out$reset$pad\n";
  '
}

# target = "session:window" の全 pane をキャプチャして連結。
# 複数 pane の場合は各 pane 前にヘッダを付ける。キャッシュが効いていれば
# 即座に cat で返す。
_pad_output() {
  # $FZF_PREVIEW_LINES まで、default bg の full-width space で埋める。
  # 前回 preview の下部が残像として残るのを物理的に上書きする。
  local rows="${FZF_PREVIEW_LINES:-50}"
  # _truncate_ansi と合わせて +4 余分に pad する
  local cols="${PREVIEW_WIDTH:-${FZF_PREVIEW_COLUMNS:-80}}"
  awk -v rows="$rows" -v cols="$cols" '
    BEGIN {
      reset = "\033[22m\033[23m\033[24m\033[25m\033[27m\033[28m\033[29m\033[39m\033[49m\033[59m"
      blank = reset
      for (i = 0; i < cols; i++) blank = blank " "
    }
    { print; n++ }
    END {
      while (n < rows) { print blank; n++ }
    }
  '
}

_compute_preview() {
  local target="$1"
  local panes
  panes=$(tmux list-panes -t "$target" -F '#{pane_id} #{pane_current_command}' 2>/dev/null)
  local pane_count
  pane_count=$(printf '%s\n' "$panes" | grep -c .)

  while IFS=' ' read -r pid cmd; do
    [ -z "$pid" ] && continue
    if [ "$pane_count" -gt 1 ]; then
      printf '\e[1;33m── %s (%s) ──\e[0m\n' "$pid" "$cmd" | _truncate_ansi
    fi
    tmux capture-pane -eNp -t "$pid" 2>/dev/null | _truncate_ansi
  done <<< "$panes"
}

_schedule_refresh() {
  # tmux server にタスクを投げて非同期で refresh-client を発火する。
  # run-shell -b は tmux server プロセス側で実行されるため fzf や preview
  # subprocess の SIGTERM の影響を受けず確実に実行される。preview script は
  # 即座に exit できるので navigation の体感遅延がない。
  local c
  for c in $(tmux list-clients -t "$LAUNCHER_SESSION" -F '#{client_name}' 2>/dev/null); do
    tmux run-shell -b "sleep 0.05 && tmux refresh-client -t '$c'" 2>/dev/null || true
  done
}

gen_preview() {
  local target="$1"
  # fzf が報告する FZF_PREVIEW_COLUMNS が実効幅より狭いケース
  # (border や余白の計上差) のセーフティとして +4 cell 余分に pad する。
  # 超過分は fzf が右端で切るので見た目に影響はない。
  local base_w="${FZF_PREVIEW_COLUMNS:-80}"
  export PREVIEW_WIDTH="$(( base_w + 4 ))"

  # cache hit / miss で出力を分岐
  local cache_file=""
  if [ -n "${LAUNCHER_CACHE_DIR:-}" ]; then
    local key
    key=$(printf '%s_%s' "$target" "$PREVIEW_WIDTH" | tr '/:' '_')
    cache_file="$LAUNCHER_CACHE_DIR/$key"
  fi

  if [ -n "$cache_file" ] && [ -f "$cache_file" ]; then
    # cache hit: そのまま出力
    cat "$cache_file" | _pad_output
  elif [ -n "$cache_file" ]; then
    # cache miss + cache dir あり: compute + 保存 + 出力
    _compute_preview "$target" | tee "$cache_file" | _pad_output
  else
    # cache 無効: compute + 出力のみ
    _compute_preview "$target" | _pad_output
  fi

  # tmux の差分描画で wezterm 側のセル状態が古いまま残る問題への対策。
  # cache hit/miss どちらの path でも必ず通るようにここに置く。
  # tmux run-shell -b で server 側に sleep + refresh-client を投げるので
  # preview script 自体は即 exit できて navigation の体感遅延ゼロ。
  _schedule_refresh
}

# ---- loop: launcher session の本体 ----
run_loop() {
  while true; do
    # list を 1 回だけ生成して変数に保持し、幅計算と fzf 両方に使い回す
    list=$("$SELF" --list)

    # list の最大可視幅を計算 (ANSI を剥いてから tab 区切りの 2 列目長を測る)
    list_w=$(
      printf '%s\n' "$list" \
        | perl -pe 's/\e\[[0-9;:?]*[ -\/]*[@-~]//g; s/\e\][^\a]*\a//g' \
        | awk -F'\t' '{ n=length($2); if (n>max) max=n } END { print max }'
    )
    # launcher session (= client) の現在幅
    cols=$(tmux display -p -t "$LAUNCHER_SESSION:" '#{window_width}' 2>/dev/null || echo 200)
    # preview 幅 = 全幅 - list 幅 - 余白 (border + gap)
    preview_w=$(( cols - list_w - 6 ))
    [ "$preview_w" -lt 20 ] && preview_w=20

    # per-iteration の preview lazy キャッシュディレクトリ
    cache_dir=$(mktemp -d -t launcher-cache.XXXXXX)
    export LAUNCHER_CACHE_DIR="$cache_dir"

    sel=$(
      printf '%s\n' "$list" \
        | fzf \
            --ansi \
            --reverse \
            --no-sort \
            --cycle \
            --border \
            --delimiter=$'\t' \
            --with-nth=2.. \
            --disabled \
            --prompt "window> " \
            --header "j/k: move  /  enter: switch  /  /: search  /  q,esc: back" \
            --bind "j:down,k:up" \
            --bind "/:unbind(j,k)+enable-search+clear-query+change-prompt(search> )" \
            --preview "LAUNCHER_CACHE_DIR='$cache_dir' bash '$SELF' --preview {1}" \
            --preview-window "right:${preview_w},border-none,nowrap" \
            --expect=q,esc
    ) || true

    # fzf 終了後にキャッシュを掃除
    rm -rf "$cache_dir"
    unset LAUNCHER_CACHE_DIR

    key=$(printf '%s\n' "$sel" | sed -n '1p')
    line=$(printf '%s\n' "$sel" | sed -n '2p')
    # 選択行の 1 列目 (tab 区切り) = "session:index"
    target=$(printf '%s' "$line" | awk -F'\t' '{print $1}')

    case "$key" in
      q|esc)
        tmux switch-client -l 2>/dev/null || true
        ;;
      "")
        if [ -n "$target" ]; then
          sname="${target%%:*}"
          widx="${target##*:}"
          tmux switch-client -t "=$sname" 2>/dev/null \
            && tmux select-window -t "=$sname:$widx" 2>/dev/null \
            || tmux switch-client -l 2>/dev/null || true
        else
          tmux switch-client -l 2>/dev/null || true
        fi
        ;;
    esac
  done
}

# ---- ディスパッチ ----
case "${1:-}" in
  --loop)
    run_loop
    exit 0
    ;;
  --list)
    gen_list
    exit 0
    ;;
  --preview)
    gen_preview "${2:-}"
    exit 0
    ;;
esac

# --- エントリモード ---
if ! tmux has-session -t "=${LAUNCHER_SESSION}" 2>/dev/null; then
  tmux new-session -d -s "$LAUNCHER_SESSION" -x 220 -y 60 \
    "bash $SELF --loop"
  tmux set-option -t "$LAUNCHER_SESSION" status off 2>/dev/null || true
fi

tmux switch-client -t "=${LAUNCHER_SESSION}"
