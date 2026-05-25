# Ideas for future improvement

Backlog of enhancement ideas. Each entry has: priority (H/M/L), effort (S/M/L), and a brief rationale. Ordered by priority × effort (high-value / low-effort first).

---

## Already shipped (v1.x)

- [x] Privacy redaction via `<private>` tags (SessionStart hook strips in-place)
- [x] CWD mismatch detection in SESSION.md frontmatter (prevents cross-project context bleed)
- [x] SESSION.md compression protocol (PreCompact instructs caveman-style prose writing)

---

## Backlog

### H/S — PostToolUse selective auto-capture

**What:** Add a `PostToolUse` hook that writes a one-line entry to SESSION.md when specific high-signal events occur: `Write` on a new file, `Bash` with `git commit`, changes to CLAUDE.md.

**Why:** These events are always worth capturing but easily forgotten mid-session. Auto-capture only these patterns keeps explicit-promotion philosophy intact while preventing missed gotchas.

**How:** Hook reads JSON from stdin, pattern-matches on `toolName` + content, appends to `# Decisions` or `# File map` in SESSION.md with timestamp.

**Risk:** Hook must be idempotent and silent-fail. Regex patterns need careful tuning to avoid false positives.

---

### H/S — SESSION.md `cwd:` auto-inject on creation

**What:** When the model creates a fresh SESSION.md, the `cwd:` frontmatter field should be pre-filled by the SessionStart hook output rather than left as a placeholder.

**Why:** Currently the model must fill `cwd:` manually. If it forgets, the staleness check gets no signal. Hook already knows the cwd at fire time.

**How:** In `session-start.sh`, include `current_cwd_canonical` in `additionalContext` so the model has it as a ready-to-paste value. Alternatively, have the hook create SESSION.md skeleton if it doesn't exist (with `cwd:` pre-filled).

---

### H/M — MCP wrapper for `/recall`

**What:** Wrap the BM25+GGUF search from `qmd` as a minimal MCP server with two tools:
- `search_memory(query, limit?)` → `[{snippet, score, file, tags}]`
- `get_identity()` → contents of `IDENTITY.md`

**Why:** `/recall` is a slash command — agents in agentic loops (subagents, task runners, headless mode) cannot call slash commands. An MCP tool is callable programmatically inside any loop.

**How:** Node.js MCP server (~100 lines) that shells out to `qmd search`. No new storage layer — reuses existing markdown files and qmd index. Register in `settings.snippet.json` under `mcpServers`.

**Tradeoff:** Adds a Node.js daemon. Must be optional and installable separately.

---

### M/S — SESSION.md size warning in SessionStart

**What:** If SESSION.md exceeds a threshold (e.g. 4 KB), inject a warning into `additionalContext` advising the model to trim it.

**Why:** SESSION.md bloats silently over long sessions. Every compaction re-reads the full file. A size warning gives the model a nudge to prune before cost compounds.

**How:** `wc -c "$session_file"` in `session-start.sh`; if above threshold add one-liner to `base` message.

---

### M/S — `.private` glob exclusion in session-start hook

**What:** Allow a `.claude-private` file at repo root listing path globs to exclude from any memory capture (similar to cavemem's `excludePatterns`).

**Why:** Whole directories (e.g. `secrets/`, `.env.local`, `certs/`) should never appear in SESSION.md or gotchas. A declarative exclude list is safer than relying on `<private>` tags.

**How:** In `session-start.sh`, read `.claude-private` if present, expose the list in `additionalContext` so the model skips those paths when building File map / Decisions.

---

### M/M — SESSION.md compression via shell (optional cavemem)

**What:** If `cavemem` CLI is installed and SESSION.md is >2 KB, run `cavemem compress "$session_file"` in SessionStart hook after privacy redaction.

**Why:** Protocol-level compression (PreCompact instruction) relies on the model following instructions. Shell-level compression is deterministic — same result regardless of model behavior.

**How:** Add to `session-start.sh` after privacy redaction block. Guard with `command -v cavemem` check so it's optional. Log to `$CLAUDE_HOME/logs/cavemem-compress.log`. Note: cavemem saves backup at `SESSION.md.original.md`; add to `.gitignore` template.

**Risk:** cavemem compress is a dependency. Must never block session start on failure — wrap in `|| true`.

---

### M/M — Periodic SESSION.md cleanup cron

**What:** A script (or cron entry added by `install.sh`) that finds SESSION.md files with `last_updated` older than N days (default: 30) and wipes them to the empty template.

**Why:** Abandoned sessions accumulate in `~/.claude/projects/*/memory/`. No cleanup mechanism exists today. Over months, stale sessions fill disk and pollute `/recall` search results.

**How:** `bin/cleanup-sessions.sh --older-than 30d --dry-run` (dry run by default). Optional cron wiring in `install.sh`.

---

### M/L — Lightweight vector search without qmd

**What:** Replace `qmd embed` dependency with a pure-Node local embedder using ONNX Runtime + a small model (e.g. all-MiniLM-L6-v2 at ~23 MB). Ship inside the package.

**Why:** `qmd` requires separate install + GGUF model download (hundreds of MB). Many users skip vector search entirely because setup friction is too high. A bundled ONNX embedder would make hybrid search zero-dependency.

**Tradeoff:** Larger package size. ONNX Runtime has native bindings — adds install complexity on some platforms. Validate on Windows first (biggest pain point currently).

---

### L/S — Obsidian `dataview` frontmatter for SESSION files

**What:** Add `status: active|done|abandoned` to SESSION.md frontmatter. The distillation step (task wrap-up) sets `status: done`.

**Why:** Obsidian users with a `~/.claude/` vault get free filtering: `dataview TABLE last_updated WHERE status = "active"` shows live sessions at a glance.

**How:** Update SESSION.md template + distillation instruction in CLAUDE.md.

---

### L/M — `/recall` cross-project timeline view

**What:** `qmd` flag or new `/recall --timeline` variant that shows results sorted by `last_updated` across all projects, not just ranked by relevance.

**Why:** Useful for "what was I doing on project X last week?" queries where recency matters more than semantic similarity.

**How:** Post-process `qmd search` results by extracting `last_updated` from matched file frontmatter and re-sorting. No changes to qmd itself needed.

---

### L/L — Remote sync for IDENTITY.md and project.md (L0/L1-fallback)

**What:** Optional encrypted sync of account-local memory files to a user-controlled remote (e.g. private Git repo or S3 bucket).

**Why:** IDENTITY.md is the most irreplaceable file — machine wipe = total loss. Users who work across multiple machines have no sync path today.

**Tradeoff:** Significant scope. Must be opt-in, encrypted, and auditable. Out of scope for core package — better as a separate companion tool.

---

## Notes

- Priority (H/M/L) = user-impact × frequency of the pain point.
- Effort (S/M/L) = engineering days: S < 1d, M = 1-3d, L > 3d.
- Items tagged `H/S` are the best next moves. Start there.
- Before implementing any idea, verify it doesn't violate the core explicit-promotion philosophy: auto-capture must be scoped to high-signal events only.
