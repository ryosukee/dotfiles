# Claude Code と Codex を両立するユーザー設定

この文書は、dotfiles における Claude Code と Codex のユーザー設定の管理方法を定める。

## Claude Code を基準とする管理方針

Claude Code の基本設定は、`claude/.claude/settings.json` で管理する。
ステータスラインは、`claude/.claude/statusline.sh` で管理する。
stow で `~/.claude` 配下へ配置し、Claude Code からそのまま読み込む。
Claude Code が読む設定ファイルには、Codex 向けの設定や説明を追加しない。
Codex との両立に必要な設定は Codex 側に置く。

Codex には、Claude Code 用の指示ファイルを読み込む設定と、Codex 固有の設定を加える。
Codex 固有の静的な設定項目は、`codex/.codex/dotfiles.config.toml` で管理する。

Claude Code と Codex に共通する作業リポジトリの指示は、`CLAUDE.md` に置く。
Codex は、ユーザー設定の `project_doc_fallback_filenames = ["CLAUDE.md"]` により、
`AGENTS.md` がない階層で `CLAUDE.md` を読む。同じ階層に `AGENTS.md` を置くと
`CLAUDE.md` が読まれないため、Codex 専用の指示を追加する目的では使わない。

`.claude/rules` のうち、`paths` を持たない rule は常時読み込む指示として
Codex 側でも使う。`codex/.codex/AGENTS.md` を `~/.codex/AGENTS.md` へ stow し、
`~/.claude/rules` から該当する rule を読むよう Codex に指示する。
この `AGENTS.md` はユーザー共通の指示として読み込まれるため、作業リポジトリの
`CLAUDE.md` も project instructions として続けて読み込まれる。
`paths` を持つ rule は、Codex 用の path rule hook で読み込む。

ユーザー共通の skill は `~/.claude/skills` を原本とし、
`~/.agents/skills` から同じディレクトリへの symlink を置く。
作業リポジトリ固有の skill も `.claude/skills` を原本とし、
`.agents/skills` から同じディレクトリへの symlink を置く。
複数の作業リポジトリで使う skill は、両ホストの plugin として配布する。

Claude Code 用の agent 定義を Codex に読ませる対応は保留する。
現時点では、Codex は `.claude/agents` の定義を読み込まない。

## Codex の設定を profile に分ける

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

4. fish を起動し直す

> [!IMPORTANT]
> Codex は profile を自動で選択しない。shell、script、エディタなどの起動方法ごとに、
> `--profile dotfiles` を指定する。指定しなければ `~/.codex/config.toml` だけが使われ、
> `dotfiles.config.toml` の設定は読み込まれない。

dotfiles 管理の `fish/.config/fish/config.fish` には、`codex` の起動時に
`--profile dotfiles` を付ける abbreviation を設定している。

## 確認

Codex に渡される project instructions は、次のコマンドで確認する。

```bash
codex --profile dotfiles -C /path/to/repository debug prompt-input
```

リポジトリルートと作業ディレクトリの `CLAUDE.md` が含まれ、
末尾が途中で切れていなければ確認は完了だ。
