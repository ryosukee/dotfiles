# dotfiles

ポータブルな設定ファイル・CLI ツール集。

## 含まれるもの

| パス | 内容 |
|---|---|
| `config/nvim/` | nvim 設定 (init.vim + lua プラグイン設定) |
| `config/git/delta.gitconfig` | delta (git pager) の設定 |
| `bin/` | 自作 CLI ツール (今後追加予定) |

### nvim プラグイン

- diffview.nvim — サイドバイサイド diff レビュー (wrap 対応、ハイライト調整済み)
- fzf-lua — ファジーファインダー
- その他: vim-gitgutter, vim-airline, markdown-preview.nvim 等

### delta

ターミナルの `git diff` / `git log` 出力を改善する pager。行番号、サイドバイサイド、シンタックスハイライト、word-level diff 付き。

## 依存ツール

```bash
brew install neovim git-delta
```

## 初回セットアップ

```bash
# 1. clone
ghq get ryosukee/dotfiles

# 2. 既存の nvim 設定をバックアップ（ある場合）
mv ~/.config/nvim ~/.config/nvim.bak

# 3. インストール
cd "$(ghq root)/github.com/ryosukee/dotfiles"
./install.sh

# 4. PATH に ~/.local/bin を追加（未設定の場合）
# fish
fish_add_path ~/.local/bin
# bash/zsh
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
```

install.sh が行うこと:
- `~/.config/nvim` → dotfiles の `config/nvim/` に symlink
- `~/.gitconfig` に `config/git/delta.gitconfig` の include を追加
- `bin/` 内のツールを `~/.local/bin/` に symlink
- nvim プラグインのインストール (`PlugInstall`)
- 依存ツールの存在チェック

## アップデート

```bash
cd "$(ghq root)/github.com/ryosukee/dotfiles"
git pull
```

nvim 設定は symlink なので pull するだけで反映される。
nvim プラグインの追加・削除があった場合は nvim 内で `:PlugInstall` / `:PlugClean` を実行する。
