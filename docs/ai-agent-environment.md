# Claude Code と Codex の作業環境

この文書は、Claude Code と Codex の設定や拡張を管理する場所と、セットアップ手順を定める。
両方のホストから、作業リポジトリの `CLAUDE.md` と cc-marketplace が配布する
plugin を利用できるようにする。
設定、拡張、作業リポジトリ固有の知識は更新理由が異なるため、管理先を分ける。

## ファイルと機能の管理先

- dotfiles では、`~/.claude` と `~/.codex` のユーザー設定、`status_line`、
  導入する CLI の一覧、symlink の配置方法、セットアップ手順を管理する
- cc-marketplace では、複数の作業リポジトリで使う skills、名前付き agents、hooks、
  実行スクリプト、既定設定、requirements、setup 手順を管理する
- 各作業リポジトリでは、業務知識と設計知識、ビルドコマンド、ディレクトリ別 rules、
  そのリポジトリだけで使う workflow を管理する

cc-marketplace の plugin 設計は、cc-marketplace の
`docs/cross-client-architecture.md` を参照する。

## 作業リポジトリの指示ファイル

Claude Code と Codex の両方が読む作業リポジトリの指示は、`CLAUDE.md` に置く。
Codex のユーザー設定では、`CLAUDE.md` を fallback filename に指定する。
Codex 専用の追加指示がなければ、`AGENTS.md` は作らない。

Codex が project instructions を読む上限は 64 KiB に設定する。既定の 32 KiB では、
リポジトリルートとサブディレクトリの `CLAUDE.md` が増えると、合計サイズが上限に達して
末尾を読み込めない可能性があるためだ。上限は無制限にしない。instructions が
64 KiB を超える場合は、指示の構成を見直す。

設定値は [`templates/codex/config.toml`](../templates/codex/config.toml) で管理する。

## Codex の `config.toml` の管理

`~/.codex/config.toml` 全体は stow しない。このファイルには、Codex が更新する hook の
trust hash と、端末ごとの project path が入るためだ。symlink すると、Codex が
実行中に更新した内容が dotfiles の working tree に書き込まれる。別の端末では使えない
絶対パスも追跡される。

静的な設定は `templates/codex/config.toml` で管理する。セットアップ時には、
必要な設定項目だけをローカルの `~/.codex/config.toml` へ反映する。
既存の hook state、project trust、model 設定は削除しない。

反映する静的設定は次のとおり。

- `CLAUDE.md` を fallback filename に指定する設定
- project instructions の上限を 64 KiB にする設定
- conversation recap を無効にする設定
- model、permission mode、context 残量、5 時間枠と週間枠の利用上限までの残量と
  リセット時刻、directory を表示する `status_line`

## Rules と skills の管理

Claude Code の path rules は、作業リポジトリの `.claude/rules/` で管理する。
Codex では、cc-marketplace に追加する Codex 専用 plugin `codex-path-rules` が、
同じ `.claude/rules/` 内の rule を読む。plugin が完成するまでは、Codex が
path rules を自動適用する前提で運用しない。

複数の作業リポジトリで使う skill は、cc-marketplace から配布する。
1 つの作業リポジトリだけで使う skill は、そのリポジトリ内で管理する。
名前付き agent 経由でのみ実行する処理は、通常の skill 一覧へ公開しない。

## セットアップ順序

1. dotfiles を clone する
2. README に記載された stow package を配置する
3. cc-marketplace を Claude Code へ登録する
4. 必要な plugin だけを Claude Code にインストールする
5. `templates/codex/config.toml` の静的設定を `~/.codex/config.toml` へ反映する
6. Codex で利用する plugin を、各 plugin の README に従って有効化する
7. setup が必要な plugin の requirements を確認する
8. plugin に同梱された setup skill を明示的に実行する

## 確認

Codex に渡される project instructions は、次のコマンドで確認する。

```bash
codex --strict-config -C /path/to/repository debug prompt-input
```

リポジトリルートと作業ディレクトリの `CLAUDE.md` が含まれ、
末尾が途中で切れていなければ確認は完了だ。
