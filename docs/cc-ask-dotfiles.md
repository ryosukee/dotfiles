# cc-ask-dotfiles

dotfiles の全ファイル内容をロードした Claude セッションに対して、fish / nvim float から質問を投げるための仕組み。

`~/.local/bin/cc-ask-dotfiles` が本体のシェルスクリプトで、nvim からはこれを呼ぶ。
キーバインドが衝突していないか、fish の関数が重複していないか、
といった dotfiles 横断の質問に答えられる。

## ファイル構成

```text
stow/bin/.local/bin/cc-ask-dotfiles                    # 本体 (POSIX sh)
stow/nvim/.config/nvim/lua/config/ask_dotfiles.lua  # nvim フロート UI
stow/nvim/.config/nvim/lua/config/keymaps.lua       # <leader>Ca キーマップ
~/.local/state/cc-ask-dotfiles/                      # ランタイム状態 (gitignore 対象外)
├── base.jsonl                                    # Claude セッションの jsonl
└── config-hash                                   # 最後に build したときの dotfiles ハッシュ
```

## キーバインド

| 起動元 | キー | モード |
| --- | --- | --- |
| fish | `cc-ask-dotfiles "question"` | one-shot |
| fish | `cc-ask-dotfiles` | 対話 REPL |
| nvim | `<leader>Ca` | floating window + follow-up 可 |

nvim の floating 内では `i` / `a` / `o` で follow-up、`q` / `<Esc>` で閉じる。

## 仕組み

### base session

初回実行時、dotfiles リポジトリの全ファイルを Claude に流し込んで
「read-only なリファレンスセッション」を作る。実体は
`claude -p --session-id <uuid>` が生成する jsonl。生成後、
`~/.local/state/cc-ask-dotfiles/base.jsonl` に move して保持する。

対象ファイルは `git ls-files -co --exclude-standard` で選ぶ。tracked な
ファイルに加えて、untracked だが `.gitignore` に含まれないものも拾うため、
まだコミットしていない新規ファイルも次の質問から反映される。

### hash による自動リビルド

`compute_hash` が毎回の起動時に dotfiles の全バイトを sha256 する。
`~/.local/state/cc-ask-dotfiles/config-hash` に保存した前回値と比較し、
一致しなければ base を作り直す。

> 補足: INDEX ではなく working tree をハッシュする<br>
> `git ls-files -s` だと INDEX (ステージング状態) の blob SHA を返すので、
> 未コミットの変更を検知できない。`cc-ask-dotfiles` では working tree の
> 実バイト列を直接ハッシュすることで、編集中の変更もすぐに反映される。

### query のフォーク

質問が来たら `claude -p --resume $BACKUP --fork-session` で base を fork して
その中で回答を得る。`--resume` にファイルパスを渡すのは非公式挙動だが動作確認済みで、
fork 先 jsonl は project dir に新規作成され、base.jsonl 自体は書き換わらない。
設定が変わらない限り base を使い回せる。

対話モードでは、最初の質問で `--session-id <uuid> --fork-session` により
fork 先 UUID を固定する。2 回目以降は `--resume <uuid>` で同じ fork を継続
するので、Claude は会話の文脈を覚えたまま follow-up に答えられる。

### cwd の固定

スクリプトは起動直後に `cd $DOTFILES` する。Claude のセッション jsonl は
cwd に紐づいた project dir (`~/.claude/projects/<encoded-path>/`) に書かれる
ので、呼び出し元が fish だろうが nvim だろうが、全て同じ
project dir に集約される。`--resume <uuid>` の解決が常に成功する。

## 状態ファイルの寿命

fork された query 用 jsonl は `~/.claude/projects/<encoded-dotfiles-path>/`
に貯まり続ける。Claude Code は 30 日を過ぎた jsonl を起動時に自動削除するので、
手動クリーンアップはしていない。

base.jsonl は `~/.local/state/cc-ask-dotfiles/` にあり、Claude Code の
cleanup 対象外。設定が変わるまで保持される。

> 情報源: Claude Code session cleanup<br>
> "Files in the paths below are deleted on startup once they're older than
> `cleanupPeriodDays`. The default is 30 days."
> ([Explore the .claude directory](https://code.claude.com/docs/en/claude-directory#application-data))

## 既知の注意点

### 用途スコープ

cc-ask-dotfiles は「dotfiles のことを聞く」ためだけの設計。「今開いている
ファイルについて Claude に聞く」といった一般的な nvim ↔ Claude 連携とは
別物で、そちらは既存のプラグインや専用の統合を別に用意する想定。
cc-ask-dotfiles にコンテキスト (現在の nvim バッファ、選択範囲など) を
注入しないのは、base session のキャッシュを使い回す設計趣旨を保つため。

### 1 つの質問に対して回答が複数回に分かれて出る

`claude -p` は、Claude がツールを呼ぶ前に書いた文章もその時点で出力する。
1 つの質問に対して「調べます」のような前置きが先に出て、ツール呼び出しの間が空いてから
本回答が出ることがある。最初の出力は回答の終わりではない。

REPL (`cc-ask-dotfiles` を引数なしで起動) では、claude の実行が終わるまで打鍵をエコーせず、
終了時に実行中に打たれた入力を捨てて `[ask-dotfiles] done (Ns)` を出す。
この行が出るまでは次の質問を打たない。

nvim の float は出力をプロセス終了時にまとめて追記し、終了まで `i` / `a` / `o` を弾くので、
この分割の影響を受けない。

### Ctrl+Shift+J が入力の確定になる

Ctrl+Shift+J (IME のかな切替) がターミナルへ Ctrl+J (改行) として届くと、
REPL の `read -r` も nvim の入力欄も「確定」として扱う。
Ghostty 側で `keybind = ctrl+shift+j=ignore` を入れて子プロセスへ渡さないようにしている
([ghostty 設定](./ghostty.md) を参照)。

## 依存

- `claude` (Claude Code CLI)
- `uuidgen` (macOS 標準)
- `sha256sum` または `shasum -a 256` (macOS は shasum が標準)
- `git`
- POSIX sh

## 関連

- [nvim 設定](./nvim.md) nvim キーマップ全般
