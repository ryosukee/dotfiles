# Tailscale

brew の OSS 版 tailscaled を使う。GUI アプリ版（App Store / Standalone）ではない。

## なぜ OSS 版か

- GUI アプリ版は sandbox 制約で `tailscale serve` の path serving（ディレクトリ直接配信）が使えない。
  claude-pages（閲覧用 HTML の tailnet 内配信。運用は cc-marketplace の
  [html-communication skill](https://github.com/ryosukee/cc-marketplace/tree/main/plugins/claude-user-communication/skills/html-communication) を参照）で path serving が必要
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

## ts.net の名前解決（split DNS）

OSS 版に乗り換えると、Mac 上で `*.ts.net` の名前が引けなくなることがある。対処は次の 1 行。

```sh
printf 'nameserver 100.100.100.100\n' | sudo tee /etc/resolver/ts.net
```

引けなくなる仕組み:

- MagicDNS の実体は、Tailscale クライアントが内蔵する DNS サーバー（`100.100.100.100`。
  トンネル内でだけ届く）で、tailnet 内の端末名と Tailscale IP の対応表を持つ。
  「ts.net 名を引く」とは、問い合わせをこのサーバーに届けること
- GUI アプリ版は NetworkExtension 経由で「ts.net はこの DNS へ」という設定を OS に注入するため、
  無設定で引ける
- OSS 版はシステム設定の書き換えで DNS を構成するが、検索ドメイン
  （短い名前を `<名前>.<tailnet 名>.ts.net` に補完する設定）しか登録されないことがある。
  検索ドメインは解決先サーバーを指定しないため、問い合わせは通常の一般 DNS に流れ、
  非公開の tailnet 名は「存在しない」と返される

`/etc/resolver/ts.net` は macOS の split DNS 設定で、「`ts.net` で終わる名前だけ
`100.100.100.100` に聞く」という例外規則を追加する。影響範囲は ts.net ドメインに限定され、
Tailscale 停止時は ts.net 名の解決が失敗するだけ。ファイルを消せば元に戻る。
スマートフォン側は各端末の Tailscale アプリが VPN として DNS を注入するため、この問題の影響を受けない。

## claude-pages 用の環境変数

html-communication skill は配置先と配信 URL を環境変数から解決する。
値は `claude/.claude/settings.json` の `env` で設定する（このマシンの現在値）:

- `CLAUDE_PAGES_BASE_URL` = `https://mac-mini.hake-tarpon.ts.net`

ホスト名・tailnet 名が変わったらこの値を更新する。

`CLAUDE_PAGES_DIR` は設定しない。未設定時は skill 側の既定値
`~/.local/share/claude-pages` が使われ、それがこのマシンでの配置先と一致する。

シェルの env ではなく settings.json に置く理由は 2 つ。この 2 変数の消費者は
Claude Code の skill だけでシェルからは使わないこと、
settings.json の `env` は起動元シェルに依存せず全セッションへ適用されること
（シェル側に置いていたときは、変数を追加する前から起動していたセッションに値が入らなかった）。

## 既知の注意点

- serve 設定（`tailscale serve --bg <dir>`）は tailscaled に永続化され、再起動後も維持される
- Mac のスリープ中は serve も応答しない
