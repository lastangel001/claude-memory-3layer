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
- [x] Fix Windows Store `python3` alias stub breaking every JSON parser (v6.17.1): `command -v` passed the non-running stub → validation/auto-capture silently dead → SessionStart fell back to minimal context every session. New `_cmd_runs`/`_json_parser` exec-probe helpers in `validate-json.sh`; all call sites routed through them; see gotchas.md
- [x] Fix `mcp-recall.mjs` `search_memory` "qmd not found" on Windows (v6.17.1): Node `execFile("qmd")` can't spawn the npm sh/`.cmd` shim (no PATHEXT; `.cmd` needs shell). `resolveQmd()` runs qmd's JS entry with `process.execPath` — no shell, safe argv; `QMD_BIN` override + `qmd.exe` fallback; see gotchas.md
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
- [x] `bin/vault-doctor.sh` — memory content health (IDENTITY >25 lines, SESSION oversize/stale, transcript retention, `.claude-docs` missing frontmatter/orphans/broken links); `--fix` wipes stale sessions (absorbs the SESSION-cleanup-cron idea) (v6.17.0)
- [x] `bin/gen-index.sh` — regenerate `.claude-docs/index.md` from `description:` frontmatter, AUTO-INDEX markers + preserved MANUAL block; `--check` CI guard; every doc gained a `description:` (v6.17.0)
- [x] `bin/uninstall.sh` + INSTALL.md Uninstall section — strips only our hooks (foreign hooks/keys preserved), never touches IDENTITY.md/projects/ (v6.17.0)
- [x] `bin/lib/validate-json.sh` — shared python3→node→jq validator; refactored all 4 copy-paste call sites (install/doctor/merge-settings/session-start) (v6.17.0)
- [x] `doctor.sh`: duplicate hook registration check + CRLF check on installed scripts + dynamic self-test (runs installed session-start/post-tool-use in throwaway home) (v6.17.0)
- [x] `session-start.sh`: SESSION.md size warning (>4KB) + version-drift nudge (weekly debounce, `sort -V` forward-only) + strong `last_updated`-required imperative + hook-trace.log rotation (daily, last 2000 lines) (v6.17.0)
- [x] `/session-end` slash command — distil to permanent layers + `## Timeline` line + wipe SESSION.md (enforces the distillation-timeline convention) (v6.17.0)
- [x] `/onboard-memory` business-flow section — app projects trace 1–3 domain processes end-to-end; skipped for libs/CLIs (v6.17.0)
- [x] Indexer-frontmatter bug class closed by audit — only session-start/doctor read scalars (both tolerant); migrate (line-1 HTML) + memstat (no memory reads) provably unaffected; canonical answer in gotchas.md + flat/nested test matrix (v6.17.0)
- [x] `.githooks/pre-commit` (opt-in) — runs bats + nudges on missing CHANGELOG; documented in dev-workflow.md (v6.17.0)
- [x] bats coverage: `codemap.bats` (skips w/o ctags/rg), `doctor.bats`, `migrate.bats` (caught a real still-live Pass B regex bug), `gen-index.bats`, `vault-doctor.bats` — 29 → 76 cases (v6.17.0)
- [x] **Fixed (found by new tests):** `migrate.sh` Pass B regex used `\<!--` — in ERE `\<` is a word-boundary anchor, never matched the literal `<!--`; Pass B was still dead after the v6.16.0 `local` fix. Now literal `<` (v6.17.0)
- [x] Release hygiene: backfilled annotated git tags `v6.3.0`–`v6.17.1` (was only through v6.2.4) + README release/CI badges (v6.18.1)
- [x] Extend SESSION compression rule to `project.md` (L1-fallback, incl. `## Timeline`) — both hooks' compress wording, PROTOCOL.md rule 4, README, fallback template; `tests/pre-compact.bats` added (first PreCompact coverage), `session-start.bats` asserts unique `agent-only memory prose` phrase; flag names/label prefix unchanged (v6.18.0)

---

## Backlog

### M/L — Lightweight vector search without qmd  *(deferred — not a batch item)*

**Status:** the one M-priority item **not** shipped in the v6.17.0 M-sweep, deliberately. It needs ONNX Runtime **native bindings**, adds significant package size, and requires per-platform validation (Windows first) — a multi-day research effort, not a mechanical batch change. Give it its own scoped release; don't fold it into a sweep.

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

Source: comparative analysis against [smixs/iva](https://github.com/smixs/iva) (willow-tree memory: verbatim daily transcripts → rollup summaries → always-on CORE.md + typed cards). The H-priority items from this section (fact lifecycle, protocol slimming, transcript indexing) + distillation timeline shipped in v6.16.0; the mechanical-hygiene items (vault-doctor, index.md auto-generation, duplicate-hook check) shipped in v6.17.0 — see "Already shipped". What remains below is the L-priority tail.

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

## Compression & subagents (caveman analysis, 2026-07-07)

Source: architect assessment against the `caveman` repo's usage analysis (`docs/analysis/optimal-usage.md` there): the two paradigms economically sounder than its flagship output-skill are (a) one-time compression of static memory files (~46% input cut, pay once / save every session) and (b) subagent tool-result digests with `path:line — symbol — note` format discipline. Verdict for this repo: write-time SESSION compression already ships (see "Already shipped"), and the format discipline is protocol-native (`# File map` = `path:line — <role>`, PROTOCOL.md rule-4 template). Gap (a) shipped in v6.18.0 (compression rule extended to project.md). Per-turn skill overhead / cache-thrash risks from that analysis don't apply here — our compression rule is injected once per session by hooks, not per turn.

### L/M — Optional cavecrew-style subagent template (memory-researcher)

**What:** Ship an opt-in agent template (e.g. `templates/agents/memory-researcher.md`) for long agentic sessions: subagent does the heavy searching/reading via `mcp-recall` tools (`search_memory`, `get_identity`) and returns only a digest in `path:line — symbol — note` format; raw tool-results stay in the subagent's context, extending the main thread's window.

**Why:** Plumbing already exists — `bin/mcp-recall.mjs` was built precisely because slash commands are unreachable from subagents (README §MCP). Format discipline is already protocol-native (`# File map`). Complementary to (not overlapping) SESSION.md persistence: cavecrew compresses in-flight tool-results before compact; SESSION.md survives the compact.

**Tradeoff:** The upstream ~60% tool-result-reduction figure is explicitly unverified — do not put numbers in README without an A/B. Must stay opt-in (install flag or manual copy) and daemon-free: core philosophy forbids background processes and auto-behavior. Low urgency until users run long multi-agent sessions against big memory stores.

---

## Hook reliability

### L/S — BSD `stat` fallback in memstat.sh

**What:** `memstat.sh` uses GNU `stat -c %Y`; BSD/macOS needs `stat -f %m`. Add a runtime probe or dual-form fallback.

**Why:** Windows-first project, but macOS users exist; staleness display silently shows 0 there.

---

### L/M — merge-settings.sh fallback dedup

**What:** The non-jq fallback path appends source hooks to an event that already exists in target without deduplicating commands (admitted in the script header comment). Implement command-level dedup in all three parser paths.

**Why:** Re-running install with a partially-merged settings.json can register a hook twice → double execution per event.

---

## Notes

### Current top queue (all H items + distillation timeline shipped v6.16.0; all 18 M-priority items shipped v6.17.0)

The M-sweep is complete. What remains is one deferred M/L and the L-priority tail:

1. **M/L — Lightweight vector search without qmd** *(deferred)* — the only unshipped M item; ONNX native bindings + cross-platform validation make it a scoped release of its own, not a batch slot.
2. **L/M — merge-settings.sh fallback dedup** — re-running install can double-register a hook on jq-only systems.
3. **L-tail** — trim `# Recent turns` quota · verify qmd indexes frontmatter · BSD `stat` in memstat · **L/M** cavecrew-style memory-researcher subagent template · **L/L** link-graph rerank for `/recall` · remote sync for L0/L1-fallback.

### Legend

- Priority (H/M/L) = user-impact × frequency of the pain point.
- Effort (S/M/L) = engineering days: S < 1d, M = 1-3d, L > 3d.
- Items tagged `H/S` are the best next moves. Start there.
- Before implementing any idea, verify it doesn't violate the core explicit-promotion philosophy: auto-capture must be scoped to high-signal events only.
