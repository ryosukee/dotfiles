# Claude Code / Codex 作業環境

Claude Code と Codex から、同じ作業リポジトリの知識と再利用可能な拡張を使う。
設定、拡張、作業リポジトリ固有の知識は、更新理由が異なるため管理先を分ける。

## 管理対象

- dotfiles: `~/.claude` と `~/.codex` のユーザー設定、statusline、
  導入する CLI の一覧、symlink とセットアップ手順
- cc-marketplace: 複数の作業リポジトリで使う skills、名前付き agents、hooks、
  実行スクリプト、既定設定、requirements と setup 手順
- 作業リポジトリ: 業務・設計知識、ビルドコマンド、ディレクトリ別 rules、
  そのリポジトリだけで使う workflow

cc-marketplace の plugin 設計は、同リポジトリの
`docs/cross-client-architecture.md` を参照する。

## Project instructions

作業リポジトリの共通知識は `CLAUDE.md` に置く。Codex のユーザー設定で
`CLAUDE.md` を fallback filename にするため、Codex 専用の追加指示が無ければ
`AGENTS.md` は作らない。

Codex がproject instructionsを読む上限は64 KiBにする。既定の32 KiBでは、
rootとサブディレクトリの `CLAUDE.md` が増えたときに末尾が読み込まれない余地が
小さいためである。上限を無制限にせず、instructionsが増え続けた場合は構成自体を
見直す。

設定値は [`templates/codex/config.toml`](../templates/codex/config.toml) を正とする。

## Codex config の管理

`~/.codex/config.toml` 全体はstowしない。このファイルには、Codexが更新するhookの
trust hashと、端末ごとのproject pathが入るためである。symlinkすると実行中の更新が
dotfilesのworking treeへ書き込まれ、別端末へ配れない絶対パスも追跡される。

静的な設定はtemplateで管理し、セットアップ時にローカルの
`~/.codex/config.toml` へ項目単位で反映する。既存のhook state、project trust、
model設定は削除しない。

反映する静的設定は次のとおり。

- `CLAUDE.md` のfallback
- project instructionsの64 KiB上限
- conversation recapの無効化
- model、permission mode、context残量、5時間・週間usage limit、directoryを表示するstatusline

## Rules と skills

Claude Code のpath rulesは、作業リポジトリの `.claude/rules/` を正とする。
Codexでは、cc-marketplaceに追加するCodex専用path-rules pluginから同じruleを読む。
pluginが完成するまではCodexでpath rulesが自動適用されるとは扱わない。

複数リポジトリで使うskillはcc-marketplaceから配布する。作業リポジトリだけで使う
skillは、そのリポジトリ内で管理する。名前付きagentだけに実行させる処理は、通常の
skill一覧へ公開しない。

## セットアップ順序

1. dotfilesをcloneし、READMEに記載されたstow packageを配置する
2. cc-marketplaceをClaude Codeへ登録し、必要なpluginだけをinstallする
3. `templates/codex/config.toml` の静的設定を `~/.codex/config.toml` へ反映する
4. Codexで利用するpluginを、各pluginのREADMEに従って有効化する
5. setup skillを必要とするpluginは、requirementsを確認して明示的にsetupする

## 確認

Codexから見えるinstructionsは次で確認する。

```bash
codex --strict-config -C /path/to/repository debug prompt-input
```

rootと作業ディレクトリの `CLAUDE.md` が入り、末尾が途中で切れていないことを確認する。
