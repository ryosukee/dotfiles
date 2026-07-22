# Tailscale

brew の OSS 版 tailscaled を使う。GUI アプリ版（App Store / Standalone）ではない。

## なぜ OSS 版か

- GUI アプリ版は sandbox 制約で `tailscale serve` の path serving（ディレクトリ直接配信）が使えない。
  claude-pages（閲覧用 HTML の tailnet 内配信。運用は
  [入り組んだ説明・報告・確認は HTML で行う](https://github.com/ryosukee/cc-marketplace/blob/main/rules/author-defaults/html-communication.md) を参照）で path serving が必要
- GUI 版と OSS 版は同一マシンで同居できない。トンネルと DNS 制御が衝突する
- 常時接続で GUI 操作もほぼしないため、CLI のみで運用できると判断した

## セットアップ

```sh
brew install tailscale                # Brewfile 管理
sudo tailscaled install-system-daemon # 起動時に自動起動するシステムデーモンとして登録
sudo tailscale set --operator=$USER   # tailscale コマンドの sudo を不要化
tailscale up                          # 表示される URL をブラウザで開いて認証
```

GUI アプリ版から乗り換える場合は、先にメニューバーから Quit →
`/Applications/Tailscale.app` を削除 → 旧アプリのラッパー `/usr/local/bin/tailscale` を削除してから
`brew link tailscale` を実行する。移行後は新ノード扱いになるため、
管理画面で旧ノードを削除して名前の衝突を解消する。

## claude-pages の serve 設定

閲覧用 HTML の共通ディレクトリを tailnet 内限定の HTTPS で配信する。

```sh
tailscale serve --bg ~/.local/share/claude-pages # 初回のみ。以降は永続
tailscale serve status                           # 設定と URL の確認
tailscale serve --https=443 off                  # 解除
```

ルート URL（`https://<ホスト名>.<tailnet 名>.ts.net/`）で index.html が配信される。

## 既知の注意点

- OSS 版は `*.ts.net` の split-DNS をシステムリゾルバに登録しないことがある。
  ts.net 名が引けない場合は `/etc/resolver/ts.net` に `nameserver 100.100.100.100` を書く
- serve 設定（`tailscale serve --bg <dir>`）は tailscaled に永続化され、再起動後も維持される
- Mac のスリープ中は serve も応答しない
