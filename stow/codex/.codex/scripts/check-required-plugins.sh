#!/bin/sh
# Warn about missing runtime dependencies and required marketplace plugins.

# Resolve the stow link so the marketplace is found in the source repository.
script_path=$0
while [ -L "$script_path" ]; do
    link=$(readlink "$script_path") || exit 1
    case $link in
        /*) script_path=$link ;;
        *) script_path=${script_path%/*}/$link ;;
    esac
done
script_dir=${script_path%/*}
[ "$script_dir" = "$script_path" ] && script_dir=.
repo_root=$(CDPATH= cd "$script_dir/../../../.." && pwd -P) || exit 1
marketplace=$repo_root/.agents/plugins/marketplace.json

# This branch cannot depend on jq: missing jq must itself produce valid JSON.
if ! command -v jq >/dev/null 2>&1 || ! jq -n 'true' >/dev/null 2>&1; then
    printf '%s\n' '{"systemMessage":"dotfiles の必須 Codex plugin を確認できません: jq がないか実行できません。Brewfile の依存ツールを確認してください。"}'
    exit 0
fi

warn() {
    jq -n --arg message "$1" '{systemMessage: $message}'
}

event=$(jq -er '.hook_event_name | select(type == "string")' 2>/dev/null) || {
    warn 'dotfiles の必須 Codex plugin を確認できません: hook 入力が不正です。'
    exit 0
}
[ "$event" = SessionStart ] || exit 0

warning_text=
if ! command -v python3 >/dev/null 2>&1 ||
    ! python3 -c 'import ast, fcntl, hashlib, json, os, pathlib, re, shlex, sys; assert sys.version_info >= (3, 9); assert hasattr(pathlib.Path, "is_relative_to")' >/dev/null 2>&1; then
    warning_text='Python 3.9 以上と必要な標準モジュールを実行できません。'
fi

if [ ! -r "$marketplace" ]; then
    warn "dotfiles の必須 Codex plugin を確認できません: marketplace.json を読めません。${warning_text:+ $warning_text}"
    exit 0
fi
catalog=$(jq -c 'if (.name | type) == "string" and (.plugins | type) == "array" and all(.plugins[]; (.name | type) == "string") then . else error("invalid marketplace") end' "$marketplace" 2>/dev/null) || {
    warn "dotfiles の必須 Codex plugin を確認できません: marketplace.json が不正です。${warning_text:+ $warning_text}"
    exit 0
}

if ! command -v codex >/dev/null 2>&1; then
    warn "dotfiles の必須 Codex plugin を確認できません: codex がありません。${warning_text:+ $warning_text}"
    exit 0
fi
listing=$(codex plugin list --json 2>/dev/null) || {
    warn "dotfiles の必須 Codex plugin を確認できません: codex plugin list --json に失敗しました。${warning_text:+ $warning_text}"
    exit 0
}
printf '%s\n' "$listing" | jq -e '(.installed | type) == "array" and all(.installed[]; (.pluginId | type) == "string" and (.installed | type) == "boolean" and (.enabled | type) == "boolean")' >/dev/null 2>&1 || {
    warn "dotfiles の必須 Codex plugin を確認できません: plugin 一覧が不正です。${warning_text:+ $warning_text}"
    exit 0
}

missing=$(jq -nr --argjson catalog "$catalog" --argjson listing "$listing" '
    $catalog.name as $marketplace |
    [$listing.installed[] | select(.installed and .enabled) | .pluginId] as $enabled |
    [$catalog.plugins[] | (.name + "@" + $marketplace) | select(. as $id | $enabled | index($id) == null)] |
    join(", ")
') || {
    warn "dotfiles の必須 Codex plugin を確認できません: plugin の照合に失敗しました。${warning_text:+ $warning_text}"
    exit 0
}

if [ -n "$missing" ]; then
    warning_text="dotfiles の必須 Codex plugin が未導入または無効です: ${missing}。dotfiles のセットアップ手順に従ってインストールまたは有効化してください。${warning_text:+ $warning_text}"
fi
[ -z "$warning_text" ] || warn "$warning_text"
