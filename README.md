# dotfiles

ポータブルな CLI ツール・設定ファイル集。

## 含まれるツール

### `bin/git-review`

ローカル完結の PR 風 diff レビューツール。`git diff` の出力をブラウザで GitHub 風に表示し、インラインコメントを付けられる。PR を出す前のセルフレビュー用。

**機能:**
- GitHub 風のサイドバイサイド / 統合 diff 表示 (diff2html)
- ファイル一覧サイドバー
- 行クリックでインラインコメント追加 (localStorage 保存)
- Markdown エクスポート (クリップボードコピー)

**使い方:**

```bash
git review              # working tree vs HEAD
git review --staged     # staged のみ
git review main         # main との差分
git review main..HEAD   # コミット間差分
```

## セットアップ

```bash
# clone
ghq get ryosukee/dotfiles
# または
git clone https://github.com/ryosukee/dotfiles.git

# インストール (~/bin に symlink を作成)
./install.sh
```

`~/bin` が `$PATH` に含まれていることを確認:

```bash
# fish
fish_add_path ~/bin

# bash/zsh
export PATH="$HOME/bin:$PATH"
```

`git review` として git サブコマンドのように使えます (`git-review` が PATH にあれば自動的に認識)。

## 構成

```
dotfiles/
  bin/          # CLI ツール
    git-review  # PR 風 diff レビュー
  install.sh    # ~/bin への symlink セットアップ
  README.md
```
