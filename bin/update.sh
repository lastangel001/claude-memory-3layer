#!/usr/bin/env bash
# update.sh — pull latest claude-memory-3layer and re-install.
#
# Usage:
#   ~/.claude/bin/update.sh            # update from tracked source
#   ~/.claude/bin/update.sh --dry-run  # preview changes, write nothing

set -e

CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
SOURCE_FILE="$CLAUDE_HOME/.memory-source"

if [[ ! -f "$SOURCE_FILE" ]]; then
  printf 'Error: %s not found.\nRe-clone the repo and run install.sh to register the source path.\n' \
    "$SOURCE_FILE" >&2
  exit 1
fi

SRC=$(tr -d '\r\n' < "$SOURCE_FILE")

if [[ ! -d "$SRC" ]]; then
  printf 'Error: source directory not found: %s\n' "$SRC" >&2
  printf 'Re-clone the repo and run install.sh again.\n' >&2
  exit 1
fi

if [[ -f "$CLAUDE_HOME/.memory-version" ]]; then
  installed=$(tr -d '\r\n' < "$CLAUDE_HOME/.memory-version")
  printf 'Installed: %s\n' "$installed"
fi
printf 'Source:    %s\n\n' "$SRC"

if [[ "${1:-}" == "--dry-run" ]]; then
  # Dry-run must not mutate the source working copy: fetch + preview only.
  printf '[dry-run] Skipping git pull. Pending upstream commits:\n'
  if git -C "$SRC" fetch --quiet 2>/dev/null; then
    pending=$(git -C "$SRC" log --oneline 'HEAD..@{u}' 2>/dev/null || true)
    if [[ -n "$pending" ]]; then printf '%s\n' "$pending"; else printf '  (none — up to date)\n'; fi
  else
    printf '  (fetch failed — offline or no upstream; preview unavailable)\n'
  fi
  printf '\n'
else
  printf 'Pulling...\n'
  git -C "$SRC" pull
  printf '\n'
fi

exec bash "$SRC/install.sh" "$@"
