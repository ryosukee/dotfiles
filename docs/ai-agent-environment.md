# Claude Code と Codex を両立するユーザー設定

この文書は、dotfiles における Claude Code と Codex のユーザー設定の管理方法を定める。

## Claude Code を基準とする管理方針

Claude Code の基本設定は、`claude/.claude/settings.json` で管理する。
ステータスラインは、`claude/.claude/statusline.sh` で管理する。
stow で `~/.claude` 配下へ配置し、Claude Code からそのまま読み込む。
Claude Code が読む設定ファイルには、Codex 向けの設定や説明を追加しない。
Codex との両立に必要な設定は Codex 側に置く。

## 指示・rule・skill・agent の共有

Claude Code と Codex に共通する作業リポジトリの指示は、`CLAUDE.md` に置く。
Codex は、ユーザー設定の `project_doc_fallback_filenames = ["CLAUDE.md"]` により、
Git リポジトリのルートから作業ディレクトリまでの各階層で、`AGENTS.md` がなければ
`CLAUDE.md` を読む。同じ階層に `AGENTS.md` を置くと `CLAUDE.md` が読まれないため、
Codex 専用の指示を追加する目的では使わない。

この fallback 設定は、グローバル scope には適用されない。Codex はグローバル scope で
`~/.codex/AGENTS.md` を読み、同ファイルがない場合も `~/.codex/CLAUDE.md` は読まない。

`.claude/rules` のうち、`paths` を持たない rule は常時読み込む指示として Codex 側でも使う。
dotfiles の `codex-claude-rules` plugin に同梱した script を SessionStart hook から実行し、
`~/.claude/rules` と起動ディレクトリの親階層にある `.claude/rules` から収集する。
`paths` を持つ rule は PreToolUse hook で、対象ファイルまでの階層を調べ、
各 rule が置かれた階層を基準に照合する。同じ rule はセッション内で重複して渡さず、
圧縮後は再度読み込めるようにする。複雑な shell コマンドなど、hook の入力から
対象ファイルを特定できない操作では、該当 rule を自動では渡せない。コマンド内で
`cd` する場合も、移動先を推測せず、そのコマンドのパスからは rule を選ばない。
起動ディレクトリの外にあるファイルは、絶対パスで操作しても選択対象にしない。
現行の rule で使用する `*` と `**` は script が照合できる。script は `?` と
`{a,b}` も扱うが、Claude Code が対応する `[]` 文字クラスは未対応なので、
その形式を rule に追加する前に script も拡張する。

ユーザー共通の skill は `~/.claude/skills` を原本とし、
`~/.agents/skills` から同じディレクトリへの symlink を置く。
作業リポジトリ固有の skill も `.claude/skills` を原本とし、
`.agents/skills` から同じディレクトリへの symlink を置く。
複数の作業リポジトリで使う skill は、両ホストの plugin として配布する。

Claude Code 用の agent 定義を Codex に読ませる対応は保留する。
現時点では、Codex は `.claude/agents` の定義を読み込まない。

## Codex の設定を profile に分ける

Codex 固有の静的な設定項目は、`codex/.codex/dotfiles.config.toml` で管理する。
`~/.codex/config.toml` 全体は stow しない。このファイルには、Codex が更新する
hook trust hash と、端末ごとの project path が入るためだ。symlink すると、Codex が
実行中に更新した内容が dotfiles の working tree に書き込まれる。別の端末では使えない
絶対パスも追跡される。

dotfiles で追跡する設定は、`codex/.codex/dotfiles.config.toml` に分ける。
このファイルを `~/.codex/dotfiles.config.toml` へ stow し、Codex を
`--profile dotfiles` 付きで起動する。Codex は `~/.codex/config.toml` を読み込んだ後に
profile の設定を重ね、同じ設定項目には profile の値を使う。

`~/.codex/dotfiles.config.toml` は dotfiles 内のファイルへの symlink である。
ローカル側で静的な設定を変更すると、dotfiles の working tree に同じ変更が入る。

## セットアップ順序

1. dotfiles を clone する
2. `stow -t ~ claude codex fish` で Claude Code、Codex、fish の設定を配置する
3. 次のコマンドでユーザー共通 skill の symlink を作る

   ```bash
   mkdir -p ~/.agents
   if ! test -e ~/.agents/skills && ! test -L ~/.agents/skills; then
     ln -s ../.claude/skills ~/.agents/skills
   fi
   ```

4. dotfiles のルートで `codex plugin marketplace add .` を実行し、
   `codex plugin add codex-claude-rules@dotfiles` で rule 読み込み plugin をインストールする
5. `codex plugin list` で `codex-claude-rules@dotfiles` が有効なことを確認する
6. fish を起動し直す

plugin を有効にした後、Codex 内の `/hooks` で同梱 hook の内容を確認して信頼する。
信頼前の hook は実行されない。信頼前に省略された SessionStart は遡って実行されないため、
信頼後に新しいセッションを開始する。信頼済みの定義はローカルの Codex 設定にハッシュで
記録され、セッションを作り直すたびに信頼する必要はない。hook の定義が変わったら再確認する。
plugin はユーザー設定としてインストールするので、別のリポジトリでも有効なら同じ hook を使う。
plugin の hook は `--profile dotfiles` の指定とは独立して読み込まれる。
リポジトリ固有の hook を別途定義した場合、その定義は別に信頼が必要になる。

plugin が未導入の場合、その plugin の SessionStart hook 自体は実行されない。
セットアップ時に上記の `codex plugin list` で検出する。起動時にも通知したい場合は
plugin と独立した常設 hook または起動 wrapper が必要になる。

> [!IMPORTANT]
> Codex は profile を自動で選択しない。shell、script、エディタなどの起動方法ごとに、
> `--profile dotfiles` を指定する。指定しなければ設定ファイルとしては
> `~/.codex/config.toml` だけが使われ、`dotfiles.config.toml` の設定は読み込まれない。

dotfiles 管理の `fish/.config/fish/config.fish` には、`codex` の起動時に
`--profile dotfiles` を付ける abbreviation を設定している。

## 確認

Codex に渡される project instructions は、次のコマンドで確認する。

```bash
codex --profile dotfiles -C /path/to/repository debug prompt-input
```

リポジトリルートと作業ディレクトリの `CLAUDE.md` が含まれ、
末尾が途中で切れていなければ確認は完了だ。
