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

Test matrix (`tests/session-start.bats`): both `cwd:` **and** `last_updated:` are covered in flat *and* metadata-nested form — any new frontmatter reader must add both-format cases or reuse `_fm_get`. Since v6.19.0 `session-start.sh` and `vault-doctor.sh` also read `status:` (same whitespace-tolerant form, both formats tested).

## Project slug: never let the model derive it, never trust a hand-written formula

confidence: verified
src: bin/lib/slug.sh#_resolve_project @ abbb81b

**Symptom:** two memory directories for one project — e.g. `C--dev-my-app` (holds the `.jsonl` transcripts) and `C--dev-my_app` (holds a SESSION.md, no transcripts). Hooks read one, the model wrote the other; staleness / cwd / size checks and auto-capture silently see nothing.

**Cause:** two independent errors. (1) Until v6.19.0 the SessionStart context told the model to *derive* the slug from a prose rule; models keep the underscore, drop a dash, etc. (2) `slug.sh` mapped only `/` and `_`, while Claude Code replaces **every non-alphanumeric character** of the native cwd with `-` (spaces, dots, non-ASCII; and a unix path keeps its leading `-`: `/home/u/p` → `-home-u-p`). Paths over 200 chars are truncated + hashed — no formula reproduces that.

**Fix (v6.19.0):** `_resolve_project` in `bin/lib/slug.sh`. The slug is the parent directory name of `transcript_path` from hook stdin — exact, no formula. Formula is the fallback only; the pre-v6.19.0 formula survives as `_legacy_slug` so an upgrade still finds memory written under an old name. The hook hands the model **absolute paths**; nothing in the protocol asks it to compute one.

**Lesson:** when the host tool already tells you where its files are, read that — don't re-implement its naming rule. And never ask the model to compute a path a hook can compute.

## `"\\u"` in a JSON-escaped Windows path is not a unicode escape

confidence: verified

**Symptom:** `_transcript_path_from_json` returned empty for `"C:\\Users\\user\\…"` but worked for `"C:\\Users\\User\\…"`.

**Cause:** the guard against undecodable `\uXXXX` escapes tested the raw JSON text for `\u`. In `\\user` the first backslash escapes the second — the pair is one path separator, and the `u` that follows is just a letter.

**Fix:** park every `\\` pair in a placeholder first, *then* look for `\u`.

**Lesson:** when scanning escaped text for an escape sequence, consume the escaped-backslash pairs before matching anything else.

## Backslash patterns inside `"${var//…}"` differ across bash versions and under `eval`

confidence: verified

**Symptom:** `tp="${tp//\\\\/$'\x01'}"` passed `bash -n` and bats, yet the same line produced a different result when the function was called through `eval` — and `$'…'` inside a double-quoted expansion is not ANSI-C quoting at all.

**Fix:** unquoted assignments, separator in a variable: `sep=$'\x01'; tp=${tp//\\\\/$sep}`. Assignments don't word-split, so the quotes buy nothing here.

**Lesson:** for substitutions involving backslashes or control characters, keep the special character in a variable and leave the expansion unquoted on the right-hand side of an assignment. Verify by running the function from a script file, not only inline.

## `grep -P` in a hook: fails on the hook's locale, and the fallback hid it

confidence: verified
src: hooks/post-tool-use.sh#_commit_re @ abbb81b

**Symptom:** every auto-captured commit line read `git commit: (see git log)` — the commit message was never captured, on any commit.

**Cause:** the message was parsed out of the command text with `grep -oP '(?<=-m …)'`. Under the hook's locale `grep -P` exits with `-P supports only unibyte and UTF-8 locales`; stderr went to `/dev/null`, the `|| true` swallowed the status, and the code fell through to its "(see git log)" default. The test only asserted that *a* capture line existed. Even with a working `grep -P` the regex returned `$(cat <<` for heredoc-style commits, and BSD grep has no `-P`.

**Fix (v6.19.0):** don't parse the command. If the command *looks like* a commit, ask the repository: `git log -1 --format='%h %ct %s'`, accept it only if it is minutes old and its sha was not captured before (`memory/.auto-last-commit`).

**Lesson:** a fallback value that is indistinguishable from "feature broken" needs a `_diag … degraded` line. And assert the *content* of a capture in tests, not its presence.

## `merge-settings.sh` dedups by command — a changed matcher never reaches existing installs

confidence: verified
src: bin/merge-settings.sh#sync_group @ abbb81b

**Symptom:** `settings.snippet.json` changes the PostToolUse matcher; fresh installs get it, upgraded installs keep `"*"` forever. `install.sh` even reported "all hooks present".

**Cause:** merge is idempotent by hook *command*: if the command is already registered, the source entry is skipped whole — matcher and extra hook keys included.

**Fix (v6.19.0):** a sync pass — a target group holding exactly one hook, ours, takes `matcher` and any missing hook keys from the snippet. Groups the user combined with other hooks are untouched. `install.sh` now always runs the merge; exit code 10 means "already up to date, nothing written".

**Lesson:** any change to `settings.snippet.json` other than adding a new command is a migration — add a test in `tests/install.bats` that starts from the previous shape.

## Reading hook stdin must not block

confidence: verified

Hooks are also run by hand, by `doctor.sh` and by bats, where stdin is a terminal or an open pipe that never closes. `input=$(cat)` hangs there. `session-start.sh` uses `[[ -t 0 ]] || IFS= read -r -d '' -t 3 _hook_input || true`; `doctor.sh` runs its self-test with `</dev/null`.

## Appending to SESSION.md from a hook costs the model a failed Write

confidence: verified

Claude Code refuses a `Write` to a file that changed since the model last read it. Every `[auto]` line PostToolUse appends therefore makes the model's next SESSION.md write fail once (re-read, retry). Keep appends rare: real commits only, and an identical `[auto] label: detail` line is never added twice.

## PreCompact cannot make the model flush — and its JSON output is thrown away

confidence: verified (plain stdout reaches the summarizer; the hook's side effect — both observed live, see "What live compactions showed") · inferred (`systemMessage` is discarded; the model gets no turn — from the hooks reference)
src: hooks/pre-compact.sh#compact-snapshot.sh @ abbb81b

(Source: the Claude Code hooks reference, which states each point below explicitly. Our side of the contract is covered by `tests/pre-compact.bats`.)

**Symptom:** the README promised "PreCompact fires, reminds Claude to flush, Claude writes SESSION.md". Nothing of the sort happened: no model ever acted on the reminder.

**Cause:** three facts about the event. (1) Compaction starts as soon as the hook returns — the model gets no turn in between. (2) For PreCompact, Claude Code **discards** the JSON fields `systemMessage` and `continue`; `hookSpecificOutput.additionalContext` is not a PreCompact channel either. (3) The only output channel is plain stdout, and it goes to the *summarizer* as instructions (10,000-character cap, truncated above it — not spilled to a file like other hooks). Until v6.20.0 `pre-compact.sh` printed a JSON `systemMessage`; it reached nobody.

**Fix (v6.20.0):** the hook stopped asking and started doing. Side effect: `bin/compact-snapshot.sh` writes `memory/compact-snapshot.md` (last user turns verbatim + git position). Output: plain-text summary instructions. Hand-back: SessionStart runs again after compaction with `source: compact` and inlines SESSION.md + the snapshot.

**Lesson:** read the per-event output contract before designing a hook — the fields are not uniform across events. A hook that must change what the model *does* at an event where the model has no turn is impossible; make it deterministic or move it to an event that has one.

## Hook context is capped at 10,000 characters — and the overflow is a preview, not an error

confidence: inferred (the cap and the spill behaviour — from the hooks reference) · verified (the two traps below — reproduced in tests)
src: hooks/session-start.sh#_CONTEXT_CAP @ abbb81b

A hook's `additionalContext` (and plain stdout) is capped at 10,000 characters *per string*. Above it Claude Code saves the text to a file and gives the model the path plus the first 2,000 characters — and does **not** ask the model to read the file. So an oversized SessionStart context silently loses its tail, which is exactly where re-injected state sits.

`session-start.sh` therefore budgets (`_CONTEXT_CAP=9500`): inline SESSION.md only up to 5,000 chars and the snapshot up to 2,200, shed the snapshot first when the fixed part has grown (warnings, `.claude-private` list), and fall back to an explicit "READ NOW" instruction instead of overflowing. Lengths are measured with `${#var}`, which counts bytes under a byte-oriented locale — conservative, never over.

Two traps found while building it: truncating with `${var:0:N}` can split a multibyte character and produce invalid UTF-8, which fails JSON validation and used to cost the *whole* context (truncate on line boundaries with awk); and file content can carry control characters `json_escape` does not cover (strip them with `tr`, and if the inlined record still breaks the envelope, re-emit without it rather than falling back to the bare error).

## The transcript `.jsonl` is internal and may lag

confidence: inferred (from the sessions and hooks docs)

The docs call the transcript entry format internal and unstable, and note it is written asynchronously — at hook time it may not yet hold the newest turn. `compact-snapshot.sh` and `transcript-export.sh` parse it anyway (there is no other source for verbatim user turns), so: keep the parsing in those two scripts only, treat "zero turns found with a transcript on hand" as `degraded` in the outcome journal (that is how format drift will show up), and never make correctness depend on the last turn being present.

## bats: a variable set by a helper is lost when the helper runs in a pipeline

confidence: verified

`{ printf …; head -c 5000 /dev/zero; } | make_session "$PWD"` runs `make_session` in a subshell, so the `SESSION_FILE` it sets never reaches the test body. A later `$(dirname "$SESSION_FILE")` silently resolves to `.` and the fixture lands in the wrong directory — the test then fails on an assertion that looks like a product bug. Re-derive the path after the pipeline, or feed the helper through a here-doc / temp file.

## A `# shellcheck disable=` directive covers only the next command

confidence: verified

**Symptom:** CI red on the shellcheck step with `SC2154: slug_source is referenced but not assigned` in `bin/doctor.sh`, although a `disable=SC2154` comment sat two lines above. bats never ran on that job — shellcheck is an earlier step.

**Cause:** the directive was written above an assignment and was meant to also cover the `if` that followed. A directive applies to the single command after it (a whole `if`/`for`/function when placed directly above that compound command), not to "the lines below". shellcheck reports SC2154 once per variable per file, at the first uncovered reference.

**Fix:** one directive directly above each command that first references a variable set by a sourced library.

**Lesson:** shellcheck is not installed on the dev machine, so this class only surfaces in CI — open a PR rather than pushing to `main`, and read the ubuntu job first: a failure there in seconds means lint, not tests.

## A sourced helper that returns 1 killed the background refresh for months

confidence: verified
src: bin/lib/paths.sh#_add_path @ abbb81b, hooks/session-start.sh#.qmd-last-refresh-done @ abbb81b

**Symptom:** on a long-lived install the qmd index was months old and held a small fraction of the memory files; no transcript had ever been exported; `~/.claude/logs/` was empty. No error anywhere, and `.qmd-last-refresh` looked fresh.

**Cause:** the SessionStart background block is a subshell of a `set -euo pipefail` script. Its first real line called `_augment_node_path`, whose helper ended with `[[ -d "$p" ]] && PATH="$p:$PATH"` — status 1 for a directory that does not exist. The list of candidate directories mixes Windows, Linux and Homebrew paths, so on **every** machine some are missing: errexit ended the subshell before the transcript export and before `qmd update`. The kick-off marker is written *before* the block is spawned, so from outside it looked like the refresh ran. (Same root as the bats-teardown gotcha above; `memstat.sh` sources the same file without `set -e` and never noticed.)

**Fix (v6.21.0):** `_add_path` returns 0 explicitly; the block starts with `set +e` and `trap - ERR` (it is best-effort — errexit has no business there); it writes `.qmd-last-refresh-done` at the end and a `SessionStartBg` line to the outcome journal. `doctor.sh` and `/memstat` compare kick-off and completion. `tests/session-start.bats` runs the block against a qmd stub and waits for the stamp.

**Lesson:** (1) a function in a sourced library must end with an explicit `return 0` unless its status is its contract. (2) A "started" marker proves nothing — record completion, and have the health check compare the two. (3) Anything a hook runs in the background needs a test that waits for its effect; "the hook exited 0" does not cover it.

## A background child of a hook must let go of stdout

confidence: inferred

The background block ends with `) </dev/null >/dev/null 2>&1 &`. A child that keeps the hook's stdout open can keep the harness waiting for EOF on the hook's output, or interleave its own output with the JSON. This could not be observed before v6.21.0 — the block never got far enough to matter — so the redirection is defensive: measured after the fix, the hook returns in about a second while the refresh continues.

## Command docs drifted from the tool they drive

confidence: verified
src: bin/recall.sh#MEMORY_QMD_CMD @ abbb81b

`commands/recall.md` told the model to run `qmd search … -k 5` (qmd's flag is `-n`; unknown flags are silently ignored, so the limit never applied), `--filter "qmd://…"` for `--here` (no such flag — the scope was never applied), and to `export PATH="…:$APPDATA/npm:$PATH"` first (on Git Bash `$APPDATA` is a backslash path; the export made qmd's shim resolve its own module to a non-existent location and every search failed). `bin/mcp-recall.mjs` carried the same `-k`.

**Fix (v6.21.0):** the command file now only says "run `bin/recall.sh`"; flags and PATH handling live in the script, covered by `tests/recall.bats` through a qmd stub that records its arguments.

**Lesson:** a prompt file that spells out another tool's CLI is untested code. Put the invocation in a script with a test, and keep the prompt file to "run this, show the output".

## Under Git Bash, `/tmp` is an alias — git answers with the Windows path

confidence: verified

In bats on Windows `mktemp -d` gives `/tmp/tmp.X`, but `git rev-parse --show-toplevel` / `--git-common-dir` inside it return `C:/Users/…/AppData/Local/Temp/tmp.X`. A test that computes an expected slug from `$PWD` and compares it with one the code derived from git output fails on Windows only. Derive both sides from the same source (ask git in the test too). Real sessions are unaffected: there the cwd is a `/c/…` path and both forms name the same directory.

## qmd indexes frontmatter as plain text — but a value with `/` is not one term

confidence: verified

`qmd get` shows the YAML frontmatter as part of the stored document, and a BM25 search for words from it (`tags identity`) returns the frontmatter line. So `description:`, `tags:` and names kept only in frontmatter are searchable — no need to copy them into the body. What does **not** work is searching for a slash-joined value as a single token: `memory/l0` finds nothing, while `memory l0` does. Query the parts.

## Citations: cite a commit that will still exist

confidence: verified

`src: path#symbol @ <sha>` is checked by `vault-doctor.sh` with `git cat-file` and `git rev-list <sha>..HEAD -- path`. This repo squash-merges: a feature-branch commit is gone from `main`'s history after the merge, and once the branch is deleted the sha may not resolve at all — the doctor then reports "cited commit … is not in this repository". Cite the merge commit on the main branch (or cite after merging). Cite a symbol, not a line number: line numbers move with every edit, a function name moves only when the fact probably changed too.

## `grep -i -F` aborts under Git for Windows (grep 3.0)

confidence: verified
src: bin/recall.sh#_bre @ 2f32af5

**Symptom:** a case-insensitive fixed-string grep — `grep -i -F -- "$term"` — returned nothing and the pipeline carried on as if there were no matches. Run by hand: `Aborted`, exit status 134. Any input, ASCII included; `LC_ALL=C` does not help. `grep -F` alone and `grep -i` alone both work.

**Cause:** a crash in GNU grep 3.0, the version Git for Windows ships, on the combination of `-i` and `-F`. Inside `$( … || true )` or `2>/dev/null` the abort is indistinguishable from "no match" — the ripgrep path hid it, because the plain-grep path only runs when `rg` is missing.

**Fix (v6.23.0):** escape the literal and use a regular expression — `grep -i -e "$(_bre "$term")"`, where `_bre` backslash-escapes `[ ] \ . * ^ $`. `tests/recall.bats` runs the grep path with ripgrep removed from PATH and asserts the script contains no `-i` + `-F` grep.

**Lesson:** never combine `grep -i` with `-F` in a script that must run on Git Bash. And a fallback path needs its own test with the preferred tool taken away — otherwise it is only ever executed on the machines least able to report a failure.

## What live compactions showed: the manual path works end to end; the idle path does not re-inject

confidence: verified (what was observed) · inferred (the explanation of the idle case)
src: hooks/pre-compact.sh#snapshot=ok @ ab55553, hooks/session-start.sh#hook_source @ ab55553

Two real compactions on v6.23.x, read from `hook-diag.jsonl` and the session transcripts.

**Manual `/compact` — the whole chain, in order:**

1. `PreCompact ok snapshot=ok turns=5 trigger=manual`. `compact-snapshot.md` held exactly the last five user turns (compared against the transcript), no tool output or reminders, three git lines.
2. The compaction summary, 50-odd seconds later, **ended with the working-state line** the hook's stdout asked for — so plain stdout from a PreCompact hook does reach the summarizer.
3. `SessionStart ok slug=transcript source=compact inject=session snapshot=yes`, two seconds after the summary. The transcript shows the order: `compact_boundary` → summary → re-attached files → the SessionStart hook's additional context. The `<memory-record>` block arrived complete — frame text, SESSION.md, snapshot — inline, not spilled to a file.

**Idle auto-compaction (`trigger: auto` on a session nobody had touched for close to an hour):** step 1 happened exactly as above. Steps 2 and 3 did not: no SessionStart fired for that session in the following quarter of an hour, its transcript gained no entry, and its next SessionStart was `source: resume` — where the hook only tells the model to read SESSION.md.

**Likely explanation of the idle case (not confirmed):** Claude Code compacts idle sessions in the background (`idleCompaction`, `precomputeCompactionEnabled` in the settings reference). PreCompact fires when that work starts; the result is applied when the session is next used.

**Consequences:**
- "The snapshot exists" does not mean "the context was compacted" — on the idle path it is written while nobody is there.
- After an idle compaction the session relies on the plain fallback: the SessionStart context always carries the SESSION.md path and "read it FIRST". Whether to inline on `resume` as well is an open item in IDEAS.md.
- A session cannot be made to compact from outside: a message sent to another session arrives as a labelled user turn, not as the `/compact` command. The manual observation above needed a person typing it.

**Lesson:** a hook event's name describes when the harness *starts* something, not when the model sees the result. Journal every hook outcome with its `source` / `trigger` — the idle finding came from reading `hook-diag.jsonl`, not from an experiment.
