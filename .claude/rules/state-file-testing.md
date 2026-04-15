# 永続 state ファイルを書き換えるスクリプトのテスト

dotfiles 内には `claude/.claude/statusline.sh` のように、実行のたびに
永続ファイルを更新するスクリプトがある。書き込み先の例:

- `~/.local/state/claude-status/weekly-snapshot.json` (statusline の週間使用量履歴)
- `/tmp/claude-status/{session_id}.json` (外部ツール連携用 export)
- `/tmp/claude-code-latest-version` (バージョンキャッシュ)

これらは **user の実データを保持している**。合成 JSON を流して
テストすると本番 state が汚染される。特に user のバグ調査中に
差し込むと実データと混ざって原因究明が困難になる。

## 必ず次のどれかを選ぶ

1. **Sandbox**: state dir を env 変数で差し替える

    ```bash
    XDG_STATE_HOME=$(mktemp -d) bash claude/.claude/statusline.sh
    ```

    `/tmp/` 固定パスに書くスクリプトは sandbox 化できないので 2 か 3 を使う。

2. **Dry-run**: スクリプトの書き込み処理を事前に読んで、影響ファイルを
   列挙。stdout 取得のみで済むか確認する。特に `mv`, `jq ... > file`,
   `echo ... > file` を grep で洗う

3. **Backup-and-restore**: 書き込み先を事前に退避

    ```bash
    cp ~/.local/state/claude-status/weekly-snapshot.json{,.bak}
    # test
    mv ~/.local/state/claude-status/weekly-snapshot.json{.bak,}
    ```

## 特に要注意

- **user のバグ調査中** に合成 JSON を流すとき → sandbox 必須。
  本番 state を書き換えると「私が汚したのか、元からなのか」が
  切り分け不能になる
- **原因究明の最中** はテスト実行を最小化。事実確認 (現状 state
  読み取り、コード読み) を先にやる
- **Instant modification の記録**: 本番 state を書き換えた場合は
  操作を記録し、後で user に報告できるようにする (user から
  「過去にインスタントに実行した処理を思い返して」と要求される
  ケースがある)
