#!/usr/bin/env bash
# bin/merge-settings.sh — programmatically merge hooks from settings.snippet.json
# into an existing settings.json without clobbering other keys.
#
# Usage:
#   bin/merge-settings.sh                       # source=../settings.snippet.json, target=~/.claude/settings.json
#   bin/merge-settings.sh --source S --target T # explicit paths
#   bin/merge-settings.sh --dry-run             # print merged JSON, write nothing
#
# Merge strategy: for each hook event in source, append matcher entries whose
# hook commands are not already present in target (idempotent). All other keys
# in target are preserved unchanged.
#
# Parser chain: python3 → node → jq
#   python3/node: full dedup (won't add duplicate hook commands within an event)
#   jq fallback: adds missing event keys; won't dedup commands within an event
#     that already exists in target (acceptable last resort).
#
# Output is validated before writing. Backs up target as .bak-<timestamp>.

set -euo pipefail

CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SRC_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

source_file="${SRC_ROOT}/settings.snippet.json"
target_file="${CLAUDE_HOME}/settings.json"
dry_run=0
TS=$(date +%Y%m%d-%H%M%S)

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)  source_file="$2"; shift 2 ;;
    --target)  target_file="$2"; shift 2 ;;
    --dry-run) dry_run=1; shift ;;
    *) printf 'Unknown arg: %s\n' "$1" >&2; exit 1 ;;
  esac
done

[[ -f "$source_file" ]] || { printf 'Error: source not found: %s\n' "$source_file" >&2; exit 1; }
[[ -f "$target_file" ]] || { printf 'Error: target not found: %s\n' "$target_file" >&2; exit 1; }

# --- Merge via best available parser ---

do_merge() {
  local src="$1" tgt="$2"

  if command -v python3 >/dev/null 2>&1; then
    python3 - "$src" "$tgt" <<'PYEOF'
import sys, json

def merge_hooks(tgt_hooks, src_hooks):
    result = dict(tgt_hooks)
    for event, entries in src_hooks.items():
        if event not in result:
            result[event] = entries
            continue
        existing = {h.get('command', '')
                    for grp in result[event]
                    for h in grp.get('hooks', [])}
        for entry in entries:
            new_cmds = {h.get('command', '') for h in entry.get('hooks', [])}
            if not new_cmds.issubset(existing):
                result[event].append(entry)
    return result

src = json.load(open(sys.argv[1]))
tgt = json.load(open(sys.argv[2]))
merged = dict(tgt)
if 'hooks' in src:
    merged['hooks'] = merge_hooks(tgt.get('hooks', {}), src['hooks'])
print(json.dumps(merged, indent=2))
PYEOF
    return $?
  fi

  if command -v node >/dev/null 2>&1; then
    node - "$src" "$tgt" <<'JSEOF'
const fs = require('fs');
const src = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const tgt = JSON.parse(fs.readFileSync(process.argv[3], 'utf8'));

function mergeHooks(tgtH, srcH) {
  const result = Object.assign({}, tgtH);
  for (const [event, entries] of Object.entries(srcH)) {
    if (!result[event]) { result[event] = entries; continue; }
    const existing = new Set(
      result[event].flatMap(g => (g.hooks || []).map(h => h.command || ''))
    );
    for (const entry of entries) {
      const newCmds = (entry.hooks || []).map(h => h.command || '');
      if (!newCmds.every(c => existing.has(c))) result[event].push(entry);
    }
  }
  return result;
}

const merged = Object.assign({}, tgt);
if (src.hooks) merged.hooks = mergeHooks(tgt.hooks || {}, src.hooks);
console.log(JSON.stringify(merged, null, 2));
JSEOF
    return $?
  fi

  if command -v jq >/dev/null 2>&1; then
    # jq fallback: preserves existing event arrays, adds missing event keys from src.
    # Won't dedup hook commands within an event already present in target.
    jq --slurpfile src "$src" '
      . as $tgt |
      . + {hooks: ($src[0].hooks + ($tgt.hooks // {}))}
    ' "$tgt"
    return $?
  fi

  printf 'Error: python3, node, or jq required for JSON merge\n' >&2
  return 1
}

merged_json=$(do_merge "$source_file" "$target_file") || exit 1
[[ -n "$merged_json" ]] || { printf 'Error: merge produced empty output\n' >&2; exit 1; }

# --- Validate merged JSON ---

_valid=1
if command -v python3 >/dev/null 2>&1; then
  printf '%s' "$merged_json" | python3 -c "import sys,json; json.loads(sys.stdin.read())" 2>/dev/null \
    || _valid=0
elif command -v node >/dev/null 2>&1; then
  printf '%s' "$merged_json" | node -e "
    let s=''; process.stdin.on('data',d=>s+=d);
    process.stdin.on('end',()=>{try{JSON.parse(s)}catch(e){process.exit(1)}});
  " 2>/dev/null \
    || _valid=0
elif command -v jq >/dev/null 2>&1; then
  # jq-only systems take the jq merge path above — validate with jq too,
  # otherwise that output would be written entirely unvalidated.
  printf '%s' "$merged_json" | jq -e . >/dev/null 2>&1 || _valid=0
fi

if [[ $_valid -eq 0 ]]; then
  printf 'Error: merged output is invalid JSON — target file unchanged\n' >&2
  exit 1
fi

# --- Write ---

if [[ $dry_run -eq 1 ]]; then
  printf '[dry-run] Would write to %s:\n' "$target_file"
  printf '%s\n' "$merged_json"
  exit 0
fi

cp "$target_file" "${target_file}.bak-${TS}"
printf '%s\n' "$merged_json" > "$target_file"
printf '  ✓ Merged. Backup: %s.bak-%s\n' "$target_file" "$TS"
