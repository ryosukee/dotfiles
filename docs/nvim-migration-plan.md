# Neovim 環境移行プラン: LazyVim + lazygit + delta + diffview.nvim

## 背景

AI にコード変更を頼んだ後、diff を確認して特定行にコメント (`@agent ...`) を書き込み、次の指示を出すワークフローを最適化したい。調査の結果、以下の構成を採用する。

## 採用構成

| ツール | 役割 |
|---|---|
| LazyVim | nvim ディストロ (lazy.nvim ベース、LSP/treesitter/補完 同梱) |
| lazygit | TUI git クライアント (staging/commit/rebase) |
| delta | git diff ページャ (side-by-side, syntax highlighting) |
| diffview.nvim | nvim 内 side-by-side diff + file tree (右ペインで直接編集可能) |

## diff レビューワークフロー

1. `<leader>do` で diffview.nvim を開く (file tree + side-by-side)
2. file tree で変更ファイルをナビゲート
3. 右ペイン (新しい側) で直接 `@agent ここを修正して` と書き込み・保存
4. staging/commit は `<leader>gg` で lazygit を起動して操作

diffview.nvim の右ペインは通常の nvim バッファなので、marks/検索/LSP も使える。lazygit の diff ビューは読み取り専用 (delta の出力をページャで表示するだけ) で、ファイル編集は `e` キーでエディタに飛ぶ形になる。

## LazyVim を選んだ理由

| 観点 | LazyVim | AstroNvim | NvChad |
|---|---|---|---|
| lazygit | 内蔵 (`<leader>gg`) | コミュニティレシピで追加 | 手動追加 |
| カスタマイズ | `lua/plugins/*.lua` に追加するだけ | AstroCommunity レシピ経由 | `custom/` ディレクトリ |
| メンテナ | folke (lazy.nvim 作者) | mehalter + コミュニティ | siduck |
| ドキュメント | extras カタログが充実 | 普通 | 薄め |
| 更新頻度 | 2026/04 時点で活発 | 活発 | やや鈍化 (2026/02) |

LunarVim は 2025/06 以降更新なし。候補外。

## 現在の nvim 設定 → LazyVim 移行マッピング

### 不要になるプラグイン (LazyVim 同梱で代替)

| 現在 | LazyVim 同梱の代替 |
|---|---|
| NERDTree + vim-devicons | neo-tree.nvim + nvim-web-devicons |
| vim-airline | lualine.nvim |
| vim-gitgutter | gitsigns.nvim |
| ALE + syntastic | LSP (gopls, ts_ls 等) + none-ls/conform.nvim |
| indentLine | indent-blankline.nvim |
| vim-niji (rainbow parens) | nvim-ts-rainbow (treesitter ベース) |
| vim-json | treesitter json パーサー |
| vim-markdown | treesitter markdown パーサー |

### 移植が必要な設定

| 設定 | 移植先 | 内容 |
|---|---|---|
| diffview.nvim | `lua/plugins/diffview.lua` | setup + keymaps (`<leader>do/dc/dh/dH/dr`) |
| claude-fzf.lua | `lua/plugins/claude-fzf.lua` | fzf-lua + `.claude` filetype |
| markdown-preview.nvim | `lua/plugins/markdown-preview.lua` | mermaid 対応プレビュー |
| goyo + limelight | `lua/plugins/zen.lua` | 使うなら。LazyVim extras に zen-mode もある |
| tabular | `lua/plugins/tabular.lua` | テーブルフォーマット。使用頻度次第 |
| エディタ基本設定 | `lua/config/options.lua` | tabstop=4, smartcase, conceallevel=0 等 |
| キーマップ | `lua/config/keymaps.lua` | j→gj, k→gk, ESC×2→nohlsearch 等 |
| diff ハイライト色 | `lua/plugins/diffview.lua` | DiffAdd/Delete/Change/Text のカスタム色 |

### 新規追加: lazygit + delta 連携

lazygit の設定ファイル (`~/.config/lazygit/config.yml`) を作成:

```yaml
git:
  paging:
    colorArg: always
    pager: delta --dark --paging=never --side-by-side
```

dotfiles に `lazygit/.config/lazygit/config.yml` として配置し、`stow lazygit` で symlink する。

Brewfile に `brew "lazygit"` を追加。

## Cica フォントの互換性

Cica は Nerd Fonts グリフを内蔵 (ビルド時パッチ) しているため、Powerline 記号と devicons は表示できる。

注意: Cica の最終リリースは 2022/03 (v5.0.3)、Nerd Fonts v2.x 時代。2023 年の Nerd Fonts v3.0 でコードポイントが再編されたため、新しいファイルタイプのアイコンが化ける可能性がある。

対処: まず Cica のまま試す。化けが気になったら Hack Nerd Font に切り替え (Cica のラテン文字部分は Hack ベースなので見た目が近い)。

## 移行手順

1. `NVIM_APPNAME=lazyvim nvim` で既存設定と並行運用しながら試す
2. `~/.config/lazyvim/` に LazyVim をセットアップ
3. 個人設定を移植 (diffview, claude-fzf, keymaps, options)
4. 問題なければ `nvim/.config/nvim/` を LazyVim 構成に置き換え
5. lazygit の stow package を追加
6. Brewfile を更新 (`lazygit` 追加)

## 参考記事

lazygit + delta セットアップ (スクショ付き):
- https://www.lorenzobettini.it/2025/06/better-diffs-in-lazygit-with-delta/
- https://medium.com/@yusuke_h/ターミナルがダサいとモテない-git-deltaでgit-diff-lazygitをside-by-sideでおしゃれ表示-7932ece7d335

lazygit + neovim 連携:
- https://dev.to/doctorscott/neovim-and-lazygit-perfect-harmony-2mgl (nvr で親 nvim にファイルを開く設定)
- https://plainenglish.io/blog/lazygit-in-neovim (lazygit.nvim 入門)

diffview.nvim:
- https://medium.com/unixification/my-neovim-git-setup-ba918d261cb6 (neogit + gitsigns + diffview の構成)

delta カラーチューニング:
- https://minerva.mamansoft.net/Notes/📜2025-06-02+Lazygitで表示するdeltaの差分カラーを見やすくする
