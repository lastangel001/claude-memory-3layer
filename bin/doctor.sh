#!/usr/bin/env bash
# doctor.sh — post-install health check for claude-memory-3layer.
#
# Usage:
#   bash ~/.claude/bin/doctor.sh          # check current install
#   CLAUDE_HOME=/custom/path bash doctor  # check custom install location
#
# Exits 0 if all critical checks pass; 1 if any critical check fails.

CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"

# Shared JSON validator (python3 → node → jq).
# shellcheck source=lib/validate-json.sh
source "${CLAUDE_HOME}/bin/lib/validate-json.sh"

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
# 0. Installed version + source
# ─────────────────────────────────────────────
say "Version:"
vf="$CLAUDE_HOME/.memory-version"
sf="$CLAUDE_HOME/.memory-source"
if [[ -f "$vf" ]]; then
  ok "Installed: $(tr -d '\r\n' < "$vf")"
else
  warn ".memory-version not found — run install.sh to register"
fi
if [[ -f "$sf" ]]; then
  _src_path=$(tr -d '\r\n' < "$sf")
  if [[ -d "$_src_path" ]]; then
    ok "Source: $_src_path"
  else
    warn "Source path missing: $_src_path (repo moved? re-clone and reinstall)"
  fi
else
  warn ".memory-source not found — run install.sh to register (update.sh won't work)"
fi
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
  # Validate JSON (shared lib feeds contents via stdin — Windows-native
  # node/python can't resolve MSYS '/c/...' path args, false "invalid JSON").
  _validate_json_file "$sf"; json_rc=$?
  if [[ $json_rc -eq 0 ]]; then
    ok "$sf valid JSON"
  elif [[ $json_rc -eq 1 ]]; then
    fail "$sf invalid JSON — Claude Code will ignore all hooks"
  else
    warn "$sf JSON not validated (python3/node/jq not found)"
  fi

  # Check each hook is registered
  for hook in SessionStart PreCompact PostToolUse; do
    if grep -q "\"$hook\"" "$sf" 2>/dev/null; then
      ok "$hook registered"
    else
      fail "$hook NOT in settings.json (merge from settings.snippet.json)"
    fi
  done

  # Duplicate hook registration — the same command wired more than once for
  # one event (repeated installs/merges) doubles token cost + execution every
  # session, invisibly. Needs a JSON parser to walk the structure.
  dup_report=""
  if _cmd_runs python3; then
    dup_report=$(python3 - "$sf" <<'PYEOF' 2>/dev/null || true
import sys, json
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
for event, groups in (d.get("hooks") or {}).items():
    seen = {}
    for grp in groups:
        for h in grp.get("hooks", []):
            c = h.get("command", "")
            if c:
                seen[c] = seen.get(c, 0) + 1
    for c, n in seen.items():
        if n > 1:
            print(f"{event}: {c} (x{n})")
PYEOF
)
  elif _cmd_runs node; then
    dup_report=$(node - "$sf" <<'JSEOF' 2>/dev/null || true
const fs = require('fs');
let d; try { d = JSON.parse(fs.readFileSync(process.argv[2], 'utf8')); } catch(e) { process.exit(0); }
for (const [event, groups] of Object.entries(d.hooks || {})) {
  const seen = {};
  for (const grp of groups) for (const h of (grp.hooks || [])) {
    const c = h.command || ''; if (c) seen[c] = (seen[c] || 0) + 1;
  }
  for (const [c, n] of Object.entries(seen)) if (n > 1) console.log(`${event}: ${c} (x${n})`);
}
JSEOF
)
  fi
  if [[ -n "$dup_report" ]]; then
    warn "Duplicate hook registrations (double token cost + execution per event):"
    while IFS= read -r _d; do [[ -n "$_d" ]] && warn "  $_d"; done <<< "$dup_report"
  else
    ok "No duplicate hook registrations"
  fi
fi
say ""

# ─────────────────────────────────────────────
# 2b. Installed hooks — CRLF + dynamic self-test
# ─────────────────────────────────────────────
say "Installed hooks runtime:"
# CRLF check — install.sh copies working-tree files verbatim; a CRLF-contaminated
# Windows checkout installs CRLF hooks. A stray \r either kills strict bash or
# mangles output silently (hooks swallow errors by design).
_crlf_found=0
for h in "$CLAUDE_HOME/hooks/"*.sh "$CLAUDE_HOME/bin/"*.sh "$CLAUDE_HOME/bin/lib/"*.sh; do
  [[ -f "$h" ]] || continue
  if grep -q $'\r' "$h" 2>/dev/null; then
    fail "$(basename "$h") has CRLF line endings — run: dos2unix '$h' (or re-checkout with LF)"
    _crlf_found=1
  fi
done
[[ $_crlf_found -eq 0 ]] && ok "No CRLF line endings in installed scripts"

# Dynamic self-test — run the INSTALLED session-start.sh in a throwaway
# CLAUDE_HOME/cwd and assert exit 0 + valid JSON output. bats covers the repo
# copy; this catches a broken runtime copy (bad merge, partial install, CRLF).
ss="$CLAUDE_HOME/hooks/session-start.sh"
if [[ -x "$ss" ]]; then
  _tmp_home=$(mktemp -d 2>/dev/null || echo "")
  _tmp_cwd=$(mktemp -d 2>/dev/null || echo "")
  if [[ -n "$_tmp_home" && -n "$_tmp_cwd" ]]; then
    mkdir -p "$_tmp_home/bin/lib" "$_tmp_home/debug" "$_tmp_home/logs" "$_tmp_home/projects"
    cp "$CLAUDE_HOME/bin/lib/"*.sh "$_tmp_home/bin/lib/" 2>/dev/null || true
    _out=$( cd "$_tmp_cwd" && CLAUDE_HOME="$_tmp_home" bash "$ss" 2>/dev/null ); _rc=$?
    if [[ $_rc -eq 0 ]] && printf '%s' "$_out" | _validate_json_stream; then
      ok "session-start.sh runs clean (exit 0, valid JSON)"
    else
      fail "session-start.sh self-test FAILED (rc=$_rc or invalid JSON) — runtime copy broken, reinstall"
    fi
    rm -rf "$_tmp_home" "$_tmp_cwd"
  else
    warn "session-start.sh self-test skipped (mktemp unavailable)"
  fi
else
  warn "session-start.sh not executable — self-test skipped"
fi

# post-tool-use.sh self-test — feed a canned event on stdin, assert exit 0.
ptu="$CLAUDE_HOME/hooks/post-tool-use.sh"
if [[ -x "$ptu" ]]; then
  _tmp_home2=$(mktemp -d 2>/dev/null || echo "")
  if [[ -n "$_tmp_home2" ]]; then
    mkdir -p "$_tmp_home2/bin/lib" "$_tmp_home2/debug"
    cp "$CLAUDE_HOME/bin/lib/"*.sh "$_tmp_home2/bin/lib/" 2>/dev/null || true
    printf '{"tool_name":"Read","tool_input":{"file_path":"/x"}}' \
      | CLAUDE_HOME="$_tmp_home2" bash "$ptu" >/dev/null 2>&1; _rc2=$?
    if [[ $_rc2 -eq 0 ]]; then
      ok "post-tool-use.sh runs clean (exit 0 on canned event)"
    else
      fail "post-tool-use.sh self-test FAILED (rc=$_rc2) — runtime copy broken, reinstall"
    fi
    rm -rf "$_tmp_home2"
  fi
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
# shellcheck disable=SC2154  # slug set by sourced _compute_slug
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
  # Check cwd field (leading whitespace allowed — Claude Code's memory
  # indexer may re-nest frontmatter under `metadata:`, see gotchas.md)
  if grep -qE '^[[:space:]]*cwd:' "$session_file" 2>/dev/null; then
    sc=$(sed -n 's/^[[:space:]]*cwd:[[:space:]]*//p' "$session_file" | head -n1 | tr -d '\r')
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
# _cmd_runs (from validate-json.sh) probes that the interpreter actually EXECUTES,
# not just that it is on PATH — a Windows Store python3 stub passes `command -v`
# but exits 49 when run, so a presence-only check would report a parser that can't
# parse. Flag that stub explicitly so the cause is obvious.
if command -v python3 >/dev/null 2>&1 && ! _cmd_runs python3; then
  warn "python3 on PATH but does NOT run (Windows Store alias stub?) — skipped; disable it in Settings > Apps > App execution aliases, or install real Python"
fi
_cmd_runs python3 && ok "python3 works"
_cmd_runs node    && ok "node works"
_cmd_runs jq      && ok "jq works"
_parser_pick=$(_json_parser || true)
if [[ -n "$_parser_pick" ]]; then
  ok "PostToolUse will use: $_parser_pick (robust JSON parsing)"
else
  fail "No working JSON parser (python3/node/jq) — grep fallback only; auto-capture may silently lose events on multi-line or escaped-quote JSON. Install any one."
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
