#!/usr/bin/env bash
# uninstall.sh — remove claude-memory-3layer, restore default Claude Code memory.
#
# Removes: the three hooks, our slash commands, bin scripts + libs, templates,
# the protocol at ~/.claude/CLAUDE.md, version markers, and strips ONLY our hook
# commands from settings.json (foreign tools' hooks on the same events are kept).
#
# PRESERVES (your data — never touched):
#   ~/.claude/memory/IDENTITY.md      (L0)
#   ~/.claude/projects/               (L1-fallback + L2 sessions + transcripts)
#
# Usage:
#   bash ~/.claude/bin/uninstall.sh              # interactive confirm
#   bash ~/.claude/bin/uninstall.sh --yes        # no prompt
#   bash ~/.claude/bin/uninstall.sh --dry-run    # preview, remove nothing
#
# Removing the hooks block from settings.json restores Claude Code's built-in
# memory behavior automatically.

set -e

CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
TS=$(date +%Y%m%d-%H%M%S)
DRY_RUN=0
ASSUME_YES=0

# _cmd_runs: probes that an interpreter actually RUNS (dodges the Windows Store
# python3 stub). Sourced now, while the lib still exists — this script deletes it
# later. Tolerate absence (partial install) so uninstall never hard-fails here.
# shellcheck source=lib/validate-json.sh
source "$CLAUDE_HOME/bin/lib/validate-json.sh" 2>/dev/null || _cmd_runs() { command -v "$1" >/dev/null 2>&1; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --yes|-y)  ASSUME_YES=1; shift ;;
    *) printf 'Unknown arg: %s\n' "$1" >&2; exit 1 ;;
  esac
done

say() { printf '%s\n' "$*"; }
rm_file() {
  local f="$1"
  [[ -e "$f" ]] || return 0
  if [[ $DRY_RUN -eq 1 ]]; then say "  [dry] rm $f"; else rm -f "$f" && say "  - removed $f"; fi
}

# Files install.sh lays down (kept in sync with install.sh).
HOOKS=(session-start.sh pre-compact.sh post-tool-use.sh)
COMMANDS=(recall.md codemap.md memory.md memstat.md onboard-memory.md
          migrate-legacy-memory.md session-end.md)
BINS=(codemap.sh doctor.sh memstat.sh merge-settings.sh onboard-report.sh
      transcript-export.sh update.sh mcp-recall.mjs vault-doctor.sh
      gen-index.sh uninstall.sh)
LIBS=(slug.sh paths.sh validate-json.sh)

say ""
say "=== claude-memory-3layer uninstaller ==="
say "CLAUDE_HOME: $CLAUDE_HOME"
[[ $DRY_RUN -eq 1 ]] && say "[DRY RUN — nothing will be removed]"
say ""
say "Will remove hooks, commands, bin scripts, templates, protocol, markers."
say "Will PRESERVE memory/IDENTITY.md and projects/ (your data)."
say ""

if [[ $DRY_RUN -eq 0 && $ASSUME_YES -eq 0 ]]; then
  printf 'Proceed? [y/N] '
  read -r _ans
  case "$_ans" in
    y|Y|yes|YES) ;;
    *) say "Aborted."; exit 0 ;;
  esac
  say ""
fi

# --- Strip our hooks from settings.json (keep foreign hooks + other keys) ---
say "settings.json:"
settings="$CLAUDE_HOME/settings.json"
if [[ -f "$settings" ]]; then
  if [[ $DRY_RUN -eq 1 ]]; then
    say "  [dry] strip our hook commands, backup -> $settings.bak-$TS"
  else
    cp "$settings" "$settings.bak-$TS"
    _stripped=""
    if _cmd_runs python3; then
      _stripped=$(python3 - "$settings" <<'PYEOF' 2>/dev/null || true
import sys, json
ours = ("hooks/session-start.sh", "hooks/pre-compact.sh", "hooks/post-tool-use.sh")
d = json.load(open(sys.argv[1]))
hooks = d.get("hooks", {})
for event in list(hooks.keys()):
    newgroups = []
    for grp in hooks[event]:
        kept = [h for h in grp.get("hooks", []) if not any(o in h.get("command", "") for o in ours)]
        if kept:
            grp["hooks"] = kept
            newgroups.append(grp)
    if newgroups:
        hooks[event] = newgroups
    else:
        del hooks[event]
if hooks:
    d["hooks"] = hooks
elif "hooks" in d:
    del d["hooks"]
print(json.dumps(d, indent=2))
PYEOF
)
    elif _cmd_runs node; then
      _stripped=$(node - "$settings" <<'JSEOF' 2>/dev/null || true
const fs = require('fs');
const ours = ["hooks/session-start.sh", "hooks/pre-compact.sh", "hooks/post-tool-use.sh"];
const d = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const hooks = d.hooks || {};
for (const event of Object.keys(hooks)) {
  const ng = [];
  for (const grp of hooks[event]) {
    const kept = (grp.hooks || []).filter(h => !ours.some(o => (h.command||'').includes(o)));
    if (kept.length) { grp.hooks = kept; ng.push(grp); }
  }
  if (ng.length) hooks[event] = ng; else delete hooks[event];
}
if (Object.keys(hooks).length) d.hooks = hooks; else delete d.hooks;
console.log(JSON.stringify(d, null, 2));
JSEOF
)
    fi
    if [[ -n "$_stripped" ]]; then
      printf '%s\n' "$_stripped" > "$settings"
      say "  ~ stripped our hooks (backup: $settings.bak-$TS)"
    else
      say "  ⚠ could not auto-edit settings.json (no working python3/node) — remove the"
      say "    hooks block referencing hooks/*.sh manually. Backup: $settings.bak-$TS"
    fi
  fi
else
  say "  = no settings.json"
fi
say ""

# --- Remove installed files ---
say "Removing files:"
for h in "${HOOKS[@]}";    do rm_file "$CLAUDE_HOME/hooks/$h"; done
for c in "${COMMANDS[@]}"; do rm_file "$CLAUDE_HOME/commands/$c"; done
for b in "${BINS[@]}";     do rm_file "$CLAUDE_HOME/bin/$b"; done
for l in "${LIBS[@]}";     do rm_file "$CLAUDE_HOME/bin/lib/$l"; done
rm_file "$CLAUDE_HOME/CLAUDE.md"
rm_file "$CLAUDE_HOME/memory/IDENTITY.template.md"
rm_file "$CLAUDE_HOME/.memory-version"
rm_file "$CLAUDE_HOME/.memory-source"
rm_file "$CLAUDE_HOME/.qmd-last-refresh"
rm_file "$CLAUDE_HOME/templates/project.md.fallback.template"
if [[ $DRY_RUN -eq 1 ]]; then
  say "  [dry] rm -rf $CLAUDE_HOME/templates/protocol $CLAUDE_HOME/templates/repo"
else
  rm -rf "$CLAUDE_HOME/templates/protocol" "$CLAUDE_HOME/templates/repo" 2>/dev/null || true
  say "  - removed templates/protocol + templates/repo"
  # Remove templates/ only if now empty.
  rmdir "$CLAUDE_HOME/templates" 2>/dev/null && say "  - removed empty templates/" || true
fi
say ""

# --- Preserved + manual notes ---
say "Preserved (your data):"
say "  = $CLAUDE_HOME/memory/IDENTITY.md"
say "  = $CLAUDE_HOME/projects/  (sessions, project memory, transcripts)"
say ""
if grep -q '"memory-recall"' "$HOME/.claude.json" 2>/dev/null; then
  say "MCP server still registered. Remove with:"
  say "  claude mcp remove --scope user memory-recall"
  say ""
fi
say "=== Done$([[ $DRY_RUN -eq 1 ]] && echo ' (dry run)') ==="
say "Default Claude Code memory behavior is restored (our hooks are gone)."
