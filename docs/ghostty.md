# ghostty 設定

kitty graphics protocol 対応のターミナルエミュレータ。nvim 内で画像/mermaid をプレビューするために使用。

## ファイル構成

```
ghostty/.config/ghostty/
└── config    # 設定ファイル (INI 風)
```

## 設定内容

- フォント: Cica Bold, 17pt
- カラースキーム: Oceanic Next (wezterm と同じ)
- `macos-titlebar-style = hidden`: タイトルバーなし
- `macos-option-as-alt`: Option キーを Alt として使用

## wezterm との使い分け

| 機能 | ghostty | wezterm |
|---|---|---|
| kitty graphics protocol | ネイティブ対応 | 不完全 (画像プラグイン非推奨) |
| 画像/mermaid プレビュー | snacks.nvim image が動作 | 動作しない |
| Lua 設定 | なし (INI 風) | あり |

画像プレビューが必要な作業は ghostty で。それ以外はどちらでも可。
