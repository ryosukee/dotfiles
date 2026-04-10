#!/usr/bin/env bash
# window を指定した session に移動する。session が無ければ新規作成。
# Usage: move-window-to-session.sh <session-name>
set -u

name="$1"

if tmux has-session -t "=$name" 2>/dev/null; then
  tmux display-message "Session '$name' already exists"
  exit 1
fi

tmux new-session -d -s "$name"
tmux move-window -k -t "$name:0"
