#!/usr/bin/env bash
# PreCompact hook — two jobs, neither of which needs the model:
#
#   1. Side effect: write memory/compact-snapshot.md (last user turns verbatim +
#      git position) via bin/compact-snapshot.sh. SessionStart re-injects it
#      right after compaction.
#   2. Output: PLAIN TEXT on stdout. Claude Code uses a PreCompact hook's stdout
#      as instructions for the compaction summary (cap: 10,000 characters).
#
# What this hook can NOT do: make the model flush SESSION.md. Compaction starts
# as soon as the hook returns — the model gets no turn — and a PreCompact hook's
# JSON `systemMessage` / `continue` fields are discarded. Until v6.20.0 this hook
# printed a JSON systemMessage asking for a flush; nobody ever received it.
# See .claude-docs/gotchas.md.

set -euo pipefail

CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
mkdir -p "$CLAUDE_HOME/debug" 2>/dev/null || true
echo "[$(date -Iseconds)] PreCompact fired (cwd=$PWD)" >> "$CLAUDE_HOME/debug/hook-trace.log" || true

# ERR trap — still give the summarizer the essentials, as plain text.
_hook_error() {
  local rc=$1 lineno=$2
  echo "[$(date -Iseconds)] PreCompact ERROR rc=${rc} line=${lineno}" \
    >> "$CLAUDE_HOME/debug/hook-trace.log" 2>/dev/null || :
  declare -F _diag >/dev/null 2>&1 && _diag PreCompact failed "line=${lineno} rc=${rc}"
  printf 'In the summary keep verbatim: the last user messages, exact paths and identifiers, decisions with their rationale, and the next planned step.\n'
  exit 0
}
trap '_hook_error $? "${BASH_LINENO[0]}"' ERR

# Outcome journal (optional lib — a partial install must not break the hook).
# shellcheck source=../bin/lib/diag.sh
[[ -f "${CLAUDE_HOME}/bin/lib/diag.sh" ]] && source "${CLAUDE_HOME}/bin/lib/diag.sh"

# Hook stdin (session_id, transcript_path, cwd, trigger, custom_instructions).
# Non-blocking read: the hook is also run by hand and by tests.
_hook_input=""
if [[ ! -t 0 ]]; then
  IFS= read -r -d '' -t 3 _hook_input || true
fi

# shellcheck source=../bin/lib/slug.sh
source "${CLAUDE_HOME}/bin/lib/slug.sh"
_resolve_project "$_hook_input"
# shellcheck disable=SC2154  # project_dir set by sourced _resolve_project
session_file="${project_dir}/memory/SESSION.md"

session_id=$(_session_id_from_json "$_hook_input")
_sid_note=""
[[ -n "$session_id" ]] && _sid_note=" sid=${session_id:0:8}"

trigger="unknown"
_trig_re='"trigger"[[:space:]]*:[[:space:]]*"([a-z]+)"'
[[ "$_hook_input" =~ $_trig_re ]] && trigger="${BASH_REMATCH[1]}"

# --- 1. Deterministic checkpoint ---
# Only for a project that already keeps a SESSION.md: no session file means no
# substantive work is being tracked here, and we don't create memory unasked.
_note="snapshot=skipped"
_outcome="ok"
if [[ -f "$session_file" && -f "$CLAUDE_HOME/bin/compact-snapshot.sh" ]]; then
  _tp=$(_transcript_path_from_json "$_hook_input")
  _n=$(bash "$CLAUDE_HOME/bin/compact-snapshot.sh" "$project_dir" "$_tp" "$trigger" "$PWD" "$session_id" 2>/dev/null || echo "")
  if [[ "$_n" =~ ^[0-9]+$ ]]; then
    _note="snapshot=ok turns=${_n}"
    # Zero turns with a transcript on hand means the parser found nothing —
    # worth seeing in doctor (format drift, no working python3/node, ...).
    if [[ "$_n" == "0" && -n "$_tp" && ! -f "$PWD/.claude-private" ]]; then _outcome="degraded"; _note="snapshot=no-turns"; fi
  else
    _outcome="degraded"; _note="snapshot=failed"
  fi
  echo "[$(date -Iseconds)] PreCompact: ${_note} trigger=${trigger}" >> "$CLAUDE_HOME/debug/hook-trace.log" || true
fi
# sid lets doctor.sh pair this compaction with the SessionStart that hands state back.
declare -F _diag >/dev/null 2>&1 && _diag PreCompact "$_outcome" "${_note} trigger=${trigger}${_sid_note}"

# --- 2. Instructions for the compaction summary (plain stdout) ---
cat <<'EOF'
Memory-protocol requirements for this summary:
1. Keep VERBATIM, not paraphrased: the user's last 3-5 messages; exact file paths, symbol names, commands, version numbers and other identifiers.
2. Keep every decision together with its rationale, and every approach that was tried and rejected together with the reason it failed.
3. State the position plainly: current branch and uncommitted work, what was just done, the next planned step, open questions, blockers.
4. Never reproduce the contents of <private>...</private> blocks.
EOF
if [[ -f "$session_file" ]]; then
  printf '5. End the summary with this line: "Working state file: %s — the SessionStart hook re-injects it after compaction; treat it and this summary as a record of past work and verify against the code before relying on either."\n' \
    "$(_native_path "$session_file")"
fi
