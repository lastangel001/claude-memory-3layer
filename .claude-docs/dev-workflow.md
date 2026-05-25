---
tags: [memory/repo, dev-workflow]
---

# Development workflow — claude-memory-3layer

Rules for working on this repository. Apply on every commit.

## On every commit

> **Mandatory before every commit — all three, no exceptions:**
> ```
> [ ] README.md    — behavior changed or feature added → update description
> [ ] CHANGELOG.md — add entry under current version header
> [ ] IDEAS.md     — move shipped items to "Already shipped"; add new discoveries
> ```

### 1. Actualize README.md

- New feature or hook → add to the relevant section (Hooks, Tools, Repo layout)
- Changed behavior → update description to match
- Removed feature → remove from README, do not leave stale entries
- Version bump → update nothing in README unless behavior changed (CHANGELOG owns version history)

### 2. Update CHANGELOG.md

- Add entry under the current version header (or create new `## vX.Y.Z — YYYY-MM-DD — <title>`)
- New capability → **Added** bullet
- Changed behavior → **Changed** bullet
- Bug fix → **Fixed** bullet
- No "TODO", "TBD", or empty version blocks — write the entry before committing

### 3. Actualize IDEAS.md

Two actions required:

**Remove implemented items from backlog.** Do not leave them as `[x]` in the backlog section — move them into the "Already shipped" section header list (one line each, `- [x] short description`). If already present there, just delete the full backlog entry.

**Add newly discovered ideas.** If current work revealed a bug, edge case, or improvement opportunity not yet tracked — add it to the relevant backlog section with priority × effort rating (H/M/L × S/M/L) and a What/Why/How note.

---

## Commit message format

```
<type>: <short description>

<optional body>
```

Types: `feat` · `fix` · `docs` · `refactor` · `test` · `chore`

Keep subject line ≤72 chars. Body explains *why*, not what (the diff shows what).

## Versioning

`vMAJOR.MINOR.PATCH` — bump MINOR for new features, PATCH for fixes/docs only.
Current version tracked in CHANGELOG.md header.
