#!/usr/bin/env bash
# PostToolUse hook — selectively auto-captures high-signal tool events to SESSION.md.
#
# Captured patterns (minimal, low-noise):
#   Bash/PowerShell that produced a NEW git commit → Decisions entry "<sha> <subject>"
#   Write/Edit/MultiEdit of **/CLAUDE.md           → Decisions entry (L1a in-repo update)
#   Write/Edit/MultiEdit of **/.claude-docs/*.md   → Decisions entry (L1b doc update)
#
# Everything else: silently ignored. Hook never blocks, never errors visibly.
# Output: none (no hookSpecificOutput needed — we write directly to SESSION.md).
#
# Cost discipline: this hook fires after tool calls, so the common no-match path
# must not spawn an interpreter. Two pure-bash gates (substring prefilter, then
# tool name) exit before any JSON parser is probed.

set -euo pipefail

CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"

# Read stdin once
input=$(cat)
if [[ -z "$input" ]]; then exit 0; fi

# --- Gate 1: substring prefilter (pure bash) ---
# None of the three patterns can match unless the raw event mentions one of
# these. Note the event also carries tool_response, so this gate only excludes.
case "$input" in
  *commit*|*CLAUDE.md*|*.claude-docs*) ;;
  *) exit 0 ;;
esac

# --- Gate 2: tool name (pure bash) ---
_tn_re='"tool_name"[[:space:]]*:[[:space:]]*"([A-Za-z_]+)"'
tool_name=""
[[ "$input" =~ $_tn_re ]] && tool_name="${BASH_REMATCH[1]}"
case "$tool_name" in
  Bash|PowerShell|Write|Edit|MultiEdit) ;;
  *) exit 0 ;;
esac

mkdir -p "$CLAUDE_HOME/debug" 2>/dev/null || true

# shellcheck source=../bin/lib/diag.sh
[[ -f "${CLAUDE_HOME}/bin/lib/diag.sh" ]] && source "${CLAUDE_HOME}/bin/lib/diag.sh"

# ERR trap — log failure and exit cleanly (hook must never block tool execution).
_hook_error() {
  local rc=$1 lineno=$2
  echo "[$(date -Iseconds)] PostToolUse ERROR rc=${rc} line=${lineno}" \
    >> "$CLAUDE_HOME/debug/hook-trace.log" 2>/dev/null || :
  declare -F _diag >/dev/null 2>&1 && _diag PostToolUse failed "line=${lineno} rc=${rc}"
  exit 0
}
trap '_hook_error $? "${BASH_LINENO[0]}"' ERR

# --- Parse JSON (python3 preferred; node fallback; jq fallback; grep last-resort) ---
# Parser is chosen by _json_parser, which probes that the interpreter actually
# RUNS — a Windows Store `python3` stub satisfies `command -v` but exits non-zero,
# so presence-only detection would silently pick a parser that can't parse.
# shellcheck source=../bin/lib/validate-json.sh
source "${CLAUDE_HOME}/bin/lib/validate-json.sh"

tool_path=""
tool_cmd=""
tool_cwd=""

_parser=$(_json_parser || true)

if [[ "$_parser" == "python3" ]]; then
  parsed=$(printf '%s' "$input" | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
    inp  = d.get("tool_input", {}) or {}
    path = inp.get("file_path", "") or ""
    cmd  = (inp.get("command", "") or "").replace("\n", " ")
    cwd  = d.get("cwd", "") or ""
    sys.stdout.write(path + "\x01" + cwd + "\x01" + cmd)
except Exception:
    sys.stdout.write("\x01\x01")
' 2>/dev/null || true)
  IFS=$'\x01' read -r tool_path tool_cwd tool_cmd <<< "$parsed"
elif [[ "$_parser" == "node" ]]; then
  parsed=$(printf '%s' "$input" | node -e "
    let s='';
    process.stdin.on('data', d => s += d);
    process.stdin.on('end', () => {
      try {
        const d = JSON.parse(s);
        const inp = d.tool_input || {};
        process.stdout.write(
          (inp.file_path||'') + '\x01' +
          (d.cwd||'') + '\x01' +
          String(inp.command||'').replace(/\n/g, ' ')
        );
      } catch(e) { process.stdout.write('\x01\x01'); }
    });
  " 2>/dev/null || true)
  IFS=$'\x01' read -r tool_path tool_cwd tool_cmd <<< "$parsed"
elif [[ "$_parser" == "jq" ]]; then
  tool_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // ""' 2>/dev/null || true)
  tool_cwd=$(printf '%s' "$input"  | jq -r '.cwd // ""' 2>/dev/null || true)
  tool_cmd=$(printf '%s' "$input"  | jq -r '.tool_input.command // "" | gsub("\n"; " ")' 2>/dev/null || true)
else
  # Minimal grep fallback — breaks on escaped quotes or multi-line JSON values.
  # Install python3, node, or jq for robust parsing; doctor.sh will warn if none present.
  echo "[$(date -Iseconds)] PostToolUse: WARNING — using grep fallback (install python3/node/jq for robust parsing)" \
    >> "$CLAUDE_HOME/debug/hook-trace.log" 2>/dev/null || true
  declare -F _diag >/dev/null 2>&1 && _diag PostToolUse degraded "grep-fallback-parser"
  tool_path=$(printf '%s' "$input" | grep -o '"file_path":"[^"]*"' | head -n1 | cut -d'"' -f4 || true)
  tool_cmd=$(printf '%s' "$input"  | grep -o '"command":"[^"]*"'   | head -n1 | cut -d'"' -f4 || true)
fi

# --- Resolve the project's SESSION.md (same resolver the SessionStart hook uses) ---
# shellcheck source=../bin/lib/slug.sh
source "${CLAUDE_HOME}/bin/lib/slug.sh"
_resolve_project "$input"

# shellcheck disable=SC2154  # project_dir set by sourced _resolve_project
session_file="${project_dir}/memory/SESSION.md"

# No SESSION.md yet means no substantive work started — nothing to capture.
if [[ ! -f "$session_file" ]]; then exit 0; fi

# --- Append a line to SESSION.md ---
# Simple append: model integrates these into proper sections on next update.
# Format: "- [HH:MM] [auto] label: detail"
# An identical "[auto] label: detail" already in the file is not repeated —
# five edits to gotchas.md are one fact, and every append makes the model's
# next Write to SESSION.md fail once with "file modified since read".

ts=$(date -u +%H:%M 2>/dev/null || echo "??:??")

capture() {
  local label="$1" detail="$2"
  if grep -qF -- "[auto] ${label}: ${detail}" "$session_file" 2>/dev/null; then
    return 0
  fi
  printf -- '- [%s] [auto] %s: %s\n' "$ts" "$label" "$detail" >> "$session_file" 2>/dev/null || true
  echo "[$(date -Iseconds)] PostToolUse captured: ${label}: ${detail}" \
    >> "$CLAUDE_HOME/debug/hook-trace.log" 2>/dev/null || true
  declare -F _diag >/dev/null 2>&1 && _diag PostToolUse ok "captured=${label// /-}"
  return 0
}

# --- Pattern matching ---

# git commit (Bash / PowerShell tool).
# The command text alone proves nothing: `grep "git commit" docs/` and
# `echo git commit` both contain the words. So the text is only a cheap
# trigger; the evidence is the repository itself — HEAD must be a commit made
# in the last few minutes that we have not captured yet. The subject comes
# from git, never from parsing -m / heredoc quoting out of the command.
_commit_re='(^|[;&|({[:space:]])git[[:space:]]+([^;&|]*[[:space:]])?commit([[:space:];&|)]|$)'
if [[ ( "$tool_name" == "Bash" || "$tool_name" == "PowerShell" ) && "$tool_cmd" =~ $_commit_re ]]; then
  _git_dir="${tool_cwd:-$PWD}"
  _head=$(git -C "$_git_dir" log -1 --format='%h %ct %s' 2>/dev/null || true)
  if [[ -n "$_head" ]]; then
    _sha="${_head%% *}"
    _rest="${_head#* }"
    _ct="${_rest%% *}"
    _subject="${_rest#* }"
    _now=$(date +%s 2>/dev/null || echo 0)
    _marker="${project_dir}/memory/.auto-last-commit"
    _last=$(cat "$_marker" 2>/dev/null || echo "")
    if [[ "$_ct" =~ ^[0-9]+$ && $((_now - _ct)) -le 300 && "$_sha" != "$_last" ]]; then
      printf '%s' "$_sha" > "$_marker" 2>/dev/null || true
      capture "git commit" "${_sha} ${_subject:0:72}"
    fi
  fi
  exit 0
fi

# File-edit tools: normalize Windows backslashes before matching paths
# (Claude Code reports C:\repo\.claude-docs\x.md on Windows).
if [[ "$tool_name" == "Write" || "$tool_name" == "Edit" || "$tool_name" == "MultiEdit" ]]; then
  _p="${tool_path//\\//}"

  # CLAUDE.md (L1a in-repo entry point updated)
  if [[ "$_p" == *"/CLAUDE.md" || "$_p" == "CLAUDE.md" ]]; then
    capture "L1a updated" "$_p"
    exit 0
  fi

  # .claude-docs/*.md (L1b repo docs updated)
  if [[ "$_p" == *".claude-docs/"*".md" ]]; then
    capture "L1b updated" "$_p"
    exit 0
  fi
fi

exit 0
