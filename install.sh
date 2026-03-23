#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== dotfiles install ==="
echo ""

# --- nvim ---
echo "[nvim] linking ~/.config/nvim -> $DOTFILES_DIR/config/nvim"
if [[ -L "$HOME/.config/nvim" ]]; then
  echo "  (updating existing symlink)"
  ln -sf "$DOTFILES_DIR/config/nvim" "$HOME/.config/nvim"
elif [[ -d "$HOME/.config/nvim" ]]; then
  echo "  WARNING: ~/.config/nvim is a real directory, not a symlink."
  echo "  Back it up and remove it, then re-run:"
  echo "    mv ~/.config/nvim ~/.config/nvim.bak"
  echo "    ./install.sh"
else
  mkdir -p "$HOME/.config"
  ln -s "$DOTFILES_DIR/config/nvim" "$HOME/.config/nvim"
  echo "  done"
fi
echo ""

# --- git delta ---
DELTA_GITCONFIG="$DOTFILES_DIR/config/git/delta.gitconfig"
INCLUDE_PATH="path = $DELTA_GITCONFIG"
if git config --global --get-all include.path 2>/dev/null | grep -qF "$DELTA_GITCONFIG"; then
  echo "[git] delta.gitconfig already included in ~/.gitconfig"
else
  echo "[git] adding include for delta.gitconfig to ~/.gitconfig"
  git config --global --add include.path "$DELTA_GITCONFIG"
  echo "  done"
fi
echo ""

# --- bin (CLI tools) ---
BIN_DIR="$HOME/.local/bin"
mkdir -p "$BIN_DIR"
if compgen -G "$DOTFILES_DIR/bin/*" > /dev/null 2>&1; then
  echo "[bin] linking tools to $BIN_DIR"
  for tool in "$DOTFILES_DIR"/bin/*; do
    [[ "$(basename "$tool")" == "README.md" ]] && continue
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
else
  echo "[bin] no tools to link"
fi
echo ""

# --- nvim plugins ---
echo "[nvim] installing plugins via vim-plug..."
if command -v nvim &>/dev/null; then
  nvim --headless +PlugInstall +qall 2>/dev/null || echo "  WARNING: PlugInstall failed. Run :PlugInstall manually in nvim."
  echo "  done"
else
  echo "  WARNING: nvim not found. Install nvim first."
fi
echo ""

# --- dependencies check ---
echo "[check] verifying dependencies..."
deps_ok=true
for cmd in nvim delta; do
  if command -v "$cmd" &>/dev/null; then
    echo "  $cmd: OK ($(command -v "$cmd"))"
  else
    echo "  $cmd: MISSING"
    deps_ok=false
  fi
done
if ! $deps_ok; then
  echo ""
  echo "Install missing dependencies:"
  echo "  brew install neovim git-delta"
fi
echo ""

echo "=== done ==="
