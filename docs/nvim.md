# nvim 設定 (LazyVim)

LazyVim ベースの nvim 環境。プラグイン管理は lazy.nvim。

## ファイル構成

```
nvim/.config/nvim/
├── init.lua                 # lazy.nvim bootstrap + LazyVim 読み込み
├── lua/config/
│   ├── options.lua          # エディタ設定 (tabstop=4, conceallevel=0 等)
│   └── keymaps.lua          # カスタムキーマップ (gj/gk, wrap toggle)
└── lua/plugins/
    ├── diffview.lua         # diffview.nvim + ✓ マーク + bufferline 連携
    ├── bufferline.lua       # bufferline の auto_toggle 無効化
    ├── scope.lua            # scope.nvim (バッファを tabpage ごとにスコープ)
    └── claude-fzf.lua       # fzf-lua の Claude Code 連携
```

`lua/plugins/*.lua` は LazyVim が自動で読み込む。ファイルを追加/削除するだけでプラグインを管理できる。

## diff レビューワークフロー

AI にコード変更を頼んだ後、diff を確認してコメントを書き込む流れ。

1. `<Space>do` で diffview を開く (file tree + side-by-side diff)
2. file tree でファイルをナビゲート
3. 右ペイン (新しい側) で直接 `@agent ここを修正して` と書き込み・保存
4. `x` でレビュー済みファイルに ✓ マークを付ける
5. `<Space>dc` で diffview を閉じる
6. `<Space>gg` で lazygit を起動して staging / commit

### diffview と lazygit の使い分け

| 観点 | diffview | lazygit |
|---|---|---|
| 用途 | レビュー & 編集 | staging & commit |
| diff 表示 | side-by-side (右ペイン編集可) | side-by-side (delta, 読み取り専用) |

## プラグイン連携の仕組み

### bufferline + scope.nvim + diffview

vim にはバッファ (開いたファイル)、ウィンドウ (表示領域)、tabpage (レイアウト集合) の 3 レイヤーがある。LazyVim は bufferline.nvim でバッファを上部にタブ風に表示する。

diffview は専用の tabpage を作るが、bufferline はデフォルトで全 tabpage のバッファを表示するため、diffview 内に無関係なバッファタブが表示されてしまう。

3 つの設定で対処:

- scope.nvim: バッファの可視範囲を tabpage ごとに分離。diffview のバッファが通常タブに漏れない
- `auto_toggle_bufferline = false` (bufferline.lua): bufferline が `showtabline` を自動リセットするのを防ぐ
- diffview hooks (diffview.lua): `view_enter` で `showtabline = 0` (bufferline 非表示)、`view_leave` で元の値に復元

### ✓ マーク機能

diffview の file tree で `x` キーを押すとファイル/ディレクトリに ✓ を付けられる。レビュー進捗の目印。

技術的な仕組み:

- `x` キーで `_G._diffview_viewed` テーブルにパスを記録
- `nvim_buf_set_extmark` で行内に仮想テキスト ✓ を描画
- diffview がパネルを再描画すると extmark が消えるため、`nvim_buf_attach` の `on_lines` コールバックで変更を検知し、毎回 ✓ を付け直す
- `get_comp_on_line` API で各行が file/directory かを判定し、ヘッダー行には付けない
- diffview を閉じると `_G._diffview_viewed` がクリアされる

## キーバインド一覧

### LazyVim 標準

| キー | 機能 |
|---|---|
| `<Space>gg` | lazygit |
| `<Space>e` | ファイルツリー (neo-tree) |
| `<Space><Space>` | ファイル検索 |
| `<Space>/` | プロジェクト内 grep |
| `H` / `L` | バッファ切り替え |
| `<Space>bd` | バッファを閉じる |
| `<Space>bo` | 他のバッファをすべて閉じる |
| `<Space><Tab>]` / `[` | tabpage 切り替え |
| `gd` | 定義へジャンプ (LSP) |
| `K` | ホバードキュメント (LSP) |

### diffview カスタム

| キー | 場所 | 機能 |
|---|---|---|
| `<Space>do` | どこでも | diffview を開く |
| `<Space>dc` | どこでも | diffview を閉じる |
| `<Space>dh` | どこでも | 現在のファイルの履歴 |
| `<Space>dH` | どこでも | ブランチ全体の履歴 |
| `<Space>dr` | どこでも | 指定ブランチとの diff |
| `x` | file tree | ✓ マークをトグル |
| `q` | diffview 内 | diffview を閉じる |
| `<Tab>` / `<S-Tab>` | diffview 内 | 次/前のファイルの diff を表示 |

### カスタムキーマップ (keymaps.lua)

| キー | 機能 |
|---|---|
| `j` / `k` | 表示行で移動 (gj/gk) |
| `<ESC>l` | 折り返し無効 |
| `<ESC>h` | 折り返し有効 |

### Claude Code 連携 (claude-fzf.lua)

`.claude` ファイルで `@` を押すと fzf でファイルを選択し、パスが挿入される。
