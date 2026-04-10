# dotfiles

設定ファイルとツールカタログのリポジトリ。

## 方針

- インストールスクリプトは持たない。何を使っているかを宣言的に管理する
- 設定ファイルは stow で symlink 配置する
- Brewfile がツールカタログを兼ねる (`brew bundle dump --describe` で生成)

## 構造

stow ベース。各トップレベルディレクトリが stow package で、中身は `~` からの相対パスを再現している。

```
nvim/.config/nvim/       → ~/.config/nvim/
tmux/.config/tmux/       → ~/.config/tmux/
tmux/.tmux.conf          → ~/.tmux.conf
ghostty/.config/ghostty/ → ~/.config/ghostty/
git/.config/git/         → ~/.config/git/
fish/.config/fish/       → ~/.config/fish/
```

デプロイ: `stow nvim tmux ghostty git fish`

## 設定変更時のルール

### 変更の波及を確認する

設定を変更・追加したら、影響を受ける他の場所がないか確認する。

- ファイルを追加/移動したら → stow の symlink が正しいか確認 (`stow <pkg> -t ~ --verbose -n`)
- ツールや設定の使い方が変わったら → `docs/` の関連ドキュメントを更新
- brew で依存を追加/削除したら → Brewfile を再生成 (`brew bundle dump --describe --force --file=Brewfile`)。Brewfile は手編集しない
- プラグインのファイルを直接編集する必要がある場合 → dotfiles にコピーして管理する。プラグイン更新で上書きされないようにする。カスタマイズ箇所はコメントで明示
- which-key の config.yaml を変更したら → `build.py` でプラグインを再生成

### 含めないもの

- シークレット (API キー、トークン)
- ランタイム生成ファイル (fish_variables 等)
- パッケージマネージャが自動生成するファイル (fisher の completions/fisher.fish, functions/fisher.fish 等)

### stow package の作り方

新しいツールの設定を追加するときは、stow package としてトップレベルディレクトリを作る。中身は `~` からの相対パスを再現する。

## ターミナル環境

- ターミナル: ghostty (kitty graphics protocol 対応、画像/mermaid プレビュー用)
- wezterm も併用可だが画像表示は ghostty が必要
- tmux + fish shell

## fish 設定の注意

- `config.fish` にシークレットを書かない。環境変数のシークレットは別の仕組み (direnv, 1Password CLI 等) で管理する
- fisher プラグインは `fish_plugins` ファイルで宣言。`fisher update` でインストール
