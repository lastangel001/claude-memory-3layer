# /recall — search Claude memory

Search account memory (L0 identity, every project's SESSION.md / project.md / exported transcripts) **and** the current repo's own docs (`.claude-docs/*.md`, `CLAUDE.md`, `AGENTS.md`) in one call.

## Usage

`/recall <query>` — ranked search, top 5 per section.

Optional flags:
- `--here` — only the current project's memory (plus this repo's docs)
- `-n <N>` — hits per section (default 5; `-k` is accepted as an alias)
- `--hybrid` — qmd hybrid search (BM25 + vectors + rerank). Needs `qmd embed` to have run; the first call of a session loads models (10–60 s). Use when plain search misses something you can only describe, not quote
- `-c <collection>` — restrict qmd to `claude-l0` or `claude-projects`

## How to execute

Run the script — do not call `qmd` yourself and do not edit `PATH` (the script does both correctly for this platform):

```bash
bash ~/.claude/bin/recall.sh <flags> <query words>
```

Display the output verbatim: do not paraphrase paths or snippets. After the hits, add one short orientation line (e.g. "the relevant note is in `billing-api/SESSION.md`").

## What the output means

- `## Memory` — account memory. Engine is `qmd` (BM25, or hybrid with `--hybrid`) when qmd is installed, otherwise ripgrep/grep with literal matching — the trailer line says which. With `--here` it is always ripgrep over the one project directory.
- `## Repo docs` — literal-match hits in the current repo's `.claude-docs/`, `CLAUDE.md`, `AGENTS.md`. This is where gotchas live; it is searched every time.
- `(no hits)` in every section — the query was logged to `~/.claude/logs/recall-misses.log`. Tell the user memory has nothing on it; do not guess.
- `(index was stale — refreshed before searching)` — the qmd index had not been updated for over 6 hours and was refreshed inline.

## Examples

- `/recall MongoDB legacy driver` — finds the notes about the legacy `\MongoClient` adapter
- `/recall --hybrid гочи WSL DNS` — hybrid: finds `CURLOPT_IPRESOLVE_V4` without the exact phrase
- `/recall --here retry backoff window` — current project only
