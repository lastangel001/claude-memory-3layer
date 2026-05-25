# Ideas for future improvement

Backlog of enhancement ideas. Each entry has: priority (H/M/L), effort (S/M/L), and a brief rationale. Ordered by priority × effort (high-value / low-effort first).

---

## Already shipped (v1.x)

- [x] Privacy redaction via `<private>` tags (SessionStart hook strips in-place)
- [x] CWD mismatch detection in SESSION.md frontmatter (prevents cross-project context bleed)
- [x] SESSION.md compression protocol (PreCompact instructs caveman-style prose writing)
- [x] SESSION compression on/off toggle (`CLAUDE_SESSION_COMPRESS` env var + `~/.claude/.session-compress-disabled` flag file)
- [x] Fix hardcoded user paths in hooks and commands (all `/c/Users/greev/` → `$CLAUDE_HOME` / `~/.claude/`)
- [x] PostToolUse selective auto-capture (git commit, CLAUDE.md, .claude-docs/ writes)
- [x] SESSION.md `cwd:` auto-inject — hook injects canonical cwd into context as ready-to-paste value
- [x] BSD `date -j` fallback for macOS (staleness check now portable)
- [x] CRLF guard before privacy redaction (`tr -d '\r'` + sed in single portable pass)
- [x] `bin/doctor.sh` post-install health check (hooks, settings.json, IDENTITY.md, SESSION.md, optional tools)
- [x] Pre-flight validation in `install.sh` (JSON validity, hook syntax, executable bits)

---

## Backlog

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

## Hook reliability

### H/M — File locking for SESSION.md (parallel worktrees)

**What:** Guard SESSION.md writes with a per-slug lockfile so two parallel agents in the same project don't clobber each other's output.

**Why:** Two worktrees or two Claude Code windows in the same project share one SESSION.md. Both read, both write → last writer wins, first writer's data silently lost.

**How:** Wrap hook's file-touch ops in `flock "$session_file.lock" -c "..."` (Linux/Windows Git Bash). On macOS `flock` requires `brew install util-linux` — document as known limitation and fall back to a temp-file rename pattern (`write to .SESSION.tmp → mv -f`). Alternatively: per-worktree SESSION.md suffix derived from `git worktree list` branch name, so each worktree gets its own file.

**Risk:** `flock` not available everywhere. Atomic rename (`mv -f`) avoids the dependency but doesn't prevent concurrent reads. Document known limitation in INSTALL.md if full locking not implemented.

---

### M/S — Validate JSON output of session-start.sh

**What:** Before printing hookSpecificOutput JSON, pipe it through a quick validity check.

**Why:** Any unescaped character in `json_escape()` (rare but possible with exotic Unicode or malformed session content) produces silent broken JSON. Claude Code silently skips the hook → model gets no memory context, user sees no error.

**How:** Add after `escaped=` assignment:
```bash
printf '%s' "$escaped" | node -e "JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'))" 2>/dev/null \
  || { echo '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"MEMORY HOOK ERROR: JSON escaped output failed validation. Check hook-trace.log."}}'; exit 0; }
```
Falls back to minimal safe output on failure; never blocks session start.

---

### M/S — Race condition on `.qmd-last-refresh` marker

**What:** Make the qmd debounce marker write atomic to prevent two parallel SessionStart hooks from both triggering `qmd update`.

**Why:** Two Claude Code windows open simultaneously each fire SessionStart within milliseconds. Both read marker → both see stale → both spawn background `qmd update` processes. Benign but wastes CPU and can cause index corruption on slow filesystems.

**How:** Replace `cat marker` + `date > marker` with an atomic check-and-set:
```bash
( flock -n 9 && cat "$qmd_marker" ... && date +%s > "$qmd_marker" ) 9>"$qmd_marker.lock"
```
Or simpler: use `mkdir` as atomic lock (`mkdir "$qmd_marker.lock" 2>/dev/null && ...`).

---

## Install / Uninstall

### M/S — Uninstall instructions and `bin/uninstall.sh`

**What:** Document and script complete removal: hook files from `~/.claude/hooks/`, entries from `settings.json`, slash command files from `~/.claude/commands/`, bin scripts. Restore default Claude Code memory behavior.

**Why:** INSTALL.md covers upgrade/rollback but has zero guidance on "I want to remove this entirely." Users who switch systems or tools are left guessing which files to delete.

**How:** `bin/uninstall.sh` mirrors `install.sh`: removes known files, strips the `hooks` block from settings.json using `jq` or a sed/Python fallback. Adds "Uninstall" section to INSTALL.md. Default Claude memory is restored automatically once hooks block is removed.

---

### M/M — Programmatic settings.json merge

**What:** Replace "merge by hand" fallback with an automated merge script.

**Why:** Current install.sh detects conflict and tells user to merge manually. In practice users copy-paste wrong, break JSON, and get cryptic Claude Code errors with no hint that hooks are the cause.

**How:** Add `bin/merge-settings.sh` that uses `jq` if available, else falls back to a 10-line Node.js/Python merge. Merge strategy: deep-merge `hooks` arrays (append if no duplicate command), keep user's other keys untouched. Validate output JSON before writing.

---

## SESSION.md lifecycle

### M/M — `/session-end` slash command (distillation enforcement)

**What:** Add a `/session-end` slash command that executes the distillation + wipe ritual.

**Why:** CLAUDE.md says "on task done, wipe SESSION.md to template". In practice the model forgets or user doesn't say "task done" explicitly. High-signal work gets lost; SESSION.md bloats across tasks.

**How:** `commands/session-end.md` slash command: (1) distil key decisions/gotchas to their permanent layers (IDENTITY.md / gotchas.md / project.md), (2) confirm with user what was promoted, (3) wipe SESSION.md to blank template with fresh `last_updated` and current `cwd:`. Optionally hook into Claude Code's `Stop` hook if supported — emit reminder if SESSION.md `last_updated` is within the last hour (active session just ended).

---

### M/S — Enforce `last_updated` presence at session start

**What:** Upgrade the "no `last_updated` marker" warning from a passive note to an actionable instruction.

**Why:** Staleness detection only works if the model writes `last_updated:` on every SESSION.md update. The existing fallback message says "treat with suspicion" — the model may acknowledge it and continue without fixing the file. Future sessions stay broken.

**How:** Change the fallback branch in `session-start.sh`:
```
NOTE: SESSION.md exists but has no last_updated marker.
→ REQUIRED FIRST ACTION: add 'last_updated: <current UTC ISO>' to YAML frontmatter NOW, before any other response. Do not skip this.
```
Strong imperative wording rather than hedged advisory.

---

## Testing & CI

### M/M — bats-core test suite for hooks (developer-side)

**What:** Add `tests/` directory with [bats-core](https://github.com/bats-core/bats-core) tests covering the two hook scripts.

**Why:** Hooks are the critical path — silent breakage = memory loss. No tests exist. Any edit to session-start.sh can break staleness detection, CWD check, privacy redaction, or compression flag without anyone noticing until a user reports lost context.

**Important:** Tests run **from the repo** against the repo's hook files (not `~/.claude/hooks/`). Post-install validation is handled separately by `bin/doctor.sh`. CI (GitHub Actions) runs `bats tests/` on push.

**Minimum scope for session-start.sh:**
- Staleness check fires when `last_updated` >24h
- CWD mismatch detected when `cwd:` doesn't match `$PWD`
- Privacy redaction strips `<private>` blocks
- Compression flag respected (env var + file)
- JSON output is valid (`node -e "JSON.parse(...)"`)

---

## Notes

- Priority (H/M/L) = user-impact × frequency of the pain point.
- Effort (S/M/L) = engineering days: S < 1d, M = 1-3d, L > 3d.
- Items tagged `H/S` are the best next moves. Start there.
- Before implementing any idea, verify it doesn't violate the core explicit-promotion philosophy: auto-capture must be scoped to high-signal events only.
