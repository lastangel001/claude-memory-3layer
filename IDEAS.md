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
- [x] Project directory resolver — slug from hook-stdin `transcript_path` → corrected formula (every non-alphanumeric → `-`) → legacy-formula directory; hook injects absolute SESSION.md/project.md paths, model never derives a slug; `doctor.sh` reports twin directories (v6.19.0)
- [x] PostToolUse rework — narrow matcher + `async`, pure-bash gates before any interpreter, commit evidence from `git log -1` (sha dedupe) instead of parsing the command, `Edit`/`MultiEdit`/PowerShell/backslash paths, no duplicate capture lines (v6.19.0)
- [x] Settings migration — `merge-settings.sh` sync pass for our single-hook groups (matcher + new hook keys), exit 10 = nothing to do; `install.sh` always merges (v6.19.0)
- [x] Hook outcome journal — `bin/lib/diag.sh` → `debug/hook-diag.jsonl` (`ok`/`degraded`/`failed`), `doctor.sh` 7-day summary (v6.19.0)
- [x] Staleness exemption for closed sessions (`status: done`) in `session-start.sh` + `vault-doctor.sh` (v6.19.0)
- [x] Repo's own `.claude-docs/` tracked (architecture.md, generated index.md); `vault-doctor.sh` validates links in the repo `CLAUDE.md` (v6.19.0)
- [x] Removed `/memory auto on|off` — flag read by no hook, contradicted explicit promotion (v6.19.0)
- [x] Compaction path redesign — PreCompact writes `memory/compact-snapshot.md` (last user turns verbatim + git position) and prints plain-text summary instructions; SessionStart `source=compact` re-injects SESSION.md + snapshot within the 10,000-char cap; PROTOCOL rule 5 rewritten (v6.20.0)
- [x] `<memory-record>` frame for injected state (record of the past, not an instruction) + stripped by `transcript-export.sh` (v6.20.0)
- [x] `doctor.sh`: non-canonical memory directory without a twin (v6.20.0)
- [x] Background refresh block resurrected — `_add_path` returned 1 under `set -e`, so transcript export + `qmd update` never ran; completion stamp + `doctor`/`memstat` kick-off-vs-completion check (v6.21.0)
- [x] `bin/recall.sh` — `/recall` as a tested script: qmd or ripgrep/grep fallback (qmd optional), always searches the current repo's `.claude-docs`, `--here`, inline refresh of a stale index, `logs/recall-misses.log` (v6.21.0)
- [x] Native auto memory coexistence — `install.sh --native-memory=off`, `doctor.sh` report, INSTALL.md section (v6.21.0)
- [x] `/memory` removed (built-in name) → `/memstat --refresh`; installer retires the old installed file (v6.21.0)
- [x] Git worktrees share the main checkout's `project.md` (v6.21.0)
- [x] BSD `stat` fallback in `memstat.sh` (v6.21.0)
- [x] Citations + verify-before-use — `src: path#symbol @ sha`, `vault-doctor.sh` checks (file / symbol / commits since), protocol rule 7 (v6.22.0)
- [x] Origin gate — `origin: external` content is not promoted without the user's confirmation; an agent's own "fixed" stays `inferred` until command output shows it (v6.22.0)
- [x] Instruction diet — `vault-doctor.sh` flags an over-long `CLAUDE.md` and README prose copied into it (v6.22.0)
- [x] `# Recent turns` trimmed to ~3 first-sentence entries — verbatim text lives in the PreCompact snapshot and transcript export (v6.22.0)
- [x] Verified: qmd indexes frontmatter as text (slash-joined values are not single terms) — no change needed (v6.22.0)
- [x] Closed-book retrieval eval — `bin/memory-eval.sh`, `/memory-eval`, `.claude-docs/eval-questions.md`; this repo's own questions run in CI (v6.23.0)
- [x] `/recall --timeline` — dated `## Timeline` lines across projects, newest first (v6.23.0)
- [x] `mcp-recall.mjs` without qmd — built-in scan + current repo docs; no exit while a call is pending (v6.23.0)
- [x] `memory-researcher` subagent template — opt-in, read-only, runs `recall.sh`, returns a digest (v6.23.0)
- [x] Fixed: `grep -i -F` aborts under Git for Windows (grep 3.0) — plain-grep recall path was dead on Git Bash (v6.23.0)

---

## Backlog

After the 2026-11 review (hooks vs current Claude Code, [vectorize-io/hindsight](https://github.com/vectorize-io/hindsight), a survey of 2026 agent-memory work) and releases v6.19.0–v6.23.0, nothing here is waiting for "someone to get to it". Each remaining idea is either open with the thing that blocks it, or parked / rejected with the reason.

### Open — blocked on something outside the code

#### L/S — Observe the post-compaction re-injection

**Known so far (2026-11-18, one live idle auto-compaction on v6.23.0):** PreCompact fired with `trigger: auto` on a session nobody was using; the snapshot was written and was correct (last five user turns, verified against the transcript). No SessionStart `source: compact` followed — the next one was `resume`. Details in gotchas.md.

**Still to see:** a *manual* `/compact` typed in a session, then `doctor.sh` → *Hook outcomes*: is there a `SessionStart … source=compact inject=…` line, and did the `<memory-record>` block arrive after the summary?

**Blocked on:** a human at the keyboard. A session cannot trigger its own compaction, another session cannot send it the command (a cross-session message is a user turn, not `/compact`), and a nested `claude -p` is not an option.

**If `source: compact` never shows up on the idle path:** consider inlining SESSION.md on `resume` too when `compact-snapshot.md` is newer than the session's last recorded injection — but only once the manual path has been seen working, so there is something to compare against.

#### L/S — Watch the background refresh across platforms

**What:** after a few days on v6.21.0+, check `doctor.sh` → *Index refresh* on macOS and Linux.

**Blocked on:** whether Claude Code lets a hook's detached child outlive the hook on every platform is not documented. Verified on Windows Git Bash only. If a platform kills it, the doctor will say "kicked but none has ever completed" — then move the refresh to an `async` hook or run it inline in `recall.sh` only (which already self-heals).

#### L/S — PostCompact: keep the compact summary

**What:** a PostCompact hook whose input carries `compact_summary`; save it next to SESSION.md.

**Blocked on:** the hooks docs give no version for the event and are silent on how an older Claude Code treats an unknown event name in `settings.json`. The transcript already holds the summary. Ship behind a version check, or once the minimum supported Claude Code version is known to have the event.

### Parked — sound idea, not worth its cost today

#### L/M — Ship as a Claude Code plugin

A plugin can carry hooks (`hooks/hooks.json`, `${CLAUDE_PLUGIN_ROOT}`), namespaced commands and agents — but **not** an always-loaded `CLAUDE.md`, which is the protocol itself; it would have to arrive through SessionStart `additionalContext`, capped at 10,000 characters, on every session. Every script also assumes `~/.claude/bin`. That is a second install path to keep correct on three platforms for the sake of a nicer first install. Revisit if plugins gain a way to contribute instructions.

#### L/M — `merge-settings.sh` jq-only path: no sync pass

On a machine with jq but neither python3 nor node, an upgrade keeps an old PostToolUse matcher and cannot add our hook to an event another tool already occupies. Rare configuration; the in-script gates keep the old matcher cheap. Port the dedup + sync logic to jq if a real report comes in.

#### L/S — `project.md` keyed by repo root for subdirectory sessions

v6.21.0 shares `project.md` across linked worktrees. A session started in a *subdirectory* of a repo still gets its own project directory, because Claude Code keys transcripts by cwd and `SESSION.md` should stay with them. Resolving only `project.md` to the repo root is possible, but splits the two files across directories for little gain — most sessions start at the root.

#### M/L — An LLM-answered eval

`memory-eval.sh` measures retrieval: does recall return a file that holds the answer. Whether an agent then *answers correctly* needs a model run per question — non-deterministic, costs tokens, cannot gate CI. Worth doing by hand before changing the compression notation or the SESSION.md template: have a subagent that may read only the memory files answer the same questions, and compare.

### Rejected — with the reason

#### Lightweight vector search without qmd (ONNX embedder)

The motivation was that qmd's setup friction left many installs without any search. Since v6.21.0 `/recall` works with ripgrep or plain grep and qmd is optional, so the friction no longer costs recall — only hybrid search, which is an opt-in refinement. Bundling ONNX Runtime means native bindings and per-platform validation for a marginal gain. The survey also found plain filesystem search competitive with dedicated memory stores on published benchmarks.

#### Remote sync for IDENTITY.md / project.md

Out of scope for a tool whose promise is "plain files you own". Syncing account memory is a private git repository in `~/.claude/memory` (or any file-sync tool); encrypting and scheduling it is a separate product with its own failure modes.

#### Link-graph rerank for `/recall`

Needs a link-graph builder and a rerank step for stores that are, in practice, a few dozen files per project. Ranking by distinct query terms plus "curated before transcripts" already puts related docs together; no measured miss points at link structure.

#### Hindsight-style automatic memory (LLM extraction at write time, background consolidation, entity graph)

Requires a server, a database and a model call on every write, and promotes without being asked — the opposite of this project's two rules (no daemons, explicit promotion). What was worth taking from it is already in: the record-of-the-past framing, hook outcome diagnostics, commit-anchored freshness, worktree identity.

---

## Notes

### Where things stand (2026-11)

All H and M items are shipped (v6.16.0–v6.23.0). The backlog above holds three *open* items that need a human or more platforms, four *parked* ones, and four *rejected* with reasons. New ideas go under **Open** with what blocks them — or straight to a release.

### Legend

- Priority (H/M/L) = user-impact × frequency of the pain point.
- Effort (S/M/L) = engineering days: S < 1d, M = 1-3d, L > 3d.
- Items tagged `H/S` are the best next moves. Start there.
- Before implementing any idea, verify it doesn't violate the core explicit-promotion philosophy: auto-capture must be scoped to high-signal events only.
