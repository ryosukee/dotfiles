# tmux 設定

tmux のキーバインドと、自前 session launcher の仕様。

## ファイル構成

```text
tmux/
├── .tmux.conf                              # エントリポイント (bindings, plugins, aliases)
└── .config/tmux/
    ├── session-launcher.sh                 # prefix + S で呼ばれる launcher 本体
    ├── move-window-to-session.sh           # window を新規 session に移動 (popup prompt)
    ├── move-window-to-other-session.sh     # window を既存 session に移動 + follow
    ├── treemux_init.lua                    # treemux sidebar 用 nvim init (カスタム版)
    └── plugins/tmux-which-key/config.yaml  # which-key メニュー定義
```

## キーバインド

prefix は tmux デフォルト (`Ctrl+B`)。

| キー | 機能 |
| --- | --- |
| `prefix + S` | session launcher を開く (自前、後述) |
| `prefix + Tab` | treemux sidebar を toggle (フォーカスなし) |
| `prefix + Backspace` | treemux sidebar を toggle + フォーカス移動 |
| `prefix + P` | 作業用 popup ターミナル (`popup` session) |

## Plugin

`.tmux.conf` で tpm 経由で入れているもの:

- `tmux-plugins/tpm` — plugin manager
- `niksingh710/minimal-tmux-status` — ステータスライン
- `alexwforsythe/tmux-which-key` — which-key 風ヒント
- `kiyoon/treemux` — Neovim の Neo-Tree を tmux sidebar として表示 (後述)

## treemux

[kiyoon/treemux][treemux] は Neovim の Neo-Tree を tmux の sidebar pane として動かす plugin。
ファイルツリーを tmux レベルで常駐させたい時に使う。

[treemux]: https://github.com/kiyoon/treemux

### セットアップ

`.tmux.conf` での設定:

```tmux
set -g @treemux-tree-client 'neo-tree'
set -g @treemux-python-command '~/.local/share/mise/shims/python3'
set -g @treemux-tree-nvim-init-file '~/.config/tmux/treemux_init.lua'
set -g @plugin 'kiyoon/treemux'
```

`@treemux-tree-nvim-init-file` はプラグインのデフォルトをコピーしたカスタム版。
元: `~/.tmux/plugins/treemux/configs/treemux_init.lua`。
`tpm update` で上書きされないようにするため dotfiles 側で管理する。
カスタマイズ箇所はファイル内の `[CUSTOM]` コメントで明示。

python バックエンドに `pynvim` が必要。mise 管理の python に入れる:

```bash
mise x python -- python -m pip install pynvim
```

mise の python を upgrade したら再インストール必要。
`@treemux-python-command` は mise shim を指しているので version 追従する。

tpm plugin インストール: `prefix + I` または `~/.tmux/plugins/tpm/bin/install_plugins`。

### キー

| キー | 動作 |
| --- | --- |
| `prefix + Tab` | sidebar を toggle (カーソルは移動しない) |
| `prefix + Backspace` | sidebar を toggle + フォーカス移動 |

Neo-Tree 内では `l` / `Enter` でファイルを main pane に開く。
既存の vim がある場合は新タブで開き、vim 終了時に pane が自動で閉じる (`exec nvim` による)。

## session launcher (`prefix + S`)

tmux 組み込みの `choose-tree` にインスパイアされた自前のランチャ。
組み込みとの違いは、**常にフル幅の左右分割**で表示できること、
**fzf のモーダルなキー操作**で navigation / search を切り替えられること。

### UI

```text
window>
  0  ├─ 0: idp-main (nvim)              <preview area>
     ├─ 1: Python (Python)
     └─ 4: blueprint-bot (2.1.97)
  59 ├─ 0: cc-market (2.1.96)
     ├─ 1: dotfiles (fish)
     └─ 3: nvim (nvim)
```

- session ごとに window を `├─` / `└─` でツリー表示
- session 名は先頭 window 行に inline、2 行目以降はスペースでパディング
- 並び順は tmux デフォルト (session 名の昇順 + session 内 window_index 昇順)。
  session 名に `0-`, `1-` のような prefix を付けて任意の順に制御する
- 右側に選択中 window のライブプレビュー (ANSI 色保持、CJK 幅対応)
- 複数 pane の window は pane ごとにヘッダ付きで縦連結表示

### 操作

| キー | 動作 |
| --- | --- |
| `j` / `k` / `↓` / `↑` | navigation |
| `Enter` | 選択した window にジャンプ (`switch-client` + `select-window`) |
| `/` | search モードに切替 (j/k が入力文字になり fuzzy filter が有効化) |
| `q` / `Esc` | 元の session に戻る (`switch-client -l`) |

起動時は `--disabled` で search 無効、`j`/`k` が navigation に bind されている。
`/` を押すと search モードに入り、その呼び出し中は j/k が入力文字として扱われる。
次回起動時はまた navigation モードで開く。

### move/send モード

launcher は window を別 session に移動する機能を持つ。
which-key の Window メニュー (`w`) から呼び出す。

| which-key キー | モード | プロンプト | Enter の動作 |
| --- | --- | --- | --- |
| `w` → `s` | 新規 session | popup で名前入力 | 新規 session 作成 + window 移動 + 切替 |
| `w` → `m` | move | `move>` | 選択 session に window 移動 + 切替 |
| `w` → `M` | send | `send>` | 選択 session に window 移動 + 元に戻る |

move/send モードでは launcher session を毎回再作成する。
環境変数 (`_LAUNCHER_MODE`, `_LAUNCHER_SRC_WIN`) でモードとソース window を伝達する。
switch モード (`prefix + S`) では既存の launcher session を再利用して高速起動する。

最後の 1 window を移動した場合、元 session は tmux に破棄される。
send モードではこの場合自動で移動先に切り替わる。

### 仕組み

専用の `_launcher` という session を初回 `prefix + S` 時に生成し、その中で fzf を `while true` ループで常駐させる。
以降の `prefix + S` は `switch-client -t _launcher` するだけで、fzf はスタンバイ状態なので即座に UI が出る。

```text
[通常の session]          [_launcher session]
                             fzf (常駐ループ)
      ↓ prefix + S              │
      switch-client ───────────→│
                                │ j/k で navigation
      ←─────────── Enter ───────│
      switch-client +           │
      select-window             │
      ←─────────── q/Esc ───────│
      switch-client -l          │
```

fzf のループ本体は `session-launcher.sh --loop` で走り、各反復で:

1. `--list` でツリー形式の window 一覧を生成
2. list 幅を計算し preview 幅を決定
3. per-iteration の cache ディレクトリを用意
4. fzf を起動してユーザ操作を待つ
5. 選択結果に応じて `switch-client` / `select-window` を発火

preview は fzf の `--preview` 経由で
`bash session-launcher.sh --preview {1}` (環境変数 `LAUNCHER_CACHE_DIR` 付き) を呼ぶ。
初回アクセス時に `tmux capture-pane -eNp` で pane 内容を取得・整形・キャッシュに保存し、
2 回目以降は cat だけで返す lazy cache 方式。

### preview の整形

`_truncate_ansi` 関数が 1 段の perl プロセスで以下を処理する:

1. underline 系 SGR の除去: fzf の `--ansi` パーサが解釈できない curly underline (`4:3m`)、
   複合 SGR 内の underline パラメータ (`;4;` / `;4:3;`)、underline color (`58;...`) などを除去
2. bg carry: 行内に bg SGR が無い場合、前行の bg を prepend して nvim の塗り残しセルを埋める
3. 幅 truncate: East Asian Wide 判定付きの `cwidth` 関数で CJK を 2 セルとして数え、
   `FZF_PREVIEW_COLUMNS` + 安全マージン 4 で truncate
4. full attribute reset: 各行の先頭と末尾に `\e[22m\e[23m\e[24m...` の個別属性リセットを挿入
5. 幅 pad: 可視幅に満たない分を default bg のスペースで埋めて preview セルを物理的に上書き

さらに `_pad_output` が `FZF_PREVIEW_LINES` まで空行 (full-width space) で埋めて、
preview pane の下部まで完全に上書きする。

### ターミナル側のセル状態残り対策

tmux は client への出力を差分描画で最適化するため、content が変わらないセルは再送しない。
過去の preview で設定された SGR 状態がターミナル側のセルに残っていると、
空白を書いても残骸として見える (特に curly underline の点線)。

これを防ぐため、各 preview 生成の末尾で `tmux run-shell -b` 経由で非同期に
`sleep 0.05 && tmux refresh-client -t <client>` を発火する。
server プロセス側で実行されるため fzf の kill に影響されず、
preview script 自体は即 exit できて navigation の体感遅延がない。

### 既知の制約

- tmux の `capture-pane` は pane グリッドを捕捉するだけなので、
  **nvim の split バッファの背景色を完全に再現できない**。
  `-N` フラグでトレイリング空白は保持するが、nvim が明示的に塗っていないセルは default bg になる
- session を切り替える際は画面全体が launcher から target に遷移する。
  choose-tree と同じく「sidebar として常駐させながら他の pane を操作する」ことはできない (tmux の session モデル上の制約)
