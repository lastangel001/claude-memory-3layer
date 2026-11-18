# claude-memory-3layer

[![Release](https://img.shields.io/github/v/release/lastangel001/claude-memory-3layer?label=release&color=blue)](https://github.com/lastangel001/claude-memory-3layer/releases/latest)
[![CI](https://github.com/lastangel001/claude-memory-3layer/actions/workflows/ci.yml/badge.svg)](https://github.com/lastangel001/claude-memory-3layer/actions/workflows/ci.yml)

> Hand-curated, in-repo memory for Claude Code. Three layers, deliberate placement, selective auto-capture (3 high-signal events only). With hybrid retrieval (qmd) and on-demand symbol map (ctags). 100% local.

A replacement for Claude Code's default memory system, battle-tested on ~15 real projects (PHP/mpcmf, Python, TS, reverse-engineering, multi-machine setups).

## Why

After trying the popular options:
- **[CodeGraph](https://github.com/colbymchenry/codegraph)** — code knowledge graph. Live MCP-transport bug at the time of evaluation; correctness bug in module-qualified symbol lookup (silently picks random collisions).
- **[AgentMemory](https://github.com/rohitg00/agentmemory)** — persistent memory via MCP. Issue #522: *"Sessions never created and silent data loss"*. Philosophically opposite to what a coding agent needs (auto-capture vector blob vs explicit curated knowledge).

This system is what crystallized as the alternative: **what you write down, you own. What you don't write down, doesn't exist.** No vector blobs, no auto-capture, no daemons, no MCP servers. Just markdown + a tiny set of tools.

## Design principle

> *"Would a server agent at midnight, with no memory and no human, need this?"*
> — **yes** → put it in the repo (git-tracked, travels with code)
> — **no** → put it in account-local memory (`~/.claude/...`)

Codebase facts go with the codebase. Personal preferences and per-task scratch stay account-local. Don't cross the wires.

## Architecture — three layers, different decay rates

| Layer | Path | Git? | Decay |
|---|---|---|---|
| **L0 Identity** | `~/.claude/memory/IDENTITY.md` | no | permanent (≤25 lines) |
| **L1a Repo entry** | `<repo>/CLAUDE.md` | **yes** | per-project; thin, auto-loaded |
| **L1b Repo docs** | `<repo>/.claude-docs/*.md` | **yes** | per-project; thick, lazy-loaded |
| **L1 fallback** | `~/.claude/projects/<slug>/memory/project.md` | no | for repos where in-repo isn't appropriate |
| **L2 Session** | `~/.claude/projects/<slug>/memory/SESSION.md` | no | per-task; dies when task ends |

`<repo>/CLAUDE.md` is loaded into every session by Claude Code automatically — keep it **thin**. Bulky knowledge lives in `<repo>/.claude-docs/*.md` and is read on demand via the doc index in `CLAUDE.md`.

The killer move is **`<repo>/.claude-docs/gotchas.md`** — every non-obvious footgun goes here. *"Looks right but breaks"* / *"Looks wrong but is intentional"*. One paragraph each. Future sessions hit the same wall and benefit immediately.

## Memory in action

### Cross-session continuity

You work on an auth module Monday, stop mid-task. SESSION.md at end of day:

```markdown
# Goal
Add rate limiting to /login endpoint

# State
- branch: feat/auth-ratelimit
- last: extracted JWT validation to src/auth/middleware.ts
- next: wire RateLimiter into middleware chain

# Decisions
- [14:30] JWT over session cookies — stateless, horizontal scale
- [14:45] dropped express-rate-limit — no Redis cluster failover handling

# File map
- src/auth/middleware.ts:42 — token validation, rate limit hook point
- src/auth/config.ts:8 — TTL constants (hardcoded intentionally, see gotchas)
```

Tuesday, new session opens. SessionStart hook injects SESSION.md. Claude knows: what's done, what's next, why JWT, why not `express-rate-limit`, where to look. **No briefing needed.**

---

### Gotcha discovered → written immediately

Claude notices `hasMany` relationships in Laravel return soft-deleted records silently. Writes to `.claude-docs/gotchas.md` without being asked:

```markdown
## Laravel: soft-delete not applied to relationship queries

confidence: verified

`hasMany`/`belongsToMany` don't apply global scope by default.
`$user->posts` includes soft-deleted posts with no warning.

Fix: `withoutTrashed()` explicitly, or override `newQuery()` in the model.
```

Every future session in this repo has this before writing any relationship query. Same wall — never hit twice.

Facts carry a lifecycle: `confidence: verified` (reproduced) vs `inferred` (deduced from reading) — the model asserts the first and hedges the second. An outdated fact is never silently deleted: it gets `status: superseded` and a dated line in `## History`, so the top of the file is always current truth and the trail survives.

---

### Decision with tradeoff → captured with rationale

After choosing UUID v7 over v4:

```markdown
# Decisions
- [10:15] UUID v7 over v4 — cursor pagination needs time-ordered inserts; v4 random = index fragmentation at scale
```

Three months later, new session asks "why UUIDs?". Answer is in Decisions. No re-research. No accidental suggestion to switch back.

---

### Compact / context reset → state comes back without the model's help

Context fills mid-task and auto-compact starts — the model gets no turn, so it cannot "flush" anything at that moment. Two things happen instead, both deterministic:

1. **PreCompact hook** writes `memory/compact-snapshot.md` — the last user turns *verbatim* and the git position — and hands the summarizer instructions on what to keep verbatim (its stdout is the only channel Claude Code offers a PreCompact hook).
2. **SessionStart hook** runs again after compaction and re-injects `SESSION.md` plus that snapshot, wrapped in a `<memory-record>` block that says what it is: a record of past work to verify against the code, not a new instruction.

What makes this work is the continuous-update rule: `SESSION.md` is written as the work proceeds, so it is already current when compaction hits. Resume is the same branch, the same next step, the same rationale.

---

### What does NOT get saved

- ✗ Read a file, found expected content → no new knowledge
- ✗ Ran grep → intermediate step, derivable from code
- ✗ Obvious implementation detail → visible in diff
- ✗ Trivial choice with no tradeoff → no future impact

**Quick test:** *"Without this, would a future agent make a worse decision or repeat work?"* — no → don't write.

---

## Tools (all local, no daemons)

### `/recall <query>` — hybrid memory search

BM25 + GGUF embeddings + LLM rerank over all your memory files. Backed by [qmd](https://github.com/tobi/qmd) (Tobi Lütke).

```
/recall MongoDB legacy driver
/recall гочи WSL DNS IPv6
/recall --here retry backoff window      # scope to current project
```

### `/codemap def|callers|callees|outline <symbol>` — on-demand symbol map

universal-ctags + ripgrep. Cache at `<repo>/.codemap.tags` (gitignore-able). Auto-rebuilds when source files are newer.

```
/codemap def LlmClient::chat
/codemap callers AgentExecutor
/codemap outline
```

### `/onboard-memory` — Bootstrap memory for an existing project

Scans the repo and creates `CLAUDE.md` + full `.claude-docs/` scaffold. Run once per project, from the repo root.

Internally uses `bin/onboard-report.sh` to collect raw data (stack files, directory structure, git log, hot files, FIXME/HACK grep, full project documentation — README + every `docs/` file read in full on first run — and a symbol outline of top-level classes/functions when `codemap` tools are present), then instructs Claude to reason over the output and create all memory files. The generated `architecture.md` includes an **architecture-layer table** (API/Service/Data/UI/Utility) and a dependency-ordered **reading order** ("start here") for new contributors; a self-review pass validates links and flags fabricated content before reporting. Does not commit — user reviews first.

**Re-running is safe.** `/onboard-memory` records a revision marker (`.claude-docs/.onboard-rev`); on a second run it enters **update mode** — it computes the git delta since the last onboard and *patches* the existing docs (preserving hand-edits) instead of overwriting them. Knowledge evolves with the codebase, no data loss.

```
/onboard-memory
```

### `/memory status | refresh` — index health

Shows qmd collection health and forces an index refresh. Promotion has one mode, **explicit** — cross-session memory only when the user says "remember"/"запомни" (gotchas are the single always-write exception). The `auto on|off` toggle was removed in v6.19.0: its flag file was read by no hook, and the mode contradicted the rule above.

### `/session-end` — distil & close a task

Enforces the wrap-up ritual so high-signal work isn't lost at the next compact: promotes SESSION.md's durable facts to their permanent layer (gotchas / architecture / conventions / `CLAUDE.md` / IDENTITY / project.md — in-repo beats account-local), appends one `## Timeline` line to `project.md`, confirms what was promoted, then wipes SESSION.md to a clean template (keeping the `cwd:` anchor). Never commits — repo edits are proposed for you to review.

### `/memstat [--watch]` — task manager for the memory subsystem

Shows running qmd/ctags processes (PID, RAM, runtime), index progress (vectors embedded vs pending), refresh schedule, recent log activity, and a stall/health check. Use when `node.exe` is eating CPU and you want to know what it's doing. Backed by `bin/memstat.sh`.

```
/memstat
/memstat --watch
```

### MCP: `search_memory` / `get_identity` — memory for subagents

Slash commands are unreachable from subagents, task runners and `claude -p` headless mode. `bin/mcp-recall.mjs` (zero dependencies, stdio, no daemon) exposes the same BM25 search and the L0 identity as MCP tools callable inside any agentic loop:

```bash
claude mcp add --scope user memory-recall -- node ~/.claude/bin/mcp-recall.mjs
```

### Health & maintenance

- **`bin/doctor.sh`** — checks the *install*: hook files + syntax, `settings.json` validity, duplicate/registered hooks, CRLF contamination, a dynamic self-test that runs the installed hooks in a throwaway home, optional tools, and the active JSON parser.
- **`bin/vault-doctor.sh`** — checks the *content*: IDENTITY.md over its 25-line cap, oversize/stale SESSION.md files, transcript retention, and (inside a repo) `.claude-docs/` missing frontmatter, orphaned docs, broken links. `--fix` wipes stale sessions to a clean template. `--stale-days N` tunes the threshold.
- **`bin/gen-index.sh`** — regenerates `.claude-docs/index.md` from each doc's `description:` frontmatter, preserving a hand-written MANUAL block. `--check` fails when the index is out of date (wire it into your project's CI).
- **`bin/uninstall.sh`** — removes everything cleanly, strips only our hooks from `settings.json` (foreign hooks kept), and never touches `IDENTITY.md` or `projects/`. `--dry-run` to preview, `--yes` to skip the prompt. See INSTALL.md → Uninstall.

## Hooks (enforce discipline)

- **SessionStart** — injects protocol reminder + active checks on every session open:
  - *Project directory* — resolved from the `transcript_path` Claude Code passes on hook stdin (exact), falling back to the naming formula; the context carries the **absolute paths** of `SESSION.md` and `project.md`, so the model never derives a slug by hand (a hand-derived slug splits memory across two directories — `doctor.sh` reports such twins)
  - *Staleness* — `SESSION.md` >24h old → forces explicit *"continue or reset?"* with user; a closed session (`status: done`) is exempt
  - *CWD mismatch* — reads `cwd:` from `SESSION.md` frontmatter; if it doesn't match current directory, injects hard reset warning — agent never silently continues the wrong project's task
  - *CWD auto-inject* — computes canonical path and injects it as a ready-to-paste value so model always has the correct `cwd:` for new `SESSION.md` files
  - *Privacy redaction* — strips `<private>...</private>` blocks from `SESSION.md` in-place before injecting context (backup at `SESSION.md.bak`; CRLF-safe)
  - *Private path exclusions* — if `.claude-private` exists at the project root, reads it as a glob pattern list (one per line, `#` comments ignored) and instructs the model to treat matching paths as non-existent for all memory and capture purposes
  - *Transcript export* — exports Claude Code's own session transcripts (`.jsonl`) to searchable markdown under `memory/raw/transcripts/` (incremental, `<private>`-stripped, 30-day rolling window, opt-out via `~/.claude/.transcript-export-disabled`) — so `/recall` can quote past conversations even when nothing was written to SESSION.md
  - Also kicks background `qmd update` debounced 6h (atomic marker — parallel sessions don't double-fire)
- **PreCompact** — does two things that need no model. (1) Writes `memory/compact-snapshot.md` via `bin/compact-snapshot.sh`: last 5 user turns verbatim (`<private>` stripped; skipped entirely for a `.claude-private` project) + branch / HEAD / uncommitted count. Only for projects that already keep a `SESSION.md`. (2) Prints plain-text instructions for the compaction summary — keep recent user messages, identifiers, decisions with rationale and the next step verbatim. It does **not** ask the model to flush: compaction starts as soon as the hook returns, and Claude Code discards a PreCompact hook's `systemMessage` (which is all this hook emitted before v6.20.0).
  - *After compaction* SessionStart fires with `source: compact` and inlines `SESSION.md` (up to 5,000 chars) and the snapshot (up to 2,200) in a `<memory-record>` frame. The hook context is capped at 10,000 characters, so the hook sheds in order — snapshot first, then SESSION.md — and falls back to "read these two files now" rather than let Claude Code cut the tail to a preview. `transcript-export.sh` strips the frame so injected state is never indexed as conversation.
- **PostToolUse** — selectively auto-captures three high-signal tool events to `SESSION.md`:
  - a **new** git commit made via Bash or PowerShell → appends `<sha> <subject>`, read from `git log -1` (a command that merely mentions `git commit` captures nothing; one commit is captured once)
  - `Write` / `Edit` / `MultiEdit` of `**/CLAUDE.md` → notes L1a in-repo entry update
  - `Write` / `Edit` / `MultiEdit` of `**/.claude-docs/*.md` → notes L1b doc update (Windows backslash paths included; repeated edits of one doc = one line)

  Registered with matcher `Bash|PowerShell|Write|Edit|MultiEdit` and `async: true`; inside the script two pure-bash gates exit before any interpreter starts, so the hook adds no JSON-parsing cost to ordinary tool calls. Upgrading installs get the new matcher from `install.sh` automatically.

  Everything else is silently ignored — explicit-promotion philosophy preserved for all other events. JSON parsed via `python3 → node → jq → grep` fallback chain; run `bin/doctor.sh` to see which parser is active on your system.
- **Outcome journal** — every hook run that matters writes one line to `~/.claude/debug/hook-diag.jsonl` (`ok` / `degraded` / `failed` + a short note). Hooks fail open by design; this is how a feature that silently falls back on every run becomes visible. `bin/doctor.sh` prints a 7-day summary.

Beyond hook-driven capture, the protocol instructs Claude to write to SESSION.md on specific triggers — no "remember" needed:

| What happened | Where it goes |
|---|---|
| Chose X over Y (reason matters) | `SESSION.md # Decisions` |
| Tried X, failed — reason known | `SESSION.md # Decisions` |
| Behavior contradicts docs/intuition | `.claude-docs/gotchas.md` |
| "Looks right but breaks" / "looks wrong but intentional" | `.claude-docs/gotchas.md` |
| File has non-obvious role or cross-file dependency | `SESSION.md # File map` |

All three hooks run in `set -euo pipefail` strict mode. Any unguarded failure is logged to `~/.claude/debug/hook-trace.log` with `rc` + line number, and a fallback message is emitted — hooks never block session start or tool execution.

### SESSION.md compression

By default, `SESSION.md` is written in compressed caveman notation (drop articles/filler, fragments OK, code/paths exact). SESSION is read by agents, not humans — terseness reduces context cost on every reload and compact. The same notation applies to `project.md` (L1-fallback) including `## Timeline` lines — like SESSION.md, it is agent-only and loads on every session start.

**Toggle:**

```bash
touch ~/.claude/.session-compress-disabled   # disable permanently
rm ~/.claude/.session-compress-disabled      # re-enable
CLAUDE_SESSION_COMPRESS=0 claude             # disable for one session
```

Both hooks read the flag on every fire — no restart needed. When disabled, the model is instructed to write prose naturally.

### Privacy: `<private>` tags

Wrap transient secrets inside `<private>...</private>` in any message or note:

```
OAuth token was <private>sk-ant-abc123</private> — stored in env ANTHROPIC_API_KEY.
```

The SessionStart hook strips all `<private>` blocks from `SESSION.md` in-place before the content reaches model context. PreCompact instructs the model to strip tags before writing. Defense-in-depth: even if tagged content slips through, it is removed at the next session boundary. **Never write raw secrets to memory files** — write the env-var name or path instead.

## What's deliberately NOT in it

- ✗ **Blind auto-capture** of arbitrary tool output — that's the failure mode `AgentMemory` documents in their open issues (silent data loss, runaway logs). The PostToolUse hook captures exactly 3 patterns (git commit, CLAUDE.md write, .claude-docs write); everything else requires explicit "remember".
- ✗ **MCP server with 50+ tools** — context-window tax in every request, whether you use those tools or not. (The optional bundled `mcp-recall` exposes exactly two: `search_memory`, `get_identity`.)
- ✗ **Persistent code-graph daemon** with per-project SQLite — `/codemap` is on-demand instead. Re-scan in ~1s for medium repos.
- ✗ **Vector blob** you can't `diff`. Memory is markdown you can read with your eyes.
- ✗ **Cloud, OpenAI keys, embedding APIs** — qmd uses local GGUF models (embeddinggemma-300M, qwen3-reranker, qmd-query-expansion).

## Quick start

See [INSTALL.md](INSTALL.md) for full instructions across Windows / macOS / Linux. TL;DR:

```bash
# 1. Run install.sh — drops everything into ~/.claude/, merges settings.json automatically
./install.sh
# 2. Edit ~/.claude/memory/IDENTITY.md (≤25 lines, who you are)
# 3. Optional: memory search for subagents / headless runs (one-time, per machine)
claude mcp add --scope user memory-recall -- node ~/.claude/bin/mcp-recall.mjs
# 4. For retrieval tools (optional, recommended):
winget install OpenJS.NodeJS.LTS UniversalCtags.Ctags BurntSushi.ripgrep.MSVC
npm install -g @tobilu/qmd
qmd collection add ~/.claude/memory --name claude-l0
qmd collection add ~/.claude/projects --name claude-projects
QMD_LLAMA_GPU=none qmd embed   # one-time, ~2GB of GGUF models download
```

### Updating

```bash
~/.claude/bin/update.sh            # git pull + re-install in one step
~/.claude/bin/update.sh --dry-run  # fetch + preview pending commits; pulls nothing, writes nothing
```

`install.sh` records the repo path at `~/.claude/.memory-source` on first install. `update.sh` reads it, does `git pull`, then re-runs `install.sh` (idempotent — backs up changed files, never touches `IDENTITY.md` or `projects/`). Run `bash ~/.claude/bin/doctor.sh` to see the installed version.

## Obsidian compatibility

All memory files use YAML frontmatter with hierarchical tags (`memory/l0` / `memory/l1` / `memory/l2` / `memory/repo`). Open `~/.claude/` or any repo's root as an Obsidian vault — graph view, tag filtering, full-text search across all your projects.

`SESSION.md` carries `status: active` while a task is running; the distillation step sets `status: done` on task wrap-up. Obsidian Dataview query to show live sessions:

```
dataview TABLE last_updated WHERE status = "active"
```

## Repo layout

```
CLAUDE.md                       — the memory protocol (replaces default; goes to ~/.claude/)
INSTALL.md                      — install instructions, troubleshooting
LICENSE                         — MIT
CHANGELOG.md                    — version history
memory/IDENTITY.md              — L0 template
templates/repo/CLAUDE.md        — L1a template (thin in-repo entry)
templates/repo/.claude-docs/*   — L1b templates (gotchas, architecture, conventions, index)
templates/project.md.fallback.template — L1-fallback template (account-local)
hooks/session-start.sh          — project-dir resolution + absolute memory paths + staleness + CWD mismatch + cwd auto-inject + privacy redaction + .claude-private exclusions + compression flag + qmd auto-refresh
hooks/pre-compact.sh            — compaction checkpoint (compact-snapshot.md) + plain-text instructions for the summary
hooks/post-tool-use.sh          — selective auto-capture: new git commits, CLAUDE.md / .claude-docs edits
commands/recall.md              — /recall slash command (hybrid memory search)
commands/codemap.md             — /codemap slash command (symbol map)
commands/memory.md              — /memory slash command (index status + refresh)
commands/memstat.md             — /memstat slash command (memory subsystem status)
commands/onboard-memory.md      — /onboard-memory slash command: scan repo, create CLAUDE.md + .claude-docs/
commands/migrate-legacy-memory.md — /migrate-legacy-memory slash command (legacy → L1-fallback synthesis)
commands/session-end.md         — /session-end slash command (distil + wipe task ritual)
bin/codemap.sh                  — universal-ctags + ripgrep symbol map
bin/doctor.sh                   — install health check (files, settings, dup hooks, CRLF, dynamic self-test, split memory dirs, hook outcomes)
bin/vault-doctor.sh             — memory content health (IDENTITY/SESSION size, stale sessions, doc links incl. the CLAUDE.md doc index); --fix
bin/gen-index.sh                — regenerate .claude-docs/index.md from doc frontmatter; --check for CI
bin/uninstall.sh                — clean removal (strips only our hooks; preserves IDENTITY.md + projects/)
bin/memstat.sh                  — memory subsystem status / task manager (backs /memstat)
bin/onboard-report.sh           — collect raw repo data (stack, git log, hot files, FIXME grep) for /onboard-memory
bin/update.sh                   — one-step updater: git pull + re-install from tracked source path
bin/merge-settings.sh           — programmatic settings.json merge (called by install.sh; usable standalone)
bin/mcp-recall.mjs              — zero-dep MCP server: search_memory + get_identity for subagents/headless
bin/compact-snapshot.sh         — last user turns verbatim + git position → memory/compact-snapshot.md (called by PreCompact)
bin/transcript-export.sh        — export Claude Code .jsonl transcripts → searchable markdown (SessionStart)
bin/lib/slug.sh                 — project-directory resolver: transcript_path → formula → legacy dir (sourced by hooks, doctor, /session-end)
bin/lib/diag.sh                 — hook outcome journal writer (debug/hook-diag.jsonl; sourced by all three hooks)
bin/lib/paths.sh                — shared PATH augmentation for Node/npm tooling (sourced by session-start + memstat)
bin/lib/validate-json.sh        — shared JSON validator (python3 → node → jq; sourced by install/doctor/merge/hook)
migrate.sh                      — mechanical HTML-comment → YAML frontmatter migration (pre-AI step)
settings.snippet.json           — hooks block for ~/.claude/settings.json (SessionStart + PreCompact + PostToolUse)
tests/                          — bats-core test suite (148 cases: hooks, compaction path, slug resolver, install/settings migration, doctor, migrate, codemap, gen-index, vault-doctor)
.githooks/pre-commit            — opt-in dev hook: runs bats + nudges on missing CHANGELOG (git config core.hooksPath .githooks)
.github/workflows/ci.yml        — CI: bash -n + shellcheck + bats + index --check on ubuntu + windows (Git Bash)
IDEAS.md                        — prioritised backlog of future enhancements
```

## License

MIT — see [LICENSE](LICENSE). Use it, fork it, share it.

## Acknowledgments

- [qmd](https://github.com/tobi/qmd) by Tobi Lütke — the retrieval engine that made `/recall` trivial to build
- [universal-ctags](https://github.com/universal-ctags/ctags) — symbol map backbone
- The folks who built [CodeGraph](https://github.com/colbymchenry/codegraph) and [AgentMemory](https://github.com/rohitg00/agentmemory) — evaluating them clarified what this system needed to be *different*

## Part of [openronin](https://github.com/openronin)

A loose collection of self-hosted AI dev tooling. This protocol is compatible with any tool that runs Claude Code — interactive sessions, headless runs, including `openronin`'s GitHub-issue-driven agents.
