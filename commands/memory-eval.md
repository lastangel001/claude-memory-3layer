# /memory-eval — does this repo's memory still answer its own questions?

A closed-book retrieval check: for every question in `<repo>/.claude-docs/eval-questions.md`, ask `/recall` as an agent would — over the repo's own docs only, i.e. what a fresh clone has — and verify that one of the top files it returns contains the expected text. Deterministic: no model, no qmd, same result locally and in CI.

## Usage

- `/memory-eval` — run all questions; non-zero exit if any fails
- `/memory-eval --report` — same output, always exit 0
- `/memory-eval -n 3` — judge the top 3 files instead of 5

## How to execute

```bash
bash ~/.claude/bin/memory-eval.sh <flags>
```

Show the output verbatim.

## What to do with a ✗

A failed question means: an agent searching memory for this would not land on a file that holds the answer. For each one, say which it is — do **not** edit anything without the user's go-ahead (repo docs are committed with the code):

1. **The fact is not recorded** → propose where it belongs (`gotchas.md` for a footgun, `architecture.md` for structure, `CLAUDE.md` only for a command or a MUST / MUST NOT).
2. **The fact is recorded, but under words nobody would search for** → propose rewording the heading or the first sentence so it carries the question's vocabulary.
3. **The question is stale** (the code moved on) → propose updating or removing the question, and check whether the fact it pointed at should be marked `status: superseded`.

## Writing questions

```markdown
- q: how is the project directory found
  expect: transcript_path
- q: what must be updated on every commit
  expect: CHANGELOG.md | IDEAS.md
```

`q:` is what you would type after `/recall`. `expect:` is literal text (case-insensitive) that must appear in a returned file; `a | b` means either. Pick a token that only the right answer contains — a function name, a flag, a number — not a common word. Add a question whenever a session had to rediscover something memory should have told it.
