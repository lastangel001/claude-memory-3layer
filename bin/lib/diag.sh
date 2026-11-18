#!/usr/bin/env bash
# bin/lib/diag.sh — sourced library: structured hook-outcome journal.
#
# Usage: source "${CLAUDE_HOME}/bin/lib/diag.sh"
#   _diag <hook> <outcome> [note]
#
# Appends one JSON line to $CLAUDE_HOME/debug/hook-diag.jsonl:
#   {"ts":"2026-01-01T00:00:00Z","hook":"SessionStart","outcome":"ok","note":"slug=transcript"}
#
# Outcomes:
#   ok       — hook did its job
#   degraded — hook finished but a feature silently fell back (no JSON parser,
#              perl missing, legacy slug directory, validation fallback, ...)
#   failed   — ERR trap fired
#
# Why: hooks fail open by design (never block a session). hook-trace.log is
# free text, so a feature that degrades on every run stays invisible for
# months. doctor.sh summarizes this file; a non-zero degraded/failed count is
# the signal. PostToolUse logs only captures/degradations — a line per no-op
# tool call would be noise.
#
# `note` is restricted to [A-Za-z0-9 _.:=-] so no JSON escaping is needed and a
# stray quote can never corrupt the journal.

_diag() {
  local _f="${CLAUDE_HOME:-$HOME/.claude}/debug/hook-diag.jsonl"
  local _note="${3:-}"
  _note="${_note//[^A-Za-z0-9 _.:=-]/}"
  printf '{"ts":"%s","hook":"%s","outcome":"%s","note":"%s"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)" \
    "${1:-unknown}" "${2:-unknown}" "$_note" >> "$_f" 2>/dev/null || true
}
