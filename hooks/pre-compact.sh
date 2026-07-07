#!/usr/bin/env bash
# PreCompact hook — reminds model to flush SESSION.md before compaction.
# NOTE: PreCompact schema does NOT accept hookSpecificOutput.additionalContext
# (unlike SessionStart/UserPromptSubmit). Use top-level `systemMessage` instead.

set -euo pipefail

CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
mkdir -p "$CLAUDE_HOME/debug" 2>/dev/null || true
echo "[$(date -Iseconds)] PreCompact fired (cwd=$PWD)" >> "$CLAUDE_HOME/debug/hook-trace.log" || true

# ERR trap — on failure emit a minimal fallback systemMessage rather than silence.
_hook_error() {
  local rc=$1 lineno=$2
  echo "[$(date -Iseconds)] PreCompact ERROR rc=${rc} line=${lineno}" \
    >> "$CLAUDE_HOME/debug/hook-trace.log" 2>/dev/null || :
  printf '{"systemMessage":"MEMORY HOOK ERROR: pre-compact.sh failed at line %s. Check ~/.claude/debug/hook-trace.log. Flush SESSION.md manually before compaction."}\n' "$lineno"
  exit 0
}
trap '_hook_error $? "${BASH_LINENO[0]}"' ERR

# --- SESSION compression flag ---
# Priority: env var CLAUDE_SESSION_COMPRESS → flag file → default on.
# Disable permanently : touch ~/.claude/.session-compress-disabled
# Disable per-session : CLAUDE_SESSION_COMPRESS=0 (set in shell env before launching Claude)
# Re-enable permanently: rm ~/.claude/.session-compress-disabled
compress_enabled=1
if [[ "${CLAUDE_SESSION_COMPRESS:-1}" == "0" ]]; then
  compress_enabled=0
elif [[ -f "$CLAUDE_HOME/.session-compress-disabled" ]]; then
  compress_enabled=0
fi

if [[ "$compress_enabled" == "1" ]]; then
  compress_rule='\n2. COMPRESSION — write prose sections in compressed caveman notation: drop articles (a/an/the) and filler words, use fragments, keep code/paths/identifiers/numbers byte-exact. Applies to SESSION.md and project.md (incl. ## Timeline lines) — both read by agents, not humans; terseness saves context-window tokens on every reload.'
else
  compress_rule='\n2. COMPRESSION — disabled. Write SESSION.md and project.md prose naturally; do not apply caveman compression.'
  echo "[$(date -Iseconds)] PreCompact: session compression disabled" >> "$CLAUDE_HOME/debug/hook-trace.log"
fi

printf '{"systemMessage":"PRE-COMPACT FLUSH REQUIRED. Before compaction, update <project>/memory/SESSION.md with: Goal, State (branch/last/next), Decisions with rationale, File map, Open questions, Blockers, and **Recent turns** (last ~5 user turns VERBATIM + 1-line '"'"'I did:'"'"' each). SESSION.md is the only artifact that survives compaction with full fidelity. After compact, re-read it first.\\n\\nThree rules when writing:\\n1. PRIVACY — strip all <private>...</private> blocks before writing. Never persist tagged content to disk. If you see <private>...</private> in what you are about to write, remove the tags and their contents entirely.%s\\n3. CWD — ensure YAML frontmatter contains a '"'"'cwd: <current working directory>'"'"' field (e.g. cwd: C:/dev/myproject). The SessionStart hook uses this to detect project switches and auto-reset stale state."}\n' \
  "$compress_rule"
