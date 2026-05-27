# /onboard — Bootstrap Claude Code memory for an existing project

Creates `CLAUDE.md` + full `.claude-docs/` scaffold by scanning the repo.
Run from the project root.

## Step 1 — Collect raw data

```bash
bash "${CLAUDE_HOME:-$HOME/.claude}/bin/onboard-report.sh"
```

Read every line of output before writing anything. Also read: `README.md`,
`CONTRIBUTING.md`, any existing `docs/` folder.

## Step 2 — Analyse

From the report, determine:
- **Language + framework** (stack files, entry points)
- **Architecture pattern** (MVC, hexagonal, monolith, microservices…)
- **Test runner + lint tooling**
- **Hot files** — what changes most, and why?
- **Real gotchas** — from FIXME/HACK grep: which are non-obvious to a new dev?

## Step 3 — Create files

**Only write what you actually found. Do not fabricate.**

If a section has no real content, write the header + `(none found — populate during work)`.

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

## Step 4 — Report to user

After creating all files, output:
- **Stack detected**: language, framework, version
- **Gotchas found**: count + top 3 titles (or "none — gotchas.md is empty, will fill during work")
- **Hottest files**: top 5 from git log + one-line hypothesis for each
- **Gaps**: what couldn't be determined from static analysis (flag for human input)

**Do NOT commit.** Say: *"Review the files, then: `git add CLAUDE.md .claude-docs/ && git commit -m 'docs: bootstrap Claude Code memory'`"*
