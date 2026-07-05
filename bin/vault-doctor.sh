#!/usr/bin/env bash
# vault-doctor.sh — memory CONTENT health check (complements doctor.sh, which
# checks the INSTALL). Deterministic, no LLM. Two scopes:
#
#   A. Account memory ($CLAUDE_HOME): IDENTITY.md size, SESSION.md oversize,
#      stale sessions (>N days), transcript-export retention.
#   B. Current repo .claude-docs/ (if cwd is a repo with one): missing
#      frontmatter, broken relative md links, docs orphaned from index.md.
#
# Usage:
#   bash ~/.claude/bin/vault-doctor.sh              # report only
#   bash ~/.claude/bin/vault-doctor.sh --fix        # also wipe stale SESSION.md
#   bash ~/.claude/bin/vault-doctor.sh --stale-days 60
#
# Exit: 0 if no failures, 1 if any hard failure (broken link).

CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
STALE_DAYS="${VAULT_STALE_DAYS:-30}"
IDENTITY_MAX_LINES=25
SESSION_MAX_BYTES=8192
TRANSCRIPT_MAX_BYTES="${TRANSCRIPT_MAX_BYTES:-307200}"   # 300 KB, matches transcript-export
FIX=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --fix)        FIX=1; shift ;;
    --stale-days) STALE_DAYS="$2"; shift 2 ;;
    -h|--help)    grep -E '^#( |$)' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) printf 'Unknown arg: %s\n' "$1" >&2; exit 1 ;;
  esac
done

pass=0; fail=0; warn=0
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; ((pass++)); }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*"; ((fail++)); }
warn() { printf '  \033[33m?\033[0m %s\n' "$*"; ((warn++)); }
say()  { printf '%s\n' "$*"; }

# Portable "epoch of last modification" and "now".
_now=$(date +%s)
_stale_cutoff=$(( _now - STALE_DAYS * 86400 ))

# Read a frontmatter scalar tolerating indexer nesting under `metadata:`
# (leading whitespace allowed — same rule the hooks use).
_fm_get() { sed -n "s/^[[:space:]]*$2:[[:space:]]*//p" "$1" 2>/dev/null | head -n1 | tr -d '\r'; }

say ""
say "=== claude-memory-3layer vault-doctor (content health) ==="
say "CLAUDE_HOME: $CLAUDE_HOME   stale threshold: ${STALE_DAYS}d   fix: $([[ $FIX -eq 1 ]] && echo on || echo off)"
say ""

# ─────────────────────────────────────────────
# A1. IDENTITY.md (L0) — hard cap 25 lines
# ─────────────────────────────────────────────
say "L0 identity:"
id="$CLAUDE_HOME/memory/IDENTITY.md"
if [[ -f "$id" ]]; then
  n=$(grep -c '' "$id" 2>/dev/null || echo 0)
  if [[ "$n" -le "$IDENTITY_MAX_LINES" ]]; then
    ok "IDENTITY.md $n lines (cap $IDENTITY_MAX_LINES)"
  else
    warn "IDENTITY.md $n lines — over ${IDENTITY_MAX_LINES}-line cap; trim to keep L0 lean (loads every session)"
  fi
else
  warn "IDENTITY.md not found"
fi
say ""

# ─────────────────────────────────────────────
# A2. SESSION.md — oversize + stale
# ─────────────────────────────────────────────
say "Session files ($CLAUDE_HOME/projects/*/memory/SESSION.md):"
_any_session=0
shopt -s nullglob
for sf in "$CLAUDE_HOME/projects"/*/memory/SESSION.md; do
  _any_session=1
  proj=$(basename "$(dirname "$(dirname "$sf")")")
  bytes=$(wc -c < "$sf" 2>/dev/null | tr -d ' ')
  [[ -z "$bytes" ]] && bytes=0
  if [[ "$bytes" -gt "$SESSION_MAX_BYTES" ]]; then
    warn "$proj: SESSION.md ${bytes}B > ${SESSION_MAX_BYTES}B — prune (re-read on every compact)"
  fi
  lu=$(_fm_get "$sf" last_updated)
  lu_epoch=0
  if [[ -n "$lu" ]]; then
    lu_epoch=$(date -d "$lu" +%s 2>/dev/null \
      || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$lu" +%s 2>/dev/null || echo 0)
  fi
  if [[ "$lu_epoch" -gt 0 && "$lu_epoch" -lt "$_stale_cutoff" ]]; then
    age_days=$(( (_now - lu_epoch) / 86400 ))
    if [[ $FIX -eq 1 ]]; then
      cwd=$(_fm_get "$sf" cwd); [[ -z "$cwd" ]] && cwd="(unknown)"
      cp "$sf" "$sf.bak-$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true
      {
        printf -- '---\nlast_updated: %s\ncwd: %s\nstatus: done\ntags: [memory/l2, session]\n---\n\n' \
          "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$cwd"
        printf '# Goal\n(none — wiped by vault-doctor: stale %dd)\n' "$age_days"
      } > "$sf"
      ok "$proj: wiped stale SESSION.md (${age_days}d old, backup kept)"
    else
      warn "$proj: SESSION.md stale ${age_days}d (>${STALE_DAYS}d) — run --fix to wipe to template"
    fi
  fi
done
[[ $_any_session -eq 0 ]] && ok "No SESSION.md files yet"
say ""

# ─────────────────────────────────────────────
# A3. Transcript-export retention
# ─────────────────────────────────────────────
say "Transcript export retention:"
_tx_total=0
_tx_dirs=0
for txdir in "$CLAUDE_HOME/projects"/*/memory/raw/transcripts; do
  [[ -d "$txdir" ]] || continue
  _tx_dirs=$((_tx_dirs + 1))
  sz=$(find "$txdir" -type f -name '*.md' -exec cat {} + 2>/dev/null | wc -c | tr -d ' ')
  [[ -z "$sz" ]] && sz=0
  _tx_total=$((_tx_total + sz))
  if [[ "$sz" -gt "$TRANSCRIPT_MAX_BYTES" ]]; then
    proj=$(basename "$(dirname "$(dirname "$(dirname "$txdir")")")")
    warn "$proj: transcripts ${sz}B > ${TRANSCRIPT_MAX_BYTES}B cap — export rolling window may be misconfigured"
  fi
done
if [[ $_tx_dirs -eq 0 ]]; then
  ok "No transcript exports (feature opt-in / not yet run)"
else
  ok "$_tx_dirs project(s) with transcripts, ${_tx_total}B total"
fi
say ""

# ─────────────────────────────────────────────
# B. Current repo .claude-docs/ (only if present in cwd)
# ─────────────────────────────────────────────
docs_dir=""
if git rev-parse --show-toplevel >/dev/null 2>&1; then
  _root=$(git rev-parse --show-toplevel 2>/dev/null)
  [[ -d "$_root/.claude-docs" ]] && docs_dir="$_root/.claude-docs"
fi
[[ -z "$docs_dir" && -d "$PWD/.claude-docs" ]] && docs_dir="$PWD/.claude-docs"

if [[ -n "$docs_dir" ]]; then
  say "Repo docs ($docs_dir):"
  index="$docs_dir/index.md"
  for md in "$docs_dir"/*.md; do
    [[ -f "$md" ]] || continue
    base=$(basename "$md")

    # Missing frontmatter (must start with '---')
    if [[ "$(head -n1 "$md" 2>/dev/null)" != "---" ]]; then
      warn "$base: no YAML frontmatter (first line is not '---')"
    fi

    # Orphan: not referenced in index.md (index.md itself exempt)
    if [[ -f "$index" && "$base" != "index.md" ]]; then
      grep -q "$base" "$index" 2>/dev/null || warn "$base: orphaned — not linked from index.md"
    fi

    # Broken relative markdown links: [text](target.md ...) where target missing.
    while IFS= read -r target; do
      [[ -z "$target" ]] && continue
      [[ "$target" =~ ^https?:// || "$target" == \#* ]] && continue
      tgt="${target%%#*}"            # strip anchor
      [[ -z "$tgt" ]] && continue
      # Only validate path-like targets (contain an extension or a slash).
      # Skips prose examples such as the literal `[text](path)` in conventions.md.
      [[ "$tgt" == *.* || "$tgt" == */* ]] || continue
      if [[ ! -e "$docs_dir/$tgt" && ! -e "$(dirname "$md")/$tgt" ]]; then
        fail "$base: broken link → $tgt (target file missing)"
      fi
    done < <(grep -oE '\]\(([^)]+)\)' "$md" 2>/dev/null | sed -E 's/^\]\(//; s/\)$//')
  done
  [[ $fail -eq 0 ]] && ok "All relative links resolve"
  say ""
else
  say "Repo docs: (no .claude-docs/ in current repo — skipped)"
  say ""
fi

# ─────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────
say "─────────────────────────────────"
printf 'Pass: \033[32m%d\033[0m  Fail: \033[31m%d\033[0m  Warn: \033[33m%d\033[0m\n' "$pass" "$fail" "$warn"
say ""
[[ $fail -gt 0 ]] && exit 1
exit 0
