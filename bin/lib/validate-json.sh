#!/usr/bin/env bash
# bin/lib/validate-json.sh — sourced library: validate JSON.
#
# Usage: source "${CLAUDE_HOME}/bin/lib/validate-json.sh"
#   _validate_json_stream   < file-or-here-string   # validate stdin
#   _validate_json_file  <path>                     # validate a file's contents
#
# Return codes:
#   0 — valid JSON
#   1 — invalid JSON
#   2 — no JSON parser available (python3 / node / jq all absent)
#
# Parser chain: python3 → node → jq (same precedence used everywhere else).
#
# Windows note: always feed file CONTENTS via stdin, NEVER the path as a string
# arg. Windows-native node/python can't resolve MSYS '/c/...' path args and
# report a false "invalid JSON". `_validate_json_file` handles this by redirect.

_validate_json_stream() {
  if command -v python3 >/dev/null 2>&1; then
    python3 -c "import sys,json; json.load(sys.stdin)" >/dev/null 2>&1
    return $?
  elif command -v node >/dev/null 2>&1; then
    node -e "let s='';process.stdin.on('data',d=>s+=d);process.stdin.on('end',()=>{try{JSON.parse(s)}catch(e){process.exit(1)}});" >/dev/null 2>&1
    return $?
  elif command -v jq >/dev/null 2>&1; then
    jq -e . >/dev/null 2>&1
    return $?
  fi
  return 2
}

_validate_json_file() {
  local f="$1"
  [[ -f "$f" ]] || return 1
  _validate_json_stream < "$f"
}
