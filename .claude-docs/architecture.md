---
tags: [memory/repo, architecture]
description: Layout, runtime flow of the three hooks, shared libs, state files, how install maps repo to ~/.claude
---

# Architecture — claude-memory-3layer

Pure bash (4+) plus one zero-dependency Node script. No build step, no daemon. The repo is the *source*; `install.sh` copies it into `~/.claude` (`$CLAUDE_HOME`), and everything runs from there.

## Repo → install mapping

| Repo | Installed as | Role |
|---|---|---|
| `PROTOCOL.md` | `~/.claude/CLAUDE.md` | the protocol itself — loads into every session |
| `hooks/*.sh` | `~/.claude/hooks/` | registered in `settings.json` (from `settings.snippet.json`) |
| `commands/*.md` | `~/.claude/commands/` | slash commands (prompt files, no code) |
| `bin/*.sh`, `bin/lib/*.sh`, `bin/mcp-recall.mjs` | `~/.claude/bin/` | tooling called by hooks, commands and the user |
| `templates/` | `~/.claude/templates/` | L1a/L1b scaffolds + on-demand protocol reference docs |
| `memory/IDENTITY.md` | `~/.claude/memory/IDENTITY.md` | L0 template — copied only if absent, never overwritten |

`install.sh` lists every file explicitly; `tests/install.bats` fails when a repo file is not mentioned. Adding a script means adding a `backup_and_install` line.

## Runtime flow

1. **SessionStart** (`hooks/session-start.sh`) — reads hook stdin, resolves the project directory, runs staleness / cwd-mismatch / size checks on SESSION.md, strips `<private>` blocks in place, and emits one JSON object whose `additionalContext` carries the protocol reminder plus the **absolute paths** of SESSION.md and project.md. Also kicks a debounced background `transcript-export.sh` + `qmd update` (subshell with `set +e` and all three streams detached; writes `.qmd-last-refresh-done` on completion). In a linked git worktree, `project.md` resolves to the main checkout's project directory.
2. **PreCompact** (`hooks/pre-compact.sh`) — calls `bin/compact-snapshot.sh` (last user turns verbatim + git position → `memory/compact-snapshot.md`) and prints plain-text instructions for the compaction summary. No JSON: Claude Code discards a PreCompact hook's `systemMessage`.
   After compaction SessionStart runs again with `source: compact` and inlines SESSION.md + the snapshot in a `<memory-record>` frame, within the 10,000-character hook-context cap (sheds the snapshot first, then falls back to a read instruction). A session compacted while idle gets no `compact` event; it is handed the same record on its next `source: resume`, once per compaction — the snapshot's `session:` + `generated:` against the `.compact-handed-back` stamp.
3. **PostToolUse** (`hooks/post-tool-use.sh`) — appends an `[auto]` line to SESSION.md for a new git commit or an edit of `CLAUDE.md` / `.claude-docs/*.md`. Two pure-bash gates exit before any interpreter is spawned.

All three fail open: `set -euo pipefail` + an ERR trap that logs and exits 0 with fallback JSON. A hook must never block a session or a tool call.

## Shared libraries (`bin/lib/`, sourced)

- `slug.sh` — `_resolve_project`: which `~/.claude/projects/<slug>` belongs to this session. Order: `transcript_path` from hook stdin → formula → legacy-formula directory. **Single source of truth** — hooks, `doctor.sh` and `/session-end` all go through it.
- `diag.sh` — `_diag hook outcome note` → `debug/hook-diag.jsonl`. Summarized by `doctor.sh`.
- `validate-json.sh` — `_cmd_runs` / `_json_parser` (python3 → node → jq, probing that the interpreter actually executes) + JSON validation via stdin.
- `paths.sh` — PATH augmentation for Node/npm tools under Git Bash. Every function here must return 0: it is sourced by `set -e` scripts.

## Search

`commands/recall.md` only tells the model to run `bin/recall.sh` — all logic lives in the script so it can be tested. Memory section: qmd (`search` / `query`, `-n`, `-c`) when installed, otherwise ripgrep/grep ranking; `--here` always goes through ripgrep. Repo-docs section: ripgrep/grep over `<repo>/.claude-docs`, `CLAUDE.md`, `AGENTS.md`, every time. `MEMORY_QMD_CMD` overrides the qmd command (tests point it at a stub — PATH is augmented inside the script, so a stub on PATH would lose to a real install). `--timeline` skips searching and prints dated `## Timeline` lines from every `project.md`; `--no-memory` restricts a search to repo docs. `bin/mcp-recall.mjs` is the MCP path for subagents: qmd when it can be started, otherwise its own literal scan, plus the cwd's repo docs. Never write `grep -i -F` anywhere in this path (see gotchas.md).

## State under `~/.claude` (none of it in git)

- `projects/<slug>/memory/{SESSION.md,project.md}` — L2 / L1-fallback; `compact-snapshot.md` — machine-written at every compaction, replaced each time; `.compact-handed-back` — `<session id> <snapshot time>` of the last compaction whose record was handed back; `.auto-last-commit` — sha of the last auto-captured commit; `raw/transcripts/` — exported transcripts.
- `debug/hook-trace.log` (free text) and `debug/hook-diag.jsonl` (structured) — both rotated to 2000 lines once a day by SessionStart.
- `.memory-version`, `.memory-source` — written by `install.sh`, read by `update.sh` and the version nudge.
- Markers: `.qmd-last-refresh` (refresh kicked), `.qmd-last-refresh-done` (refresh finished), `.version-check`. Logs: `logs/qmd-refresh.log`, `logs/recall-misses.log`. Flags: `.session-compress-disabled`, `.transcript-export-disabled`.

## Health tooling

- `bin/doctor.sh` — the *install*: files, settings.json, duplicate registrations, CRLF, dynamic self-test of installed hooks, split memory directories, hook outcomes.
- `bin/memory-eval.sh` — the *usefulness*: canned questions in `.claude-docs/eval-questions.md`, each answered by `recall.sh --no-memory`; passes when a returned file holds the expected text. Runs in `tests/memory-eval.bats` against this repo's own docs.
- `bin/vault-doctor.sh` — the *content*: IDENTITY size, SESSION size/staleness, `.claude-docs` frontmatter / orphans / links, including the doc index in the repo's `CLAUDE.md`; `src:` citations (file / symbol still there, commits since the cited one); CLAUDE.md diet (length, lines copied from README).

## Tests and CI

`tests/*.bats` run the **repo** copies against a throwaway `CLAUDE_HOME` (`tests/helpers.bash`). CI (`.github/workflows/ci.yml`) runs `bash -n`, shellcheck (ubuntu only) and bats on ubuntu + windows Git Bash. shellcheck is not assumed to exist locally.
