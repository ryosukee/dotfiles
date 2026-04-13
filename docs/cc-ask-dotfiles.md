# cc-ask-dotfiles

dotfiles の全ファイル内容をロードした Claude セッションに対して、fish / tmux popup / nvim float から質問を投げるための仕組み。

`~/.local/bin/cc-ask-dotfiles` が本体のシェルスクリプトで、nvim や tmux からはこれを呼ぶ。
tmux のキーバインドと nvim の設定が衝突していないか、fish の関数が重複していないか、
といった dotfiles 横断の質問に答えられる。

## ファイル構成

```text
bin/.local/bin/cc-ask-dotfiles                       # 本体 (POSIX sh)
nvim/.config/nvim/lua/config/ask_dotfiles.lua     # nvim フロート UI
nvim/.config/nvim/lua/config/keymaps.lua          # <leader>Ca キーマップ
tmux/.config/tmux/plugins/tmux-which-key/config.yaml  # prefix + Space → C → a エントリ
~/.local/state/cc-ask-dotfiles/                      # ランタイム状態 (gitignore 対象外)
├── base.jsonl                                    # Claude セッションの jsonl
└── config-hash                                   # 最後に build したときの dotfiles ハッシュ
```

## キーバインド

| 起動元 | キー | モード |
| --- | --- | --- |
| fish | `cc-ask-dotfiles "question"` | one-shot |
| fish | `cc-ask-dotfiles` | 対話 REPL |
| tmux which-key | `prefix + Space → C → a` | 対話 REPL (display-popup 内) |
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
ので、呼び出し元が fish だろうが nvim だろうが tmux popup だろうが、全て同じ
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

### tmux-which-key の反映

`tmux/.config/tmux/plugins/tmux-which-key/config.yaml` を編集しても、tmux を再起動するか下記のコマンドを叩くまでライブのメニューには反映されない。

```bash
~/.tmux/plugins/tmux-which-key/plugin.sh.tmux
```

プラグインは `config.yaml` → `build.py` → `plugin/init.tmux` という
2 段階生成を行うため、`tmux source-file ~/.tmux.conf` だけでは
`init.tmux` の再生成まで辿り着かないことがある。

`@tmux-which-key-xdg-enable=1` がランタイムに set されていると、プラグインが
GNU 限定の `realpath --relative-to` を呼ぶ箇所で macOS が落ちる。
`tmux set-option -gu @tmux-which-key-xdg-enable` で unset してから再 build する。

### 用途スコープ

cc-ask-dotfiles は「dotfiles のことを聞く」ためだけの設計。「今開いている
ファイルについて Claude に聞く」といった一般的な nvim ↔ Claude 連携とは
別物で、そちらは既存のプラグインや専用の統合を別に用意する想定。
cc-ask-dotfiles にコンテキスト (現在の nvim バッファ、選択範囲など) を
注入しないのは、base session のキャッシュを使い回す設計趣旨を保つため。

## 依存

- `claude` (Claude Code CLI)
- `uuidgen` (macOS 標準)
- `sha256sum` または `shasum -a 256` (macOS は shasum が標準)
- `git`
- POSIX sh

## 関連

- [tmux 設定](./tmux.md) tmux-which-key プラグインのセットアップ
- [nvim 設定](./nvim.md) nvim キーマップ全般
