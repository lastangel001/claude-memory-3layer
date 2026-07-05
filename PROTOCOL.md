# Memory Protocol (overrides default)

The memory system described in your default system prompt is **disabled**. Use this protocol instead.

## Core principle

> **"Would a server agent at midnight, with no memory and no human, need this?"**
> — yes → **in the repo** (git-tracked, travels with code, visible to teammates and headless agents)
> — no → **account-local memory** (`~/.claude/memory/...` or `~/.claude/projects/<slug>/memory/`)

Codebase facts live with the codebase. Personal preferences and per-task scratch live in account memory. Don't cross the wires.

## Layers

| Layer | Path | Loaded | Git | Purpose |
|---|---|---|---|---|
| **L0 Identity** | `~/.claude/memory/IDENTITY.md` | every session | no | who you are, hard prefs, env-wide creds |
| **L1a Repo entry** | `<repo>/CLAUDE.md` | auto (cwd in repo) | yes | thin: commands, MUST/MUST NOT, doc index → L1b |
| **L1b Repo docs** | `<repo>/.claude-docs/*.md` | on demand via index | yes | thick: gotchas, architecture, conventions, patterns |
| **L1-fallback** | `~/.claude/projects/<slug>/memory/project.md` | every session (hook) | no | projects without repo / not-in-repo context |
| **L2 Session** | `~/.claude/projects/<slug>/memory/SESSION.md` | session start + after compact | no | per-task working state; survives compact, dies with task |

`<slug>` = cwd: drive letter + `--` + rest with `\`/`/`/`_` → `-` (e.g. `C:\dev\my_app` → `C--dev-my-app`). `<repo>` = `git rev-parse --show-toplevel`. No journal/archive layer — sessions are per-task; carrying them forward is noise.

## ON SESSION START — DO THIS FIRST

Before answering the first message, in parallel:

1. `Read ~/.claude/memory/IDENTITY.md`
2. `<repo>/CLAUDE.md` is auto-loaded — treat as L1a. Do NOT auto-read `.claude-docs/*` — open on demand via the index.
3. `Read ~/.claude/projects/<slug>/memory/SESSION.md` if exists — working state from before compact/restart, authoritative.
4. `Read ~/.claude/projects/<slug>/memory/project.md` if exists.

No L1a and no L1-fallback + substantive work starting → propose creating L1a (templates in `~/.claude/templates/repo/`; process: `~/.claude/templates/protocol/workflows.md`). No SESSION.md → create from template below when substantive work begins.

## What goes where

| Learned | Goes to |
|---|---|
| **Non-obvious gotcha / footgun / "looks wrong but intentional"** | `<repo>/.claude-docs/gotchas.md` ← **HIGHEST LEVERAGE** |
| Architecture, recurring pattern | `<repo>/.claude-docs/architecture.md` / `patterns.md` |
| Codebase convention (naming, commits, lint) | `<repo>/.claude-docs/conventions.md` |
| Top-level command, MUST/MUST NOT, doc-index entry | `<repo>/CLAUDE.md` (keep thin) |
| What's in flight on current task | SESSION.md |
| User identity, hard preference, env-wide credential | `IDENTITY.md` |
| Project context, no repo / not for repo | `project.md` (L1-fallback) |

Never put codebase facts in account memory. Never put personal preferences in repo files.

## Rules

1. **L0 is sacred** — ≤25 lines hard cap. Never project-specific.
2. **L1a is thin** — it loads into every session in that repo; bloat taxes all work there.
3. **L1b is read on demand** — big, typed, lazy; the L1a doc index routes to it.
4. **L2 is the killer feature — update SESSION.md as you work, not at end.** Default prose: compressed caveman notation (drop articles/filler, fragments OK, code/paths/numbers exact) — toggle off via `~/.claude/.session-compress-disabled` flag file or `CLAUDE_SESSION_COMPRESS=0`; hooks announce the active mode. Write triggers:
   - `# Decisions` — chose X over Y (reason matters later); tried X, failed (reason known); constraint discovered; obvious solution rejected intentionally.
   - `# State` — after each task chunk, on block/unblock, on branch change. Last action + next step.
   - `# File map` — non-obvious source of truth; misleading name; non-obvious cross-file dependency.
   - `# Recent turns` — update before any potentially-large operation and on PreCompact; last ~5 user turns verbatim (long → first sentence + `[...]`; rapid chains grouped with `->`) + 1-line "I did:" each.
   - Quick test: *"Without this fact, would a future agent decide worse or repeat work?"* yes → write; no → skip. Ad-hoc sections encouraged.
5. **PreCompact = mandatory flush.** Write everything needed to resume. Refresh `last_updated:` (UTC ISO) on **every** SESSION.md write. If SessionStart warns `SESSION.md is stale` (>24h), do not silently continue — ask: "last touched X ago, goal was Y. Continue or reset?"
6. **Promotion, not archival.** Cross-session memory persists ONLY on explicit "remember"/"запомни": about user → `IDENTITY.md`; about codebase → propose `<repo>/CLAUDE.md` / `.claude-docs/`; no repo → `project.md`; else ask. Task done without the signal → wipe SESSION.md to template (`# Goal: (none — last task: X)`, frontmatter `status: done`), append one timeline line `- YYYY-MM-DD: <task> — <outcome>` under `## Timeline` in `project.md` (create section if absent). **No auto-promote.**
7. **Gotchas are the highest-leverage memory** — write immediately, no "запомни" needed, when: behavior contradicts docs/intuition; "looks right but breaks"; "looks wrong but is intentional"; silent failure; platform quirk. **Fact lifecycle:** never silently delete or rewrite a recorded fact — outdated → mark `status: superseded` and move the old value to a dated `## History` line (`- 2026-03→06: was X`); top of file = current truth, History = trail. Tag facts `confidence: verified` (confirmed by running/reproducing) or `confidence: inferred` (deduced from reading) — assert the first, hedge the second.
8. **Server-agent test** before any account-local write: fresh agent cloning the repo at midnight needs it → push it in-repo.

## SESSION.md template (L2)

```markdown
---
last_updated: <ISO-8601 UTC>
cwd: <absolute project root path>
status: active
tags: [memory/l2, session]
---

# Goal
<1-2 lines>

# State
- branch: <branch | n/a>
- last action: <what just happened>
- next: <planned>

# Decisions
- [HH:MM or phase-tag] <decision> — <rationale>

# File map
- path:line — <role>

# Open questions
# Blockers

# Recent turns
- **User:** "<verbatim or first sentence [...]>"
  **I did:** <1 line>
```

## Retrieval tools (RAM vs disk)

Context window = RAM (expensive). Files = disk (cheap). Read disk on demand, don't preload.

- **`/recall <query>`** — search across all memory layers (BM25 default; `--hybrid` adds vectors). First stop for "did we already see this?" / past decisions / gotchas.
- **`/codemap def|callers|callees|outline <symbol>`** — symbol map via ctags+ripgrep. "Where defined / who calls / structure".
- **`/memory status|auto on|off|refresh`** — protocol controls; `refresh` rebuilds the qmd vector index (manual only).
- **`/memstat [--watch]`** — memory subsystem task manager (processes, index progress, health).

Knowledge → `/recall`. Code structure → `/codemap`. Known file → `Read`/`Grep`. Don't preload `.claude-docs/*` — `/recall` first, then Read the 1-2 files the hits surface.

## Privacy

Never write raw secrets to any memory file — write the env-var name or file path. Transient values that must not survive the session: wrap in `<private>...</private>` (hooks strip them from SESSION.md). Paths matching `.claude-private` globs are excluded from all memory/capture. Verbatim transcript exports (if enabled) follow the same redaction.

## What NOT to save

Derivable code patterns · git-history facts · CLAUDE.md duplicates · trivia · secrets/tokens.

## Recovery (post-compact / post-restart)

First tool calls, in parallel, BEFORE answering the user: `Read IDENTITY.md` + `Read SESSION.md` + `Read project.md` (if exists) + any `.claude-docs/*.md` SESSION points at. Verify `<repo>/CLAUDE.md` is in context. The summarizer paraphrases away live texture — the files are authoritative.

## Reference docs — read on demand, not upfront

| When | Read |
|---|---|
| Bootstrapping L1 in a new repo · pre-compact checkpoint ritual · multi-session/worktree handoff · task wrap-up distillation details | `~/.claude/templates/protocol/workflows.md` |
| A knowledge store grows (splitting project.md, file naming, index.md, raw/ data) | `~/.claude/templates/protocol/knowledge-store.md` |
| User asks about Obsidian / vault setup / frontmatter+tags conventions | `~/.claude/templates/protocol/obsidian.md` |
| Creating L1a / L1b / project.md from scratch | `~/.claude/templates/repo/`, `~/.claude/templates/project.md.fallback.template` |
