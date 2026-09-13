# Claude Code と Codex を両立するユーザー設定

この文書は、dotfiles における Claude Code と Codex のユーザー設定の管理方法を定める。

## Claude Code を基準とする管理方針

Claude Code の基本設定は、`stow/claude/.claude/settings.json` で管理する。
ステータスラインは、`stow/claude/.claude/statusline.sh` で管理する。
stow で `~/.claude` 配下へ配置し、Claude Code からそのまま読み込む。
Claude Code が読む設定ファイルには、Codex 向けの設定や説明を追加しない。
Codex との両立に必要な設定は Codex 側に置く。

## 指示・rule・skill・agent の共有

### AGENTS.md と CLAUDE.md

Claude Code と Codex に共通する作業リポジトリの指示は、`CLAUDE.md` に置く。
Codex は、ユーザー設定の `project_doc_fallback_filenames = ["CLAUDE.md"]` により、
Git リポジトリのルートから作業ディレクトリまでの各階層で、`AGENTS.md` がなければ
`CLAUDE.md` を読む。同じ階層に `AGENTS.md` を置くと `CLAUDE.md` が読まれないため、
Codex 専用の指示を追加する目的では使わない。

この fallback 設定は、グローバル scope には適用されない。Codex はグローバル scope で
`~/.codex/AGENTS.md` を読み、同ファイルがない場合も `~/.codex/CLAUDE.md` は読まない。

### rule

`.claude/rules` は
[codex-claude-rules plugin](../plugins/codex-claude-rules/README.md) で
Codex にも適用する。rule の探索・照合・制約は plugin の README を参照する。

dotfiles の marketplace には、この rule 読み込みのように Codex の環境設定に
必要な plugin だけを置く。任意の便利機能やツール系の plugin は dotfiles では管理しない。

### skill

ユーザー共通の skill は `~/.claude/skills` を原本とし、
`~/.agents/skills` から同じディレクトリへの symlink を置く。
作業リポジトリ固有の skill も `.claude/skills` を原本とし、
`.agents/skills` から同じディレクトリへの symlink を置く。
複数の作業リポジトリで使う skill は、Claude Code と Codex の両方に対応する plugin として配布する。

### agent

Claude Code 用の agent 定義を Codex に読ませる対応は保留する。
現時点では、Codex は `.claude/agents` の定義を読み込まない。

## stow 管理する Codex の config.toml は profile に分ける

`~/.codex/config.toml` には Codex が更新する hook trust hash と
端末固有の project path が含まれるため、stow しない。
共通の静的設定は `stow/codex/.codex/dotfiles.config.toml` で管理し、
`~/.codex/dotfiles.config.toml` へ stow する。
Codex は `~/.codex/config.toml` を読み込んだ後に profile の設定を重ね、
同じ設定項目には profile の値を使う。

> [!IMPORTANT]
> Codex は profile を自動で選択しない。stow 管理する設定値を反映するには、
> shell、script、エディタなどの起動方法ごとに `--profile dotfiles` を指定する。

### 必須 plugin 警告 hook

`--profile dotfiles` で起動すると、
必須 plugin 警告 hook が marketplace 内の plugin と Python・jq の不足を警告する。
profile を指定しない起動では、この警告 hook は動かない。

> [!NOTE]
> dotfiles 管理の `stow/fish/.config/fish/config.fish` には、`codex` の起動時に
> `--profile dotfiles` を付ける abbreviation を設定している。

## セットアップ順序

1. dotfiles を clone する
2. `stow -d stow -t ~ claude codex fish` で Claude Code、Codex、fish の設定を配置する
3. dotfiles のルートで次のコマンドを実行し、ユーザー共通 skill の symlink を作る

   ```bash
   /bin/sh scripts/setup-shared-skills.sh
   ```

4. dotfiles のルートで `codex plugin marketplace add .` を実行し、
   `codex plugin add codex-claude-rules@dotfiles` で rule 読み込み plugin をインストールする
5. `codex plugin list` で `codex-claude-rules@dotfiles` が有効なことを確認する
6. fish を起動し直す

> [!IMPORTANT]
> `codex --profile dotfiles` を起動し、`/hooks` で plugin の hook と
> 必須 plugin 警告 hook を信頼する。信頼後は新しいセッションを開始する。
> hook の定義が変わるまでは、再度信頼する必要はない。

## 確認

Codex に渡される project instructions は、次のコマンドで確認する。

```bash
codex --profile dotfiles -C /path/to/repository debug prompt-input
```

リポジトリルートと作業ディレクトリの `CLAUDE.md` が含まれ、
内容が末尾まで表示されることを確認する。
