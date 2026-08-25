#!/usr/bin/env bash
# 現在の window を新しい session に移動して、その session に切り替える。
# tmux popup 内で実行される。
#
# 引数:
#   なし (環境変数 _MW_WINDOW_ID, _MW_CLIENT は呼び出し元でセット済み)
set -eu

window_id=$(tmux showenv -g _MW_WINDOW_ID 2>/dev/null | cut -d= -f2) || true
client=$(tmux showenv -g _MW_CLIENT 2>/dev/null | cut -d= -f2) || true

if [ -z "$window_id" ] || [ -z "$client" ]; then
  echo "Error: missing window/client info"
  sleep 2
  exit 0
fi

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

# 環境変数をクリーンアップ
tmux setenv -gu _MW_WINDOW_ID
tmux setenv -gu _MW_CLIENT
