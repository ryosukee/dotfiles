#!/bin/sh
# List changed files in the repository and added lines that look like personal information.
# Usage: scan-changes.sh [--staged]
#   default   working tree and index against HEAD, plus untracked files
#   --staged  only the staged changes, for the check right before commit
set -eu

repo=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
pattern='/Users/[a-z]|/home/[a-z]|api.key|token|secret|password|sk-|ghp_|bearer|@[a-z]+\.[a-z]|[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}'

mode=all
if [ "${1-}" = --staged ]; then
  mode=staged
fi

# Print each added line as "path: line" so a match can be traced to its file.
added_lines() {
  awk '/^\+\+\+ /{f = substr($0, 7); next} /^\+/{print f ": " substr($0, 2)}'
}

if [ "$mode" = staged ]; then
  printf '%s\n' '## staged files'
  git -C "$repo" diff --cached --name-status
  printf '\n%s\n' '## staged added lines matching personal-information patterns'
  git -C "$repo" diff --cached -U0 | added_lines | grep -iE "$pattern" || printf '%s\n' '(none)'
  exit 0
fi

printf '%s\n' '## changed files'
git -C "$repo" status --porcelain=v1 --untracked-files=all

printf '\n%s\n' '## added lines matching personal-information patterns'
{
  git -C "$repo" diff HEAD -U0 | added_lines
  git -C "$repo" ls-files --others --exclude-standard | while IFS= read -r f; do
    if [ -f "$repo/$f" ] && [ ! -L "$repo/$f" ]; then
      grep -nI '' "$repo/$f" | sed "s|^|$f: |" || true
    fi
  done
} | grep -iE "$pattern" || printf '%s\n' '(none)'
