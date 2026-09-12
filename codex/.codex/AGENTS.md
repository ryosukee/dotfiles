# ユーザー共通の指示

セッションを開始したら、`~/.claude/rules` 配下の Markdown を確認する。
YAML frontmatter に `paths` がない rule を読み、常時適用する。
`paths` がある rule はここでは読まない。
