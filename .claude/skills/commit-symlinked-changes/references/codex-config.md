# Codex の 2 つの設定ファイル

`stow/codex/.codex/dotfiles.config.toml` に差分があるときに、Codex の 2 つの設定ファイルを棚卸しして仕分ける手順を定める。

## 2 つのファイルと書き込み元

Codex のユーザー設定は 2 つのファイルに分かれている。git で管理して差分を追えるのは `dotfiles.config.toml` だけ。

| ファイル | 配置 | git 管理 |
| --- | --- | --- |
| `~/.codex/config.toml` | 端末ごとの実ファイル | しない |
| `~/.codex/dotfiles.config.toml` | `stow/codex/.codex/dotfiles.config.toml` への symlink | する |

※ 表 1 Codex のユーザー設定ファイル

Codex は `~/.codex/config.toml` を読んだ後に `--profile dotfiles` の内容を重ねる。
table は両方の中身が合わさり、同じキーには `dotfiles.config.toml` の値が効く。

どちらのファイルにも Codex が自動で書き込む。書き込み先は、ユーザーの意図ではなく操作の種類で決まる。

- `--profile dotfiles` で起動した Codex は、hook の信頼（`[hooks.state.*]`）、project の trust（`[projects.*]`）、
  `/model` で選んだ `model`、TUI の表示状態を `dotfiles.config.toml` に書き込む
- `codex plugin add`・`codex plugin marketplace add`・`codex mcp add` は、
  `--profile dotfiles` の有無にかかわらず `~/.codex/config.toml` に書き込む
- Codex アプリの設定画面からの変更（`[desktop]` など）は `~/.codex/config.toml` に入る

そのため、共有したい設定が `~/.codex/config.toml` に入り、端末固有の状態が `dotfiles.config.toml` に入る。
`~/.codex/config.toml` は git の差分に現れないので、`dotfiles.config.toml` の差分だけを見ても、共有したい設定の取りこぼしに気づけない。

## 両方のファイルを棚卸しする

1. `dotfiles.config.toml` は差分を、`~/.codex/config.toml` は中身の全体を項目ごとに読む
2. 各項目を、下の基準で書くべきファイルに仕分ける。どちらとも決められない項目は「判断が要る」とする
3. `dotfiles.config.toml` に既にある値を Codex が書き換えた項目（`/model` で変わった `model` など）は、
   共有の設定として採るかを「判断が要る」とする
4. `[hooks.state.*]` の key が今の hook の定義と対応しているかを確かめる。
   対応する hook が無い key は、どちらのファイルにも移さず消す案にする

`[hooks.state.*]` の key は `<定義元>:<イベント>:<グループの番号>:<グループ内の hook の番号>` の形で、番号は 0 から数える。
定義元は、hook を定義したファイルの絶対パスか、`plugin名@marketplace名:plugin 内のファイル` になる。
定義元のファイルに、そのイベントのその番号のグループと hook が無ければ、key は対応していない。
hook を定義したファイルの構成が変わると（グループが減るなど）、古い key が残る。

| 書くファイル | 項目 |
| --- | --- |
| `dotfiles.config.toml` | 端末をまたいで共有したい静的な設定。`model`・`personality` などの既定値、hook の定義、`[tui]` の表示項目 |
| `~/.codex/config.toml` | 端末固有の値と、Codex が保存する状態。`[hooks.state.*]`、`[projects.*]`、`[marketplaces.*]`、`[plugins.*]`、ChatGPT アプリが書く `[mcp_servers.node_repl]`、`[desktop]`、`tui.model_availability_nux` と `tui.screen_reader_detection_done`、`shell_environment_policy` |

※ 表 2 項目を書くファイルの基準

## 項目を移す

- 移す先に同じキーがあれば、今効いている値を採る。両方のファイルにあるキーは `dotfiles.config.toml` の値が効いている
- `~/.codex/config.toml` は git で元に戻せない。編集する前にコピーを取り、仕分けを終えて Codex の動作を確かめるまで消さない
- `[hooks.state.*]` を移したら、次に起動した Codex の `/hooks` で信頼のし直しを求められないことをユーザーに確かめてもらう
