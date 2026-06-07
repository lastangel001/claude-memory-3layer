# /onboard-memory — Bootstrap Claude Code memory for an existing project

Creates `CLAUDE.md` + full `.claude-docs/` scaffold by scanning the repo.
Run from the project root.

## Step 1 — Collect raw data

```bash
bash "${CLAUDE_HOME:-$HOME/.claude}/bin/onboard-report.sh"
```

Read every line of output before writing anything. The report includes:
README, CONTRIBUTING, full docs/ folder content (every file, no cap), stack files,
directory structure, entry points, symbol outline (classes/functions via codemap —
if ctags/ripgrep installed), git log, hot files, FIXME/HACK grep, `@deprecated`.

The first block of the report is **"Onboard mode"** — read it now, it decides everything below.

## Mode — first run vs update

The report's mode block says one of two things:

- **FIRST RUN** — no prior onboard. Create all memory files from scratch (Step 3, create path).
- **UPDATE** — memory already exists (`.claude-docs/.onboard-rev` present). The report includes a **delta** (commits + changed files + stale-doc hints since the last onboard). Do **NOT** rewrite from scratch — this is an *evolutionary* update: **patch surgically, preserve every hand-edit.** Follow Step 3's update path.

Either way, finish with Step 5 to refresh the revision marker.

## Step 2 — Analyse

From the report, determine:
- **Language + framework** (stack files, entry points)
- **Architecture pattern** (MVC, hexagonal, monolith, microservices…) — use README + docs/ if present; they often describe design decisions code doesn't reveal
- **Architecture layers** — classify each top-level dir/module into a layer: **API / Service / Data / UI / Utility** (add project-specific ones like Worker, Domain if they fit). Note which layer each entry point sits in. Use the symbol outline section to see what each module actually contains.
- **Reading order (guided tour)** — derive a dependency-ordered learning path: entry point → core modules it depends on → leaf utilities. 5–10 stops max, each with a one-line "why read this here". This is the path a new dev should follow.
- **Test runner + lint tooling**
- **Hot files** — what changes most, and why?
- **Real gotchas** — from FIXME/HACK grep + docs "known issues" / "caveats" sections: which are non-obvious to a new dev?
- **Existing conventions** — check CONTRIBUTING.md first; it often has commit format, PR rules, coding standards already written

## Step 3 — Create or update files

**Only write what you actually found. Do not fabricate.**

If a section has no real content, write the header + `(none found — populate during work)`.

### UPDATE path (mode = UPDATE) — patch, don't clobber

When the report says UPDATE mode, the templates below are **targets to reconcile against**, not blank files to overwrite:

1. **Read each existing file first** (`CLAUDE.md`, every `.claude-docs/*.md`). Treat current content as authoritative.
2. **Only touch what the delta implies.** Use the report's "Stale-doc hints" + changed-files list to decide which docs are affected. Leave untouched docs exactly as they are.
3. **Preserve hand-edits.** Never delete a human-written line unless the code now contradicts it (e.g. a documented command that no longer exists). When you remove or rewrite a factual claim, it must be because the delta proves it stale — say so in the change report (Step 4).
4. **Additive by default.** New layers, new modules, new gotchas, new conventions → append / extend. Existing structure stays.
5. **Refresh derived sections** when structure changed: the Layers table and Reading order in `architecture.md` (if dirs/entry points moved), stack version in `architecture.md`, new `gotchas.md` entries from new FIXME/HACK.
6. When unsure whether a line is a hand-edit worth keeping — **keep it.** Loss-aversion is the rule here.

For **FIRST RUN** mode, just create each file from the templates below.

### `CLAUDE.md` (≤60 lines — thin entry point)

Use this shape:

```markdown
# CLAUDE.md — <project name>

Entry point for Claude Code agents. Deeper reference: [.claude-docs/](.claude-docs/index.md).

## Commands
- build: `<command>`
- test:  `<command>`
- lint:  `<command>`

## Documentation index
- [.claude-docs/architecture.md](.claude-docs/architecture.md) — stack, layout, data flow
- [.claude-docs/conventions.md](.claude-docs/conventions.md) — naming, commit style, code patterns
- [.claude-docs/gotchas.md](.claude-docs/gotchas.md) — non-obvious footguns
- [.claude-docs/index.md](.claude-docs/index.md) — routing table

## Boundaries
### MUST
- (fill from project rules / CI gates)
### MUST NOT
- (fill from project rules / deploy constraints)
```

### `.claude-docs/architecture.md`

- Stack (language, framework, version)
- Top-level directory roles (one line each)
- Request → service → persistence flow (or equivalent)
- Entry points: HTTP handler, CLI, queue workers, cron
- External dependencies: DB type, cache, queue, third-party APIs

Add a **Layers** table (from the layer classification in Step 2):

```markdown
## Layers
| Layer | Dirs / modules | Role |
|---|---|---|
| API | routes/, controllers/ | HTTP entry |
| Service | services/ | business logic |
| Data | models/, repositories/ | persistence |
| UI | components/, views/ | presentation |
| Utility | lib/, helpers/ | shared helpers |
```

Add a **Reading order** section (the guided tour from Step 2) — dependency-ordered, where a new dev should start:

```markdown
## Reading order (start here)
1. `path` — <why first: entry point / orchestrator>
2. `path` — <next: core dependency of #1>
3. `path` — <leaf utility>
```

### `.claude-docs/conventions.md`

Derive from `git log` patterns + code structure:
- Commit message format (if consistent)
- File / class / function / DB table naming
- Code style signals (tabs/spaces, semicolons, type annotations)
- Test file placement and naming pattern

### `.claude-docs/gotchas.md`

From FIXME/HACK grep and `@deprecated` markers. Per entry:

```markdown
## <Short title>

<What the gotcha is. Why it bites. Fix or workaround.>
```

Non-obvious only. Skip trivial TODOs. Leave file with header only if auto-scan
found nothing — it fills in during real work.

### `.claude-docs/index.md`

```markdown
# .claude-docs index

| Task | Read |
|---|---|
| Understand architecture / data flow | architecture.md |
| Code style, naming, commit format | conventions.md |
| Hit unexpected behavior | gotchas.md |
```

## Step 3.5 — Self-review (validate before reporting)

Before reporting, run an integrity pass over what you just wrote. Fix issues, then proceed:

- **Links resolve** — every link in the `CLAUDE.md` doc-index and `index.md` points to a file you actually created.
- **No fabrication** — every claim traces back to report data. Anything you couldn't determine is marked `(none found — populate during work)`, not invented.
- **Sections complete** — each template section is either filled or explicitly marked empty. No dangling placeholders like `<command>`.
- **Thin entry point** — `CLAUDE.md` is ≤ 60 lines. Move detail into `.claude-docs/` if it overflows.
- **Layers + reading order present** — `architecture.md` has both the Layers table and Reading order (or a note why N/A, e.g. single-file project).
- **(UPDATE mode) No content lost** — diff your changes against the pre-existing docs (`git diff` on the doc files). Confirm every removal is justified by the delta. If you can't justify a deletion, restore it.

## Step 4 — Report to user

After creating all files, output:
- **Stack detected**: language, framework, version
- **Gotchas found**: count + top 3 titles (or "none — gotchas.md is empty, will fill during work")
- **Hottest files**: top 5 from git log + one-line hypothesis for each
- **Gaps**: what couldn't be determined from static analysis (flag for human input)

In UPDATE mode, frame the report as a **changelog**: what changed since the last onboard, which docs you patched, and (explicitly) any line you removed + why.

## Step 5 — Persist the onboard revision

Write the marker so the **next** `/onboard-memory` can compute its delta. Run from the repo root:

```bash
mkdir -p .claude-docs
{ printf '# .claude-docs/.onboard-rev — last /onboard-memory sync point. Auto-managed; commit with docs.\n'
  printf 'rev: %s\n'  "$(git rev-parse HEAD 2>/dev/null || echo none)"
  printf 'date: %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
} > .claude-docs/.onboard-rev
```

The marker is **git-tracked** — commit it with the docs so teammates' future updates measure drift from the team's last sync, not their local clone.

**Do NOT commit automatically.** Say: *"Review the files, then: `git add CLAUDE.md .claude-docs/ && git commit -m 'docs: bootstrap Claude Code memory'`"* (first run) or *`'docs: update Claude Code memory (onboard delta)'`* (update).
