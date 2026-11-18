#!/usr/bin/env bash
# paths.sh — shared PATH augmentation for Node/npm tooling (qmd etc.).
# Source this file, then call _augment_node_path.
#
# Normalizes Windows paths (C:\... with backslashes) to unix form, since
# $APPDATA/$USERPROFILE come back backslash-style in Git Bash and would
# otherwise poison PATH (qmd resolves to a non-executable mangled path).

_add_path() {
  local p="$1"
  p="${p//\\//}"  # backslashes -> forward slashes
  [[ "$p" =~ ^([A-Za-z]):(.*)$ ]] && p="/${BASH_REMATCH[1],,}${BASH_REMATCH[2]}"  # C:/x -> /c/x
  # `[[ -d … ]] && PATH=…` as the LAST statement returns 1 for a missing
  # directory. Under `set -e` that aborted every caller on the first path that
  # does not exist on this OS — which is always some of them (see gotchas.md).
  if [[ -d "$p" ]]; then PATH="$p:$PATH"; fi
  return 0
}

_augment_node_path() {
  _add_path "/c/Program Files/nodejs"
  _add_path "${APPDATA:-}/npm"
  _add_path "${USERPROFILE:-}/AppData/Roaming/npm"
  _add_path "$HOME/.npm-global/bin"
  _add_path "/usr/local/bin"
  _add_path "/opt/homebrew/bin"
  export PATH
}
