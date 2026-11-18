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
# Sync pass (python3/node): a target group that holds exactly ONE hook, and that
# hook is one of ours (same command as a source entry), is brought up to date
# with the source — its `matcher` and any hook keys the source adds (e.g.
# `async`). Dedup is by command, so without this a changed matcher in the
# snippet would never reach an existing install. Groups a user has combined
# with other hooks are left alone.
#
# Exit codes: 0 merged and written (or dry-run printed) · 10 target already up
#             to date, nothing written · 1 error.
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

# Shared JSON validator (python3 → node → jq).
# shellcheck source=lib/validate-json.sh
source "${SCRIPT_DIR}/lib/validate-json.sh"

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

  # _cmd_runs (from validate-json.sh) probes that the interpreter actually runs,
  # not just that it is on PATH — dodges the Windows Store python3 stub.
  if _cmd_runs python3; then
    python3 - "$src" "$tgt" <<'PYEOF'
import sys, json, copy

def sync_group(grp, entry):
    """Bring a single-hook group of ours up to date with the source entry."""
    hooks = grp.get('hooks', [])
    src_hooks = entry.get('hooks', [])
    if len(hooks) != 1 or len(src_hooks) != 1:
        return
    if hooks[0].get('command', '') != src_hooks[0].get('command', ''):
        return
    if 'matcher' in entry:
        grp['matcher'] = entry['matcher']
    for k, v in src_hooks[0].items():
        hooks[0].setdefault(k, v)

def merge_hooks(tgt_hooks, src_hooks):
    result = copy.deepcopy(tgt_hooks)
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
            else:
                for grp in result[event]:
                    sync_group(grp, entry)
    return result

src = json.load(open(sys.argv[1]))
tgt = json.load(open(sys.argv[2]))
merged = dict(tgt)
if 'hooks' in src:
    merged['hooks'] = merge_hooks(tgt.get('hooks', {}), src['hooks'])
if merged == tgt:
    sys.exit(10)
print(json.dumps(merged, indent=2))
PYEOF
    return $?
  fi

  if _cmd_runs node; then
    node - "$src" "$tgt" <<'JSEOF'
const fs = require('fs');
const src = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const tgt = JSON.parse(fs.readFileSync(process.argv[3], 'utf8'));

// Bring a single-hook group of ours up to date with the source entry.
function syncGroup(grp, entry) {
  const hooks = grp.hooks || [];
  const srcHooks = entry.hooks || [];
  if (hooks.length !== 1 || srcHooks.length !== 1) return;
  if ((hooks[0].command || '') !== (srcHooks[0].command || '')) return;
  if ('matcher' in entry) grp.matcher = entry.matcher;
  for (const [k, v] of Object.entries(srcHooks[0])) {
    if (!(k in hooks[0])) hooks[0][k] = v;
  }
}

function mergeHooks(tgtH, srcH) {
  const result = JSON.parse(JSON.stringify(tgtH));
  for (const [event, entries] of Object.entries(srcH)) {
    if (!result[event]) { result[event] = entries; continue; }
    const existing = new Set(
      result[event].flatMap(g => (g.hooks || []).map(h => h.command || ''))
    );
    for (const entry of entries) {
      const newCmds = (entry.hooks || []).map(h => h.command || '');
      if (!newCmds.every(c => existing.has(c))) result[event].push(entry);
      else for (const grp of result[event]) syncGroup(grp, entry);
    }
  }
  return result;
}

const merged = Object.assign({}, tgt);
if (src.hooks) merged.hooks = mergeHooks(tgt.hooks || {}, src.hooks);
// Both passes preserve key order, so equal JSON text means nothing changed.
if (JSON.stringify(merged) === JSON.stringify(tgt)) process.exit(10);
console.log(JSON.stringify(merged, null, 2));
JSEOF
    return $?
  fi

  if _cmd_runs jq; then
    # jq fallback: preserves existing event arrays, adds missing event keys from src.
    # Won't dedup hook commands within an event already present in target.
    # No sync pass here — matcher/async migration needs python3 or node.
    local _jq_out
    _jq_out=$(jq --slurpfile src "$src" '
      . as $tgt |
      . + {hooks: ($src[0].hooks + ($tgt.hooks // {}))}
    ' "$tgt") || return 1
    if [[ "$(printf '%s' "$_jq_out" | jq -S -c . 2>/dev/null)" == "$(jq -S -c . "$tgt" 2>/dev/null)" ]]; then
      return 10
    fi
    printf '%s\n' "$_jq_out"
    return 0
  fi

  printf 'Error: python3, node, or jq required for JSON merge\n' >&2
  return 1
}

_merge_rc=0
merged_json=$(do_merge "$source_file" "$target_file") || _merge_rc=$?
if [[ $_merge_rc -eq 10 ]]; then
  printf '  = %s already up to date (no hook changes)\n' "$target_file"
  exit 10
fi
[[ $_merge_rc -eq 0 ]] || exit 1
[[ -n "$merged_json" ]] || { printf 'Error: merge produced empty output\n' >&2; exit 1; }

# --- Validate merged JSON ---

# rc 1 = invalid; rc 2 (no parser) can't happen here — do_merge already
# required python3/node/jq — so treat only rc 1 as a validation failure.
_valid=1
_vrc=0
printf '%s' "$merged_json" | _validate_json_stream || _vrc=$?
[[ ${_vrc:-0} -eq 1 ]] && _valid=0

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
