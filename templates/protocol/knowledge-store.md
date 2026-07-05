---
tags: [memory/protocol, knowledge-store]
---

# Knowledge store organization — memory protocol reference

Applies to both `<repo>/.claude-docs/` (L1b) and `~/.claude/projects/<slug>/memory/` (L1-fallback once a single `project.md` outgrows itself). Convention: **flat + tags + filename-prefix**.

## Layout rules

- **Flat by default; shallow grouping allowed when it helps `tree`-readability.** Tags do the primary categorization; subdirs are visual aid only. At most **one** level of nesting, and only when a category has 5+ peer files of the same type. `protocols/`, `formats/`, `handoffs/` OK; `protocols/v2/handshake/` not OK.
- **Filename prefixes for grouping.** `protocol_<name>.md`, `format_<name>.md`, `handoff_<topic>.md`, `decoded_<thing>.md`, `recipe_<task>.md`. Lowercase, underscore between prefix and name. Alphabetical sort gives free clustering in `ls`.
- **`index.md` is the routing source.** Every multi-file store has one: a table mapping "you need to do X" → "read Y.md". Always update it when adding a doc. For in-repo L1 the index lives at `.claude-docs/index.md` AND is mirrored as a doc-index in `<repo>/CLAUDE.md`.
- **Frontmatter tags carry semantics.** `tags: [memory/repo, protocol]`, `tags: [memory/l1, format, binary-layout]`. Hierarchical + semantic, Obsidian-native.
- **Raw data dumps in `raw/`.** Non-markdown (`.txt`, `.tsv`, `.json`, `.bin`) belongs in `raw/` — the one meaningful directory split ("notes" vs "data"). Verbatim transcript exports live in `raw/transcripts/` (machine-written, rotated). Markdown notes stay flat.

## When to split a single project.md

- File exceeds ~200 lines, OR
- 3+ clearly distinct categories of knowledge accumulating, OR
- You'll cross-reference specific subsections from multiple places.

When splitting: keep `project.md` (or `CLAUDE.md`) as the **thin entry + doc index**, move each category to its own `<prefix>_<name>.md` with frontmatter tags. Split as topics emerge — don't migrate everything at once.

## Fact lifecycle (gotchas, decisions, any recorded fact)

- Top of file/entry = **current truth**. Never silently delete or rewrite.
- Outdated fact → `status: superseded` (frontmatter or inline) + dated line in append-only `## History`: `- 2026-03→06: was X`.
- `confidence: verified` — confirmed by running/reproducing. `confidence: inferred` — deduced from reading code/docs. Assert verified facts; hedge inferred ones.
- Answering about the past ("how did this work before") → History is fair game; otherwise answer from current truth only.
