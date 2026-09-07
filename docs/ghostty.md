# ghostty 設定

kitty graphics protocol 対応のターミナルエミュレータ。nvim 内で画像/mermaid をプレビューするために使用。

## ファイル構成

```
ghostty/.config/ghostty/
└── config    # 設定ファイル (INI 風)
```

## 設定内容

- フォント: Cica Bold, 17pt
- カラースキーム: Oceanic Next
- `macos-titlebar-style = tabs`: タイトルバーをタブバーと統合
- `macos-option-as-alt`: Option キーを Alt として使用
- `keybind = ctrl+shift+j=ignore`: Ctrl+Shift+J をターミナル内のプログラムへ渡さない (後述)

## Ctrl+Shift+J を握り潰す理由

Ctrl+Shift+J は IME のかな切替に使っている。IME が受け取らなかった場合、
ターミナルはこれを Ctrl+J (改行) として子プロセスへ送る。
cc-ask-dotfiles の REPL (`read -r`) や nvim の入力欄では改行が「入力の確定」なので、
途中まで打った質問がそのまま送信されてしまう。

`ignore` は Ghostty が子プロセスへ転送しないだけで、OS や IME 側の処理は妨げない。

> "Ignore this key combination. Ghostty will not process this combination nor forward it to the child process within the terminal, but it may still be processed by the OS or other applications."
>
> 出典: [Keybinding Action Reference](https://ghostty.org/docs/config/keybind/reference)

設定変更後は Ghostty の設定を再読み込みする。
