#!/usr/bin/env bash
# treemux の toggle を呼ぶ wrapper。
# which-key yaml から直接 toggle.sh を呼ぶと引数のクォートが tmux の
# init.tmux 生成時に壊れるため、wrapper で吸収する。
#
# Usage: treemux-toggle.sh [focus] <pane_id>

set -u
SCRIPT="$HOME/.tmux/plugins/treemux/scripts/toggle.sh"
ARGS='nvim,~/.tmux/plugins/treemux/configs/treemux_init.lua,,~/.local/share/mise/shims/python3,left,40,top,70%,editor,0.5,2,@treemux-refresh-interval-inactive-window,0'

if [ "${1:-}" = "focus" ]; then
  ARGS="${ARGS},focus,neo-tree"
  shift
else
  ARGS="${ARGS},,neo-tree"
fi

exec "$SCRIPT" "$ARGS" "${1:-%0}"
