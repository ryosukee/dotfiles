# ユーザー共通の指示

セッションを開始したら、`codex-path-rules always "$PWD"` を実行し、出力された rule を常時適用する。
コマンドが見つからない場合は環境を変更せず、`setup-codex-path-rules` skill の実行をユーザーへ案内する。
