#!/usr/bin/env bash
# bin/lib/slug.sh — sourced library: compute Claude Code project slug and canonical cwd.
#
# Usage: source "${CLAUDE_HOME}/bin/lib/slug.sh"; _compute_slug
#
# After _compute_slug returns:
#   $slug                  — project slug matching ~/.claude/projects/ naming
#   $current_cwd_canonical — Windows-style canonical path (C:/dev/foo) or $PWD
#
# Slug formula (matches Claude Code's actual slug generation):
#   /c/dev/my_project  →  C--dev-my-project
#   Drive letter uppercased + "--" + path with "/" and "_" both mapped to "-"
#
# Optional arg: _compute_slug [cwd]  (defaults to $PWD)

_compute_slug() {
  local _cwd="${1:-$PWD}"
  slug=""
  current_cwd_canonical=""

  if [[ "$_cwd" =~ ^/([a-zA-Z])/(.*)$ ]]; then
    local _drive="${BASH_REMATCH[1]^^}"
    local _rest="${BASH_REMATCH[2]}"
    slug="${_drive}--${_rest//\//-}"
    current_cwd_canonical="${_drive}:/${_rest}"
  elif [[ "$_cwd" =~ ^/([a-zA-Z])/?$ ]]; then
    local _drive="${BASH_REMATCH[1]^^}"
    slug="${_drive}-"
    current_cwd_canonical="${_drive}:/"
  else
    slug="${_cwd//\//-}"
    slug="${slug#-}"
    current_cwd_canonical="$_cwd"
  fi
  # Match Claude Code: underscores -> hyphens in slug
  slug="${slug//_/-}"
}
