#!/usr/bin/env bash
# 現在の window を新しい session に移動して、その session に切り替える。
# tmux popup 内で実行される。
#
# 引数:
#   $1 - 移動元の window ID (#{window_id} で展開済み)
#   $2 - 移動元の client (#{client_name} で展開済み)
set -eu

window_id="$1"
client="$2"

printf "New session name: "
read -r name

if [ -z "$name" ]; then
  exit 0
fi

if tmux has-session -t "=$name" 2>/dev/null; then
  echo "Error: Session '$name' already exists"
  sleep 2
  exit 0
fi

# 新規 session を作成し、元の window を移動 (-k で空 window を上書き)
tmux new-session -d -s "$name"
tmux move-window -k -s "$window_id" -t "$name:0"

# 移動先の session に切り替え
tmux switch-client -t "$name" -c "$client"
