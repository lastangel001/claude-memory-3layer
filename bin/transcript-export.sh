#!/usr/bin/env bash
# bin/transcript-export.sh — export Claude Code session transcripts (.jsonl) to
# searchable markdown under the project's memory tree (verbatim recall layer).
#
#   ~/.claude/projects/<slug>/*.jsonl
#     -> ~/.claude/projects/<slug>/memory/raw/transcripts/<session-id>.md
#
# Why: everything the model didn't explicitly write to SESSION.md dies at
# compact/wipe. Claude Code already keeps the verbatim record — this makes it
# reachable via /recall (qmd indexes ~/.claude/projects recursively).
#
# Privacy:
#   - <private>...</private> blocks are stripped from the export
#   - a project with .claude-private in its root is skipped entirely
#   - opt-out: touch ~/.claude/.transcript-export-disabled
#
# Incremental: a .jsonl is skipped when its export is already newer.
# Rotation: exports older than TRANSCRIPT_KEEP_DAYS (default 30) are deleted.
# Cap: output truncated at TRANSCRIPT_MAX_BYTES (default 300000) per file.
#
# Usage: transcript-export.sh [slug]   (default: slug computed from $PWD)

set -euo pipefail

CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
KEEP_DAYS="${TRANSCRIPT_KEEP_DAYS:-30}"
MAX_BYTES="${TRANSCRIPT_MAX_BYTES:-300000}"

log() {
  echo "[$(date -Iseconds)] transcript-export: $*" \
    >> "$CLAUDE_HOME/debug/hook-trace.log" 2>/dev/null || true
}

# Opt-out flag file.
[[ -f "$CLAUDE_HOME/.transcript-export-disabled" ]] && exit 0

# Privacy: project opted out of memory capture entirely.
if [[ -f "$PWD/.claude-private" ]]; then
  log "skipped (.claude-private present in $PWD)"
  exit 0
fi

if [[ -n "${1:-}" ]]; then
  slug="$1"
else
  # shellcheck source=lib/slug.sh
  source "$CLAUDE_HOME/bin/lib/slug.sh"
  _compute_slug
fi

proj_dir="$CLAUDE_HOME/projects/$slug"
out_dir="$proj_dir/memory/raw/transcripts"
[[ -d "$proj_dir" ]] || exit 0

# Pick a JSON-capable interpreter. No python3 and no node -> nothing to do.
engine=""
if command -v python3 >/dev/null 2>&1; then
  engine="python3"
elif command -v node >/dev/null 2>&1; then
  engine="node"
else
  log "skipped (no python3/node for jsonl parsing)"
  exit 0
fi

convert_with_python3() { # $1=src $2=dst
  python3 - "$1" "$2" "$MAX_BYTES" <<'PYEOF'
import json, re, sys, io

src, dst, max_bytes = sys.argv[1], sys.argv[2], int(sys.argv[3])
PRIVATE = re.compile(r"<private>.*?</private>", re.S)

def text_of(content):
    if isinstance(content, str):
        return content
    parts = []
    if isinstance(content, list):
        for item in content:
            # only human/model text; tool_use, tool_result, thinking are noise
            if isinstance(item, dict) and item.get("type") == "text":
                parts.append(item.get("text", ""))
    return "\n".join(p for p in parts if p.strip())

out = io.StringIO()
for line in open(src, encoding="utf-8", errors="replace"):
    line = line.strip()
    if not line:
        continue
    try:
        d = json.loads(line)
    except ValueError:
        continue
    if d.get("isMeta"):
        continue
    typ = d.get("type")
    if typ not in ("user", "assistant"):
        continue
    msg = d.get("message") or {}
    text = text_of(msg.get("content"))
    if not text.strip():
        continue
    who = "User" if typ == "user" else "Assistant"
    out.write(f"**{who}:**\n{text.strip()}\n\n---\n\n")

body = PRIVATE.sub("", out.getvalue())
if not body.strip():
    sys.exit(3)  # nothing exportable — caller removes empty target
enc = body.encode("utf-8")
truncated = ""
if len(enc) > max_bytes:
    body = enc[:max_bytes].decode("utf-8", errors="ignore")
    truncated = "\n\n*[truncated at size cap]*\n"
with open(dst, "w", encoding="utf-8") as f:
    f.write(body + truncated)
PYEOF
}

convert_with_node() { # $1=src $2=dst
  node - "$1" "$2" "$MAX_BYTES" <<'JSEOF'
const fs = require("fs");
const [src, dst, maxBytesArg] = process.argv.slice(2);
const maxBytes = parseInt(maxBytesArg, 10);

function textOf(content) {
  if (typeof content === "string") return content;
  if (!Array.isArray(content)) return "";
  return content
    .filter((i) => i && i.type === "text")
    .map((i) => i.text || "")
    .filter((t) => t.trim())
    .join("\n");
}

let out = "";
for (const line of fs.readFileSync(src, "utf8").split("\n")) {
  if (!line.trim()) continue;
  let d;
  try { d = JSON.parse(line); } catch { continue; }
  if (d.isMeta) continue;
  if (d.type !== "user" && d.type !== "assistant") continue;
  const text = textOf((d.message || {}).content);
  if (!text.trim()) continue;
  out += `**${d.type === "user" ? "User" : "Assistant"}:**\n${text.trim()}\n\n---\n\n`;
}
out = out.replace(/<private>[\s\S]*?<\/private>/g, "");
if (!out.trim()) process.exit(3);
let buf = Buffer.from(out, "utf8");
let truncated = "";
if (buf.length > maxBytes) {
  out = buf.subarray(0, maxBytes).toString("utf8");
  truncated = "\n\n*[truncated at size cap]*\n";
}
fs.writeFileSync(dst, out + truncated);
JSEOF
}

mkdir -p "$out_dir"

exported=0
shopt -s nullglob
for src in "$proj_dir"/*.jsonl; do
  base=$(basename "$src" .jsonl)
  dst="$out_dir/$base.md"
  # Incremental: skip when export is current.
  [[ -f "$dst" && "$dst" -nt "$src" ]] && continue
  # Don't export sessions already past the retention window.
  if [[ -n "$(find "$src" -maxdepth 0 -mtime "+$KEEP_DAYS" 2>/dev/null)" ]]; then
    continue
  fi

  tmp="$dst.tmp.$$"
  rc=0
  header="---
tags: [memory/transcript]
source: $src
exported: $(date -u +%Y-%m-%dT%H:%M:%SZ)
---

# Transcript $base

"
  if [[ "$engine" == "python3" ]]; then
    convert_with_python3 "$src" "$tmp" || rc=$?
  else
    convert_with_node "$src" "$tmp" || rc=$?
  fi
  if [[ $rc -eq 0 && -s "$tmp" ]]; then
    { printf '%s' "$header"; cat "$tmp"; } > "$dst"
    exported=$((exported + 1))
  fi
  rm -f "$tmp"
done

# Rotation: exports past the retention window are deleted (verbatim layer is a
# rolling window, not an archive — SESSION.md/gotchas carry the distilled truth).
find "$out_dir" -name '*.md' -mtime "+$KEEP_DAYS" -delete 2>/dev/null || true

[[ $exported -gt 0 ]] && log "exported $exported transcript(s) for $slug"
exit 0
