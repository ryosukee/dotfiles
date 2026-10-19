---
name: commit-symlinked-changes
description: >-
  dotfiles の repo 内のファイルが symlink 経由でツールに書き換えられ、手元に差分（変更・未追跡ファイル）が出ているとき、
  差分を書き込み元ごとに仕分け、ユーザーの承認を得てから整理して commit する。
  「dotfiles の差分をコミットして」「手元の変更を整理して」「stow の差分を見て」と言われたとき、
  または symlink 経由で書き換わったファイルを含む commit を作る前に必ず使う。
user-invocable: true
---

# symlink 経由で書き換わったファイルの差分を仕分けて commit する

stow などで repo の外から symlink を張ったファイルは、ツールが symlink 越しに repo 内の実体を書き換える。
そのため、ツールの自動書き込みと手での編集が同じ差分に混ざる。
この skill はその差分を項目ごとに仕分け、ユーザーの承認を得てから整理して commit する。

対象は、repo 内で手元に差分があるファイルのうち、symlink 経由でツールが書き換えたもの。
stow/ 配下に限らない。セッションや人が repo 内で直接編集した変更は対象外とし、stage せずにそのまま残す。

## 1. 差分を集める

次のスクリプトを実行し、repo 全体の差分のあるファイルと、個人情報らしい追加行を一覧にする。
`<repo>` は dotfiles のルートの絶対パスに置き換える。

```bash
/bin/sh <repo>/.claude/skills/commit-symlinked-changes/scripts/scan-changes.sh
```

## 2. ファイルごとに書き込み元と扱いを決める

ファイルごとに `git -C <repo> diff -- <file>` を絞り込まずに全部読み、各変更を誰が書いたかを特定する。
まず、symlink 経由でツールが書き換えた変更か、repo 内で直接編集した変更かを見分ける。
今のセッションで編集した変更は直接編集として扱う。どちらか見分けられない変更は、ユーザーに問う。
以降の仕分けは、symlink 経由でツールが書き換えた変更だけに行う。

既知のファイルは [よく差分が出るファイルの方針](./references/known-writers.md) に従う。
`stow/codex/.codex/dotfiles.config.toml` に差分があるときは、
[Codex の 2 つの設定ファイル](./references/codex-config.md) の手順で、stow 管理外の `~/.codex/config.toml` も合わせて棚卸しする。

変更ごとに、次のどれかに仕分ける。

- そのまま commit する: 端末をまたいで共有したい変更
- 汎用化して commit する: 共有したいが端末固有の値を含む変更。例: 絶対パスを `$HOME` に置き換える
- 破棄する: commit 済みの内容に戻す変更。ツールが commit 済みの汎用化を書き戻した変更など
- repo の管理外へ移す: 端末固有の値と、ツールが保存する状態。移し先はツールごとの端末固有ファイル
- 判断が要る: 上のどれとも決められない変更

## 3. 仕分けの案を示して承認を得る

ファイルと変更ごとに、書き込み元・仕分け・理由をユーザーに示す。
commit の分け方とメッセージも合わせて示す。
commit は書き込み先のツールごとに分け（stow/ 配下は stow の package ごと）、メッセージは `git log` の既存の形式（例: `chore(nvim): update lazy-lock`）に合わせる。

承認を得るまで、ファイルの編集・移動・破棄と commit をしない。
判断が要る変更は 1 件ずつ問う。

## 4. 承認された仕分けを適用する

- 移す変更は、移し先に書き込んでから元のファイルから消す。移し先に同じ項目があれば、今効いている値を採る
- 破棄は、1 回の呼び出しに `git -C <repo> restore -- <file>` だけを置いて実行する。
  ファイルの一部だけを破棄するときは、該当箇所を commit 済みの内容へ書き戻す
- 適用した後に差分が出直すファイルがある。書き込み元のツールが動いている間に適用したときは、手順 1 からやり直す

## 5. 検算してから commit する

1. ファイルごとに `git -C <repo> diff -- <file>` を読み、承認した変更だけが残っていることを確かめる
2. 移した項目は、移す前後で件数が合っていることを確かめる
3. 編集したファイルの構文を検査する。JSON は `jq empty <file>`、TOML は `python3 -c 'import sys, tomllib; tomllib.load(open(sys.argv[1], "rb"))' <file>`、
   sh は `sh -n <file>`、fish は `fish -n <file>`
4. commit 単位ごとに、パスを明示して `git -C <repo> add -- <file>...` で stage する。`git add -A` は使わない
5. `--staged` を付けて手順 1 のスクリプトを実行し、個人情報らしい追加行が無いことを確かめる。
   出たら、その行を汎用化するか、repo の管理外へ移すかをユーザーに問う
6. commit する。push はユーザーが求めたときだけ行う
