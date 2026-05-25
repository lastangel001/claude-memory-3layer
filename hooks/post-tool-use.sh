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

CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
mkdir -p "$CLAUDE_HOME/debug" 2>/dev/null

# Read stdin once
input=$(cat 2>/dev/null)
[[ -z "$input" ]] && exit 0

# --- Parse JSON (python3 preferred; node fallback; grep last-resort) ---

tool_name=""
tool_path=""
tool_cmd=""

if command -v python3 >/dev/null 2>&1; then
  parsed=$(printf '%s' "$input" | python3 - <<'PYEOF' 2>/dev/null
import sys, json
try:
    d = json.load(sys.stdin)
    name = d.get('tool_name', '')
    inp  = d.get('tool_input', {})
    path = inp.get('file_path', '')
    cmd  = inp.get('command', '')
    print(name + '\x00' + path + '\x00' + cmd)
except Exception:
    print('\x00\x00')
PYEOF
  )
  IFS=$'\x00' read -r tool_name tool_path tool_cmd <<< "$parsed"
elif command -v node >/dev/null 2>&1; then
  parsed=$(printf '%s' "$input" | node -e "
    let s='';
    process.stdin.on('data', d => s += d);
    process.stdin.on('end', () => {
      try {
        const d = JSON.parse(s);
        const inp = d.tool_input || {};
        process.stdout.write(
          (d.tool_name||'') + '\x00' +
          (inp.file_path||'') + '\x00' +
          (inp.command||'')
        );
      } catch(e) { process.stdout.write('\x00\x00'); }
    });
  " 2>/dev/null)
  IFS=$'\x00' read -r tool_name tool_path tool_cmd <<< "$parsed"
else
  # Minimal grep fallback — covers common single-line JSON formats
  tool_name=$(printf '%s' "$input" | grep -o '"tool_name":"[^"]*"' | head -n1 | cut -d'"' -f4)
  tool_path=$(printf '%s' "$input" | grep -o '"file_path":"[^"]*"' | head -n1 | cut -d'"' -f4)
  tool_cmd=$(printf '%s' "$input" | grep -o '"command":"[^"]*"' | head -n1 | cut -d'"' -f4)
fi

[[ -z "$tool_name" ]] && exit 0

# --- Compute slug + session file path (same logic as session-start.sh) ---

slug=""
cwd_unix="$PWD"
if [[ "$cwd_unix" =~ ^/([a-zA-Z])/(.*)$ ]]; then
  drive="${BASH_REMATCH[1]^^}"
  rest="${BASH_REMATCH[2]}"
  slug="${drive}--${rest//\//-}"
elif [[ "$cwd_unix" =~ ^/([a-zA-Z])/?$ ]]; then
  drive="${BASH_REMATCH[1]^^}"
  slug="${drive}-"
else
  slug="${cwd_unix//\//-}"
  slug="${slug#-}"
fi

session_file="$CLAUDE_HOME/projects/${slug}/memory/SESSION.md"

# No SESSION.md yet means no substantive work started — nothing to capture.
[[ ! -f "$session_file" ]] && exit 0

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
    | cut -c1-72)
  [[ -z "$msg" ]] && msg="(see git log)"
  capture "git commit" "$msg"
  exit 0
fi

# Write to CLAUDE.md (L1a in-repo entry point updated)
if [[ "$tool_name" == "Write" && "$tool_path" == *"/CLAUDE.md" || "$tool_path" == "CLAUDE.md" ]]; then
  capture "L1a updated" "$tool_path"
  exit 0
fi

# Write to .claude-docs/*.md (L1b repo docs updated)
if [[ "$tool_name" == "Write" && "$tool_path" == *".claude-docs/"*".md" ]]; then
  capture "L1b updated" "$tool_path"
  exit 0
fi

exit 0
