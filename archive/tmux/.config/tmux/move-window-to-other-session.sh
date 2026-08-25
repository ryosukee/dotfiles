#!/usr/bin/env bash
# window を指定した session に移動して、その session に切り替える。
# choose-tree の %% から呼ばれる。
# Usage: move-window-to-other-session.sh <target> [--follow]
set -eu

target="$1"
follow="${2:-}"

tmux move-window -t "$target"

if [ "$follow" = "--follow" ]; then
  # target は "=session:" 形式。session 名を抽出
  session=$(echo "$target" | sed 's/^=//; s/:$//')
  tmux switch-client -t "=$session"
fi
