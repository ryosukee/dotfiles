# mkdocs-setup

mkdocs.yml に MkDocs Material テーマの共通設定を注入するスキル。

---
name: mkdocs-setup
description: >
  mkdocs.yml に MkDocs Material テーマの共通設定を注入する。
  タブナビゲーション・monorepo 統合のオプション選択に対応。
  "/mkdocs-setup"、"mkdocs設定"、"MkDocs セットアップ"、"mkdocs setup"、
  "mkdocs theme"、"documentation site setup" 等で発動。
user-invocable: true
argument-hint: "mkdocs.yml のパス（省略時はカレントディレクトリの mkdocs.yml）"
allowed-tools: Read, Edit, Write, Bash, Glob, AskUserQuestion
---

本スキルはセットアップとテンプレート管理の複合スキル。ステップ 1〜8 がプロジェクトへの設定注入、ステップ 9 がテンプレートへの逆反映（プロジェクト固有設定の共通化検討）を担う。

## 処理フロー

### 1. 対象ファイルの特定

- 引数があればそのパスを使用
- 省略時はカレントディレクトリの `mkdocs.yml`
- ファイルが存在しない場合は → ステップ 7 へ

### 2. テンプレートの読み込み

`${CLAUDE_SKILL_DIR}/references/mkdocs-template.yml` を読み込む。

### 3. オプション機能の選択

既存の mkdocs.yml がある場合、各オプションの現在の有効/無効状態を検出する。検出結果に基づき、質問を2段階に分ける。

#### 3a. 未設定オプションの有効化（該当がある場合のみ）

現在無効なオプションがある場合、AskUserQuestion（multiSelect）で有効にしたいものを選択させる。質問文の前に現在の状態を提示する:

```
現在の状態: tabs ✓ / monorepo ✓ / github-edit ✗

無効になっているオプションのうち、有効にしたいものを選択してください（選択しなければ現状維持）:
```

#### 3b. 有効中オプションの無効化（該当がある場合のみ）

現在有効なオプションがある場合、AskUserQuestion（multiSelect）で無効にしたいものを選択させる:

```
有効中のオプションのうち、無効にしたいものを選択してください（選択しなければ現状維持）:
```

全て無効 or 全て有効の場合は該当するステップのみ実行する。新規セットアップ（mkdocs.yml が存在しない場合）は従来通り全オプションを multiSelect で一括選択する。

#### オプション一覧

**navigation.tabs（タブナビゲーション）**

ヘッダー直下に nav のトップレベルセクションをタブバーとして表示する機能。ドキュメントが複数の大きなセクション（例: API Reference / Guide / Tutorials）に分かれている場合に有効。

- 選択した場合:
  - `theme.features` に `navigation.tabs` と `navigation.tabs.sticky` を追加
  - `theme.features` から `navigation.expand` を除外（tabs と expand は相互排他: tabs はトップレベルをタブ化するため、全セクション自動展開の expand と併用すると意味が衝突する）
  - `extra_css` に `assets/css/tabs.css` を追加
  - `tabs.css`（タブバーのカスタムスタイル: アクティブタブの下線強調、ダークモード対応）をプロジェクトにコピー
- 選択しない場合:
  - `navigation.expand` を維持（サイドバーの全セクションがデフォルトで展開される）
  - タブバーは表示されない

**github-edit（GitHub 編集・ソース表示ボタン）**

各ドキュメントページに「GitHub で編集」ボタンを追加する機能。`repo_url` と `edit_uri` の設定が前提。公開ドキュメントでコントリビューションを促したい場合に有効。なお「ソースを表示」ボタン（`content.action.view`）はテンプレート標準で含まれており、`repo_url` + `edit_uri` が設定されていれば自動的に表示される。

- 選択した場合:
  - `theme.features` に `content.action.edit` を追加
  - `edit_uri` の値をユーザーに確認（例: `edit/main/docs/`）
- 選択しない場合:
  - 編集ボタンは表示されない（ソース表示ボタンは `repo_url` + `edit_uri` があれば表示される）
  - `edit_uri` はテンプレートから除外
  - `repo_url` / `repo_name`（ヘッダーのリポジトリリンク）は github-edit とは独立して設定可能

**monorepo（マルチサイト統合）**

`mkdocs-monorepo-plugin` を有効化し、複数の mkdocs.yml を `!include` で1つのサイトに統合する機能。サブプロジェクトごとに独立した mkdocs.yml を持つ大規模リポジトリ向け。

- 選択した場合:
  - `plugins` に `monorepo` を追加
  - `pip install mkdocs-monorepo-plugin` が必要な旨を完了報告で案内
- 選択しない場合:
  - 単一の mkdocs.yml でサイトを構成（通常のプロジェクトはこちら）

### 4. 既存 mkdocs.yml の読み込みと差分チェック

対象の mkdocs.yml を読み込み、テンプレートの各セクションと比較する。

対象セクション:
- `repo_url` / `repo_name` / `edit_uri`
- `hooks`
- `extra_css` / `extra_javascript`
- `theme`（`custom_dir` 含む）
- `plugins`
- `markdown_extensions`

### 5. セクションごとの注入（コンフリクト時はユーザー確認）

#### 5a. テンプレートの動的調整

比較の前に、ステップ 3 の選択結果に応じてテンプレートの内容を調整する:

- **tabs 選択時**:
  1. `theme.features` リストから `navigation.expand` を削除
  2. `theme.features` リストに `navigation.tabs` と `navigation.tabs.sticky` を追加
  3. `extra_css` リストに `assets/css/tabs.css` を追加
- **tabs 未選択時**: テンプレートのまま（`navigation.expand` を維持）
- **github-edit 選択時**:
  1. `theme.features` リストに `content.action.edit` を追加
  2. `edit_uri` をテンプレートに含める（値はユーザーに確認）
- **github-edit 未選択時**:
  1. テンプレートから `edit_uri` 行を除外
- **monorepo 選択時**: `plugins` リストの先頭に `monorepo` を追加（`search` の前）
- **monorepo 未選択時**: テンプレートのまま

#### 5b. セクション比較と注入

調整後のテンプレートと既存 mkdocs.yml を各セクションごとに比較する:

- **セクションが存在しない場合**: テンプレートの内容をそのまま追加する（確認不要）
- **セクションが存在し、テンプレートと同一の場合**: 変更なし（スキップ）
- **セクションが存在し、テンプレートと異なる場合**: AskUserQuestion で既存の内容とテンプレートの内容を両方提示し、以下の選択肢を出す:
  - **不足分を追加**: テンプレートにあってプロジェクトにない項目を追加（既存の設定はそのまま残る）
  - **既存を維持**: 変更しない
  - **マージ（手動確認）**: 両方の内容を見せてユーザーに最終的な内容を決めてもらう

### 6. プロジェクト固有設定の維持

以下のキーは一切変更しない:
- `site_name`
- `site_description`
- `docs_dir`
- `nav`
- その他テンプレートに含まれないキー

`repo_url` / `repo_name` / `edit_uri` はテンプレートに含まれるが、値はプロジェクト固有のため、既存の値があれば維持する。新規セットアップ時はステップ 7b で確認する。

### 7. mkdocs.yml が存在しない場合（新規セットアップ）

#### 7a. プロジェクト構造の調査

カレントディレクトリから以下の情報を収集する:

- **プロジェクト名の推定**: `package.json` の `name`、`pyproject.toml` の `project.name`、ディレクトリ名のいずれかから取得
- **説明文の推定**: `package.json` の `description`、`pyproject.toml` の `project.description`、`README.md` の冒頭から取得
- **repo_url / repo_name の自動取得**: `git remote get-url origin` からリモート URL を取得し、`https://github.com/org/repo` 形式の URL と `org/repo` 形式の名前に変換する
- **docs ディレクトリの検出**: `docs/`, `doc/`, `documentation/` など既存のドキュメントディレクトリを探す
- **既存 Markdown ファイルの検出**: docs ディレクトリ内の `.md` ファイル一覧を取得（nav 構成の提案に使う）

#### 7b. ユーザーへの提案と確認

調査結果をもとに AskUserQuestion で以下を確認する:

- `site_name`（推定値をデフォルトとして提示）
- `site_description`（推定値をデフォルトとして提示）
- `docs_dir`（既存ディレクトリが見つかればそれを、なければ `docs` をデフォルトとして提示）
- `repo_url`（自動取得値があれば提示。なければ入力を求める）
- `repo_name`（自動取得値があれば提示。なければ入力を求める）

#### 7c. mkdocs.yml の生成

テンプレート全体 + ユーザーが確認した `site_name`, `site_description`, `docs_dir` を合わせて mkdocs.yml を書き出す。ステップ 5a の動的調整結果も反映する。

既存の Markdown ファイルがある場合は `nav` セクションも生成する（ファイル一覧から提案）。

#### 7d. docs ディレクトリと index.md の作成

- `docs_dir` が存在しなければディレクトリを作成
- `docs_dir/index.md` が存在しなければ、`${CLAUDE_SKILL_DIR}/references/index-template.md` をベースに作成する
  - テンプレート内の `{{site_name}}` と `{{site_description}}` をユーザーの回答で置換する
- 既に `index.md` が存在する場合は何もしない

### 8. hooks スクリプトと overrides のコピー

#### 8a. hooks

`${CLAUDE_SKILL_DIR}/references/.mkdocs/hooks/` から以下をプロジェクトの `.mkdocs/hooks/` にコピーする:

- `show_frontmatter.py` — YAML フロントマターを折りたたみ admonition として表示
- `source_lines.py` — レンダリング後の HTML ブロック要素に `data-source-line` 属性を付与。Markdown ソースの行番号をヒューリスティックに照合する。**依存: `beautifulsoup4`**（brew の mkdocs-material 環境に入っていない場合はインストールが必要）
- `yaml_to_md.py` — docs/ 配下の `.yaml` ファイルを自動的に markdown ページ（YAML code block）に変換する。`on_pre_build` で `.yaml` の隣に `.md` を生成し、`on_post_build` で削除する。symlink 先も `followlinks=True` で辿る。nav では `.md` 拡張子で参照する（例: `_refs/workflows/investigation.md`）

ディレクトリがなければ作成する。既にファイルが存在し内容が異なる場合は、差分を提示してユーザーに上書きするか確認する。

#### 8b. overrides（標準アセット）

`${CLAUDE_SKILL_DIR}/references/.mkdocs/overrides/` から以下を常にコピーする:

- `assets/css/external-links.css` — 外部リンクに ↗ アイコンを付与する CSS
- `assets/js/external-links.js` — 外部リンクに `target="_blank"` を自動付与する JS
- `assets/js/nav-persist.js` — サイドバーの開閉状態を localStorage で永続化する JS
- `assets/css/toc-collapse.css` — 右サイドバー（TOC）の開閉トグル CSS。ヘッダーにボタン配置、閉じた時は本文領域を拡張、ピーク時はフローティングカード表示
- `assets/js/toc-collapse.js` — 右サイドバー（TOC）の開閉トグル JS。ヘッダーの GitHub リンク右隣にボタンを配置。クリックで永続的に開閉、ホバーで一時的にカード表示（ピーク）。状態は localStorage で永続化
- `assets/css/source-lines.css` — ソース行番号の表示スタイル。コンテンツ左側にガター領域を確保し、各ブロック要素の Markdown ソース行番号を表示。ヘッダーのトグルボタンのスタイルも含む
- `assets/js/source-lines.js` — ソース行番号のトグルボタン。ヘッダーに `#` アイコンで配置。クリックで行番号の表示/非表示を切替。状態は localStorage で永続化
- `partials/source.html` — ヘッダーのリポジトリリンクを別タブで開く
- `partials/actions.html` — 「GitHub で編集」「GitHub で閲覧」ボタンのラベル日本語化 + リンクを別タブで開く（ラベルはホバー時のみ表示）

コピー先: プロジェクトの `.mkdocs/overrides/` 配下の対応するパス

- ディレクトリがなければ作成する
- 既にファイルが存在し内容が異なる場合は、差分を提示してユーザーに上書きするか確認する

#### 8c. overrides（オプションアセット）

ステップ 3 の選択に応じてコピーする:

- **tabs 選択時**: `assets/css/tabs.css` — タブバーのカスタムスタイル（ダークモード対応）

既にファイルが存在し内容が異なる場合は、差分を提示してユーザーに上書きするか確認する。

### 9. テンプレートへの逆反映確認

ステップ 5 のマージ結果を分析し、**プロジェクト側にあってテンプレートにない設定**を特定する。

対象セクション（ステップ 4 と同じ）:
- `repo_url` / `repo_name` / `edit_uri`
- `hooks`
- `extra_css` / `extra_javascript`
- `theme`（`custom_dir` 含む）
- `plugins`
- `markdown_extensions`

該当する設定がある場合、AskUserQuestion で以下を提示する:

- プロジェクト固有の設定一覧（セクション名と具体的な項目）
- 各項目について**その設定が何をするものか**を1行で説明する（例: 「pymdownx.tasklist — チェックボックス付きタスクリストを Markdown で使えるようにする」）
- 各項目について以下の選択肢:
  - **テンプレートに追加**: `references/mkdocs-template.yml` に項目を追記する
  - **追加しない**: プロジェクト固有のままにする（テンプレートは変更しない）

「テンプレートに追加」が選ばれた項目は、`${CLAUDE_SKILL_DIR}/references/mkdocs-template.yml` の該当セクションの適切な位置に追記する。

該当する設定がない場合はこのステップをスキップする。

### 10. 完了報告

変更内容のサマリを出力する。テンプレートへの逆反映があった場合はそれも含める。

monorepo を選択した場合は以下を案内する:
```
pip install mkdocs-monorepo-plugin
```

## エラーハンドリング

| エラー | 原因 | 解決方法 |
|--------|------|---------|
| mkdocs.yml の YAML パースエラー | 構文不正 | エラー箇所を提示しユーザーに修正を依頼 |
| custom_dir 競合 | 既存の custom_dir が `.mkdocs/overrides` 以外 | ユーザーに既存パスを維持するか `.mkdocs/overrides` に移行するか確認 |
| overrides ファイル競合 | プロジェクト側に同名の異なるファイルが存在 | 差分を提示しユーザーに上書き可否を確認 |
| monorepo plugin 未インストール | pip install 未実行 | 完了報告でインストールコマンドを案内 |
| ディレクトリ作成失敗 | 権限不足やパス不正 | エラーメッセージを提示し手動作成を依頼 |
| テンプレートファイル読み込み失敗 | スキルの references が破損・欠落 | `${CLAUDE_SKILL_DIR}/references/` の存在を確認し、スキルの再インストールを案内 |
