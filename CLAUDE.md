# dotfiles

設定ファイルとツールカタログのリポジトリ。

## 方針

- インストールスクリプトは持たない。何を使っているかを宣言的に管理する
- 設定ファイルは stow で symlink 配置する
- Brewfile がツールカタログを兼ねる (`brew bundle dump --describe` で生成)

## 構造

stow ベース。各トップレベルディレクトリが stow package で、中身は `~` からの相対パスを再現している。

```
nvim/.config/nvim/   → ~/.config/nvim/
git/.config/git/     → ~/.config/git/
fish/.config/fish/   → ~/.config/fish/
```

デプロイ: `stow nvim git fish`

## 設定変更時のルール

- 新しいツールの設定を追加するときは、stow package として新しいトップレベルディレクトリを作る
- Brewfile は `brew bundle dump --describe --force --file=Brewfile` で再生成する（手編集しない）
- シークレット (API キー、トークン) は絶対にコミットしない
- fish_variables はランタイム生成ファイルなので含めない
- fisher が自動生成するファイル (completions/fisher.fish, functions/fisher.fish) は含めない

## fish 設定の注意

- `config.fish` にシークレットを書かない。環境変数のシークレットは別の仕組み (direnv, 1Password CLI 等) で管理する
- fisher プラグインは `fish_plugins` ファイルで宣言。`fisher update` でインストール
