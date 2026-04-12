# nvim 設定 (LazyVim)

LazyVim ベースの nvim 環境。プラグイン管理は lazy.nvim。

## ファイル構成

```
nvim/.config/nvim/
├── init.lua                 # lazy.nvim bootstrap + LazyVim 読み込み
├── lazyvim.json             # LazyVim extras (lang.markdown 有効化)
├── lua/config/
│   ├── options.lua          # エディタ設定 (tabstop=4, conceallevel=0, PUPPETEER_EXECUTABLE_PATH 等)
│   ├── keymaps.lua          # カスタムキーマップ + コンテキストメニュー
│   ├── autocmds.lua         # markdown の format on save 無効化等
│   ├── ask_dotfiles.lua     # ask-dotfiles 用フロート UI
│   └── markdown_preview.lua # markdown 要素の popup 描画 (table 等)
└── lua/plugins/
    ├── diffview.lua         # diffview.nvim + ✓ マーク
    ├── bufferline.lua       # bufferline 無効化 (ネイティブ tab 表示)
    ├── scrollbar.lua        # nvim-scrollbar (gitsigns 連携)
    ├── snacks.lua           # 画像/mermaid プレビュー + dashboard + gitbrowse
    ├── blink-cmp.lua        # prose filetype で補完を無効化
    ├── render-markdown.lua  # render-markdown.nvim を default off に上書き
    └── claude-fzf.lua       # fzf-lua の Claude Code 連携
```

`lua/plugins/*.lua` は LazyVim が自動で読み込む。ファイルを追加/削除するだけでプラグインを管理できる。

## tab 表示

bufferline.nvim は無効化し、neovim ネイティブの tab 表示を使う。`showtabline` のデフォルト値 (`1`: タブが 2 つ以上で表示) で動作。

## カーソル位置プレビュー (`<Space>ip`)

カーソル下の要素を popup で描画する統一エントリポイント。画像・mermaid・markdown の table を 1 つのキーから扱う。

### 動作

`<Space>ip` を押すと、カーソルがどこにあるかで分岐する。

| カーソル位置 | 挙動 |
|---|---|
| markdown の table (`|` 行) | scratch buffer + render-markdown.nvim で描画した popup |
| 画像参照 (`![](...)`) または mermaid コードブロック | snacks.image で kitty graphics の popup |
| どれでもない | `No image/mermaid at cursor` を notify |

### 操作 (popup 内共通)

| キー | 機能 |
|---|---|
| `hjkl` / 矢印 | フローティング移動 |
| `+` / `-` | 縦横同時リサイズ |
| `Shift+矢印` | 幅・高さ個別リサイズ |
| `f` | フルスクリーントグル |
| `o` | macOS Preview.app で開く (画像 popup のみ) |
| `q` / `<Esc>` | 閉じる |

### 画像 / mermaid 側の前提

- ターミナル: ghostty (wezterm では画像表示不可)
- mermaid-cli (`mmdc`): brew でインストール、システム Chrome を使用 (`PUPPETEER_EXECUTABLE_PATH` を options.lua で設定)

### 制約

- 画像の元ピクセルサイズ (セル換算) が表示サイズの上限。元サイズ以上には拡大できない
- mermaid は `mmdc` の `-s` (scale) で元画像を大きくレンダリングすることで対応 (現在 4x)
- 複雑な mermaid 図はターミナルのセル数制約で読みづらい。`o` で macOS Preview に開いてズームする方が実用的

### markdown table popup の仕組み

LazyVim の `lang.markdown` extra で render-markdown.nvim を導入している。ただし:

- `lua/plugins/render-markdown.lua` で `opts.enabled = false` に上書き。通常の markdown バッファはインライン描画されず、生のままになる
- 同じファイルで `iamcco/markdown-preview.nvim` (ブラウザ経由の preview プラグイン) も `enabled = false` で無効化。ブラウザを開かないという方針のため
- popup は `lua/config/markdown_preview.lua` の `preview_table()` が担当
    - 連続する `|` 行を検出してテーブル範囲を特定
    - 同じ内容を scratch buffer に載せて filetype を markdown に
    - floating window を開き、その scratch buffer に `require("render-markdown").buf_enable()` を呼んで**その buffer だけ**レンダリング有効化
    - グローバルの `state.enabled` は false のまま。他の markdown バッファには影響しない

### インラインレンダリングを使いたいとき

LazyVim の extra が `<Space>um` で render-markdown のグローバル toggle を提供している (`Snacks.toggle`)。`<Space>um` を一度押すと全 markdown バッファで **インライン描画 ON** になり、もう一度押すと OFF に戻る。普段は popup で十分でも、長めの markdown を一気に俯瞰したい場面で使える。

### 将来の拡張

`popup_markdown(lines, title)` を汎用に切ってあるので、`find_xxx_range()` を書き足すだけで heading ブロック / code block / blockquote / 入れ子 list も同じ流儀で popup 描画できる。dispatch 側にも該当チェックを足せば、`<Space>ip` が一段賢くなる。

## ask-dotfiles (Claude)

dotfiles の全ファイルを読み込ませた Claude セッションに対して floating window から質問を投げる。`<Space>cq` で起動、`i` / `a` / `o` で follow-up、`q` / `<Esc>` で閉じる。nvim から見ると UI レイヤー (lua/config/ask_dotfiles.lua) だけで、実際の Claude 呼び出しは `~/.local/bin/ask-dotfiles` に委譲している。

詳細・仕組みは [ask-dotfiles](./ask-dotfiles.md) を参照。

## markdown lint / formatter

LazyVim の `lang.markdown` extra を有効化しているので、以下が自動で入る。

| 種類 | ツール | 動作 |
|---|---|---|
| LSP | marksman | heading / link 補完、section ジャンプ |
| Linter | markdownlint-cli2 (nvim-lint 経由) | BufEnter / BufWritePost / InsertLeave で diagnostic を出す |
| Formatter | prettier | `<Space>cf` で markdown を整形 |
| Formatter | markdownlint-cli2 | violation がある場合のみ auto-fix を試みる |
| Formatter | markdown-toc | `<!-- toc -->` がある場合のみ目次生成 |

### auto-format on save は markdown だけ無効

`lua/config/autocmds.lua` が markdown / markdown.mdx バッファで `vim.b.autoformat = false` を立てるため、**保存時に prettier が勝手に走ることはない**。既存の docs (このファイル含め) は prettier で整形されていないので、保存のたびに大量の diff が出るのを防ぐため。

手動整形は今まで通り `<Space>cf` で走る。lint (nvim-lint → markdownlint-cli2) の diagnostic 表示は自動で出る。

### ブラウザ preview は無効化

extra は `iamcco/markdown-preview.nvim` (ブラウザで rendered markdown を開く) も入れにくるが、`lua/plugins/render-markdown.lua` で `enabled = false` にして無効化してある。vim 完結で preview する方針のため。

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
| `<Space>ip` | カーソル位置プレビュー (画像 / mermaid / markdown table) |
| `<Space>cq` | ask-dotfiles popup |
| `<Space>um` | render-markdown インライン描画の toggle (LazyVim extra 由来) |
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
