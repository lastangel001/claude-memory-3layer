---
tags: [memory/repo, gotcha]
description: Cross-platform footguns — install/doctor/path-handling; unexpected behavior
---

# Gotchas — claude-memory-3layer

Non-obvious foot-guns. Read before editing install/validation scripts.

## install.sh / doctor.sh: false "settings.json invalid JSON" on Windows Git Bash

**Symptom:** `install.sh` and `bin/doctor.sh` report `✗ settings.json invalid JSON` even when the file is perfectly valid JSON.

**Cause:** Both validate via
```bash
node -e "JSON.parse(require('fs').readFileSync('$CLAUDE_HOME/settings.json','utf8'))"
```
On Windows, `$CLAUDE_HOME` is an MSYS path like `/c/Users/User/.claude`. The `node` on PATH is the **Windows-native** build — it cannot resolve `/c/...` paths, so `readFileSync` throws `ENOENT` → validation reports invalid. The JSON is fine; the path handoff is broken. (python3 fallback only kicks in if `node` is absent — when both exist, node runs first and false-fails.)

**Fix:** pipe the file through `cat` (bash resolves the MSYS path) into node stdin, so node never touches the path:
```bash
cat "$CLAUDE_HOME/settings.json" | node -e "JSON.parse(require('fs').readFileSync(0,'utf8'))"
```
`readFileSync(0)` reads fd 0 (stdin). Cross-platform: works on Linux/macOS/Windows. Apply same fix to `bin/doctor.sh` (~line 79).

**Lesson:** never pass an MSYS/Git-Bash path as a string argument to a Windows-native interpreter (node/python from winget). Pipe via stdin, or convert with `cygpath -w`.

## grep -F silently breaks `^`/`$` anchors (codemap.sh def was dead)

**Symptom:** `codemap.sh def <symbol>` returned nothing for any symbol; no error.

**Cause:** v6.7.0 switched ctags lookup to `grep -F "^${arg}\t"` to neutralize regex chars in symbol names. But `-F` makes EVERYTHING literal, including `^` — grep searched for a literal caret character, which никогда не стоит в начале tags-строки. Looks right (anchored + fixed-string), silently matches nothing.

**Fix (v6.15.0):** exact first-field compare via awk — both anchored and regex-safe:
```bash
awk -F'\t' -v s="$arg" '$1 == s' "$root/.codemap.tags"
```

**Lesson:** `-F` and anchors are mutually exclusive. Need "literal string at line start" → awk string compare, or `grep -E "^$(escaped)"` with metachars escaped. Never combine `-F` with `^`/`$`.

## bash `local` outside a function errors — and `set -e` turns it fatal

confidence: verified

**Symptom:** `migrate.sh` Pass B (HTML-marker → YAML frontmatter) never migrated anything; with files present it died silently on the first candidate.

**Cause:** `local _html_outer=...` sat in a top-level `for` loop (v6.13 regex-hardening moved the pattern into a variable and reflexively kept the `local` from its function origin). `local` outside a function is an error (`local: can only be used in a function`), and under `set -e` that kills the whole script on the FIRST loop iteration — before any output.

**Fix (v6.16.0):** plain assignment. Found by shellcheck SC2168 the day CI got a shellcheck step.

**Lesson:** moving code out of a function → strip `local`. shellcheck catches this class statically; behavioral bats coverage for migrate.sh is still an open IDEAS item.

## bash printf: format string starting with `-` is parsed as an option

**Symptom:** `printf '- %s\n' "$f"` → `printf: - : invalid option`, exit 2; under `set -euo pipefail` kills the whole script (broke onboard-report.sh sections 4/6-10 on any repo with `.gitignore`).

**Fix:** `printf -- '- %s\n' "$f"` (option terminator) or move the dash into data: `printf '%s\n' "- $f"`.

**Lesson:** any dynamically-shaped or dash-leading printf format needs `--`. Grep check: `grep -rn "printf '\-" --include='*.sh'`.

## Claude Code's memory indexer re-nests SESSION.md frontmatter under `metadata:`

**Symptom:** doctor warns "SESSION.md missing cwd: field" even though you wrote `cwd:` into frontmatter; CWD mismatch detection silently dead.

**Cause:** some Claude Code versions rewrite files under `~/.claude/projects/*/memory/` — frontmatter becomes:
```yaml
---
name: ""
metadata:
  node_type: memory
  last_updated: ...
  cwd: C:/...
  originSessionId: ...
---
```
Fields get indented under `metadata:`, so anchored patterns (`grep '^cwd:'`, `sed 's/^cwd:...'`) stop matching. Staleness check survived only because its grep was unanchored.

**Fix (v6.15.0):** all frontmatter field lookups in `session-start.sh` / `doctor.sh` allow leading whitespace: `^[[:space:]]*cwd:`.

**Lesson:** never anchor frontmatter-field regexes to line start in files Claude Code itself may rewrite. Match `^[[:space:]]*field:`.

**Canonical answer (v6.17.0 audit — kills the bug class):** exactly two scripts read frontmatter *scalars* from indexer-rewritable files, and both use the leading-whitespace form:
- `session-start.sh` — `cwd:` (sed, whitespace-tolerant) + `last_updated:` (unanchored grep).
- `doctor.sh` / `vault-doctor.sh` / `gen-index.sh` — via `sed -n 's/^[[:space:]]*KEY:...'` (a shared `_fm_get` idiom).

The two other frontmatter-adjacent scripts are **not** affected and need no whitespace tolerance:
- `migrate.sh` only matches a **line-1 HTML comment** (`<!-- last_updated: … -->`); a file already in YAML (flat or metadata-nested) starts with `---` and is correctly skipped.
- `memstat.sh` reads **no** memory `.md` files at all (only `qmd status` + process list).

Test matrix (`tests/session-start.bats`): both `cwd:` **and** `last_updated:` are covered in flat *and* metadata-nested form — any new frontmatter reader must add both-format cases or reuse `_fm_get`.
