# codex-claude-rules

対応 CodingAgent: `Codex only`

Claude Code 向けに管理している rule の本文を、Codex のコンテキストにも注入する plugin。
対象の rule は、`~/.claude/rules` と、起動ディレクトリの親階層・
操作対象ファイルまでの階層にある `.claude/rules` の Markdown ファイル。
元の rule ファイルをその場で読み、Codex 用の複製は作らない。

収集した rule 本文は hook 応答の `hookSpecificOutput.additionalContext` に入れ、
Codex の実行中のセッションに追加の指示として渡す。

## 探索と制約

- SessionStart は `~/.claude/rules` と、ファイルシステムのルートから
  起動ディレクトリまでの各階層の `.claude/rules` を探す。
  `paths` キーがない rule だけを渡し、
  `paths: []` は渡さない
- PreToolUse はツール入力から対象ファイルのパスを検出し、そのファイルまでの
  階層にある `.claude/rules` も探す。対象パスと `paths` が一致した rule の本文を渡す。
  project rule の `paths` は、その rule を含む `.claude` の親ディレクトリを
  基準に照合する。`~/.claude/rules` の
  `paths` は起動ディレクトリを基準にする
- 同じ rule ファイルの同じ本文はセッション内で重複して渡さない。
  圧縮後の SessionStart で記録を初期化し、`paths` のない rule を再送する。
  `paths` のある rule は、次に一致した PreToolUse で再送する。
  SessionEnd で記録を削除する
- 起動ディレクトリ外のファイルは、絶対パスで指定しても対象にしない。
  複雑な shell コマンドなどで対象パスを検出できなければ、該当 rule は渡さない。
  コマンド内の `cd` による移動先は推測せず、コマンド文字列からはパスを選ばない
- glob は現行 rule で使う `*`・`**` と、`?`・`{a,b}` を照合する。
  Claude Code が対応する `[]` 文字クラスは未対応なので、その形式の rule を
  追加する前に script を拡張する

hook 定義は `hooks/hooks.json`、実装は `scripts/codex-claude-rules`、
テストはリポジトリルートの `tests/plugin/codex_claude_rules/` に置く。
導入手順は
[Claude Code と Codex のユーザー設定](../../docs/ai-agent-environment.md) を参照。
