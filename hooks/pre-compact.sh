#!/usr/bin/env bash
# PreCompact hook — reminds model to flush SESSION.md before compaction.
# NOTE: PreCompact schema does NOT accept hookSpecificOutput.additionalContext
# (unlike SessionStart/UserPromptSubmit). Use top-level `systemMessage` instead.

CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
mkdir -p "$CLAUDE_HOME/debug" 2>/dev/null
echo "[$(date -Iseconds)] PreCompact fired (cwd=$PWD)" >> "$CLAUDE_HOME/debug/hook-trace.log"

cat <<'EOF'
{"systemMessage":"PRE-COMPACT FLUSH REQUIRED. Before compaction, update <project>/memory/SESSION.md with: Goal, State (branch/last/next), Decisions with rationale, File map, Open questions, Blockers, and **Recent turns** (last ~5 user turns VERBATIM + 1-line 'I did:' each). SESSION.md is the only artifact that survives compaction with full fidelity. After compact, re-read it first.\n\nThree rules when writing:\n1. PRIVACY — strip all <private>...</private> blocks before writing. Never persist tagged content to disk. If you see <private>...</private> in what you are about to write, remove the tags and their contents entirely.\n2. COMPRESSION — write prose sections in compressed caveman notation: drop articles (a/an/the) and filler words, use fragments, keep code/paths/identifiers/numbers byte-exact. SESSION.md is read by agents, not humans — terseness saves context-window tokens on every reload.\n3. CWD — ensure YAML frontmatter contains a 'cwd: <current working directory>' field (e.g. cwd: C:/dev/myproject). The SessionStart hook uses this to detect project switches and auto-reset stale state."}
EOF
