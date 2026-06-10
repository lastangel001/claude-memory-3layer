#!/usr/bin/env bash
# PostToolUse hook — selectively auto-captures high-signal tool events to SESSION.md.
#
# Captured patterns (minimal, low-noise):
#   Bash  + "git commit" in command → Decisions entry with commit message
#   Write to **/CLAUDE.md           → Decisions entry (L1a in-repo update)
#   Write to **/.claude-docs/*.md   → Decisions entry (L1b doc update)
#
# Everything else: silently ignored. Hook never blocks, never errors visibly.
# Output: none (no hookSpecificOutput needed — we write directly to SESSION.md).

set -euo pipefail

CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
mkdir -p "$CLAUDE_HOME/debug" 2>/dev/null || true

# ERR trap — log failure and exit cleanly (hook must never block tool execution).
_hook_error() {
  local rc=$1 lineno=$2
  echo "[$(date -Iseconds)] PostToolUse ERROR rc=${rc} line=${lineno}" \
    >> "$CLAUDE_HOME/debug/hook-trace.log" 2>/dev/null || :
  exit 0
}
trap '_hook_error $? "${BASH_LINENO[0]}"' ERR

# Read stdin once
input=$(cat)
if [[ -z "$input" ]]; then exit 0; fi

# --- Parse JSON (python3 preferred; node fallback; jq fallback; grep last-resort) ---

tool_name=""
tool_path=""
tool_cmd=""

if command -v python3 >/dev/null 2>&1; then
  parsed=$(printf '%s' "$input" | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
    name = d.get("tool_name", "")
    inp  = d.get("tool_input", {})
    path = inp.get("file_path", "")
    cmd  = inp.get("command", "")
    sys.stdout.write(name + "\x01" + path + "\x01" + cmd)
except Exception:
    sys.stdout.write("\x01\x01")
' 2>/dev/null || true)
  IFS=$'\x01' read -r tool_name tool_path tool_cmd <<< "$parsed"
elif command -v node >/dev/null 2>&1; then
  parsed=$(printf '%s' "$input" | node -e "
    let s='';
    process.stdin.on('data', d => s += d);
    process.stdin.on('end', () => {
      try {
        const d = JSON.parse(s);
        const inp = d.tool_input || {};
        process.stdout.write(
          (d.tool_name||'') + '\x01' +
          (inp.file_path||'') + '\x01' +
          (inp.command||'')
        );
      } catch(e) { process.stdout.write('\x01\x01'); }
    });
  " 2>/dev/null)
  IFS=$'\x01' read -r tool_name tool_path tool_cmd <<< "$parsed"
elif command -v jq >/dev/null 2>&1; then
  tool_name=$(printf '%s' "$input" | jq -r '.tool_name           // ""' 2>/dev/null || true)
  tool_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // ""' 2>/dev/null || true)
  tool_cmd=$(printf '%s' "$input"  | jq -r '.tool_input.command   // ""' 2>/dev/null || true)
else
  # Minimal grep fallback — breaks on escaped quotes or multi-line JSON values.
  # Install python3, node, or jq for robust parsing; doctor.sh will warn if none present.
  echo "[$(date -Iseconds)] PostToolUse: WARNING — using grep fallback (install python3/node/jq for robust parsing)" \
    >> "$CLAUDE_HOME/debug/hook-trace.log" 2>/dev/null || true
  tool_name=$(printf '%s' "$input" | grep -o '"tool_name":"[^"]*"' | head -n1 | cut -d'"' -f4 || true)
  tool_path=$(printf '%s' "$input" | grep -o '"file_path":"[^"]*"' | head -n1 | cut -d'"' -f4 || true)
  tool_cmd=$(printf '%s' "$input"  | grep -o '"command":"[^"]*"'   | head -n1 | cut -d'"' -f4 || true)
fi

if [[ -z "$tool_name" ]]; then exit 0; fi

# --- Compute slug + session file path ---
# shellcheck source=../bin/lib/slug.sh
source "${CLAUDE_HOME}/bin/lib/slug.sh"
_compute_slug

session_file="$CLAUDE_HOME/projects/${slug}/memory/SESSION.md"

# No SESSION.md yet means no substantive work started — nothing to capture.
if [[ ! -f "$session_file" ]]; then exit 0; fi

# --- Append a line to SESSION.md ---
# Simple append: model integrates these into proper sections on next update.
# Format: "- [HH:MM] [auto] label: detail"

ts=$(date -u +%H:%M 2>/dev/null || echo "??:??")

capture() {
  local label="$1" detail="$2"
  printf -- '- [%s] [auto] %s: %s\n' "$ts" "$label" "$detail" >> "$session_file" 2>/dev/null || true
  echo "[$(date -Iseconds)] PostToolUse captured: ${label}: ${detail}" \
    >> "$CLAUDE_HOME/debug/hook-trace.log" 2>/dev/null || true
}

# --- Pattern matching ---

# git commit (Bash tool)
if [[ "$tool_name" == "Bash" && "$tool_cmd" == *"git commit"* ]]; then
  # Extract -m message if present; keep it short (first 72 chars)
  msg=$(printf '%s' "$tool_cmd" \
    | grep -oP '(?<=-m ["\x27])[^"\x27]+' 2>/dev/null \
    | head -n1 \
    | cut -c1-72 || true)
  [[ -z "$msg" ]] && msg="(see git log)"
  capture "git commit" "$msg"
  exit 0
fi

# Write to CLAUDE.md (L1a in-repo entry point updated)
if [[ "$tool_name" == "Write" && ( "$tool_path" == *"/CLAUDE.md" || "$tool_path" == "CLAUDE.md" ) ]]; then
  capture "L1a updated" "$tool_path"
  exit 0
fi

# Write to .claude-docs/*.md (L1b repo docs updated)
if [[ "$tool_name" == "Write" && "$tool_path" == *".claude-docs/"*".md" ]]; then
  capture "L1b updated" "$tool_path"
  exit 0
fi

exit 0
