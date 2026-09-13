#!/bin/sh
# Link the user-level Codex skills directory to the Claude Code source.
set -eu

setup_home=${DOTFILES_SETUP_HOME:-${HOME:-}}
if [ -z "$setup_home" ]; then
  printf '%s\n' 'HOME is not set' >&2
  exit 1
fi

source_dir=$setup_home/.claude/skills
target_dir=$setup_home/.agents/skills
if [ ! -d "$source_dir" ]; then
  printf 'skills source does not exist: %s\n' "$source_dir" >&2
  exit 1
fi

if [ -L "$target_dir" ]; then
  if [ "$(readlink "$target_dir")" = '../.claude/skills' ]; then
    printf 'skills link already exists: %s\n' "$target_dir"
    exit 0
  fi
  printf 'skills path already points elsewhere: %s\n' "$target_dir" >&2
  exit 1
fi
if [ -e "$target_dir" ]; then
  printf 'skills path already exists: %s\n' "$target_dir" >&2
  exit 1
fi

mkdir -p "$setup_home/.agents"
ln -s ../.claude/skills "$target_dir"
printf 'created skills link: %s\n' "$target_dir"
