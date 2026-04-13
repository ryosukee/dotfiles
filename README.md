# dotfiles

設定ファイルとツールカタログ。インストールスクリプトは持たず、何を使っているかを宣言的に管理する。

## 方針

- 設定ファイルの同期: stow でシンボリックリンクを作成
- ツールカタログ: Brewfile がパッケージ一覧を兼ねる
- インストールは手動 or AI に任せる: スクリプトは腐りやすいので持たない

## 構造

```text
dotfiles/
├── nvim/          # Neovim (LazyVim)
├── git/           # gitconfig, gitignore
├── fish/          # Fish shell
├── lazygit/       # lazygit (delta 連携)
├── tig/           # tig
├── tmux/          # tmux + claude popup editor
├── bin/           # 自作 CLI (~/.local/bin/cc-ask-dotfiles 等)
├── claude/        # Claude Code 設定 (settings, rules, hooks, skills, statusline)
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
stow -t ~ nvim git fish lazygit tig tmux bin claude

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
| yazi | ターミナルファイルマネージャ (Rust, 画像プレビュー対応) | `brew install yazi` |
| fd | find の代替 (yazi のバックエンド) | `brew install fd` |
| ripgrep | grep の代替 (yazi のバックエンド) | `brew install ripgrep` |
| jq | JSON プロセッサ | `brew install jq` |
| yq | YAML/JSON/XML プロセッサ | `brew install yq` |
| imagemagick | 画像処理 | `brew install imagemagick` |
| ffmpeg | 動画処理 (yazi の動画プレビュー) | `brew install ffmpeg` |
| poppler | PDF プロセッサ (yazi の PDF プレビュー) | `brew install poppler` |
| sevenzip | アーカイブ操作 (yazi のアーカイブプレビュー) | `brew install sevenzip` |
| mpv | 動画プレイヤー (yazi から `M` で起動) | `brew install mpv` |

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

## fish のキーバインド・関数

| キー / コマンド | 機能 |
|---|---|
| `Ctrl+G` | git branch を peco で選択して checkout |
| `Ctrl+H` | ghq リポジトリを peco で選択して cd |
| `Ctrl+T` | git worktree を peco で選択して cd |
| `Ctrl+R` | コマンド履歴を peco で検索 |
| `y` | yazi 起動、終了時に yazi 内の cwd に fish を cd |

### シークレット (API キー等)

macOS Keychain に保存し、`~/.config/fish/conf.d/secrets.fish` (stow 管理外) から読み出す。

```bash
# 1. Keychain に保存 (一度だけ)
security add-generic-password -s anthropic-api-key -a $USER -w "sk-ant-..."

# 2. secrets.fish が起動時に読み出す (既にセットアップ済み)
# ~/.config/fish/conf.d/secrets.fish:
#   set -gx ANTHROPIC_API_KEY (security find-generic-password -s anthropic-api-key -w 2>/dev/null)
```

キーを追加するときは同じパターンで `security add-generic-password` + `secrets.fish` に `set -gx` 行を追加する。

## tmux

prefix は tmux デフォルト (`Ctrl+B`)。

| キー | 機能 |
|---|---|
| `prefix + S` | session launcher (自前・choose-tree 風、ツリー表示 + fzf) |
| `prefix + Tab` | treemux sidebar (Neo-Tree を tmux pane として表示) |
| `prefix + P` | 作業用 popup ターミナル (`popup` session) |
| `prefix + e` | Claude Code プロンプト編集用の popup nvim |
| `prefix + Space → C → a` | cc-ask-dotfiles popup (後述) |

詳細・内部仕様は [tmux 設定](./docs/tmux.md) を参照。

## nvim (LazyVim)

LazyVim ベース。プラグイン構成、キーバインド、ワークフローの詳細は [nvim 設定](./docs/nvim.md) を参照。

主要キーバインド:

| キー | 機能 |
|---|---|
| `<Space>gg` | lazygit |
| `<Space>e` | ファイルツリー (neo-tree) |
| `<Space><Space>` | ファイル検索 |
| `<Space>/` | プロジェクト内 grep |
| `<Space>do` | diffview open |
| `<Space>dc` | diffview close |
| `<Space>Ca` | cc-ask-dotfiles popup (後述) |
| `x` (diffview file tree) | レビュー済み ✓ マークをトグル |

## cc-ask-dotfiles

dotfiles の全ファイルを読み込ませた Claude セッションに対して、fish / tmux popup / nvim float から横断的な質問を投げるための自作ツール。設定の意図や tmux と nvim のキー衝突などを 1 つのセッションから聞ける。

| 起動口 | 呼び方 |
|---|---|
| fish | `cc-ask-dotfiles "質問"` (one-shot) または `cc-ask-dotfiles` (対話) |
| tmux | `prefix + Space → C → a` |
| nvim | `<Space>Ca` (floating window、`i` で follow-up、`q` で閉じる) |

詳細・仕組み・既知の注意点は [cc-ask-dotfiles](./docs/cc-ask-dotfiles.md) を参照。

## Brewfile の更新

```bash
cd "$(ghq root)/github.com/ryosukee/dotfiles"
brew bundle dump --describe --force --file=Brewfile
```
