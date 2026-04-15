# dotfiles

設定ファイルとツールカタログのリポジトリ。

## 方針

- インストールスクリプトは持たない。何を使っているかを宣言的に管理する
- 設定ファイルは stow で symlink 配置する
- Brewfile がツールカタログを兼ねる (`brew bundle dump --describe` で生成)

## 構造

stow ベース。各トップレベルディレクトリが stow package で、中身は `~` からの相対パスを再現している。

```text
nvim/.config/nvim/       → ~/.config/nvim/
tmux/.config/tmux/       → ~/.config/tmux/
tmux/.tmux.conf          → ~/.tmux.conf
ghostty/.config/ghostty/ → ~/.config/ghostty/
git/.config/git/         → ~/.config/git/
fish/.config/fish/       → ~/.config/fish/
```

デプロイ: `stow -t ~ nvim git fish lazygit tig tmux bin claude`

## 設定変更時のルール

### 変更の波及を確認する

設定を変更・追加したら、その変更が他のどこに影響するかを考える。以下は代表例だが、これらに限らず「この変更で他に壊れるもの・更新すべきものはないか」を常に意識する。

- ファイル追加/移動 → symlink の整合性
- 使い方の変更 → ドキュメント
- 依存の追加/削除 → パッケージ管理 (Brewfile 等)
- プラグインの動作変更 → プラグイン更新で上書きされない管理方法
- ビルドが必要な設定 → ビルドステップの実行

### 含めないもの

- シークレット (API キー、トークン)
- ランタイム生成ファイル
- パッケージマネージャが自動生成するファイル

### コミット前の個人情報チェック

このリポジトリは public。コミット・push する前に、ステージされた全ファイルを
以下の観点でスキャンする。特に設定ファイル (`settings.json` 等) はツールが自動
で書き換えるため、ユーザー固有の情報が混入しやすい。

チェック項目:

- 絶対パスに含まれる OS ユーザー名 (`/Users/<name>/`, `/home/<name>/`)
- プライベートなプロジェクト名やリポジトリ名
- API キー、トークン、パスワード (`sk-`, `ghp_`, `Bearer` 等)
- メールアドレス
- 固有の識別子 (ntfy topic, webhook URL, デバイス ID 等)
- IP アドレス

検出方法の例:

```bash
git diff --cached | grep -iE '/Users/[a-z]|/home/[a-z]|api.key|token|secret|password|sk-|ghp_|@[a-z]+\.[a-z]'
```

見つかった場合は、その行を汎用化するかファイルごと除外する。テンプレート +
`.gitignore` パターン (例: `notify-config.example` を追跡し `notify-config`
は除外) も選択肢。

### stow package の作り方

新しいツールの設定を追加するときは、stow package としてトップレベルディレクトリを作る。中身は `~` からの相対パスを再現する。

## 問題解決の進め方

最初の試行は直感で進めてよい。ただし一度詰まったら場当たり的な修正を繰り返さず、立ち止まって全体を整理する。

仕様が不確かなものは推測で断定せず、公式ドキュメント・ソースコード・man page 等で確認してから回答する。「たぶんこう」で進めて間違えると手戻りが大きい。

sed / awk / perl の in-place 編集 (`-i`) は、
echo やパイプで小さいサンプルに対してテストしてから
実ファイルに適用する。テストなしの直接適用は禁止。

### 「詰まった」の判定基準

以下のいずれかが該当したら立ち止まって全体整理に移る。

- ユーザーから同じ症状の指摘を 2 回以上受けた (例: 「まだ更新されない」が繰り返される)
- 小修正を 3 回以上連続で加えたが症状が解消しない
- state / 永続化系のバグを調査している。表面症状だけ直しても再発しやすいので、早めに state モデルの妥当性から疑う
- ユーザーが「詳細に調べて」「整理して」と明示要求した

立ち止まったら以下の手順に切り替える。

- 症状の全列挙 (これまでの小修正で観測した事象も含む)
- 影響範囲の全読取り (関連ファイル、関連状態、並行処理の有無)
- 根本原因仮説の列挙 (表面症状ではなく構造的原因)
- テストは原因究明の後に限定 (仮説検証目的に絞る)

### 調査手順

1. 現状の事実を整理する (設定値、実装の流れ、エラーメッセージ、使える API)
2. 問題を体系的に分析する (何が起きていて、原因の候補は何か、どの仮説を検証すべきか)
3. 検証プランを立てる (どの順番で切り分ければ最短で原因に辿り着けるか)
4. ターミナルで完結する検証は先に済ませる。Web 検索やソースコード読みも活用する
5. ユーザーへの確認は最小限にする (「試してください」の連打はしない)

## ターミナル環境

- ターミナル: ghostty (kitty graphics protocol 対応、画像/mermaid プレビュー用)
- wezterm も併用可だが画像表示は ghostty が必要
- tmux + fish shell

## fish 設定の注意

- `config.fish` にシークレットを書かない
- fisher プラグインは `fish_plugins` ファイルで宣言。`fisher update` でインストール

### シークレットの管理方針

API キーやトークンは **macOS Keychain + `conf.d/secrets.fish`** で管理する。

- Keychain にキーを保存: `security add-generic-password -s <service> -a $USER -w "<value>"`
- `~/.config/fish/conf.d/secrets.fish` (stow 管理外) で Keychain から読み出して環境変数に設定
- `secrets.fish` にはキー本体を書かない。`security find-generic-password -s <service> -w` の呼び出しだけ

この方式を選んだ理由:

- `set -Ux` (fish universal variable) だと `fish_variables` に平文でキーが残り、
    誤って git add すると漏洩する
- Keychain 方式なら `secrets.fish` や `fish_variables` を git add しても API キー本体は含まれない
- ランタイムでは環境変数に載るのでプロセスから読める点は `set -Ux` と同等。ディスク上の平文回避が主な利点
- `security find-generic-password` は数 ms で完了するので shell 起動速度に影響しない
