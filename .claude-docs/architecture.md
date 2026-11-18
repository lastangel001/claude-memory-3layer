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

1. **SessionStart** (`hooks/session-start.sh`) — reads hook stdin, resolves the project directory, runs staleness / cwd-mismatch / size checks on SESSION.md, strips `<private>` blocks in place, and emits one JSON object whose `additionalContext` carries the protocol reminder plus the **absolute paths** of SESSION.md and project.md. Also kicks a debounced background `transcript-export.sh` + `qmd update`.
2. **PreCompact** (`hooks/pre-compact.sh`) — emits a `systemMessage` flush reminder.
3. **PostToolUse** (`hooks/post-tool-use.sh`) — appends an `[auto]` line to SESSION.md for a new git commit or an edit of `CLAUDE.md` / `.claude-docs/*.md`. Two pure-bash gates exit before any interpreter is spawned.

All three fail open: `set -euo pipefail` + an ERR trap that logs and exits 0 with fallback JSON. A hook must never block a session or a tool call.

## Shared libraries (`bin/lib/`, sourced)

- `slug.sh` — `_resolve_project`: which `~/.claude/projects/<slug>` belongs to this session. Order: `transcript_path` from hook stdin → formula → legacy-formula directory. **Single source of truth** — hooks, `doctor.sh` and `/session-end` all go through it.
- `diag.sh` — `_diag hook outcome note` → `debug/hook-diag.jsonl`. Summarized by `doctor.sh`.
- `validate-json.sh` — `_cmd_runs` / `_json_parser` (python3 → node → jq, probing that the interpreter actually executes) + JSON validation via stdin.
- `paths.sh` — PATH augmentation for Node/npm tools under Git Bash.

## State under `~/.claude` (none of it in git)

- `projects/<slug>/memory/{SESSION.md,project.md}` — L2 / L1-fallback; `.auto-last-commit` — sha of the last auto-captured commit; `raw/transcripts/` — exported transcripts.
- `debug/hook-trace.log` (free text) and `debug/hook-diag.jsonl` (structured) — both rotated to 2000 lines once a day by SessionStart.
- `.memory-version`, `.memory-source` — written by `install.sh`, read by `update.sh` and the version nudge.
- Markers: `.qmd-last-refresh`, `.version-check`. Flags: `.session-compress-disabled`, `.transcript-export-disabled`.

## Health tooling

- `bin/doctor.sh` — the *install*: files, settings.json, duplicate registrations, CRLF, dynamic self-test of installed hooks, split memory directories, hook outcomes.
- `bin/vault-doctor.sh` — the *content*: IDENTITY size, SESSION size/staleness, `.claude-docs` frontmatter / orphans / links, including the doc index in the repo's `CLAUDE.md`.

## Tests and CI

`tests/*.bats` run the **repo** copies against a throwaway `CLAUDE_HOME` (`tests/helpers.bash`). CI (`.github/workflows/ci.yml`) runs `bash -n`, shellcheck (ubuntu only) and bats on ubuntu + windows Git Bash. shellcheck is not assumed to exist locally.
