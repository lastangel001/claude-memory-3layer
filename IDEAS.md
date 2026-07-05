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
- [x] `set -euo pipefail` + ERR traps in all hooks (strict mode; fallback JSON on error; never blocks session start)
- [x] Robust JSON parsing in `post-tool-use.sh` — `jq` fallback added; `\x01` separator (bash-safe); python3 `-c` fix (heredoc conflict); `doctor.sh` section 6 reports active parser
- [x] Slug `_` → `-` normalization in all slug computations (matches Claude Code's actual slug formula)
- [x] `.claude-private` glob exclusion in session-start hook (patterns injected into additionalContext; model skips matching paths for all memory/capture)
- [x] Obsidian `dataview` frontmatter for SESSION files (`status: active` in template; distillation sets `status: done`)
- [x] Validate JSON output of `session-start.sh` (python3 → node fallback; broken JSON uses safe error fallback instead of silent failure)
- [x] Atomic qmd marker write (`mkdir` lock prevents parallel SessionStart hooks from both triggering qmd update; marker written before spawn)
- [x] Programmatic `settings.json` merge (`bin/merge-settings.sh`; python3 → node → jq; `install.sh` calls it automatically when hooks missing)
- [x] DRY slug helper (`bin/lib/slug.sh`; sourced by session-start, post-tool-use, doctor — single source of truth for slug formula)
- [x] `${APPDATA:-}` / `${USERPROFILE:-}` guards in all `_add_path` calls (safe under `set -u` on macOS/Linux where these vars are unset)
- [x] `grep -F` for ctags symbol lookup in `bin/codemap.sh` (fixed-string prevents dots/stars in symbol names from being treated as regex)
- [x] One-step updater (`bin/update.sh`; reads `~/.claude/.memory-source`; `git pull` + re-install); version tracking (`.memory-version` + `.memory-source` written by `install.sh`); `doctor.sh` section 0 shows installed version
- [x] Sharp SESSION.md write triggers in protocol (replaced vague "meaningful action" with explicit criteria per section: Decisions / State / File map / gotchas.md; added quick test: "would future agent decide worse without this?")
- [x] `/onboard` slash command + `bin/onboard-report.sh` (bootstrap memory for existing projects: stack detection, git log, hot files, FIXME/HACK grep → creates CLAUDE.md + .claude-docs/ scaffold; does not commit)
- [x] Windows-specific section in INSTALL.md (space-in-username, backslash paths, PATH precedence, MSYS2/Cygwin coexistence, qmd PATH setup)
- [x] Harden `migrate.sh` HTML-comment regex (allow leading whitespace before `<!--`; don't require closing `-->`; pattern stored in variable to avoid bash `<` parse error)
- [x] `/onboard` full-capture on first run (`bin/onboard-report.sh`: removed docs/ regex filter + 3-file cap; README/docs/stack files read with `cat` not `head` — maximal one-time capture, later sessions run from memory)
- [x] Fix false "settings.json invalid JSON" on Windows (`install.sh` + `doctor.sh`: pipe file via `cat` to node/python stdin — Windows-native interpreters can't resolve MSYS `/c/...` path args; see gotchas.md)
- [x] `/onboard` enrichment from Understand-Anything concepts: architecture-layer classification (API/Service/Data/UI/Utility) + dependency-ordered guided tour (reading order) + self-review validation step (`commands/onboard.md`); symbol outline via existing `codemap.sh outline` fed into `onboard-report.sh` (graceful degrade)
- [x] `/onboard` evolutionary update (incremental re-onboard, no data loss): `.claude-docs/.onboard-rev` marker + delta-aware report (commits / changed files / stale-doc hints since last onboard) → UPDATE mode patches existing docs surgically instead of overwriting; preserves hand-edits
- [x] Fix `onboard-report.sh` printf leading-dash crash (`printf -- '- %s\n'` at lines 145+179; under `set -e` aborted sections 4/6–10 on any repo with `.gitignore`; gotcha documented)
- [x] Fix `codemap.sh def`/`callees` dead lookup — `grep -F "^sym\t"` made `^` literal (matched nothing); replaced with awk exact first-field compare; `callers` rg pattern now escapes regex metachars; `.sh` added to staleness check
- [x] Multiline `<private>` stripping — perl `-0pe 's/<private>.*?<\/private>//gs'` (old single-line sed missed blocks spanning lines = privacy leak); sed fallback + trace warning when perl absent
- [x] install.sh completeness: `bin/memstat.sh` (was missing → `/memstat` broken on fresh install), `commands/migrate-legacy-memory.md`, `bin/lib/paths.sh`, `templates/` → `~/.claude/templates/` (CLAUDE.md refs fixed from phantom `~/.claude/dist/...`)
- [x] post-tool-use.sh precedence fix — `A && B || C` matched any tool writing `CLAUDE.md`; parenthesized
- [x] Stale qmd lock cleanup — crash between mkdir/rmdir would silently disable qmd refresh forever; locks >10 min now removed at SessionStart
- [x] DRY `_add_path` → `bin/lib/paths.sh` (was duplicated in session-start.sh + memstat.sh)
- [x] bats-core test suite (`tests/`: 29 cases — session-start staleness/CWD/privacy-multiline/compression/JSON-validity, post-tool-use capture patterns, onboard-report printf regression, install.sh completeness sanity) + GitHub Actions CI (ubuntu + windows Git Bash, `bash -n` + `bats tests/`)
- [x] Hook detection by command, not event name (`install.sh`: foreign tools' hooks on same events no longer cause silently-skipped registration); `update.sh --dry-run` no longer pulls (fetch + preview only); jq validator in merge-settings; INSTALL.md update-flow section (v6.15.1)
- [x] Protocol slimming + double-load dedup: `PROTOCOL.md` slim core → `~/.claude/CLAUDE.md`; fat sections → `templates/protocol/{workflows,knowledge-store,obsidian}.md` on demand; repo CLAUDE.md now thin dev entry (v6.16.0)
- [x] Verbatim transcript export: `bin/transcript-export.sh`, SessionStart-wired, incremental + rolling 30d + `<private>`-stripped + `.claude-private`-aware; `/recall` now searches past conversations (v6.16.0)
- [x] MCP wrapper for `/recall`: `bin/mcp-recall.mjs` — zero-dep stdio server, `search_memory` + `get_identity` for subagents/headless (v6.16.0)
- [x] Fact lifecycle: `confidence: verified|inferred` + SUPERSEDE + dated `## History` in gotchas/decisions; protocol rule 7 + templates + onboard (v6.16.0)
- [x] Distillation timeline line in project.md (`## Timeline`, one line per wrapped task) (v6.16.0)
- [x] shellcheck in CI (ubuntu, `-S warning`, all scripts) + cleanup; found & fixed dead `migrate.sh` Pass B (`local` at top level under `set -e`) (v6.16.0)

---

## Backlog

### M/S — `/onboard-memory` domain / business-flow section

**What:** Optional `architecture.md` block that maps code → real business processes (e.g. `checkout: cart → payment → order → fulfillment`), beyond the technical request→service→persistence flow.

**Why:** Technical layers don't capture *what the product does*. A domain view helps a new agent reason about feature work, not just structure. Analog of Understand-Anything's `domain-analyzer`.

**How:** Add a directive to `commands/onboard-memory.md` Step 2 ("for app projects, trace 1–3 primary business flows from entry point through services") + a `## Business flows` template section. Skip for libraries/tools. Pure LLM reasoning, no new tooling.

**Deferred from:** v6.12.0 scoping (kept lean — A+B shipped, C deferred).

---

### M/S — SESSION.md size warning in SessionStart

**What:** If SESSION.md exceeds a threshold (e.g. 4 KB), inject a warning into `additionalContext` advising the model to trim it.

**Why:** SESSION.md bloats silently over long sessions. Every compaction re-reads the full file. A size warning gives the model a nudge to prune before cost compounds.

**How:** `wc -c "$session_file"` in `session-start.sh`; if above threshold add one-liner to `base` message.

---

### M/M — Periodic SESSION.md cleanup cron

> **Absorbed by** "vault-doctor.sh" (Memory quality & token budget section) — implement as its stale-session check + `--fix` mode rather than a standalone cron.

**What:** A script (or cron entry added by `install.sh`) that finds SESSION.md files with `last_updated` older than N days (default: 30) and wipes them to the empty template.

**Why:** Abandoned sessions accumulate in `~/.claude/projects/*/memory/`. No cleanup mechanism exists today. Over months, stale sessions fill disk and pollute `/recall` search results.

**How:** `bin/cleanup-sessions.sh --older-than 30d --dry-run` (dry run by default). Optional cron wiring in `install.sh`.

---

### M/L — Lightweight vector search without qmd

**What:** Replace `qmd embed` dependency with a pure-Node local embedder using ONNX Runtime + a small model (e.g. all-MiniLM-L6-v2 at ~23 MB). Ship inside the package.

**Why:** `qmd` requires separate install + GGUF model download (hundreds of MB). Many users skip vector search entirely because setup friction is too high. A bundled ONNX embedder would make hybrid search zero-dependency.

**Tradeoff:** Larger package size. ONNX Runtime has native bindings — adds install complexity on some platforms. Validate on Windows first (biggest pain point currently).

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

## Memory quality & token budget (iva analysis, 2026-07-05)

Source: comparative analysis against [smixs/iva](https://github.com/smixs/iva) (willow-tree memory: verbatim daily transcripts → rollup summaries → always-on CORE.md + typed cards). The H-priority items from this section (fact lifecycle, protocol slimming, transcript indexing) + distillation timeline shipped in v6.16.0 — see "Already shipped".

### M/S — index.md auto-generation (iva `moc.generate` analog)

**What:** Script regenerates the routing table in `.claude-docs/index.md` from each doc's frontmatter (`description`, `tags`). Hand-written routing notes survive in a marked manual block.

**Why:** index.md is maintained by hand and drifts — new docs get forgotten, deleted docs leave dead rows. iva regenerates MOC.md nightly for the same reason.

**How:** `bin/gen-index.sh` (bash + awk over frontmatter); callable from `/onboard-memory` UPDATE mode and vault-doctor.

---

### M/S — vault-doctor.sh (memory content health, mechanical)

**What:** `bin/vault-doctor.sh` — deterministic, no-LLM checks over memory content (vs `doctor.sh` which checks the install): broken relative md links in `.claude-docs/`, docs missing frontmatter, docs absent from index.md (orphans), IDENTITY.md > 25 lines, SESSION.md oversize, stale sessions (>30d). Absorbs the "Periodic SESSION.md cleanup cron" idea below as one of its checks (`--fix` mode wipes stale sessions).

**Why:** Content rots silently today; install-doctor can't see it. iva runs exactly this split: LLM does rollup, mechanical doctor does hygiene.

---

### M/S — Duplicate hook registration check in doctor.sh

**What:** Detect the same command registered more than once for the same event across settings files; warn with file/event.

**Why:** Observed live: a SessionStart context block injected twice → double token cost every session + double execution. Easy to cause via repeated installs/merges, invisible without tracing.

**How:** jq/python pass over merged `settings.json` + `settings.local.json` in `doctor.sh`.

---

### L/S — Trim `# Recent turns` verbatim quota

**What:** Reduce from 5 verbatim turns to 3, or gate behind a flag file.

**Why:** Verbatim quotes are token-heavy on every reload; after a compact the summary already carries the gist. Tradeoff: protocol explicitly values "live texture" the summarizer paraphrases away — measure before cutting.

---

### L/S — Verify qmd indexes frontmatter fields

**What:** Check whether qmd's FTS index covers frontmatter values (`description`, `tags`, names). If not: document as a known `/recall` limitation, or prepend key frontmatter fields into the indexed body via the transcript-export/gen-index tooling.

**Why:** iva weights frontmatter meta-fields high because name/company facts often exist ONLY in frontmatter — search misses them otherwise. Same risk applies to our cards-style docs.

---

### L/L — Link-graph rerank for /recall

**What:** Rerank BM25 hits by markdown-link proximity between memory files (iva reranks via its nightly-built vault graph).

**Why:** Related docs surface together. Requires patching qmd or a post-processing wrapper + a link-graph builder. Low value until memory stores grow large; defer.

---

## Hook reliability

### M/M — Indexer frontmatter format as first-class citizen

**What:** Claude Code's memory indexer rewrites SESSION.md frontmatter, nesting fields under `metadata:` (see gotchas.md). v6.15.0 patched the `cwd:`/`last_updated:` readers to tolerate indentation, but the SESSION.md template in CLAUDE.md still teaches the flat format — every file effectively lives in two formats. Decide: either ship the template in indexer format, or add a test matrix "both formats" for every frontmatter reader (`migrate.sh` and `memstat.sh` read frontmatter too and were not audited for this).

**Why:** Each new frontmatter consumer is a fresh chance to repeat the dead-`^cwd:` bug. One canonical answer kills the bug class.

---

### M/S — hook-trace.log rotation

**What:** Every SessionStart/PostToolUse appends to `~/.claude/debug/hook-trace.log`; nothing ever truncates it. Add rotation at SessionStart (debounced daily): keep last N lines (e.g. 2000), `tail -n 2000 log > tmp && mv`.

**Why:** Grows unbounded forever. Months of sessions = megabytes of noise that also slows any doctor/debug grep.

---

### M/S — Shared `bin/lib/validate-json.sh`

**What:** Extract the python3 → node → jq JSON-validation chain (currently copy-pasted in `install.sh`, `doctor.sh`, `merge-settings.sh`, `session-start.sh` — 4 copies) into a sourced library, like `slug.sh`/`paths.sh`.

**Why:** Any fix to the validation logic (e.g. the Windows MSYS-path gotcha) must be applied 4 times today; drift is inevitable.

---

### L/S — BSD `stat` fallback in memstat.sh

**What:** `memstat.sh` uses GNU `stat -c %Y`; BSD/macOS needs `stat -f %m`. Add a runtime probe or dual-form fallback.

**Why:** Windows-first project, but macOS users exist; staleness display silently shows 0 there.

---

### L/M — merge-settings.sh fallback dedup

**What:** The non-jq fallback path appends source hooks to an event that already exists in target without deduplicating commands (admitted in the script header comment). Implement command-level dedup in all three parser paths.

**Why:** Re-running install with a partially-merged settings.json can register a hook twice → double execution per event.

---

## Install / Uninstall

### M/S — Dynamic hook self-test in doctor.sh

**What:** doctor.sh checks statics only (files exist, JSON valid, hooks registered). Add a live check: run the *installed* `session-start.sh` with a temp `CLAUDE_HOME` + temp cwd, assert exit 0 and valid output JSON. Same for `post-tool-use.sh` with a canned stdin event.

**Why:** A broken runtime copy (bad merge, CRLF, partial install) currently surfaces only as silent memory loss in the next session. bats tests cover the repo copy, not the installed one.

---

### M/S — CRLF check for installed hooks in doctor.sh

**What:** `install.sh` copies working-tree files verbatim; on Windows a CRLF-contaminated working copy installs CRLF hooks (git warned about exactly this during the v6.15.0 commit). Add to doctor: `grep -q $'\r' ~/.claude/hooks/*.sh` → fail with "re-checkout with LF / run dos2unix".

**Why:** A `\r` in a hook either kills it outright on strict bash or produces mangled output — silently, since hooks swallow errors by design.

---

### M/S — Version-drift nudge at SessionStart

**What:** `update.sh` exists but users forget it. SessionStart (debounced weekly, same marker pattern as qmd refresh): compare `~/.claude/.memory-version` against the source repo's CHANGELOG head (path from `.memory-source`); if behind, add one line to additionalContext: "memory protocol vX installed, vY available — run bash ~/.claude/bin/update.sh".

**Why:** v6.15.0 shipped fixes for silently-broken features; an outdated install keeps the bugs without anyone noticing. Zero-cost nudge closes the loop.

---

### M/S — Uninstall instructions and `bin/uninstall.sh`

**What:** Document and script complete removal: hook files from `~/.claude/hooks/`, entries from `settings.json`, slash command files from `~/.claude/commands/`, bin scripts. Restore default Claude Code memory behavior.

**Why:** INSTALL.md covers upgrade/rollback but has zero guidance on "I want to remove this entirely." Users who switch systems or tools are left guessing which files to delete.

**How:** `bin/uninstall.sh` mirrors `install.sh`: removes known files, strips the `hooks` block from settings.json using `jq` or a sed/Python fallback. Adds "Uninstall" section to INSTALL.md. Default Claude memory is restored automatically once hooks block is removed.

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

### M/S — pre-commit hook for this repo (dev-side)

**What:** A repo-local git pre-commit hook (installed via `git config core.hooksPath .githooks` or documented one-liner): run `bats tests/` + warn if CHANGELOG.md is untouched while *.sh/commands/* changed (dev-workflow's mandatory triple).

**Why:** dev-workflow.md discipline currently relies on memory. The v6.14 rename shipped without installing the renamed command anywhere — exactly what an automated triple-check would have caught.

---

### M/S — extend bats coverage to codemap.sh and doctor.sh

**What:** `tests/` covers hooks, onboard-report and install completeness (since v6.15.0). Add cases for `codemap.sh` (def/callers/outline against a fixture repo — would have caught the dead `grep -F "^sym"` lookup) and a `doctor.sh` smoke run.

**Why:** codemap def was silently broken for several releases; only a behavioral test catches "command runs fine, returns nothing".

---

### M/S — bats coverage for migrate.sh

**What:** Behavioral tests for both migration passes against a fixture CLAUDE_HOME: Pass B (HTML-comment marker → YAML frontmatter, asserting the file is actually rewritten) and Pass A (legacy MEMORY.md / typed-prefix detection).

**Why:** v6.16.0's shellcheck run revealed Pass B had been completely dead (`local` at top level under `set -e`) across multiple releases — zero test coverage meant zero signal. Same "runs fine, does nothing" class as the codemap bug.

---

## Notes

### Current top queue (re-ranked 2026-07-05; all five H items + distillation timeline shipped in v6.16.0)

1. **M/S — vault-doctor.sh** (absorbs SESSION cleanup cron) — content rots silently; now also the natural home for transcript-export retention checks.
2. **M/S — Duplicate hook registration check in doctor.sh** — observed live; double token cost per session.
3. **M/S — bats coverage for migrate.sh** (new) — Pass B was silently dead for multiple releases; only a behavioral test catches "runs fine, does nothing".
4. **M/S — index.md auto-generation** — routing drift.
5. **M/S — doctor dynamic self-test + CRLF check + version-drift nudge** — installed-copy health.
6. **M/M — `/session-end` command** — now higher value: it's the enforcement point for the shipped distillation-timeline convention.
7. Rest: `/onboard-memory` business flows, SESSION size warning, frontmatter format matrix, validate-json lib, L/S–L/L tail.

### Legend

- Priority (H/M/L) = user-impact × frequency of the pain point.
- Effort (S/M/L) = engineering days: S < 1d, M = 1-3d, L > 3d.
- Items tagged `H/S` are the best next moves. Start there.
- Before implementing any idea, verify it doesn't violate the core explicit-promotion philosophy: auto-capture must be scoped to high-signal events only.
