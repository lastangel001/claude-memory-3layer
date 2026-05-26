#!/usr/bin/env bash
# doctor.sh — post-install health check for claude-memory-3layer.
#
# Usage:
#   bash ~/.claude/bin/doctor.sh          # check current install
#   CLAUDE_HOME=/custom/path bash doctor  # check custom install location
#
# Exits 0 if all critical checks pass; 1 if any critical check fails.

CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"

pass=0
fail=0
warn=0

ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; ((pass++)); }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*"; ((fail++)); }
warn() { printf '  \033[33m?\033[0m %s\n' "$*"; ((warn++)); }

say()  { printf '%s\n' "$*"; }

say ""
say "=== claude-memory-3layer doctor ==="
say "CLAUDE_HOME: $CLAUDE_HOME"
say ""

# ─────────────────────────────────────────────
# 1. Hook files
# ─────────────────────────────────────────────
say "Hook files:"
for h in session-start.sh pre-compact.sh post-tool-use.sh; do
  f="$CLAUDE_HOME/hooks/$h"
  if [[ ! -f "$f" ]]; then
    fail "$f — NOT FOUND (run install.sh)"
  elif [[ ! -x "$f" ]]; then
    fail "$f — not executable (run: chmod +x $f)"
  elif ! bash -n "$f" 2>/dev/null; then
    fail "$f — syntax error (run: bash -n $f)"
  else
    ok "$f"
  fi
done
say ""

# ─────────────────────────────────────────────
# 2. settings.json — hooks registered
# ─────────────────────────────────────────────
say "settings.json:"
sf="$CLAUDE_HOME/settings.json"
if [[ ! -f "$sf" ]]; then
  fail "$sf — NOT FOUND (run install.sh)"
else
  # Validate JSON
  json_ok=0
  if command -v node >/dev/null 2>&1; then
    node -e "JSON.parse(require('fs').readFileSync('$sf','utf8'))" 2>/dev/null && json_ok=1
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c "import json; json.load(open('$sf'))" 2>/dev/null && json_ok=1
  fi
  if [[ $json_ok -eq 1 ]]; then
    ok "$sf valid JSON"
  elif [[ $json_ok -eq 0 ]]; then
    fail "$sf invalid JSON — Claude Code will ignore all hooks"
  else
    warn "$sf JSON not validated (node/python3 not found)"
  fi

  # Check each hook is registered
  for hook in SessionStart PreCompact PostToolUse; do
    if grep -q "\"$hook\"" "$sf" 2>/dev/null; then
      ok "$hook registered"
    else
      fail "$hook NOT in settings.json (merge from settings.snippet.json)"
    fi
  done
fi
say ""

# ─────────────────────────────────────────────
# 3. Core memory files
# ─────────────────────────────────────────────
say "Memory files:"
id="$CLAUDE_HOME/memory/IDENTITY.md"
if [[ ! -f "$id" ]]; then
  fail "IDENTITY.md NOT FOUND — create at $id (≤25 lines)"
elif grep -q "<your name\|<fill" "$id" 2>/dev/null; then
  warn "IDENTITY.md still has placeholder text — edit it"
else
  ok "IDENTITY.md present"
fi
say ""

# ─────────────────────────────────────────────
# 4. Current project SESSION.md (optional)
# ─────────────────────────────────────────────
say "Current project:"
# shellcheck source=lib/slug.sh
source "${CLAUDE_HOME}/bin/lib/slug.sh"
_compute_slug
session_file="$CLAUDE_HOME/projects/${slug}/memory/SESSION.md"
if [[ ! -f "$session_file" ]]; then
  warn "No SESSION.md for current project (normal for new projects)"
else
  # Check last_updated present
  if grep -q 'last_updated:' "$session_file" 2>/dev/null; then
    lu=$(grep -oE 'last_updated:[[:space:]]*[0-9T:.Z+-]+' "$session_file" | head -n1 | sed 's/last_updated:[[:space:]]*//')
    ok "SESSION.md present, last_updated: $lu"
  else
    warn "SESSION.md missing last_updated — staleness check won't fire"
  fi
  # Check cwd field
  if grep -q '^cwd:' "$session_file" 2>/dev/null; then
    sc=$(sed -n 's/^cwd:[[:space:]]*//p' "$session_file" | head -n1 | tr -d '\r')
    ok "SESSION.md has cwd: $sc"
  else
    warn "SESSION.md missing cwd: field — CWD mismatch detection won't fire"
  fi
fi
say ""

# ─────────────────────────────────────────────
# 5. PATH sanity (Windows spaces-in-username)
# ─────────────────────────────────────────────
say "PATH sanity:"
_space_entries=$(printf '%s\n' "$PATH" | tr ':' '\n' | grep ' ' || true)
if [[ -n "$_space_entries" ]]; then
  warn "PATH entries with embedded spaces detected — may cause tool lookup failures on some shells:"
  while IFS= read -r _e; do warn "  '$_e'"; done <<< "$_space_entries"
  warn "  Usually caused by Windows username with spaces; hooks use _add_path() to normalize."
else
  ok "No spaces in PATH entries"
fi
say ""

# ─────────────────────────────────────────────
# 6. Optional retrieval tools
# ─────────────────────────────────────────────
say "Optional tools (needed for /recall and /codemap):"
command -v qmd   >/dev/null 2>&1 && ok "qmd on PATH"   || warn "qmd not found — /recall unavailable (see INSTALL.md)"
command -v ctags >/dev/null 2>&1 && ok "ctags on PATH" || warn "ctags not found — /codemap unavailable"
command -v rg    >/dev/null 2>&1 && ok "rg on PATH"    || warn "rg (ripgrep) not found — /codemap callers/callees unavailable"
say ""

# ─────────────────────────────────────────────
# 7. JSON parsers for PostToolUse hook
# ─────────────────────────────────────────────
say "JSON parsers (PostToolUse hook — python3 > node > jq > grep):"
_json_parser=""
command -v python3 >/dev/null 2>&1 && { ok "python3 on PATH"; _json_parser="${_json_parser:-python3}"; } || true
command -v node    >/dev/null 2>&1 && { ok "node on PATH";    _json_parser="${_json_parser:-node}";    } || true
command -v jq      >/dev/null 2>&1 && { ok "jq on PATH";      _json_parser="${_json_parser:-jq}";      } || true
if [[ -n "$_json_parser" ]]; then
  ok "PostToolUse will use: $_json_parser (robust JSON parsing)"
else
  fail "No JSON parser found (python3/node/jq) — grep fallback only; auto-capture may silently lose events on multi-line or escaped-quote JSON. Install any one."
fi
say ""

# ─────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────
say "─────────────────────────────────"
printf 'Pass: \033[32m%d\033[0m  Fail: \033[31m%d\033[0m  Warn: \033[33m%d\033[0m\n' "$pass" "$fail" "$warn"
say ""

if [[ $fail -gt 0 ]]; then
  say "Critical issues found. Run install.sh to fix, or resolve manually."
  exit 1
else
  say "All critical checks passed."
  exit 0
fi
