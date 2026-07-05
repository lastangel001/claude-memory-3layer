# CLAUDE.md — claude-memory-3layer

Entry point for Claude Code agents working **on this repository** (the 3-layer memory protocol for Claude Code).

The protocol itself lives in [`PROTOCOL.md`](PROTOCOL.md) — `install.sh` copies it to `~/.claude/CLAUDE.md`, where it loads globally into every session. It is deliberately NOT duplicated here: if the protocol is installed on this machine, it's already in your context; if not, read `PROTOCOL.md` when the task needs it.

## Documentation index

| Task | Read |
|---|---|
| Making a commit — mandatory README/CHANGELOG/IDEAS triple | [.claude-docs/dev-workflow.md](.claude-docs/dev-workflow.md) |
| Editing install.sh / doctor.sh / migrate.sh / any Windows-path handling | [.claude-docs/gotchas.md](.claude-docs/gotchas.md) |
| Stack, layout, how hooks/bin/commands fit together | [.claude-docs/architecture.md](.claude-docs/architecture.md) |
| Code style, naming, commit format | [.claude-docs/conventions.md](.claude-docs/conventions.md) |
| Routing table (start here when unsure) | [.claude-docs/index.md](.claude-docs/index.md) |

## Commands

- `bats tests/` — run the test suite (bats-core; CI runs it on ubuntu + windows Git Bash)
- `shellcheck -S warning install.sh migrate.sh hooks/*.sh bin/*.sh bin/lib/*.sh` — static analysis (CI-enforced)
- `bash -n <script>` — quick syntax check
- `./install.sh --dry-run` — preview an install without writing

## Boundaries

### MUST
- Update README.md + CHANGELOG.md + IDEAS.md on every commit (see dev-workflow.md — no exceptions)
- Keep `PROTOCOL.md` ≤ ~150 lines — it loads into every session on every machine; fat sections go to `templates/protocol/*.md`
- Read `.claude-docs/gotchas.md` before touching install/validation/path-handling code
- Keep hooks non-blocking: `set -euo pipefail` + ERR trap emitting fallback JSON

### MUST NOT
- Reintroduce a full protocol copy into this file (double-load costs ~9k tokens/session)
- Pass MSYS paths as string args to Windows-native node/python (pipe via stdin — see gotchas.md)
- Add daemons or auto-promotion — explicit promotion is the core philosophy

## Workflow

Default branch: `main`. Commit format: `<type>: <short description>` (feat/fix/docs/refactor/test/chore). Version: `vMAJOR.MINOR.PATCH` in CHANGELOG.md.
