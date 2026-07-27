# herdr 運用メモ

ターミナル用の agent multiplexer。tmux からの移行先として使う。
ここは日常運用で必要になる要点だけを置く。設定実体は stow package `herdr/` にある。

## アップグレード

Homebrew 管理なので self-update 系は使えない。

- `brew upgrade herdr` で更新する。`herdr update`・preview チャンネル・live handoff (`--handoff`) はいずれも Homebrew インストールでは無効
- 更新後はサーバ再起動が必要。バイナリを上げても動いているサーバは旧バージョンのまま動き続ける (`herdr status` の `restart_needed` / `compatible` で確認できる)

## サーバ再起動で失われるもの・残るもの

再起動すると全 pane のプロセスが落ちる。実行中の `claude` プロセスも終了し、進行中のターンは失われる。ただし Claude Code の会話履歴はディスクに残るので、会話データ自体は消えない。

| 対象 | 再起動後 |
| --- | --- |
| pane のプロセス | 落ちる。復活しない |
| レイアウト (space / tab / pane・cwd・focus) | 復元される。pane は保存 cwd の素の shell で戻る |
| 直近の画面内容 (スクロールバック) | `pane_history = true` のときだけ復元。既定 off |
| 会話の自動再開 | Claude Code integration が入っているときだけ (下記) |

integration 無しでも各 pane の cwd で `claude --resume` を叩けば会話を拾い直せる。integration はこれを自動化するもの。

`pane_history` は画面に残ったトークン・シークレットを `session-history.json` に平文保存するため、既定 off のまま運用する。

## 会話の自動再開 (Claude Code integration)

`herdr integration install claude` で有効化する。現状は未導入。

- 効果: サーバ再起動後、herdr が対象 pane を `claude --resume <id>` で自動的に復帰させる
- 仕組み: Claude Code のセッション開始時に、その pane のセッション識別子を herdr の socket へ報告する hook を入れる。状態 (working / idle / blocked) の判定は従来どおり herdr の画面検出が担い、hook はセッション識別だけを提供する
- 導入すると `~/.claude/settings.json` に hook エントリが追加され、`~/.claude/hooks/herdr-agent-state.sh` が置かれる。settings.json は stow 管理下なので、変更が dotfiles に波及する点に注意 (コミット前の個人情報チェックを通す)
- `resume_agents_on_restore` は既定 true。integration が識別子を報告した pane だけが自動復帰の対象
- 導入直後の再起動には既に動いているセッションは間に合わない (hook はセッション開始時に報告するため)。次回起動分から自動復帰が効く

## popup (floating window)

tmux の `prefix + P` (display-popup) 相当。`prefix + f` に割り当てている (config は stow 管理)。

- session-modal な floating terminal を開き、中のコマンドが終了すると閉じる
- 0.7.4 以降の機能。更新直後にサーバを再起動していないと `popup という type は受け付けない` と出る
- `prefix + shift + p` は既定で `rename_pane` に割り当て済みのため避けている

## 現状できないこと

- agents サイドバーパネルの非表示: 設定が存在しない (0.7.5 時点)。仕切りのドラッグで最小化 (下限あり) までが限界
- spaces の任意グループ化: git worktree グループのみ。任意グループの階層は持てない

どちらも herdr 本体の実装依存で plugin 化もできない。plugin v1 は native な非ターミナル UI を持てず (公式ドキュメント "Runtime action registration and native non-terminal plugin UI are not part of plugin v1.")、公開されている拡張点は pane と workflow に限られる。fork して Rust を直すか、upstream の実装を待つ。後者は次節で追跡する。

## 追跡中の upstream 項目

未実装で、実装されたら `herdr/.config/herdr/config.toml` を変える予定のもの。
判定はリリースノートを意味で読む (後述の理由で番号照合・discussion 更新では判定できない)。

最終確認: v0.7.5 / 2026-07-27

| 欲しいもの | upstream | 実装されたらやること |
| --- | --- | --- |
| agents パネルの非表示 | Discussions #1554, #1247 | config に非表示設定を追加する (例 `[ui.sidebar.agents] enabled = false`、実際のキー名は実装を見る) |
| spaces のグループ化 | Discussion #801 | worktree group 以外の階層化設定が入れば config に反映する |

関連: Discussion #1907 は agents パネルの行を (spaces と同様に) グループ化する提案。
上記 2 件とは別物だが、パネルのグループ化という方向の動きとして観察対象に含める。

参考: popup は v0.7.4 で実装済み (#1125)。対象外。

### 確認手順

最新安定版のタグを最終確認バージョンと比べ、上がっていたらリリースノートを読む。

```bash
gh api repos/ogulcancelik/herdr/releases/latest --jq '.tag_name'   # prerelease を除外
```

- `gh release list` は使わない。安定版の直後に preview build が publish され、先頭に出て誤検知する
- リリースノートは discussion 番号を引かない (PR 番号どまり)。上記項目に該当する記述がないか意味で読む
- discussion の updatedAt は信号として弱い。3 件とも Ideas カテゴリで、Ideas だけで 500 件超あり無関係な更新で動く
- 該当実装を確認したら config を更新し、この節の「最終確認」行を新しいタグと日付に更新する
