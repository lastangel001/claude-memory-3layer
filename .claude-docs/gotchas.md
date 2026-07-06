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

## Windows Store `python3` alias: on PATH, `command -v` succeeds, but running it fails

confidence: verified

**Symptom:** `doctor.sh` reports `✗ session-start.sh self-test FAILED (invalid JSON)` and `? settings.json not validated (python3/node/jq not found)` on Win11 — even though the hook output is valid JSON and `node` is installed. Every SessionStart logs `JSON validation failed, using safe fallback` to `hook-trace.log`, so the rich memory-protocol context silently degrades to a minimal fallback each session.

**Cause:** Win11 ships a `python3` **execution-alias stub** at `%LOCALAPPDATA%\Microsoft\WindowsApps\python3` (enabled by default). It satisfies `command -v python3` (the file exists on PATH), but *running* it prints `Python was not found; run without arguments to install from the Microsoft Store…` to stderr and **exits 49**. Every parser chain in the repo selected the interpreter with `command -v python3 >/dev/null` — presence, not function — so it picked the stub, ran it, got empty output + rc 49, and declared valid JSON invalid. `node` (which works) was never reached because it sat in an `elif`. Doctor even mislabeled rc 49 as "no parser found" (the "absent" branch).

**Fix (v6.17.1):** detection must probe that the interpreter actually **executes**, not just that it is on PATH. Shared helper in `bin/lib/validate-json.sh`:
```bash
_cmd_runs() {   # 0 only if present AND runs (no-op probe exits 0)
  case "$1" in
    python3) command -v python3 >/dev/null 2>&1 && python3 -c '' >/dev/null 2>&1 ;;
    node)    command -v node    >/dev/null 2>&1 && node -e ''     >/dev/null 2>&1 ;;
    jq)      command -v jq       >/dev/null 2>&1 && jq --version   >/dev/null 2>&1 ;;
  esac
}
_json_parser() { for p in python3 node jq; do _cmd_runs "$p" && { printf '%s' "$p"; return; }; done; return 1; }
```
All callers route through these: `validate-json.sh`, `hooks/post-tool-use.sh`, `bin/merge-settings.sh`, `bin/doctor.sh`, `bin/transcript-export.sh`, `bin/uninstall.sh`. `install.sh` inherits the fix via `_validate_json_file`.

**Lesson:** `command -v` proves a name resolves, NOT that it runs. On Windows especially, prefer a trivial exec probe (`tool --version` / `-c ''` / `-e ''`) before selecting an interpreter. User-side alternative: disable the stub in *Settings → Apps → Advanced app settings → App execution aliases*.

## bats: a teardown ending in `&&` fails every *skipped* test

confidence: verified

**Symptom:** CI red on ubuntu + windows since v6.17.0; `tests/codemap.bats` reported `not ok N … # skip ctags not installed` with `# teardown … failed`. Passed locally.

**Cause:** bats fails any test whose `teardown` returns non-zero. `codemap.bats` skips when ctags/ripgrep are absent (true on GitHub runners), so `FIX` is never set — and its teardown ended with `[[ -n "${FIX:-}" ]] && rm -rf "$FIX"`. With `FIX` unset the `[[ … ]]` is false, so the `&&` compound's exit status is **1**, teardown returns 1, and the *skipped* test flips to `not ok`. Ran green locally only because the dev machine has ctags → tests execute → `FIX` set → teardown ends on a successful `rm`.

**Fix (v6.17.1):** end such teardowns with an explicit `return 0`. Applies to any `teardown`/last-line `&&` guarding optional cleanup.

**Lesson:** a function (or bats hook) whose last statement is `cond && cmd` returns 1 whenever `cond` is false — a silent failure that only surfaces when the guarded branch is skipped. In bats teardown that fails the test; under `set -e` it aborts the script. End with `return 0` (or `|| true`) when the last line is a guarded action.

## Node `execFile("qmd")` can't spawn an npm-shim CLI on Windows (ENOENT)

confidence: verified

**Symptom:** `bin/mcp-recall.mjs` `search_memory` always returned `qmd not found on PATH — install it…` on Windows, even though `command -v qmd` succeeds and `/recall` (which shells out from bash) works fine.

**Cause:** an npm-global CLI like `qmd` is **not** a real executable on PATH — npm drops a set of shims: `qmd` (POSIX sh, used by Git Bash), `qmd.cmd` (batch, used by cmd/PowerShell), `qmd.ps1`. Node's `child_process.execFile("qmd", …)` does **not** consult `PATHEXT`, so it looks for a file literally named `qmd`, finds only the sh shim (not a Windows executable), and throws `ENOENT`. Two dead ends make this worse: `execFile("qmd.cmd", …)` **throws** on modern Node (`.bat`/`.cmd` without `shell:true` is blocked since CVE-2024-27980), and `execFile(..., {shell:true})` would re-parse a free-text search query through cmd.exe (injection + broken quoting on spaces).

**Fix (v6.17.1):** skip the shim entirely — run the CLI's **JS entry** with the current `node`. `resolveQmd()` scans PATH for the `qmd`/`qmd.cmd` shim and, beside it, `node_modules/@tobilu/qmd/bin/qmd`, then invokes `execFile(process.execPath, [entry, …args])`: no shell, argv stays safe, same node that launched the server. Escape hatches: `QMD_BIN` env override, and a real `qmd.exe` on PATH is used directly. macOS/Linux keep the bare `execFile("qmd", …)`.

**Related:** the `claude mcp add` command must get a **Windows** path to the `.mjs`, not an MSYS `/c/...` one — Windows-native `node` reads `/c/Users/…` as `C:\c\Users\…` → MODULE_NOT_FOUND (same class as the settings.json MSYS-path gotcha above). Register with `node "$(cygpath -w ~/.claude/bin/mcp-recall.mjs)"`.

**Lesson:** to call an npm-installed CLI from Node on Windows, don't spawn the bare command — resolve and run its JS entry with `process.execPath`, or you inherit the shim/PATHEXT/`.cmd`-shell mess.

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
