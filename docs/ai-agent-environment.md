# Claude Code と Codex を両立するユーザー設定

この文書は、dotfiles における Claude Code と Codex のユーザー設定の管理方法を定める。

## Claude Code を基準とする管理方針

Claude Code の基本設定は、`claude/.claude/settings.json` で管理する。
ステータスラインは、`claude/.claude/statusline.sh` で管理する。
stow で `~/.claude` 配下へ配置し、Claude Code からそのまま読み込む。

Codex には、Claude Code 用の指示ファイルを読み込む設定と、Codex 固有の設定を加える。
Codex 固有の静的な設定項目は、`templates/codex/config.toml` で管理する。

Claude Code と Codex に共通する作業リポジトリの指示は、`CLAUDE.md` に置く。
Codex は、ユーザー設定の `project_doc_fallback_filenames = ["CLAUDE.md"]` により、
`AGENTS.md` がない階層で `CLAUDE.md` を読む。同じ階層に `AGENTS.md` を置くと
`CLAUDE.md` が読まれないため、Codex 専用の指示を追加する目的では使わない。

`.claude/rules` のうち、`paths` を持たない rule は常時読み込む指示として
Codex 側にも配置する。Codex は rule ディレクトリを instruction として読まないため、
配布方法は別途決める。`paths` を持つ rule は、Codex 用の path rule hook で読み込む。

作業リポジトリ固有の skill は `.claude/skills` を原本とし、
`.agents/skills` から同じディレクトリへの symlink を置く。
複数の作業リポジトリで使う skill は、両ホストの plugin として配布する。

Claude Code 用の agent 定義を Codex に読ませる対応は保留する。
現時点では、Codex は `.claude/agents` の定義を読み込まない。

## Codex の `config.toml` の管理

`~/.codex/config.toml` 全体は stow しない。このファイルには、Codex が更新する
hook trust hash と、端末ごとの project path が入るためだ。symlink すると、Codex が
実行中に更新した内容が dotfiles の working tree に書き込まれる。別の端末では使えない
絶対パスも追跡される。

GNU Stow はファイル単位で symlink を管理し、TOML の設定項目単位では管理できない。
`--adopt` も対象ファイル全体を stow package へ移す。
このため、dotfiles で追跡する設定項目だけを `templates/codex/config.toml` で管理する。

ローカルで管理対象の設定値を変更した場合は、`~/.codex/config.toml` と
`templates/codex/config.toml` に同じ名前で存在する設定項目の値だけを、
`templates/codex/config.toml` へコピーする。
hook trust hash、project trust 設定、model 設定は `templates/codex/config.toml` へ追加しない。

## セットアップ順序

1. dotfiles を clone する
2. `stow -t ~ claude` で Claude Code のユーザー設定を配置する
3. `templates/codex/config.toml` と `~/.codex/config.toml` をエディタで開く
4. `templates/codex/config.toml` にある各設定項目を、同名の設定項目として `~/.codex/config.toml` へ追加または更新する

`templates/codex/config.toml` にない `~/.codex/config.toml` の設定項目は変更しない。

## 確認

Codex に渡される project instructions は、次のコマンドで確認する。

```bash
codex --strict-config -C /path/to/repository debug prompt-input
```

リポジトリルートと作業ディレクトリの `CLAUDE.md` が含まれ、
末尾が途中で切れていなければ確認は完了だ。
