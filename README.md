# dotfiles

設定ファイルとツールカタログ。インストールスクリプトは持たず、何を使っているかを宣言的に管理する。

## 方針

- 設定ファイルの同期: stow でシンボリックリンクを作成
- ツールカタログ: Brewfile がパッケージ一覧を兼ねる
- インストールは手動 or AI に任せる: スクリプトは腐りやすいので持たない

## 構造

```
dotfiles/
├── nvim/          # Neovim (LazyVim)
├── git/           # gitconfig, gitignore
├── fish/          # Fish shell
├── lazygit/       # lazygit (delta 連携)
├── tig/           # tig
├── tmux/          # tmux + claude popup editor
├── Brewfile       # brew パッケージ一覧 (brew bundle dump --describe で生成)
└── .stow-local-ignore
```

各ディレクトリは stow package。中身は `~` からの相対パスをそのまま再現している。

## セットアップ

```bash
# 1. clone
ghq get ryosukee/dotfiles

# 2. stow と依存ツールをインストール
brew install stow
brew bundle --file="$(ghq root)/github.com/ryosukee/dotfiles/Brewfile"

# 3. 既存設定をバックアップ (必要な場合)
mv ~/.config/nvim ~/.config/nvim.bak
mv ~/.config/fish ~/.config/fish.bak
mv ~/.config/git/config ~/.config/git/config.bak

# 4. symlink を作成
cd "$(ghq root)/github.com/ryosukee/dotfiles"
stow -t ~ nvim git fish lazygit tig tmux

# 5. nvim プラグインをインストール (初回起動で自動)
nvim

# 6. fish プラグインをインストール
fisher update
```

## ツールカタログ

主要なツールと用途。全量は Brewfile を参照。

### シェル & ターミナル

| ツール | 用途 | インストール |
|---|---|---|
| fish | メインシェル (vi キーバインド) | `brew install fish` |
| starship | プロンプト | `brew install starship` |
| wezterm | ターミナルエミュレータ | `brew install --cask wezterm` |
| tmux | ターミナルマルチプレクサ | `brew install tmux` |
| direnv | ディレクトリ単位の環境変数 | `brew install direnv` |
| zoxide | cd の高速化 | `brew install zoxide` |

### エディタ

| ツール | 用途 | インストール |
|---|---|---|
| neovim | メインエディタ (LazyVim) | `brew install neovim` |

### Git

| ツール | 用途 | インストール |
|---|---|---|
| git-delta | diff/log の pager (行番号, サイドバイサイド, シンタックスハイライト) | `brew install git-delta` |
| lazygit | TUI git クライアント (delta 連携, LazyVim 内蔵) | `brew install lazygit` |
| ghq | リポジトリ管理 (`~/ghq_root/` 配下) | `brew install ghq` |
| gwq | git worktree マネージャ | `brew install d-kuro/tap/gwq` |
| git-graph | ブランチグラフ表示 | `cargo install git-graph` |
| tig | TUI git クライアント | `brew install tig` |
| gitui | TUI git クライアント (Rust) | `brew install gitui` |

### ランタイム管理

| ツール | 用途 | インストール |
|---|---|---|
| mise | 言語ランタイム管理 (Node, Python, Go 等) | `brew install mise` |
| uv | Python パッケージマネージャ | `brew install uv` |

### CLI ユーティリティ

| ツール | 用途 | インストール |
|---|---|---|
| bat | cat の代替 (シンタックスハイライト) | `brew install bat` |
| lsd | ls の代替 (アイコン, カラー) | `brew install lsd` |
| fzf | ファジーファインダー | `brew install fzf` |
| peco | インタラクティブフィルタ | `brew install peco` |
| jq | JSON プロセッサ | `brew install jq` |
| yq | YAML/JSON/XML プロセッサ | `brew install yq` |
| imagemagick | 画像処理 | `brew install imagemagick` |

### AI

| ツール | 用途 | インストール |
|---|---|---|
| claude-code | Claude Code CLI + VS Code 拡張 | `brew install anthropic/claude-code/claude-code` / VS Code |
| codex | OpenAI のコーディングエージェント | `brew install codex` |

### インフラ & クラウド

| ツール | 用途 | インストール |
|---|---|---|
| terraform | IaC | `brew install terraform` |
| kubernetes-cli | kubectl | `brew install kubernetes-cli` |
| k9s | Kubernetes TUI | `brew install k9s` |
| kubectx | context/namespace 切り替え | `brew install kubectx` |
| cloudflared | Cloudflare Tunnel | `brew install cloudflared` |

## fish のキーバインド

| キー | 機能 |
|---|---|
| `Ctrl+G` | git branch を peco で選択して checkout |
| `Ctrl+H` | ghq リポジトリを peco で選択して cd |
| `Ctrl+T` | git worktree を peco で選択して cd |
| `Ctrl+R` | コマンド履歴を peco で検索 |

## nvim (LazyVim)

LazyVim ベース。カスタムプラグイン:

| プラグイン | 設定ファイル | 目的 |
|---|---|---|
| diffview.nvim | `diffview.lua` | サイドバイサイド diff (右ペインで直接編集可能) |
| diffview ✓ マーク | `diffview-viewed.lua` | file tree でレビュー済みファイルに ✓ を付ける |
| scope.nvim | `scope.lua` | バッファを tabpage ごとにスコープ |
| bufferline.nvim | `bufferline.lua` | diffview 表示中は bufferline を非表示にする |
| fzf-lua | `claude-fzf.lua` | Claude Code 連携 (`.claude` ファイルで `@` キーでファイル補完) |

主要キーバインド:

| キー | 機能 |
|---|---|
| `<Space>gg` | lazygit |
| `<Space>e` | ファイルツリー (neo-tree) |
| `<Space><Space>` | ファイル検索 |
| `<Space>/` | プロジェクト内 grep |
| `<Space>do` | diffview open |
| `<Space>dc` | diffview close |
| `<Space>dh` | ファイル履歴 |
| `x` (diffview file tree) | レビュー済み ✓ マークをトグル |
| `H` / `L` | バッファ切り替え |
| `<Space><Tab>]` / `[` | tabpage 切り替え |

## Brewfile の更新

```bash
cd "$(ghq root)/github.com/ryosukee/dotfiles"
brew bundle dump --describe --force --file=Brewfile
```
