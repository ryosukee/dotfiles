# よく差分が出るファイルの方針

symlink 経由でツールが自動で書き込み、繰り返し差分が出るファイルと、その差分の扱いを定める。
ここに無いファイルと、ここに書いた書き込み元以外の変更は、差分を読んで個別に仕分ける。

## stow/claude/.claude/settings.json

書き込み元は Claude Code と Orca。

- Claude Code の UI・`/plugin`・`/config` で変わった設定（plugin の有効化、model・effort、attribution など）は、
  内容を確かめて `chore(claude): ...` で commit する
- Orca が入れる hook の `command` は、Orca の更新に合わせて Orca が書き換える。Orca の書いた値をそのまま採り、手で直さない
- 端末固有の値（URL、絶対パス、環境変数）は、stow 管理外の `~/.claude/settings.machine.json` へ移す。
  移し方は [ユーザー設定の管理方針](../../../../docs/ai-agent-environment.md#claude-code-の共有設定と端末固有設定) に従う

## stow/nvim/.config/nvim/lazy-lock.json

書き込み元は lazy.nvim（`:Lazy update`・`:Lazy sync`）。

- plugin の commit hash だけが変わった差分は、単独で `chore(nvim): update lazy-lock` として commit する
- plugin の追加・削除による差分は、`lua/plugins/` の設定変更と同じ commit に入れる

## Docker Desktop が書き込むシェルの初期化ファイル

対象は `stow/shell/.bash_profile`・`stow/shell/.profile`・`stow/shell/.zprofile`・`stow/fish/.config/fish/config.fish`。
書き込み元は Docker Desktop で、先頭の `# The following lines were added by Docker Desktop` から
`# End of Docker Desktop section.` までのブロックに書き込む。

- commit 済みのブロックは、PATH を `$HOME/.docker/bin` で書いている。
  Docker Desktop はこれを絶対パス（`/Users/<name>/.docker/bin`）に書き戻す。
  書き戻しだけの差分は破棄する
- ブロックに新しい行が増えたときは、絶対パスを `$HOME` に置き換えて commit する

## stow/codex/.codex/dotfiles.config.toml

stow 管理外の `~/.codex/config.toml` と合わせて仕分ける。手順は [Codex の 2 つの設定ファイル](./codex-config.md) に従う。
