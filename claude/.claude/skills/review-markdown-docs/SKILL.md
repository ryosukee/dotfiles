---
name: review-markdown-docs
description: "Markdown の文体・記法・AI パターンをレビューし修正する。\"/review-markdown-docs\"、\"/md-humanize\"、\"AI っぽさを直して\"、\"humanize\"、\"文体チェック\"、\"markdown review\" 等で発動。"
argument-hint: "<対象ファイルパス or glob パターン>"
---

# Markdown ドキュメントレビュー

対象: `$ARGUMENTS`

2 つのルールを参照してチェックする:

- `.claude/rules/markdown-authoring.md` — 文体・語彙・記法ルール（認知負荷低減、強調・装飾、改行、和欧混植、引用ブロック等）
- `.claude/rules/markdown-anti-ai-authoring.md` — AI 文体アンチパターン (A1-E2)

両ルールは `.md` ファイル編集時に自動読み込みされるため、追加の Read は不要。

## Step 1: 準備

`$ARGUMENTS` で指定されたファイルを Read する。glob パターンの場合は Glob で対象ファイルを特定してから Read。

## Step 2: チェック

対象ファイルを 2 つのルールに照らしてスキャンする。

markdownlint (機械的ルール違反):

```bash
npx -y markdownlint-cli2 "{対象ファイル}" 2>&1
```

markdown-authoring (文体・記法):

- 強調・装飾の過剰使用
- 改行・余白の問題
- 文体の硬さ（「〜となる」「〜である」等）
- 和欧混植のスペーシング
- 引用ブロックの用途違反
- ファイル間リンクの問題

markdown-anti-ai-authoring (AI パターン A1-E2):

- 各パターンの検出ヒューリスティックに照らしてスキャン
- 検出ごとにパターン ID・該当箇所・種別 (mechanical/judgment) を記録

## Step 3: 検出結果の報告

```text
## markdown review: {filename}

### markdownlint
{lint 結果。エラーがなければ「OK」}

### 文体・記法 (markdown-authoring)
{検出項目。なければ「OK」}

### AI パターン (A1-E2)
検出数: N 件 (mechanical: M 件, judgment: J 件)

| # | ID | パターン | 該当箇所 (抜粋) | 種別 |
|---|---|---|---|---|
| 1 | B1 | AI 語彙連鎖 | 「活用することで効率的に」 | mechanical |
| ... | ... | ... | ... | ... |
```

検出が 0 件の場合は「問題は検出されませんでした」と報告して終了。

## Step 4: 修正方針の確認

AskUserQuestion で修正範囲を確認する:

- mechanical のみ自動修正 — 機械的に置換可能なパターンのみ修正
- 全て修正提案を見る — judgment 含め全パターンの修正案を提示
- 特定パターンのみ — ID を指定して修正
- レポートのみ — 修正せず Step 6 に進む

## Step 5: 修正の実行

### 「mechanical のみ自動修正」の場合

確認なしで即 Edit する。修正前後を簡潔に記録し、Step 6 で結果を報告する。

### 「全て修正提案を見る」の場合

全件の before/after を一覧提示する。提示が終わるまで Edit しない。提示後に AskUserQuestion で「全て適用 / 個別に選択 / キャンセル」を確認し、承認されたものだけ Edit する。

### 「特定パターンのみ」の場合

指定された ID の before/after を提示する。確認後に Edit する。

## Step 6: サマリー報告

```text
## markdown review 完了: {filename}

- 修正: X 件 (mechanical: M, judgment: J)
- スキップ: Y 件
```

## 注意事項

- 技術文書の正確性を損なう修正はしない
- 著者が意図的に使っている表現を過剰に修正しない (judgment 分類で対応)
- 修正で文意が変わる場合は必ず judgment として扱い、確認を取る
