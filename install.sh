#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="$HOME/bin"

mkdir -p "$BIN_DIR"

echo "Linking tools to $BIN_DIR ..."

for tool in "$DOTFILES_DIR"/bin/*; do
  name=$(basename "$tool")
  target="$BIN_DIR/$name"
  if [[ -L "$target" ]]; then
    echo "  $name (updating symlink)"
    ln -sf "$tool" "$target"
  elif [[ -e "$target" ]]; then
    echo "  $name (SKIPPED: file already exists and is not a symlink)"
  else
    echo "  $name -> $target"
    ln -s "$tool" "$target"
  fi
done

echo ""
echo "Done. Make sure ~/bin is in your PATH:"
echo "  fish:     fish_add_path ~/bin"
echo "  bash/zsh: export PATH=\"\$HOME/bin:\$PATH\""
