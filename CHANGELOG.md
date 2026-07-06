# Changelog

## v6.17.1 — 2026-07-06 — Windows JSON-parser + MCP-recall footguns

**Fixed**
- **`bin/mcp-recall.mjs` `search_memory` always failed on Windows with "qmd not found on PATH".** The npm-installed `qmd` on PATH is a shim (`qmd` + `qmd.cmd`), not a real exe; Node's `execFile("qmd", …)` can't spawn it (no PATHEXT resolution, and a `.cmd` needs a shell — unsafe with a free-text query), so it `ENOENT`ed and the tool misreported qmd as absent even though `command -v qmd` succeeded. New `resolveQmd()` locates qmd's JS entry (`node_modules/@tobilu/qmd/bin/qmd`) beside the shim and runs it with the server's own `node` — no shell, argv stays safe. Honors a `QMD_BIN` override; falls back to a real `qmd.exe` on PATH; unchanged on macOS/Linux. `get_identity` was unaffected.
- **`python3` execution-alias stub on Win11 silently disabled JSON validation + auto-capture.** Windows 11 ships a `python3` stub at `%LOCALAPPDATA%\Microsoft\WindowsApps\python3` (enabled by default) that satisfies `command -v python3` but, when run, prints "Python was not found…" and exits 49. Every parser chain in the repo selected its interpreter with `command -v <tool> >/dev/null` — presence, not function — so on a stock Win11 box it picked the stub, ran it, got rc 49, and declared valid JSON invalid. Fallout: `doctor.sh` self-test FAILED, `settings.json` reported "not validated", and **every SessionStart discarded its rich memory-protocol context for a minimal safe fallback** (logged as `JSON validation failed, using safe fallback` in `hook-trace.log`) — `node`, which works, was never reached because it sat in an `elif`. This was live on the maintainer's machine, caught by the v6.17.0 dynamic self-test.
- **Detection now probes that the interpreter actually runs.** New `_cmd_runs` (present *and* executes a no-op) + `_json_parser` (first working parser) helpers in `bin/lib/validate-json.sh`; all call sites routed through them: `validate-json.sh`, `hooks/post-tool-use.sh`, `bin/merge-settings.sh`, `bin/doctor.sh`, `bin/transcript-export.sh`, `bin/uninstall.sh` (`install.sh` inherits it via `_validate_json_file`). `doctor.sh` also now flags an on-PATH-but-non-running `python3` explicitly instead of mislabeling it "no parser found".

## v6.17.0 — 2026-07-05 — content-health tooling, uninstall, install hygiene

All eighteen M-priority backlog items shipped in one sweep (the sole M/L item —
a bundled ONNX embedder to replace `qmd` — stays deferred; it needs native
bindings + cross-platform validation and doesn't belong in a batch). One real,
still-live bug surfaced and was fixed along the way (see **Fixed**).

**Added**
- **`bin/vault-doctor.sh` — memory content health** (complements `doctor.sh`, which checks the *install*): mechanical, no-LLM checks over memory *content* — IDENTITY.md over the 25-line cap, oversize SESSION.md, stale sessions (`--stale-days`, default 30), transcript-export retention, and — when run inside a repo — `.claude-docs/` missing frontmatter, orphaned docs, and broken relative links. `--fix` wipes stale SESSION.md files to a blank template (preserving `cwd:`, backup kept). Absorbs the old "SESSION cleanup cron" idea as its stale-session check.
- **`bin/gen-index.sh` — routing-table generator**: regenerates `.claude-docs/index.md` from each doc's `description:` frontmatter (falls back to first heading, then filename). Only the region between `AUTO-INDEX` markers is rewritten; a MANUAL block of hand-written notes is preserved. An existing markerless `index.md` is **never clobbered** — the script refuses and prints the two marker lines to add (or `--force` to scaffold). `--check` exits non-zero when a doc was added/removed without regenerating (wire it into a project's CI). Every shipped `.claude-docs/*.md` template gained a `description:` field.
- **`bin/uninstall.sh` — clean removal**: strips *only our* hook commands from `settings.json` (foreign tools' hooks + other keys preserved), removes hooks/commands/bin/libs/templates/protocol/markers, and **never touches** `memory/IDENTITY.md` or `projects/` (your data). `--dry-run` + `--yes`. Backs up `settings.json` first. New **Uninstall** section in INSTALL.md.
- **`/session-end` slash command**: enforces the task-wrap-up ritual — distil high-signal SESSION.md content to its permanent layer (gotchas/architecture/conventions/CLAUDE.md/IDENTITY/project.md, in-repo beats account-local), append one `## Timeline` line to project.md, confirm what was promoted, then wipe SESSION.md to a clean template. Never commits; repo-file promotions are proposed for the user to commit.
- **`bin/lib/validate-json.sh` — shared JSON validator** (`python3 → node → jq`): the validation chain that was copy-pasted into `install.sh`, `doctor.sh`, `merge-settings.sh`, and `session-start.sh` is now one sourced library (`_validate_json_stream` / `_validate_json_file`). All four call sites refactored onto it.
- **`doctor.sh` install-health checks**: duplicate hook registration (same command wired twice for one event = double token cost + execution), CRLF line endings in installed scripts, and a **dynamic self-test** that runs the *installed* `session-start.sh` + `post-tool-use.sh` in a throwaway home and asserts exit 0 + valid JSON — catches a broken runtime copy (bad merge, partial install) that static checks miss.
- **`session-start.sh` nudges**: SESSION.md size warning (>4 KB — it re-loads in full on every compact), version-drift nudge (weekly-debounced; compares `.memory-version` against the source CHANGELOG head, `sort -V` forward-only so dev machines aren't nudged backwards), and a stronger "add `last_updated:` NOW" imperative when the marker is missing. `hook-trace.log` now self-rotates (daily-debounced, last 2000 lines) so it stops growing unbounded.
- **`/onboard-memory` business-flow section**: app projects now get a `## Business flows` block tracing 1–3 primary domain processes end-to-end (e.g. `checkout: cart → payment → order → fulfillment`) — *what the product does*, beyond the technical layer view. Skipped for libraries / CLIs / tooling.
- **Test suite grew 29 → 78 bats cases**: new `codemap.bats` (skips without ctags/rg), `doctor.bats` (dup-hook, CRLF, self-test, broken-runtime), `migrate.bats` (Pass A + Pass B), `gen-index.bats`, `vault-doctor.bats`, plus session-start coverage for the new nudges and a metadata-nested `last_updated` case (completes the flat + nested frontmatter matrix). Repo-local `.githooks/pre-commit` (opt-in via `git config core.hooksPath .githooks`) runs bats + nudges on a missing CHANGELOG entry.

**Fixed**
- **`migrate.sh` Pass B was *still* dead after v6.16.0**: the marker regex used `\<!--`, but in ERE (glibc) `\<` is a **word-boundary anchor**, not a literal `<` — so it never matched an `<!-- last_updated: … -->` marker and no file was ever migrated. v6.16.0 fixed the `local`-under-`set -e` abort but not this; the new `migrate.bats` caught it immediately. Both regexes now use a literal `<`.

**Changed**
- **Indexer-frontmatter bug class closed by audit, not just patches**: confirmed only `session-start.sh` + `doctor.sh` (+ the new `vault-doctor.sh`/`gen-index.sh` via a shared `_fm_get` idiom) read frontmatter *scalars*, and all use the whitespace-tolerant `^[[:space:]]*key:` form. `migrate.sh` (line-1 HTML only) and `memstat.sh` (reads no memory files) are provably unaffected. Documented as the canonical answer in `gotchas.md`, with the both-formats test matrix locking it in.

## v6.16.0 — 2026-07-05 — token-budget split, verbatim recall layer, MCP, fact lifecycle

All five H-priority backlog items shipped (from the analysis session vs smixs/iva memory architecture).

**Added**
- **`PROTOCOL.md` — slim always-loaded protocol core (~150 lines)**: the ~320-line protocol cost ~9k tokens in *every* session of *every* project, and loaded **twice** (~18k) inside this repo because the repo's `CLAUDE.md` was a full copy. The core (layers, rules, session-start ritual, SESSION.md template, tools) now installs to `~/.claude/CLAUDE.md`; fat reference sections moved to on-demand docs `templates/protocol/{workflows,knowledge-store,obsidian}.md` (installed to `~/.claude/templates/protocol/`). This repo's `CLAUDE.md` is now a thin dev entry point — no protocol copy.
- **Verbatim transcript export (`bin/transcript-export.sh`)**: SessionStart exports Claude Code's own `.jsonl` session transcripts to searchable markdown under `memory/raw/transcripts/` (incremental, debounced with the qmd refresh, background). Closes the biggest data-loss hole: context the model never wrote to SESSION.md used to die at compact — now `/recall` can quote past conversations verbatim. Privacy: `<private>` blocks stripped, projects with `.claude-private` skipped entirely, opt-out flag `~/.claude/.transcript-export-disabled`, 30-day rolling retention (`TRANSCRIPT_KEEP_DAYS`), 300 KB size cap (`TRANSCRIPT_MAX_BYTES`). python3 → node parser fallback; 5 bats cases.
- **MCP server `bin/mcp-recall.mjs`** (zero dependencies, stdio, no daemon): exposes `search_memory(query, limit?, collection?)` (BM25 via `qmd search`) and `get_identity()` to subagents, task runners and headless `claude -p` — contexts that cannot call slash commands. Register: `claude mcp add --scope user memory-recall -- node ~/.claude/bin/mcp-recall.mjs`.
- **Fact lifecycle for gotchas/decisions**: `confidence: verified|inferred` tag (assert vs hedge) and SUPERSEDE semantics — outdated facts get `status: superseded` + a dated `## History` line instead of silent deletion/rewrite. Top of file = current truth, History = trail. Wired into the protocol (rule 7), the gotchas template, and `/onboard-memory` (onboard-generated entries start as `inferred`).
- **Distillation timeline**: task wrap-up now appends one line `- YYYY-MM-DD: <task> — <outcome>` to `## Timeline` in `project.md` before wiping SESSION.md — answers "what did I do on this project in May" without resurrecting a journal layer.
- **shellcheck in CI** (ubuntu job, `-S warning`, all shell scripts) + full cleanup of existing findings.

**Fixed**
- **`migrate.sh` Pass B was completely dead**: `local` used at top level (outside any function) errors on every file iteration, and under `set -e` aborted the script on the first candidate file — HTML-comment → YAML frontmatter migration never ran. Found by the new shellcheck pass (SC2168).

**Changed**
- `session-start.sh`: slug computed before the background block (transcript export needs it); export runs before `qmd update` so fresh exports land in the same index refresh.
- `install.sh` "Next steps" now prints the ready-to-paste `claude mcp add` command when `memory-recall` is not yet registered in `~/.claude.json` (registration stays opt-in); same step added to README quick start.
- tests: 38 cases (+5 transcript-export); shellcheck directives documented inline where variables are set by sourced libraries.

## v6.15.1 — 2026-06-11 — install/update logic audit fixes

Re-verification of the install/update path with live scenarios in isolated environments surfaced one high-impact detection bug and several smaller issues.

**Fixed**
- **False "all hooks present" silently skipped hook registration** (`install.sh`): hook detection grepped for the event *name* (`"SessionStart"`), so a settings.json that already had *another tool's* hooks on the same events made the installer believe memory hooks were registered — they never were, and the whole protocol stayed dead with zero errors. Detection now greps for our actual hook commands (`hooks/session-start.sh` etc.); `merge-settings.sh` dedups by command, so foreign hooks and ours coexist. Regression-tested.
- **`update.sh --dry-run` mutated the source repo**: it ran `git pull` unconditionally despite promising "write nothing". Dry-run now does `fetch` + pending-commit preview only; the pull happens only on a real run. Regression-tested (HEAD and `.memory-version` asserted unchanged).
- **`merge-settings.sh` jq-only path wrote unvalidated output**: the validation chain only knew python3/node, but the jq merge path runs precisely when those are absent. jq added as a third validator.
- **Unmatched template glob could abort install**: `templates/repo/.claude-docs/*.md` loop now skips non-existent matches (broken/partial archive) instead of crashing under `set -e`.

**Changed**
- Stale descriptions fixed: `install.sh` header and INSTALL.md claimed the installer "prints merge instructions" — it auto-merges since v6.7.0. INSTALL.md gained an "Updating an existing install" section (update.sh was documented only in README) and a custom-`CLAUDE_HOME` caveat (snippet hook paths always point to `~/.claude/`). "Next steps" numbering no longer starts at "2."; quoting nit in the executable check.
- tests/: +4 cases (foreign-hooks merge regression, fresh-install hook commands, update.sh dry-run purity) — suite now 33.

## v6.15.0 — 2026-06-10 — bug-fix sweep + bats test suite + CI

Full project audit: 6 confirmed bugs fixed (two of them silently broke shipped features), installer completeness restored, docs drift cleaned, and the long-planned test suite landed.

**Fixed**
- **`onboard-report.sh` printf leading-dash crash** (lines 145/179): `printf '- %s\n'` was parsed as an option → exit 2 under `set -euo pipefail` killed sections 4/6–10 on any repo with a `.gitignore` or Makefile. Now `printf -- '- %s\n'`. Gotcha documented; regression-tested.
- **Multiline `<private>` blocks leaked past privacy redaction** (`session-start.sh`): single-line sed couldn't strip blocks spanning lines. Now perl `-0pe 's/<private>.*?<\/private>//gs'` (non-greedy, multiline); sed fallback + trace warning when perl is absent. Non-portable `grep -qP` probe removed.
- **`codemap.sh def`/`callees` returned nothing for any symbol**: v6.7.0's `grep -F "^sym\t"` made `^` a literal character — matched nothing, silently. Replaced with awk exact first-field compare (anchored AND regex-safe). `callers` now escapes regex metachars in the symbol name; `.sh` files added to the tags staleness check.
- **`install.sh` missing files**: `bin/memstat.sh` was never installed (→ `/memstat` broken on fresh installs) and `commands/migrate-legacy-memory.md` was never installed despite being documented. Both added.
- **`post-tool-use.sh` operator precedence**: `A && B || C` made any tool writing a file named `CLAUDE.md` match the L1a capture; parenthesized so only `Write` matches.
- **Stale qmd lock could disable index refresh forever**: a crash between mkdir-lock and rmdir left the lock in place and every later session silently skipped `qmd update`. Locks older than 10 minutes are now removed at SessionStart.
- **CWD mismatch detection dead on indexer-rewritten SESSION.md**: Claude Code's memory indexer re-nests frontmatter under `metadata:` (fields get indented), so the anchored `^cwd:` lookups in `session-start.sh` and `doctor.sh` stopped matching. Frontmatter lookups now allow leading whitespace. Gotcha documented; regression-tested.

**Added**
- **bats-core test suite** (`tests/`, 29 cases): session-start (staleness, CWD mismatch, privacy redaction incl. multiline + non-greedy, compression flag, JSON validity), post-tool-use (capture patterns + precedence regression), onboard-report (printf regression, full render on fixture repo), install.sh completeness sanity (every repo command/script/hook must appear in `--dry-run` output — catches the `/memstat` bug class).
- **GitHub Actions CI** (`.github/workflows/ci.yml`): ubuntu + windows (Git Bash — primary platform), `bash -n` on all scripts + `bats tests/`.
- **`bin/lib/paths.sh`** — shared `_add_path`/`_augment_node_path` (was duplicated in session-start.sh and memstat.sh).
- **Templates installed to `~/.claude/templates/`** — CLAUDE.md referenced a phantom `~/.claude/dist/claude-memory-3layer/templates/` path that nothing created; install.sh now copies `templates/` and the protocol references the real location.

**Changed**
- README: `/memstat` documented in Tools; repo layout completed (`bin/memstat.sh`, `bin/lib/paths.sh`, `migrate.sh`, `commands/migrate-legacy-memory.md`). INSTALL.md "Files in this archive" completed. IDEAS.md: shipped items deduplicated out of the backlog; new deferred items recorded (shared validate-json lib, BSD stat fallback, merge-settings dedup, codemap test coverage); post-release +7 audit-inspired items (shellcheck CI, doctor dynamic self-test, CRLF check for installed hooks, hook-trace.log rotation, version-drift nudge, indexer-frontmatter decision, repo pre-commit hook).

## v6.14.0 — 2026-06-07 — rename /onboard → /onboard-memory

The onboarding slash command is renamed to avoid collision with other tools' generic `/onboard` and to read clearly in the command list.

**Changed**
- **`/onboard` → `/onboard-memory`** — command file renamed `commands/onboard.md` → `commands/onboard-memory.md`; invocation self-references and headings updated. `install.sh` installs the new filename. Backend `bin/onboard-report.sh` and the `.onboard-rev` marker are unchanged (internal names). README + IDEAS updated to the new invocation.
- **Note for existing installs:** re-run `./install.sh`, then delete the stale `~/.claude/commands/onboard.md` (installer adds the new command but does not remove the old name).

## v6.13.0 — 2026-05-29 — /onboard: evolutionary update (incremental re-onboard, no data loss)

`/onboard` is now **idempotent-friendly**: re-running it on a project that was already onboarded patches the existing memory instead of overwriting it. Hand-edits survive. (Implements deferred idea D.)

**Added**
- **Onboard revision marker** — `/onboard` writes `.claude-docs/.onboard-rev` (git-tracked: `rev` + `date`) at the end of every run (`commands/onboard.md` Step 5).
- **Delta-aware report** (`bin/onboard-report.sh`, new section 0). If the marker exists → **UPDATE mode**: emits commits (`git log rev..HEAD`), changed files (`git diff rev --stat`), and heuristic **stale-doc hints** (changed deps → architecture.md, test files → conventions.md, CI → conventions/architecture, docs → all). No marker → **FIRST RUN** banner. Guards against rebase/shallow/non-git (falls back to full refresh but still preserves hand-edits). Safe under `set -euo pipefail`.
- **UPDATE path in `/onboard`** (`commands/onboard.md`). New "Mode" section + Step 3 update path: read existing docs first, patch only what the delta implies, additive by default, loss-aversion rule ("when unsure whether a line is a hand-edit worth keeping — keep it"). Self-review gains a "(UPDATE) no content lost" check (diff against pre-existing docs; every removal must be justified). Step 4 report becomes a changelog in update mode.

## v6.12.0 — 2026-05-29 — /onboard: layers, guided tour, symbol outline, self-review

Concepts ported from [Understand-Anything](https://github.com/Lum1104/Understand-Anything) (a heavy Tree-sitter + knowledge-graph plugin) — adapted as lightweight markdown/bash, no new infrastructure.

**Added**
- **Architecture-layer classification** (`commands/onboard.md`). Step 2 now classifies every top-level dir/module into a layer (API / Service / Data / UI / Utility); `architecture.md` gets a **Layers** table. Analog of their `architecture-analyzer`.
- **Guided tour / reading order** (`commands/onboard.md`). Step 2 derives a dependency-ordered learning path (entry point → core deps → leaf utilities, 5–10 stops); `architecture.md` gets a **Reading order (start here)** section. Analog of their `tour-builder`.
- **Symbol outline in onboard report** (`bin/onboard-report.sh`). New section 5 calls the existing `bin/codemap.sh outline` (universal-ctags + ripgrep) to feed real class/function structure into `/onboard`. Degrades gracefully to a skip note when ctags/ripgrep aren't installed (guarded against `set -euo pipefail`). Sections 5–9 renumbered to 6–10.
- **Self-review step** (`commands/onboard.md`, new Step 3.5). Before reporting, validates: doc-index links resolve, no fabricated content, sections complete, `CLAUDE.md` ≤60 lines, layers + reading order present. Analog of their `graph-reviewer`.

**Fixed**
- `commands/onboard.md` Step 1 description was stale (said docs read "up to 3 key files") — the 3-file cap was removed in v6.11.0. Now describes full-capture + symbol outline.

## v6.11.1 — 2026-05-29 — Fix false "settings.json invalid JSON" on Windows

**Fixed**
- **`install.sh` + `bin/doctor.sh` JSON validation.** Both reported `✗ settings.json invalid JSON` on Windows Git Bash even when the file was valid. Cause: validators passed the MSYS path (`/c/Users/…/settings.json`) as a string arg to Windows-native `node`/`python3`, which cannot resolve `/c/...` → `ENOENT` → false failure. Fix: pipe the file through `cat` into the interpreter's stdin (`readFileSync(0)` / `sys.stdin`) so the interpreter never touches the path; bash resolves it for `cat`. Cross-platform. Documented in `.claude-docs/gotchas.md`.

## v6.11.0 — 2026-05-29 — /onboard: full-capture, no truncation

**Changed**
- **`bin/onboard-report.sh` — maximal first-run capture.** First `/onboard` no longer truncates source material (later sessions run from memory, so the one-time token cost is worth it):
  - **docs/ files**: removed the `architect|overview|design|setup|install|…` filename regex filter — every `*.md` in docs folders is now read, not just name-matched ones (`api_public.md`, `database.md`, `parsing_vk.md` were silently skipped before).
  - **docs/ file count**: removed the 3-file cap — all matched docs are read.
  - **docs/ file body**: `head -80` → `cat` (full file).
  - **README**: `head -120` → `cat` (full file); dropped the "_(truncated at N lines)_" note.
  - **Stack files** (`package.json`, `pyproject.toml`, …): `head -60` → `cat` (full file — extras/scripts/tool-config no longer cut off).

## v6.10.1 — 2026-05-27 — /onboard: include project docs in scan

**Changed**
- **`bin/onboard-report.sh`**: new section 2 "Project documentation" — reads README (up to 120 lines), CONTRIBUTING, and up to 3 architecture/overview/setup files from `docs/` / `doc/` / `documentation/` / `wiki/` folders. Also lists all `.md`/`.rst`/`.txt` files in docs folders. Remaining sections renumbered 3–9.
- **`commands/onboard.md`**: Step 1 updated to describe that docs are now in the report (no more manual "also read"). Step 2 adds explicit instructions to use README/docs for architecture pattern and CONTRIBUTING.md for conventions.

## v6.10.0 — 2026-05-27 — /onboard command + onboard-report.sh

**Added**
- **`/onboard` slash command** (`commands/onboard.md`). Bootstraps Claude Code memory for an existing project in 4 steps: run `onboard-report.sh`, analyse output, create `CLAUDE.md` + `.claude-docs/` scaffold (architecture, conventions, gotchas, index), report gaps to user. Does not commit — user reviews first.
- **`bin/onboard-report.sh`** — collects raw repo data for `/onboard`: stack files (package.json, composer.json, pyproject.toml…), directory structure, entry points, config files, git log (last 50), most-changed files (last 6 months), FIXME/HACK/WORKAROUND inline comment grep, `@deprecated` markers. Cross-platform (macOS/Linux/Windows Git Bash); gracefully degrades when `tree` is not available.

**Changed**
- `install.sh`: installs `commands/onboard.md` and `bin/onboard-report.sh`.
- `README.md`: `/onboard` added to Tools section; repo layout entries expanded from glob to per-file.

## v6.9.1 — 2026-05-27 — README: scenarios + trigger table

**Changed**
- **README: "Memory in action" section.** Four concrete scenarios with actual file content: cross-session continuity, gotcha discovered, decision with tradeoff, compact/context reset. Includes "what does NOT get saved" list and quick test heuristic.
- **README: model write-trigger table in Hooks section.** Documents what Claude writes automatically beyond the 3 hook-captured events (Decisions, gotchas.md, File map) with explicit trigger criteria per row.

## v6.9.0 — 2026-05-27 — Sharp SESSION.md write triggers

**Changed**
- **`CLAUDE.md` — sharper write-trigger criteria for SESSION.md.** Replaced the vague "after every meaningful action" rule with explicit per-section triggers:
  - `# Decisions`: write when chose X over Y, tried X and failed, discovered constraint, rejected obvious solution intentionally. Skip trivial implementation choices.
  - `# State`: update after each task chunk, on block/unblock, on branch change. Last action + next step only.
  - `# File map`: write for non-obvious source of truth, unexpected file role, non-obvious cross-file dependency. Skip self-evident files.
  - `.claude-docs/gotchas.md`: write immediately (no "запомни") when behavior contradicts intuition/docs, silent failure, platform quirk, "looks right but breaks" / "looks wrong but intentional".
  - Added **quick test**: *"Without this fact, would a future agent make a worse decision or repeat work?"* — yes → write; no → skip.

## v6.8.0 — 2026-05-26 — One-step updater, version tracking

**Added**
- **`bin/update.sh` — one-step updater.** Reads source path from `~/.claude/.memory-source`, does `git pull`, then re-runs `install.sh`. Usage: `~/.claude/bin/update.sh` (or `--dry-run` to preview). Clients no longer need to remember where they cloned the repo.
- **Version tracking in `install.sh`.** After every install/upgrade, writes two files to `$CLAUDE_HOME/`: `.memory-version` (current semver from CHANGELOG.md) and `.memory-source` (absolute path to the source repo). These power `update.sh` and doctor version display.
- **`doctor.sh` section 0 — Version.** Shows installed version and source path. Warns if source directory has moved or either file is missing (guides user to reinstall).

**Changed**
- `install.sh`: installs `bin/update.sh`; writes `.memory-version` + `.memory-source` to `$CLAUDE_HOME/` on every run.
- `bin/doctor.sh`: section numbering shifted (new section 0 prepended); all previous sections unchanged.

## v6.7.0 — 2026-05-26 — DRY slug lib, APPDATA guards, codemap fix, Windows docs, migrate regex

**Added**
- **`bin/lib/slug.sh` — shared slug library.** Extracts the Claude Code project slug + canonical-cwd computation into a single sourced library (`_compute_slug`). All three consumers (session-start, post-tool-use, doctor) now `source "${CLAUDE_HOME}/bin/lib/slug.sh"` instead of duplicating ~12 lines each. Eliminates the drift risk that caused the v6.5.0 slug bug. Installed to `$CLAUDE_HOME/bin/lib/slug.sh`.
- **Windows-specific section in INSTALL.md.** Documents: space-in-username PATH handling, Git Bash backslash-path normalization, PATH precedence (MSVC/MINGW/Cygwin vs Git Bash), MSYS2/Cygwin coexistence, and qmd-not-found diagnositcs.
- **`doctor.sh` PATH spaces check (section 5).** Warns when any PATH entry contains an embedded space — usually caused by a Windows username with spaces. Informational only (bash handles these correctly, but other tools may not).

**Fixed**
- **`${APPDATA:-}` / `${USERPROFILE:-}` guards.** `session-start.sh` runs with `set -u`; the qmd refresh subshell inherits it. On macOS/Linux `$APPDATA` and `$USERPROFILE` are unset, causing `_add_path "$APPDATA/npm"` to throw "unbound variable" and silently kill the qmd update. Fixed with `${APPDATA:-}` / `${USERPROFILE:-}` forms in both `session-start.sh` and `memstat.sh`.
- **`grep -F` for ctags symbol lookup in `codemap.sh`.** The two `grep "^${arg}\t"` calls used ERE, so symbol names containing `.`, `*`, `[`, or other regex metacharacters would produce wrong or empty results silently. Changed to `grep -F` (fixed-string) — ctags symbol names are never regex patterns.
- **`migrate.sh` HTML-comment regex hardened.** Previous regex required no leading whitespace before `<!--` and required a closing `-->` on the same line. Files with `  <!-- last_updated: ... -->` (leading indent) or without a proper closing `-->` were silently skipped. New patterns: allow `^[[:space:]]*\<!--` prefix, require only the ISO timestamp (trailing content ignored). Pattern stored in a variable to prevent bash parser from misinterpreting bare `<` as a comparison operator.

**Changed**
- `install.sh`: creates `$CLAUDE_HOME/bin/lib/` directory; installs `slug.sh`; `chmod +x` covers lib files.
- Inline slug computation removed from `session-start.sh`, `post-tool-use.sh`, `doctor.sh` — replaced with `source + _compute_slug` call.

## v6.6.0 — 2026-05-26 — Private exclusions, JSON validation, atomic qmd, settings merge, Obsidian status

**Added**
- **`.claude-private` glob exclusion.** If `$PWD/.claude-private` exists, SessionStart hook reads it as a list of glob patterns (one per line, `#` comments and blank lines ignored, CRLF-safe) and injects them into `additionalContext`. Model is instructed to treat matching paths as non-existent for all memory and capture purposes. Logged to `hook-trace.log`.
- **Obsidian `dataview` frontmatter for SESSION files.** `status: active` added to SESSION.md YAML template. Distillation step sets `status: done` on task wrap-up. Obsidian users get free session filtering: `dataview TABLE last_updated WHERE status = "active"`.
- **JSON output validation in `session-start.sh`.** After building the final JSON payload, validates it via python3 → node before emitting. On failure, emits a safe error JSON instead of potentially broken output, logs to `hook-trace.log`. Catches exotic Unicode or control characters not handled by `json_escape`.
- **`bin/merge-settings.sh` — programmatic settings merge.** Merges `settings.snippet.json` hooks into an existing `settings.json` without clobbering other keys. Parser chain: python3 → node → jq. python3/node: full dedup (won't add duplicate hook commands within an event already present). jq fallback: adds missing event keys, preserves existing. Validates merged JSON before writing. Backs up target as `.bak-<timestamp>`. `install.sh` now calls this automatically when hooks are missing — no more manual merge instructions.

**Fixed**
- **Race condition on `.qmd-last-refresh` marker.** Replaced non-atomic read→check→spawn pattern with `mkdir`-based atomic lock. Marker is written BEFORE the background qmd process is spawned, so a second parallel SessionStart hook sees the updated marker immediately and skips the duplicate update. No external dependencies (`mkdir` is POSIX atomic on all target filesystems).

**Changed**
- `install.sh`: installs `bin/merge-settings.sh`; calls it automatically when settings.json exists but hooks are missing (replaces manual merge instructions).
- IDEAS.md: 5 shipped items moved to "Already shipped". Removed "cavemem compression" (external dependency, anti-goal) and "file locking for SESSION.md" (proposed flock approach doesn't reliably prevent errors on all platforms) from backlog.

## v6.5.0 — 2026-05-25 — Hook strict mode, jq fallback, slug normalization, capture bugfixes

**Added**
- **`set -euo pipefail` + ERR traps in all three hooks.** Each hook now runs in strict mode. Any unguarded failure emits a fallback JSON/systemMessage instead of producing silence. ERR trap logs `rc` + line number to `hook-trace.log` and exits 0 — hook never blocks session start or tool execution. Intentionally-fallible commands wrapped with `|| true`.
- **`jq` fallback in PostToolUse JSON parser chain.** Parser chain extended to `python3 → node → jq → grep`. The `jq` path handles cases where only `jq` is installed (common on minimal server environments). `doctor.sh` section 6 now reports which parser is active and fails if none of the three robust parsers are available.
- **`doctor.sh` JSON parser section.** New section 6 checks for python3/node/jq; shows which parser PostToolUse will use (highest priority first); emits a `✗` critical failure if only grep fallback is available.

**Fixed**
- **Slug `_` → `-` normalization.** Claude Code converts underscores to hyphens in project slugs (e.g., `llm_projects` → `llm-projects`). All three slug computations (session-start, post-tool-use, doctor) were preserving underscores, causing SESSION.md lookups to silently miss the file on any path containing `_`. Added `slug="${slug//_/-}"` after each slug block.
- **PostToolUse null-byte separator stripped by bash.** Python3 and node paths used `\x00` (null byte) as field separator, but bash `$(...)` command substitutions silently strip null bytes — the `IFS=$'\x00' read` split never fired, leaving all three variables empty and causing the hook to exit without capturing anything. Replaced separator with `\x01` (SOH), which bash preserves.
- **Python3 heredoc vs pipe conflict.** `python3 - <<'PYEOF'` used a heredoc for the script, which consumed stdin — `json.load(sys.stdin)` always received an empty stream and threw `JSONDecodeError`. Switched to `python3 -c '...'` so the pipe delivers `$input` to `sys.stdin` correctly.

**Improved**
- Installed hooks updated to v6.5.0 (copy `hooks/*.sh` + `bin/doctor.sh` to `~/.claude/`).

## v6.4.0 — 2026-05-25 — PostToolUse capture, cwd auto-inject, portability fixes, doctor.sh

**Added**
- **PostToolUse selective auto-capture** (`hooks/post-tool-use.sh`). New hook captures three high-signal patterns and appends one-line entries to SESSION.md automatically: `Bash` with `git commit` (records commit message), `Write` to any `**/CLAUDE.md` (notes L1a update), `Write` to `**/.claude-docs/*.md` (notes L1b update). Everything else silently ignored — explicit-promotion philosophy preserved. JSON parsed via python3 → node → grep fallback chain; silent-fail on all errors.
- **SESSION.md `cwd:` auto-inject.** SessionStart hook now computes canonical cwd once and injects it into every `additionalContext` as a ready-to-paste value (`"Current project cwd: C:/dev/project"`). Eliminates the placeholder that the model previously had to fill from memory and often forgot.
- **`bin/doctor.sh` post-install health check.** Standalone script checking: hook files present + executable + syntax-clean; `settings.json` valid JSON + all three hooks registered; `IDENTITY.md` present and not placeholder; current-project `SESSION.md` has `last_updated` + `cwd` fields; optional tools (qmd, ctags, rg, node, python3). Outputs ✓/✗/? per check; exits 1 on any critical failure (CI-friendly).

**Fixed**
- **BSD `date` portability.** Staleness check used `date -d` (GNU-only). On macOS/BSD it silently returned epoch 0 — staleness detection never fired. Now tries `date -d` first, falls back to `date -j -f "%Y-%m-%dT%H:%M:%SZ"` for BSD.
- **CRLF in privacy redaction.** `sed -i` pattern could silently miss `<private>` blocks if SESSION.md had Windows `\r\n` line endings. Replaced with portable pipeline: `tr -d '\r' | sed 's/...'//g' > tmp && mv` — single pass, no `-i` dialect issues, handles CRLF on all platforms.

**Improved**
- `install.sh` now installs `post-tool-use.sh`, `memstat.md`, `bin/doctor.sh`. Missing-hooks check covers PostToolUse. Pre-flight validation added at end of install: JSON validity of `settings.json`, `bash -n` syntax check for all hooks, executable bit check.
- `settings.snippet.json` updated with PostToolUse hook registration.
- IDEAS.md: 7 newly shipped items marked `[x]`.

## v6.3.0 — 2026-05-25 — Privacy redaction, CWD mismatch, compression toggle + bugfixes

**Added**
- **Privacy redaction via `<private>` tags.** SessionStart hook strips `<private>...</private>` blocks from SESSION.md in-place before injecting context (backup preserved at `SESSION.md.bak`). PreCompact instructs model to strip tags before writing. Defense-in-depth: tagged content removed at session boundary even if model wrote it.
- **CWD mismatch detection.** SessionStart reads `cwd:` from SESSION.md YAML frontmatter. If it doesn't match current project path, injects a hard reset warning — prevents agent from silently continuing the wrong project's task after switching directories. SESSION.md template updated to include `cwd:` field.
- **SESSION.md compression protocol.** PreCompact instructs model to write SESSION.md prose in compressed caveman notation (drop articles/filler, fragments OK, code/paths exact). Reduces context-window cost on every SESSION.md reload.
- **Compression on/off toggle.** Flag file `~/.claude/.session-compress-disabled` (or env var `CLAUDE_SESSION_COMPRESS=0`) disables compression. Both hooks read flag on every fire — no restart needed. Documented in CLAUDE.md Rule 4.
- **IDEAS.md backlog.** Prioritised enhancement backlog: 5 new sections covering hook reliability, concurrency, install/uninstall, SESSION.md lifecycle, and testing/CI. 13 new items with priority×effort ratings and implementation notes.

**Fixed**
- **Hardcoded user paths removed.** `hooks/session-start.sh` had `/c/Users/greev/.claude/` hardcoded in two places (debug log line + SESSION.md path). Broke the system for any user other than the original author. Both replaced with `$CLAUDE_HOME`. `CLAUDE_HOME` assignment moved before first use.
- **Hardcoded paths in command files.** `commands/codemap.md`, `commands/memstat.md`: `/c/Users/greev/.claude/bin/` → `~/.claude/bin/`. `commands/recall.md`, `commands/memory.md`: hardcoded npm PATH examples → `$APPDATA/npm` with explanatory note.

## v6.2.3 — 2026-05-21 — memstat process detection actually works

**Fixed**
- **`/memstat` couldn't see running processes** (always showed "idle" even while `node`/qmd was pegging CPU). Root cause: the PowerShell command was passed inside a bash single-quoted string containing `''node.exe''` — the embedded `''` silently terminates bash quoting, so PowerShell received a mangled command and returned nothing. Rewrote the process query using bash double-quotes with `\"`/`\$` escaping.
- **`running -1s`** — `Get-CimInstance` returns `CreationDate` already as a `[DateTime]`; the code called `ToDateTime()` (a WMI/`Get-WmiObject` idiom) which threw, yielding age -1. Now uses `CreationDate` directly.
- **False "possible stall" warning during model load.** The stall heuristic (>2min running, 0 vector delta) fired during the normal ~30-60s model-load / batch-compute phase when vectors haven't committed yet. Added a CPU-time delta as a second signal: if vectors aren't moving but the process is burning CPU → "working (vectors commit per-batch), not hung"; only flags a real stall when vectors are static AND CPU is idle.

## v6.2.2 — 2026-05-21 — Portable PATH fix (Git Bash) + memstat hardening

**Fixed**
- **PATH normalization on Git Bash.** The portable `_add_path` helper now converts Windows-style paths (`C:\Users\...\npm` with backslashes from `$APPDATA`/`$USERPROFILE`) to unix form before prepending to PATH. Previously these poisoned PATH and `qmd` resolved to a mangled, non-executable path — meaning the SessionStart hook's background `qmd update` and `/memstat`'s status query silently did nothing on a fresh install. Switched from empty `$USER` to `$USERPROFILE`. Affects `hooks/session-start.sh` and `bin/memstat.sh`.
- **`/memstat` honesty when qmd status is unavailable.** Retries once (transient SQLite lock during concurrent `qmd update`), and if still no data, HEALTH reports "index status unknown" instead of falsely claiming "fully embedded".

## v6.2.1 — 2026-05-21 — Hook does FTS-only refresh (no surprise CPU)

**Changed**
- SessionStart hook now runs **only** the lightweight `qmd update` (BM25/FTS rebuild, seconds) in its 6h-debounced background refresh. The heavy `qmd embed` (CPU-bound GGUF vector generation, minutes-long) is **no longer auto-run** — it's manual via `/memory refresh`.
- Rationale: on machines without working GPU acceleration, the background embed pegged CPU for ~30min and surprised users. BM25 (the `/recall` default) doesn't need vectors, so FTS-only auto-refresh keeps search fresh without the CPU cost. Run `/memory refresh` (or `/recall --hybrid` workflows) when you actually want fresh vectors.
- Removed `QMD_LLAMA_GPU` export from the hook (no longer loads models in background).

## v6.2.0 — 2026-05-21 — Memory dispatcher

**Added**
- `bin/memstat.sh` + `/memstat` slash command — a "task manager" for the memory subsystem. Shows:
  - **Processes** — running qmd/ctags processes with PID, RAM, runtime (yellow flag if >30min)
  - **Index** — vectors embedded vs pending, % coverage, per-collection file counts
  - **Refresh** — when the SessionStart hook last refreshed, whether next auto-refresh is due (6h debounce)
  - **Activity** — last line + age of each qmd log
  - **Health** — if an embed is running, samples vector delta over 3s to confirm forward progress; flags possible stall (>2min running, 0 delta) with the PID to kill
  - `--watch [seconds]` for a live auto-refreshing view
- Answers the recurring "why is node.exe eating my CPU and is it stuck?" question. The CPU spikes are the background `qmd embed` launched by the SessionStart hook (6h debounce); on machines without working GPU acceleration it runs CPU-only (~1-3s/chunk, ~30min full re-embed).

## v6.1.0 — 2026-05-19 — Migration tools

**Added**
- `migrate.sh` — mechanical migration of HTML-comment `<!-- last_updated: ISO -->` markers to YAML frontmatter (with `tags:` derived from filename). Auto-detects pre-2026-04-30 legacy directories (`MEMORY.md`, `feedback_*.md`, `project_*.md`, `reference_*.md`) and prints guidance for the AI-synthesis step. `--dry-run` flag for safe preview. Writes `.bak-<timestamp>` for every touched file.
- `commands/migrate-legacy-memory.md` — Claude Code slash command. Spawns an Agent that reads each legacy project directory, synthesizes a single new-format `project.md` per project preserving verbatim technical specificity (reviewer quotes, exact paths, error messages, port/version numbers), and moves originals into `<slug>/memory/legacy/`. Skips projects that already have new-format `project.md`. Non-destructive: only `mv`, never `rm`.
- INSTALL.md: new "Migrating older data" section explaining the two-step path (mechanical → AI synthesis) and when to use each.

## v6.0.1 — 2026-05-19 — Upgrade-safe installer

**Added**
- `install.sh` — idempotent installer. Detects first-install vs upgrade, backs up changed files with `.bak-<timestamp>`, **never overwrites** your `IDENTITY.md` (L0 user data) or `projects/` tree (L1-fallback + L2 sessions). `--dry-run` flag previews changes without writing.
- INSTALL.md: new "Install (or upgrade)" section explaining behaviour per file/dir, rollback recipe, format-compat notes for older installs (HTML-comment `last_updated` markers still work).

**Fixed**
- Manual install path in INSTALL.md guards `cp memory/IDENTITY.md` with a `[ ! -f ... ]` check to prevent silent L0 data loss on upgrade.

**Changed**
- `/recall` default mode flipped to BM25 (`qmd search`), with `--hybrid` flag opt-in for full BM25+vector+rerank. Hybrid requires the full GGUF model bundle loaded and a complete embed index — BM25 covers ~80% of recall queries with zero loading cost.

## v6.0.0 — 2026-05-19 — Initial public release

First public release. Hand-curated, in-repo memory protocol with hybrid retrieval and on-demand symbol map. 100% local. MIT.

## v6 — 2026-05-19 — Retrieval tools (pre-release development log)

**Added**
- `/recall <query>` slash command — hybrid search (BM25 + GGUF embeddings + LLM rerank) over all memory files, backed by [qmd](https://github.com/tobi/qmd)
- `/codemap def|callers|callees|outline <symbol>` — on-demand symbol map for the current repo via universal-ctags + ripgrep; cache in `<repo>/.codemap.tags`
- `/memory status | auto on|off | refresh` — protocol controls and optional auto-capture toggle (off by default)
- `bin/codemap.sh` — portable ctags+rg wrapper, self-locates binaries on Windows (winget paths) / macOS (brew) / Linux (apt)
- SessionStart hook now auto-refreshes the qmd retrieval index in background, debounced 6h

**Changed**
- Knowledge store organization: flat-only rule softened to allow shallow (1-level) folder grouping when a category has 5+ peer files — `protocols/`, `formats/`, `handoffs/` OK; deeper nesting still forbidden. Obsidian tags continue to do the primary categorization.
- Karpathy "LLM-OS" framing added to CLAUDE.md (context = RAM, file system = disk, tools = peripherals)

## v5 — 2026-05-13 — Knowledge store conventions

**Added**
- "Knowledge store organization" section in CLAUDE.md codifying flat + tags + filename-prefix conventions (`protocol_<name>.md`, `format_<name>.md`, `handoff_<topic>.md`)
- `index.md` as the routing source for multi-file knowledge stores
- `raw/` subdirectory convention for non-markdown data dumps
- Rule for when to split single `project.md` into multi-file (>200 lines, ≥3 distinct categories, or cross-file refs needed)

## v4 — 2026-05-07 — In-repo L1 pivot

**Changed**
- L1 split into **L1a** (`<repo>/CLAUDE.md`, thin entry, git-tracked, auto-loaded) + **L1b** (`<repo>/.claude-docs/*.md`, thick lazy-loaded, git-tracked)
- Old account-local `project.md` renamed to **L1-fallback** for repos where in-repo isn't appropriate
- Adopted "midnight server agent test" as the explicit decision rule for layer placement
- Added templates: `templates/repo/CLAUDE.md`, `templates/repo/.claude-docs/{index,gotchas,architecture,conventions}.md`

## v3 — 2026-05-07 — Obsidian compatibility

**Changed**
- HTML-comment `<!-- last_updated: ... -->` migrated to YAML frontmatter with `tags: [memory/l0|l1|l2|repo, ...]`
- StalenessHook regex stays compatible with both formats — no migration needed for existing files

## v2 — 2026-05-05 — Workflow patterns + L1 templates

**Added**
- Workflow patterns: pre-compact checkpoint, post-compact recovery, multi-session handoff, distillation on task wrap-up, bootstrapping in-repo L1
- L1-fallback template with structured sections (Repository, Layout, Stack, Endpoints, Conventions, Known gotchas, Roadmap)
- Rule: "L1 is where grabli live" — non-obvious footguns are the highest-leverage memory

## v1 — 2026-05-05 — Staleness detection + portability

**Added**
- `bin/session-start.sh` staleness check: if `SESSION.md` is >24h old, the hook injects a STALENESS WARNING so the model surfaces it to the user before silently continuing
- Portable hooks (use `$HOME`/`$CLAUDE_HOME` instead of hardcoded paths)
- `templates/` directory with separate `IDENTITY.md`, `project.md` templates for new installs
- Friend-shareable zip packaging
