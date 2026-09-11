# Claude Code と Codex のユーザー設定

この文書は、dotfiles で管理する Claude Code と Codex のユーザー設定と、
その設定をローカル環境に反映して確認する手順を定める。

## dotfiles で管理する設定

dotfiles では、次のファイルと手順を管理する。

- `~/.claude` と `~/.codex` に配置するユーザー設定
- 導入する CLI を記載した Brewfile
- stow による symlink の配置手順
- Codex のステータスライン (`status_line`) の表示項目

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

反映する静的設定は次のとおり。

- `CLAUDE.md` を fallback filename に指定する設定
- project instructions の上限を 64 KiB にする設定
- conversation recap (`auto_recap`) を無効にする設定
- model、permission mode、context 残量を表示する `status_line`
- 5 時間枠と週間枠の利用可能な残量とリセット時刻を表示する `status_line`
- 現在の directory を表示する `status_line`

## セットアップ順序

1. dotfiles を clone する
2. README に記載された stow package を配置する
3. `templates/codex/config.toml` の設定項目を `~/.codex/config.toml` へ反映する

## 確認

Codex に渡される project instructions は、次のコマンドで確認する。

```bash
codex --strict-config -C /path/to/repository debug prompt-input
```

リポジトリルートと作業ディレクトリの `CLAUDE.md` が含まれ、
末尾が途中で切れていなければ確認は完了だ。
