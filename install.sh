#!/usr/bin/env bash
# install.sh — claude-memory-3layer installer.
#
# Idempotent and upgrade-safe:
# - First install: lays out everything cleanly
# - Upgrade: backs up changed files with .bak-<timestamp>, NEVER overwrites
#   your IDENTITY.md (L0 user data) or projects/ tree (L1-fallback + L2)
# - Detects existing settings.json and auto-merges missing hooks via
#   bin/merge-settings.sh (backs up first, never clobbers other keys)
#
# Usage:
#   ./install.sh            # installs to ~/.claude (or $CLAUDE_HOME if set)
#   ./install.sh --dry-run  # show what would change, write nothing

set -e

CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
TS=$(date +%Y%m%d-%H%M%S)
SRC=$(cd "$(dirname "$0")" && pwd)
DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

# --- Helpers ---

say() { printf '%s\n' "$*"; }
# shellcheck disable=SC2294  # eval-as-string is the point: callers pass pre-quoted commands
do_or_dry() { if [[ $DRY_RUN -eq 1 ]]; then say "  [dry] $*"; else eval "$@"; fi; }

backup_and_install() {
  local src="$1" dst="$2"
  if [[ -f "$dst" ]]; then
    if cmp -s "$src" "$dst"; then
      say "  = $dst (unchanged)"
      return 0
    fi
    do_or_dry "cp '$dst' '$dst.bak-$TS'"
    say "  ~ $dst (backed up -> $dst.bak-$TS)"
  else
    say "  + $dst (new)"
  fi
  do_or_dry "mkdir -p '$(dirname "$dst")'"
  do_or_dry "cp '$src' '$dst'"
}

# --- Detect mode ---

mode="first-install"
[[ -f "$CLAUDE_HOME/CLAUDE.md" ]] && mode="upgrade"

say "=== claude-memory-3layer installer ==="
say "Source:      $SRC"
say "Destination: $CLAUDE_HOME"
say "Mode:        $mode"
[[ $DRY_RUN -eq 1 ]] && say "[DRY RUN — no changes will be written]"
say ""

# --- Layout ---

if [[ $DRY_RUN -eq 0 ]]; then
  mkdir -p "$CLAUDE_HOME/hooks" "$CLAUDE_HOME/memory" "$CLAUDE_HOME/commands" \
           "$CLAUDE_HOME/bin"   "$CLAUDE_HOME/bin/lib" \
           "$CLAUDE_HOME/debug" "$CLAUDE_HOME/logs"
fi

# --- Protocol + tooling (safe to overwrite, backup if differs) ---

say "Protocol + tools:"
# PROTOCOL.md is the slim always-loaded core; fat reference sections live in
# templates/protocol/ and are read on demand (v6.16.0 token-budget split).
backup_and_install "$SRC/PROTOCOL.md"                  "$CLAUDE_HOME/CLAUDE.md"
backup_and_install "$SRC/hooks/session-start.sh"       "$CLAUDE_HOME/hooks/session-start.sh"
backup_and_install "$SRC/hooks/pre-compact.sh"         "$CLAUDE_HOME/hooks/pre-compact.sh"
backup_and_install "$SRC/hooks/post-tool-use.sh"       "$CLAUDE_HOME/hooks/post-tool-use.sh"
backup_and_install "$SRC/commands/recall.md"           "$CLAUDE_HOME/commands/recall.md"
backup_and_install "$SRC/commands/codemap.md"          "$CLAUDE_HOME/commands/codemap.md"
backup_and_install "$SRC/commands/memory.md"           "$CLAUDE_HOME/commands/memory.md"
backup_and_install "$SRC/commands/memstat.md"          "$CLAUDE_HOME/commands/memstat.md"
backup_and_install "$SRC/commands/onboard-memory.md"   "$CLAUDE_HOME/commands/onboard-memory.md"
backup_and_install "$SRC/commands/migrate-legacy-memory.md" "$CLAUDE_HOME/commands/migrate-legacy-memory.md"
backup_and_install "$SRC/bin/codemap.sh"               "$CLAUDE_HOME/bin/codemap.sh"
backup_and_install "$SRC/bin/doctor.sh"                "$CLAUDE_HOME/bin/doctor.sh"
backup_and_install "$SRC/bin/memstat.sh"               "$CLAUDE_HOME/bin/memstat.sh"
backup_and_install "$SRC/bin/merge-settings.sh"        "$CLAUDE_HOME/bin/merge-settings.sh"
backup_and_install "$SRC/bin/onboard-report.sh"        "$CLAUDE_HOME/bin/onboard-report.sh"
backup_and_install "$SRC/bin/transcript-export.sh"     "$CLAUDE_HOME/bin/transcript-export.sh"
backup_and_install "$SRC/bin/update.sh"                "$CLAUDE_HOME/bin/update.sh"
backup_and_install "$SRC/bin/mcp-recall.mjs"           "$CLAUDE_HOME/bin/mcp-recall.mjs"
backup_and_install "$SRC/bin/lib/slug.sh"              "$CLAUDE_HOME/bin/lib/slug.sh"
backup_and_install "$SRC/bin/lib/paths.sh"             "$CLAUDE_HOME/bin/lib/paths.sh"

# Templates (referenced by CLAUDE.md protocol + /onboard-memory)
if [[ $DRY_RUN -eq 0 ]]; then
  mkdir -p "$CLAUDE_HOME/templates/repo/.claude-docs" "$CLAUDE_HOME/templates/protocol"
fi
backup_and_install "$SRC/templates/project.md.fallback.template" "$CLAUDE_HOME/templates/project.md.fallback.template"
backup_and_install "$SRC/templates/repo/CLAUDE.md"               "$CLAUDE_HOME/templates/repo/CLAUDE.md"
for _t in "$SRC/templates/repo/.claude-docs/"*.md; do
  [[ -f "$_t" ]] || continue  # unmatched glob (broken/partial archive) — skip, don't crash
  backup_and_install "$_t" "$CLAUDE_HOME/templates/repo/.claude-docs/$(basename "$_t")"
done
# Protocol reference docs (read on demand — pointed at by the slim core)
for _t in "$SRC/templates/protocol/"*.md; do
  [[ -f "$_t" ]] || continue
  backup_and_install "$_t" "$CLAUDE_HOME/templates/protocol/$(basename "$_t")"
done

if [[ $DRY_RUN -eq 0 ]]; then
  chmod +x "$CLAUDE_HOME/hooks/"*.sh "$CLAUDE_HOME/bin/"*.sh \
            "$CLAUDE_HOME/bin/lib/"*.sh 2>/dev/null || true
fi
say ""

# --- IDENTITY.md (L0 — USER DATA, NEVER overwrite) ---

say "L0 identity:"
if [[ ! -f "$CLAUDE_HOME/memory/IDENTITY.md" ]]; then
  do_or_dry "cp '$SRC/memory/IDENTITY.md' '$CLAUDE_HOME/memory/IDENTITY.md'"
  say "  + $CLAUDE_HOME/memory/IDENTITY.md (template, please edit)"
  say "  ★ EDIT THIS FILE (hard cap 25 lines: who you are, OS, prefs, env creds)"
else
  do_or_dry "cp '$SRC/memory/IDENTITY.md' '$CLAUDE_HOME/memory/IDENTITY.template.md'"
  say "  = $CLAUDE_HOME/memory/IDENTITY.md (preserved — your data)"
  say "    reference template available at: $CLAUDE_HOME/memory/IDENTITY.template.md"
fi
say ""

# --- settings.json (NEVER auto-merge, just guide) ---

say "settings.json:"
if [[ ! -f "$CLAUDE_HOME/settings.json" ]]; then
  do_or_dry "cp '$SRC/settings.snippet.json' '$CLAUDE_HOME/settings.json'"
  say "  + $CLAUDE_HOME/settings.json (fresh, with hooks)"
else
  # Detect by OUR hook command, not by event name — the user may have other
  # tools' hooks registered on the same events (false "all hooks present").
  missing_hooks=()
  grep -q 'hooks/session-start.sh' "$CLAUDE_HOME/settings.json" 2>/dev/null || missing_hooks+=("SessionStart")
  grep -q 'hooks/pre-compact.sh'   "$CLAUDE_HOME/settings.json" 2>/dev/null || missing_hooks+=("PreCompact")
  grep -q 'hooks/post-tool-use.sh' "$CLAUDE_HOME/settings.json" 2>/dev/null || missing_hooks+=("PostToolUse")
  if [[ ${#missing_hooks[@]} -eq 0 ]]; then
    say "  = $CLAUDE_HOME/settings.json (all hooks present)"
  else
    say "  ⚠ $CLAUDE_HOME/settings.json missing: ${missing_hooks[*]}"
    say "    Auto-merging hooks..."
    _merge_ok=0
    if [[ $DRY_RUN -eq 1 ]]; then
      do_or_dry "bash '$SRC/bin/merge-settings.sh' --source '$SRC/settings.snippet.json' --target '$CLAUDE_HOME/settings.json'"
      _merge_ok=1
    else
      if bash "$SRC/bin/merge-settings.sh" \
           --source "$SRC/settings.snippet.json" \
           --target "$CLAUDE_HOME/settings.json"; then
        _merge_ok=1
      fi
    fi
    if [[ $_merge_ok -eq 0 ]]; then
      say "  ✗ Auto-merge failed. Fix manually:"
      say "    Merge 'hooks' block from $SRC/settings.snippet.json into $CLAUDE_HOME/settings.json"
    fi
  fi
fi
say ""

# --- L1-fallback + L2 (NEVER touch) ---

say "L1-fallback + L2 sessions:"
say "  = $CLAUDE_HOME/projects/ (untouched — your project + session memory)"
say ""

# --- Version tracking ---

say "Version tracking:"
_ver=$(grep -m1 '^## v' "$SRC/CHANGELOG.md" 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -n1)
if [[ -n "$_ver" ]]; then
  do_or_dry "printf '%s\n' '$_ver' > '$CLAUDE_HOME/.memory-version'"
  say "  + .memory-version = $_ver"
fi
do_or_dry "printf '%s\n' '$SRC' > '$CLAUDE_HOME/.memory-source'"
say "  + .memory-source  = $SRC"
say ""

# --- Backup summary ---

backups=$(find "$CLAUDE_HOME" -name "*.bak-$TS" 2>/dev/null | sort)
if [[ -n "$backups" ]]; then
  say "Backups created (timestamp $TS):"
  while IFS= read -r b; do say "  - $b"; done <<< "$backups"
  say ""
fi

# --- Next steps ---

# --- Pre-flight validation ---

if [[ $DRY_RUN -eq 0 ]]; then
  say "Validation:"

  # 1. settings.json is valid JSON
  # Pipe via stdin — Windows-native node/python can't resolve MSYS '/c/...' paths
  # passed as string args (false "invalid JSON"). bash resolves the path for cat.
  if command -v node >/dev/null 2>&1; then
    if cat "$CLAUDE_HOME/settings.json" | node -e "JSON.parse(require('fs').readFileSync(0,'utf8'))" 2>/dev/null; then
      say "  ✓ settings.json valid JSON"
    else
      say "  ✗ settings.json invalid JSON — fix before starting Claude Code"
    fi
  elif command -v python3 >/dev/null 2>&1; then
    if cat "$CLAUDE_HOME/settings.json" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
      say "  ✓ settings.json valid JSON"
    else
      say "  ✗ settings.json invalid JSON — fix before starting Claude Code"
    fi
  else
    say "  ? settings.json not validated (node/python3 not found)"
  fi

  # 2. Hook syntax check
  for h in session-start.sh pre-compact.sh post-tool-use.sh; do
    hf="$CLAUDE_HOME/hooks/$h"
    if [[ -f "$hf" ]]; then
      if bash -n "$hf" 2>/dev/null; then
        say "  ✓ hooks/$h syntax OK"
      else
        say "  ✗ hooks/$h syntax error — run: bash -n $hf"
      fi
    fi
  done

  # 3. Hook files executable
  for h in "$CLAUDE_HOME/hooks/"*.sh; do
    [[ -f "$h" && ! -x "$h" ]] && say "  ✗ $(basename "$h") not executable — run: chmod +x $h"
  done

  say "  Run 'bash ~/.claude/bin/doctor.sh' anytime for a full health check."
  say ""
fi

say "=== Done ($mode) ==="
say ""
say "Next steps:"
if [[ ! -f "$CLAUDE_HOME/memory/IDENTITY.md" ]] || \
   grep -q "<your name" "$CLAUDE_HOME/memory/IDENTITY.md" 2>/dev/null; then
  say "  - Edit $CLAUDE_HOME/memory/IDENTITY.md (≤25 lines)"
fi
# MCP hint: opt-in by design (tool defs cost context in every session), but
# remind when not yet registered. User-scope MCP config lives in ~/.claude.json
# (fixed location, independent of CLAUDE_HOME).
if ! grep -q '"memory-recall"' "$HOME/.claude.json" 2>/dev/null; then
  say "  - Optional: memory search for subagents/headless (one-time, this machine):"
  say "      claude mcp add --scope user memory-recall -- node $CLAUDE_HOME/bin/mcp-recall.mjs"
fi
say "  - Optional: install retrieval tools (qmd, ctags, ripgrep) — see INSTALL.md"
say "  - Start a new Claude Code session — hooks fire automatically"
say ""
say "To rollback to backed-up versions:"
say "  for f in $CLAUDE_HOME/**/*.bak-$TS; do mv \"\$f\" \"\${f%.bak-$TS}\"; done"
