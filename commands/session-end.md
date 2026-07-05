# /session-end — Distil & close the current task

Enforces the protocol's **task wrap-up** ritual (CLAUDE.md rule 6): promote the
high-signal parts of SESSION.md to their permanent homes, log one timeline line,
then wipe SESSION.md to a blank template. Without this, distilled knowledge is
lost at the next compact and SESSION.md bloats across unrelated tasks.

Run when a task is done — especially when the user did NOT say "запомни"/"remember"
explicitly (that path promotes eagerly; this is the catch-all at task boundary).

## Step 0 — Locate the session

Compute the project slug from cwd and read the current SESSION.md:

```bash
SLUG=$(cd "$PWD" && source "${CLAUDE_HOME:-$HOME/.claude}/bin/lib/slug.sh" && _compute_slug && printf '%s' "$slug")
SESSION="${CLAUDE_HOME:-$HOME/.claude}/projects/$SLUG/memory/SESSION.md"
PROJECT="${CLAUDE_HOME:-$HOME/.claude}/projects/$SLUG/memory/project.md"
```

If no SESSION.md exists, tell the user there is nothing to close and stop.

## Step 1 — Distil (promote, don't archive)

Read SESSION.md. For each item, decide its permanent home. **Only promote what a
future agent would decide worse without.** Route by the protocol's rules:

| SESSION.md content | Promote to |
|---|---|
| Non-obvious gotcha / footgun / "looks wrong but intentional" | `<repo>/.claude-docs/gotchas.md` (in-repo) — **highest leverage** |
| Durable architecture / recurring pattern | `<repo>/.claude-docs/architecture.md` / `patterns.md` |
| Codebase convention (naming, commit, lint) | `<repo>/.claude-docs/conventions.md` |
| New top-level command / MUST / MUST NOT | `<repo>/CLAUDE.md` (keep it thin) |
| User identity, hard preference, env-wide fact | `~/.claude/memory/IDENTITY.md` (L0 — respect the 25-line cap) |
| Project context with no repo / not for the repo | `project.md` (L1-fallback) |

Rules while promoting:
- **In-repo beats account-local** — apply the server-agent test: a fresh agent
  cloning the repo at midnight needs codebase facts → they go in the repo.
- **Never silently rewrite a recorded fact.** Outdated → mark `status: superseded`
  and move the old value to a dated `## History` line. Tag new facts
  `confidence: verified` (reproduced) or `confidence: inferred` (deduced).
- **Do not touch a repo file without the user's go-ahead** — propose the in-repo
  edits, let the user approve, since they get committed with the code.
- Pure working-state (last action, next step, transient blockers) is **not**
  promoted — it dies with the task.

## Step 2 — Log one timeline line

Append a single line to `## Timeline` in project.md (create the section if absent).
This answers "what did I do on this project in <month>" without a journal layer:

```
- YYYY-MM-DD: <task, one phrase> — <outcome>
```

If project.md does not exist and the work was repo-scoped, it's fine to skip the
timeline (the repo's git history + docs already carry it); mention that you did.

## Step 3 — Confirm what was promoted

Report to the user, concisely:
- **Promoted:** each fact → its destination (and whether it needs a commit).
- **Dropped:** working-state that was intentionally not kept (one line).
- **Timeline:** the line you appended (or why you skipped it).

## Step 4 — Wipe SESSION.md to template

Only after Steps 1–3. Overwrite SESSION.md with the blank template, preserving
the canonical `cwd:` and stamping a fresh `last_updated:`. Set `status: done` and
record the finished task name so the next session sees a clean slate, not stale state:

```markdown
---
last_updated: <current UTC ISO>
cwd: <canonical cwd — keep the existing value>
status: done
tags: [memory/l2, session]
---

# Goal
(none — last task: <one-phrase description of what just closed>)

# State
- branch: <current | n/a>
- last action: task closed via /session-end
- next: (await next task)

# Decisions
# File map
# Open questions
# Blockers

# Recent turns
```

Do **not** delete SESSION.md — a blank template is the resting state; deleting it
loses the `cwd:` anchor that drives CWD-mismatch detection.

## Notes

- This command **never commits.** Repo-file promotions are proposed; the user
  commits them with the code.
- Distillation is lossy on purpose: SESSION.md is per-task scratch, and the value
  worth keeping is exactly what Step 1 moved to a durable layer.
