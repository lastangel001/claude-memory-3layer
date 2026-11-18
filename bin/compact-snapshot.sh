#!/usr/bin/env bash
# bin/compact-snapshot.sh — deterministic pre-compaction checkpoint.
#
#   compact-snapshot.sh <project_dir> <transcript_path> [trigger] [cwd]
#     -> <project_dir>/memory/compact-snapshot.md   (overwritten every time)
#
# Why: when compaction starts, the model gets no turn to write anything — the
# "flush SESSION.md before compact" step cannot be performed by the model at
# that moment. This script captures, without a model, the two things a summary
# paraphrases away: the last user turns VERBATIM and the git position. The
# SessionStart hook re-injects the file right after compaction.
#
# Not a notes file: it is machine-written and replaced at the next compaction.
#
# Privacy: <private>…</private> blocks are stripped; a project with
# .claude-private in its root gets no user turns captured (git position only).
#
# Exit: always 0 (called from a hook — must never block compaction). Prints the
# number of captured turns on stdout.

set -uo pipefail

CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
project_dir="${1:-}"
transcript="${2:-}"
trigger="${3:-unknown}"
cwd="${4:-$PWD}"
MAX_TURNS="${COMPACT_SNAPSHOT_TURNS:-5}"
MAX_CHARS="${COMPACT_SNAPSHOT_TURN_CHARS:-700}"

[[ -n "$project_dir" ]] || { echo 0; exit 0; }
mkdir -p "$project_dir/memory" 2>/dev/null || { echo 0; exit 0; }
out="$project_dir/memory/compact-snapshot.md"
tmp="$out.tmp.$$"

# shellcheck source=lib/validate-json.sh
source "$CLAUDE_HOME/bin/lib/validate-json.sh" 2>/dev/null || true

# --- last user turns (verbatim) ---
# Reads the transcript on STDIN (never pass an MSYS path to a Windows-native
# interpreter — see gotchas.md). Prints numbered turns, oldest first.
turns=""
if [[ -n "$transcript" && -f "$transcript" && ! -f "$cwd/.claude-private" ]]; then
  if declare -F _cmd_runs >/dev/null 2>&1 && _cmd_runs python3; then
    turns=$(python3 -c '
import json, re, sys
max_turns, max_chars = int(sys.argv[1]), int(sys.argv[2])
PRIVATE = re.compile(r"<private>.*?</private>", re.S)
RECORD = re.compile(r"<memory-record\b.*?</memory-record>", re.S)
SKIP = ("<system-reminder>", "<task-notification>", "<local-command-", "<memory-record")
out = []
for line in sys.stdin.buffer:
    try:
        d = json.loads(line.decode("utf-8", "replace"))
    except ValueError:
        continue
    if d.get("type") != "user" or d.get("isMeta") or d.get("isSidechain") or d.get("isCompactSummary"):
        continue
    c = (d.get("message") or {}).get("content")
    if isinstance(c, str):
        parts = [c]
    elif isinstance(c, list):
        parts = [i.get("text", "") for i in c if isinstance(i, dict) and i.get("type") == "text"]
    else:
        parts = []
    parts = [p for p in parts if p.strip() and not p.lstrip().startswith(SKIP)]
    if not parts:
        continue
    t = RECORD.sub("", PRIVATE.sub("", "\n".join(parts))).strip()
    if not t:
        continue
    t = re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f]", "", t)
    if len(t) > max_chars:
        t = t[:max_chars].rstrip() + " [...]"
    out.append(t)
for n, t in enumerate(out[-max_turns:], 1):
    sys.stdout.buffer.write(("%d. %s\n\n" % (n, t.replace("\n", "\n   "))).encode("utf-8"))
' "$MAX_TURNS" "$MAX_CHARS" < "$transcript" 2>/dev/null || true)
  elif declare -F _cmd_runs >/dev/null 2>&1 && _cmd_runs node; then
    turns=$(node -e '
const maxTurns = parseInt(process.argv[1], 10), maxChars = parseInt(process.argv[2], 10);
const SKIP = ["<system-reminder>", "<task-notification>", "<local-command-", "<memory-record"];
let buf = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", (d) => { buf += d; });
process.stdin.on("end", () => {
  const out = [];
  for (const line of buf.split("\n")) {
    if (!line.trim()) continue;
    let d;
    try { d = JSON.parse(line); } catch { continue; }
    if (d.type !== "user" || d.isMeta || d.isSidechain || d.isCompactSummary) continue;
    const c = (d.message || {}).content;
    let parts = [];
    if (typeof c === "string") parts = [c];
    else if (Array.isArray(c)) parts = c.filter((i) => i && i.type === "text").map((i) => i.text || "");
    parts = parts.filter((p) => p.trim() && !SKIP.some((s) => p.trimStart().startsWith(s)));
    if (!parts.length) continue;
    let t = parts.join("\n")
      .replace(/<private>[\s\S]*?<\/private>/g, "")
      .replace(/<memory-record\b[\s\S]*?<\/memory-record>/g, "")
      .trim();
    if (!t) continue;
    t = t.replace(/[\x00-\x08\x0b\x0c\x0e-\x1f]/g, "");
    if (t.length > maxChars) t = t.slice(0, maxChars).trimEnd() + " [...]";
    out.push(t);
  }
  const last = out.slice(-maxTurns);
  process.stdout.write(last.map((t, i) => `${i + 1}. ${t.replace(/\n/g, "\n   ")}\n\n`).join(""));
});
' "$MAX_TURNS" "$MAX_CHARS" < "$transcript" 2>/dev/null || true)
  fi
fi
n_turns=$(printf '%s' "$turns" | grep -cE '^[0-9]+\. ' || true)

# --- git position ---
git_block="- (not a git repository)"
if git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  _branch=$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")
  _head=$(git -C "$cwd" log -1 --format='%h %s' 2>/dev/null | cut -c1-100 || echo "?")
  _dirty=$(git -C "$cwd" status --porcelain 2>/dev/null | grep -c '' || true)
  git_block="- branch: ${_branch}
- head: ${_head}
- uncommitted files: ${_dirty}"
fi

{
  printf -- '---\ntags: [memory/l2, compact-snapshot]\ngenerated: %s\ntrigger: %s\n---\n\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$trigger"
  printf '<!-- Machine-written by the PreCompact hook; replaced at the next compaction. Do not keep notes here. -->\n\n'
  printf '# Git position at compaction\n%s\n\n' "$git_block"
  printf '# Last user turns (verbatim, oldest first)\n'
  if [[ -n "$turns" ]]; then
    printf '%s\n' "$turns"
  elif [[ -f "$cwd/.claude-private" ]]; then
    printf '(not captured: .claude-private present in the project root)\n'
  else
    printf '(none captured)\n'
  fi
} > "$tmp" 2>/dev/null && mv "$tmp" "$out" 2>/dev/null || rm -f "$tmp" 2>/dev/null

echo "${n_turns:-0}"
exit 0
