# Claude Code と Codex を両立するユーザー設定

この文書は、Claude Code の設定を基準として、dotfiles で管理するユーザー設定を Claude Code と Codex の両方へ反映する方法を定める。
新しい端末へ設定を反映するときや、両ツールの設定を変更するときに使う。

## Claude Code を基準とする管理方針

Claude Code の基本設定は、`claude/.claude/settings.json` で管理する。
ステータスラインは、`claude/.claude/statusline.sh` で管理する。
stow で `~/.claude` 配下へ配置し、Claude Code からそのまま読み込む。

Codex には、Claude Code 用の指示ファイルを読み込む設定と、Codex 固有の設定を加える。
Codex 固有の静的な設定項目は、`templates/codex/config.toml` で管理する。
実行中に更新される値を保持するため、`~/.codex/config.toml` 全体は dotfiles で置き換えない。

## Codex が読み込む指示ファイル

Codex のユーザー設定では、`AGENTS.md` がない場合に読む fallback filename として
`CLAUDE.md` を指定する。Codex 専用の追加指示がなければ、`AGENTS.md` は作らない。

Codex が `CLAUDE.md` などから読み込む指示（project instructions）の上限は、
64 KiB に設定する。既定の 32 KiB では、
リポジトリルートとサブディレクトリの `CLAUDE.md` が増えると、合計サイズが上限に達して
末尾を読み込めない可能性があるためだ。上限は無制限にしない。project instructions が
64 KiB を超える場合は、指示の構成を見直す。

設定値は [`templates/codex/config.toml`](../templates/codex/config.toml) で管理する。

## Codex の `config.toml` の管理

`~/.codex/config.toml` 全体は stow しない。このファイルには、Codex が更新する
hook trust hash と、端末ごとの project path が入るためだ。symlink すると、Codex が
実行中に更新した内容が dotfiles の working tree に書き込まれる。別の端末では使えない
絶対パスも追跡される。

dotfiles で追跡する設定項目は `templates/codex/config.toml` で管理する。セットアップ時には、
必要な設定項目だけをローカルの `~/.codex/config.toml` へ反映する。
既存の hook trust hash、project trust 設定、model 設定は削除しない。

## セットアップ順序

1. dotfiles を clone する
2. `stow -t ~ claude` で Claude Code のユーザー設定を配置する
3. `templates/codex/config.toml` の設定項目を `~/.codex/config.toml` へ反映する

## 確認

Codex に渡される project instructions は、次のコマンドで確認する。

```bash
codex --strict-config -C /path/to/repository debug prompt-input
```

リポジトリルートと作業ディレクトリの `CLAUDE.md` が含まれ、
末尾が途中で切れていなければ確認は完了だ。
