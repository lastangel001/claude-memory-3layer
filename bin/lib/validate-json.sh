#!/usr/bin/env bash
# bin/lib/validate-json.sh — sourced library: pick a JSON parser + validate JSON.
#
# Usage: source "${CLAUDE_HOME}/bin/lib/validate-json.sh"
#   _cmd_runs python3|node|jq        # 0 if that interpreter actually EXECUTES
#   _json_parser                     # echo first working parser name (or nothing)
#   _validate_json_stream   < input  # validate stdin
#   _validate_json_file  <path>      # validate a file's contents
#
# Return codes (_validate_json_*):
#   0 — valid JSON
#   1 — invalid JSON
#   2 — no WORKING JSON parser available (python3 / node / jq all absent or broken)
#
# Parser chain: python3 → node → jq (same precedence used everywhere else).
#
# Windows gotcha — Store execution-alias stub:
#   Win11 ships a `python3` stub at %LOCALAPPDATA%\Microsoft\WindowsApps that
#   satisfies `command -v python3` but, when run, prints "Python was not found…"
#   and exits 49. Presence-only detection (`command -v`) therefore picks a parser
#   that can't parse, and every validation falsely fails. `_cmd_runs` guards this
#   by actually executing the interpreter (trivial no-op) before selecting it.
#
# Windows note (paths): always feed file CONTENTS via stdin, NEVER the path as a
# string arg. Windows-native node/python can't resolve MSYS '/c/...' path args
# and report a false "invalid JSON". `_validate_json_file` handles this by redirect.

# Return 0 only if the named interpreter is present AND actually runs. The no-op
# probe (python3 -c '', node -e '', jq --version) exits 0 on a real install and
# non-zero on the Windows Store stub / a broken shim.
_cmd_runs() {
  case "$1" in
    python3) command -v python3 >/dev/null 2>&1 && python3 -c '' >/dev/null 2>&1 ;;
    node)    command -v node    >/dev/null 2>&1 && node -e ''     >/dev/null 2>&1 ;;
    jq)      command -v jq       >/dev/null 2>&1 && jq --version   >/dev/null 2>&1 ;;
    *) return 1 ;;
  esac
}

# Echo the first working JSON parser name (python3 → node → jq); echo nothing +
# return 1 if none run.
_json_parser() {
  local p
  for p in python3 node jq; do
    if _cmd_runs "$p"; then printf '%s' "$p"; return 0; fi
  done
  return 1
}

_validate_json_stream() {
  case "$(_json_parser)" in
    python3)
      python3 -c "import sys,json; json.load(sys.stdin)" >/dev/null 2>&1
      return $? ;;
    node)
      node -e "let s='';process.stdin.on('data',d=>s+=d);process.stdin.on('end',()=>{try{JSON.parse(s)}catch(e){process.exit(1)}});" >/dev/null 2>&1
      return $? ;;
    jq)
      jq -e . >/dev/null 2>&1
      return $? ;;
    *)
      return 2 ;;
  esac
}

_validate_json_file() {
  local f="$1"
  [[ -f "$f" ]] || return 1
  _validate_json_stream < "$f"
}
