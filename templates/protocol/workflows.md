---
tags: [memory/protocol, workflows]
---

# Workflow patterns — memory protocol reference

Read on demand from the core protocol (`~/.claude/CLAUDE.md`). Not loaded automatically.

## Pre-compact checkpoint

When the user signals an upcoming compact ("compact me", "теперь можно компакт"):

1. Confirm git is clean (or note dirty files explicitly)
2. Confirm pushed to remote (`git status -sb`)
3. Update SESSION.md fully (Goal/State/Decisions/File map/**Recent turns verbatim**)
4. Reply with explicit "PRE-COMPACT CHECKPOINT" line listing: HEAD hash, what's pushed, where the next session should start reading
5. Only after that — let the compact happen

## Multi-session handoff (parallel worktrees / chats)

If you're working in a side worktree or another chat is touching the same project, leave a `<!-- NOTE: ... -->` block right after `last_updated` in SESSION.md describing what state the OTHER session expects.

## Distillation on task wrap-up

When the user says "task done" / "done" / "wrap it up" **without** "remember":

1. Append one line `- YYYY-MM-DD: <task> — <outcome>` under `## Timeline` in `project.md` (create the section, or the file from the fallback template, if absent). One line only — this is a pointer trail, not a journal.
2. Rewrite SESSION.md to the empty template, preserving only `# Goal: (none — last task: <X>)`.
3. Set `status: done` in the YAML frontmatter.
4. Do **not** auto-promote anything else.

Obsidian users can filter live vs completed sessions with:

```
dataview TABLE last_updated WHERE status = "active"
```

## Bootstrapping in-repo L1

When the user starts substantive work in a repo with no `<repo>/CLAUDE.md`:

1. Propose creating it. Use templates from `~/.claude/templates/repo/`.
2. Create `<repo>/.claude-docs/` with at minimum `index.md` (routing table) and `gotchas.md` (start empty — populate as you discover).
3. Add `architecture.md` only when you have something real to write — don't fabricate.
4. Commit as part of the user's work, not a separate commit unless asked.

For existing codebases prefer `/onboard-memory` — it generates a stack/layout/hot-files report and scaffolds the docs.

## Recent turns — discipline

Update `# Recent turns` **before any potentially-large operation** and on PreCompact. Verbatim. Long user turn → first sentence + `[...]`. Drop oldest beyond 5.

Rapid chain of short messages → group with `->`:

```
- **User:** "проверь" -> "ну?" -> "ок коммить"
  **I did:** <one summary line>
```
