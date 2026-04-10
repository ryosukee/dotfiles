# nvim 設定 (LazyVim)

LazyVim ベースの nvim 環境。プラグイン管理は lazy.nvim。

## ファイル構成

```
nvim/.config/nvim/
├── init.lua                 # lazy.nvim bootstrap + LazyVim 読み込み
├── lua/config/
│   ├── options.lua          # エディタ設定 (tabstop=4, conceallevel=0, PUPPETEER_EXECUTABLE_PATH 等)
│   └── keymaps.lua          # カスタムキーマップ + コンテキストメニュー
└── lua/plugins/
    ├── diffview.lua         # diffview.nvim + ✓ マーク
    ├── bufferline.lua       # bufferline 無効化 (ネイティブ tab 表示)
    ├── scrollbar.lua        # nvim-scrollbar (gitsigns 連携)
    ├── snacks.lua           # 画像/mermaid プレビュー + dashboard + gitbrowse
    ├── blink-cmp.lua        # prose filetype で補完を無効化
    └── claude-fzf.lua       # fzf-lua の Claude Code 連携
```

`lua/plugins/*.lua` は LazyVim が自動で読み込む。ファイルを追加/削除するだけでプラグインを管理できる。

## tab 表示

bufferline.nvim は無効化し、neovim ネイティブの tab 表示を使う。`showtabline` のデフォルト値 (`1`: タブが 2 つ以上で表示) で動作。

## 画像/mermaid プレビュー

ghostty の kitty graphics protocol を利用して、nvim 内で画像や mermaid 図をフローティングウィンドウで表示する。snacks.nvim の image 機能を使用。

自動表示は OFF。キーバインドで必要な時だけ表示する。

### 前提

- ターミナル: ghostty (wezterm では画像表示不可)
- mermaid-cli (`mmdc`): brew でインストール、システム Chrome を使用 (`PUPPETEER_EXECUTABLE_PATH` を options.lua で設定)

### 操作 (`<Space>ip` でプレビュー表示後、`Ctrl+w w` でフォーカス)

| キー | 機能 |
|---|---|
| `hjkl` / 矢印 | フローティング移動 |
| `+` / `-` | 縦横同時リサイズ |
| `Shift+矢印` | 幅・高さ個別リサイズ |
| `f` | フルスクリーントグル |
| `o` | macOS Preview.app で開く |
| `q` | 閉じる |

### 制約

- 画像の元ピクセルサイズ (セル換算) が表示サイズの上限。元サイズ以上には拡大できない
- mermaid は `mmdc` の `-s` (scale) で元画像を大きくレンダリングすることで対応 (現在 4x)
- 複雑な mermaid 図はターミナルのセル数制約で読みづらい。`o` で macOS Preview に開いてズームする方が実用的

## コンテキストメニュー

`<Space>a` でカーソル位置にコンパクトなドロップダウンメニューを表示。右側にツールチップ。nui.nvim で実装。

### 常時表示される項目

| 項目 | 機能 |
|---|---|
| Go to Definition | LSP 定義ジャンプ |
| Find References | LSP 参照一覧 |
| Rename | LSP リネーム |
| Code Action | LSP アクション |
| Open in GitHub | ファイル+行をブラウザで開く |
| Open Permalink | コミット固定 URL |
| Copy GitHub URL | Permalink をクリップボードにコピー |

### 動的項目 (カーソル位置に画像/mermaid がある場合)

| 項目 | 機能 |
|---|---|
| Preview here | フローティングプレビュー |
| Open in Preview.app | macOS Preview で開く |

## diff レビューワークフロー

1. `<Space>do` で diffview を開く (file tree + side-by-side diff)
2. file tree でファイルをナビゲート
3. 右ペイン (新しい側) で直接編集・保存
4. `x` でレビュー済みファイルに ✓ マーク
5. `<Space>dc` で diffview を閉じる

### ✓ マーク機能

diffview の file tree で `x` キーを押すとファイル/ディレクトリに ✓ を付けられる。

- `_G._diffview_viewed` テーブルにパスを記録
- `nvim_buf_set_extmark` で仮想テキスト ✓ を描画
- パネル再描画時に `on_lines` コールバックで ✓ を付け直す
- diffview を閉じると `_G._diffview_viewed` がクリアされる

## キーバインド一覧

### カスタムキーマップ

| キー | 機能 |
|---|---|
| `j` / `k` | 表示行で移動 (gj/gk) |
| `<ESC>l` / `<ESC>h` | 折り返し無効/有効 |
| `s` | ネイティブの s を復元 (flash.nvim を上書き) |
| `<Space>a` | コンテキストメニュー |
| `<Space>ip` | 画像/mermaid プレビュー |
| `<Space>go` | GitHub で開く |
| `<Space>gO` | GitHub permalink で開く |

### diffview

| キー | 場所 | 機能 |
|---|---|---|
| `<Space>do` | どこでも | diffview を開く |
| `<Space>dc` | どこでも | diffview を閉じる |
| `<Space>dh` | どこでも | 現在のファイルの履歴 |
| `<Space>dH` | どこでも | ブランチ全体の履歴 |
| `<Space>dr` | どこでも | 指定ブランチとの diff |
| `x` | file tree | ✓ マークをトグル |
| `q` | diffview 内 | diffview を閉じる |

### ダッシュボード

| キー | 機能 |
|---|---|
| `f` | Find File |
| `n` | New File |
| `/` | Find Text (grep) |
| `r` | Recent Files |
| `c` | Config |
| `s` | Restore Session |
| `l` | Lazy (plugin manager) |
| `q` | Quit |
