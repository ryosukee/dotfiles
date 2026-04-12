#!/bin/bash
INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')
case "$TOOL" in
  Write|Edit) ;;
  *) exit 0 ;;
esac
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
case "$FILE_PATH" in
  *.md|*.json|*.yaml|*.yml|*.toml|*.txt|*.csv|*.xml|*.html|*.css) exit 0 ;;
esac
CONTENT=""
if [ "$TOOL" = "Write" ]; then
  CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // empty')
elif [ "$TOOL" = "Edit" ]; then
  CONTENT=$(echo "$INPUT" | jq -r '.tool_input.new_string // empty')
fi
if echo "$CONTENT" | grep -qi '\.netrc'; then
  REASON="blocked: script content references .netrc ($FILE_PATH)"
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$REASON"
  exit 0
fi
exit 0
