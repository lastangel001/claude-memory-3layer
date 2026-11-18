#!/usr/bin/env bats
# Tests for hooks/session-start.sh — staleness, CWD mismatch, privacy
# redaction (incl. multiline), compression flag, JSON validity.

load helpers

setup() {
  setup_claude_home
  WORK_DIR="$(mktemp -d)"
  cd "$WORK_DIR"
}

teardown() {
  cd /
  rm -rf "$WORK_DIR"
  teardown_claude_home
}

run_hook() {
  run bash "$REPO_ROOT/hooks/session-start.sh"
}

json_is_valid() {
  # Use the repo's own validator so the test picks a WORKING parser (dodges the
  # Windows Store python3 stub — presence-only checks pick it and it exits 49).
  source "$REPO_ROOT/bin/lib/validate-json.sh"
  printf '%s' "$1" | _validate_json_stream
}

@test "emits valid JSON with protocol reminder (no SESSION.md)" {
  run_hook
  [ "$status" -eq 0 ]
  json_is_valid "$output"
  [[ "$output" == *"MEMORY PROTOCOL ACTIVE"* ]]
}

@test "staleness warning fires when last_updated >24h" {
  make_session "$PWD" <<EOF
---
last_updated: $(iso_ago $((3*86400)))
cwd: $PWD
---
# Goal
old task
EOF
  run_hook
  [ "$status" -eq 0 ]
  [[ "$output" == *"STALENESS WARNING"* ]]
}

@test "no staleness warning when last_updated is fresh" {
  make_session "$PWD" <<EOF
---
last_updated: $(iso_ago 60)
cwd: $PWD
---
# Goal
current task
EOF
  run_hook
  [ "$status" -eq 0 ]
  [[ "$output" != *"STALENESS WARNING"* ]]
}

@test "missing last_updated marker produces suspicion note" {
  make_session "$PWD" <<EOF
# Goal
no frontmatter at all
EOF
  run_hook
  [ "$status" -eq 0 ]
  [[ "$output" == *"no last_updated marker"* ]]
}

@test "cwd mismatch warning when session belongs to another project" {
  make_session "$PWD" <<EOF
---
last_updated: $(iso_ago 60)
cwd: C:/somewhere/else
---
# Goal
other project task
EOF
  run_hook
  [ "$status" -eq 0 ]
  [[ "$output" == *"CWD MISMATCH"* ]]
}

@test "cwd mismatch detected in metadata-nested frontmatter (indexer rewrite, regression v6.15.0)" {
  make_session "$PWD" <<EOF
---
name: ""
metadata:
  node_type: memory
  last_updated: $(iso_ago 60)
  cwd: C:/somewhere/else
---
# Goal
other project task
EOF
  run_hook
  [ "$status" -eq 0 ]
  [[ "$output" == *"CWD MISMATCH"* ]]
}

@test "privacy: single-line <private> block stripped from SESSION.md" {
  make_session "$PWD" <<EOF
---
last_updated: $(iso_ago 60)
cwd: $PWD
---
key was <private>sk-secret-123</private>, stored in env.
EOF
  run_hook
  [ "$status" -eq 0 ]
  ! grep -q "sk-secret-123" "$SESSION_FILE"
  grep -q "stored in env" "$SESSION_FILE"
}

@test "privacy: MULTILINE <private> block stripped (regression v6.15.0)" {
  make_session "$PWD" <<EOF
---
last_updated: $(iso_ago 60)
cwd: $PWD
---
before
<private>secret line A
secret line B</private>
after
EOF
  run_hook
  [ "$status" -eq 0 ]
  ! grep -q "secret line A" "$SESSION_FILE"
  ! grep -q "secret line B" "$SESSION_FILE"
  grep -q "before" "$SESSION_FILE"
  grep -q "after" "$SESSION_FILE"
}

@test "privacy: two <private> blocks on one line stripped non-greedily" {
  make_session "$PWD" <<EOF
---
last_updated: $(iso_ago 60)
cwd: $PWD
---
a <private>one</private> keep <private>two</private> b
EOF
  run_hook
  [ "$status" -eq 0 ]
  ! grep -q "one" "$SESSION_FILE"
  ! grep -q "two" "$SESSION_FILE"
  grep -q "keep" "$SESSION_FILE"
}

@test "compression enabled by default" {
  run_hook
  [ "$status" -eq 0 ]
  [[ "$output" == *"SESSION COMPRESSION: enabled"* ]]
  [[ "$output" == *"agent-only memory prose"* ]]
}

@test "compression disabled via env var" {
  CLAUDE_SESSION_COMPRESS=0 run bash "$REPO_ROOT/hooks/session-start.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SESSION COMPRESSION: disabled"* ]]
}

@test "compression disabled via flag file" {
  touch "$TEST_CLAUDE_HOME/.session-compress-disabled"
  run_hook
  [ "$status" -eq 0 ]
  [[ "$output" == *"SESSION COMPRESSION: disabled"* ]]
}

@test ".claude-private globs injected into context" {
  printf '# comment\nsecrets/**\n.env.local\n' > "$WORK_DIR/.claude-private"
  run_hook
  [ "$status" -eq 0 ]
  [[ "$output" == *"PRIVATE PATH EXCLUSIONS"* ]]
  [[ "$output" == *"secrets/**"* ]]
}

@test "staleness fires on metadata-nested last_updated (indexer format, matrix)" {
  make_session "$PWD" <<EOF
---
name: ""
metadata:
  node_type: memory
  last_updated: $(iso_ago $((3*86400)))
  cwd: $PWD
---
# Goal
old task
EOF
  run_hook
  [ "$status" -eq 0 ]
  [[ "$output" == *"STALENESS WARNING"* ]]
}

@test "SESSION.md size warning fires above 4KB" {
  {
    printf -- '---\nlast_updated: %s\ncwd: %s\n---\n' "$(iso_ago 60)" "$PWD"
    head -c 5000 /dev/zero | tr '\0' 'x'
  } | make_session "$PWD"
  run_hook
  [ "$status" -eq 0 ]
  [[ "$output" == *"SESSION.md SIZE"* ]]
}

@test "no size warning for a small SESSION.md" {
  make_session "$PWD" <<EOF
---
last_updated: $(iso_ago 60)
cwd: $PWD
---
# Goal
tiny
EOF
  run_hook
  [[ "$output" != *"SESSION.md SIZE"* ]]
}

@test "missing last_updated note is a strong imperative" {
  make_session "$PWD" <<EOF
# Goal
no frontmatter
EOF
  run_hook
  [[ "$output" == *"REQUIRED FIRST ACTION"* ]]
}

@test "version-drift nudge fires when source CHANGELOG is newer" {
  printf 'v1.0.0\n' > "$TEST_CLAUDE_HOME/.memory-version"
  fake_src="$(mktemp -d)"
  printf '## v9.9.9 — test\n' > "$fake_src/CHANGELOG.md"
  printf '%s\n' "$fake_src" > "$TEST_CLAUDE_HOME/.memory-source"
  run_hook
  [ "$status" -eq 0 ]
  [[ "$output" == *"UPDATE AVAILABLE"* ]]
  [[ "$output" == *"v9.9.9"* ]]
  rm -rf "$fake_src"
}

@test "version-drift nudge does not fire backwards (installed newer)" {
  printf 'v9.9.9\n' > "$TEST_CLAUDE_HOME/.memory-version"
  fake_src="$(mktemp -d)"
  printf '## v1.0.0 — test\n' > "$fake_src/CHANGELOG.md"
  printf '%s\n' "$fake_src" > "$TEST_CLAUDE_HOME/.memory-source"
  run_hook
  [ "$status" -eq 0 ]
  [[ "$output" != *"UPDATE AVAILABLE"* ]]
  rm -rf "$fake_src"
}

@test "version-drift check is debounced (marker suppresses second run)" {
  printf 'v1.0.0\n' > "$TEST_CLAUDE_HOME/.memory-version"
  fake_src="$(mktemp -d)"
  printf '## v9.9.9 — test\n' > "$fake_src/CHANGELOG.md"
  printf '%s\n' "$fake_src" > "$TEST_CLAUDE_HOME/.memory-source"
  run_hook
  [[ "$output" == *"UPDATE AVAILABLE"* ]]
  # Second run within the week: marker is fresh, no repeat nudge.
  run_hook
  [[ "$output" != *"UPDATE AVAILABLE"* ]]
  rm -rf "$fake_src"
}

@test "hook-trace.log rotation caps the log at 2000 lines" {
  seq 1 5000 | sed 's/^/line /' > "$TEST_CLAUDE_HOME/debug/hook-trace.log"
  run_hook
  [ "$status" -eq 0 ]
  # After rotation the log holds ~2000 lines (+ this run's own append lines).
  [ "$(wc -l < "$TEST_CLAUDE_HOME/debug/hook-trace.log")" -lt 2100 ]
}

@test "closed session (status: done) does not raise the staleness warning" {
  make_session "$PWD" <<EOF
---
last_updated: $(iso_ago $((90*86400)))
cwd: $PWD
status: done
---
# Goal
(none — last task: shipped)
EOF
  run_hook
  [ "$status" -eq 0 ]
  [[ "$output" != *"STALENESS WARNING"* ]]
}

@test "closed session in metadata-nested frontmatter is not stale either (matrix)" {
  make_session "$PWD" <<EOF
---
name: ""
metadata:
  node_type: memory
  last_updated: $(iso_ago $((90*86400)))
  cwd: $PWD
  status: done
---
# Goal
(none)
EOF
  run_hook
  [ "$status" -eq 0 ]
  [[ "$output" != *"STALENESS WARNING"* ]]
}

@test "active old session still raises the staleness warning" {
  make_session "$PWD" <<EOF
---
last_updated: $(iso_ago $((3*86400)))
cwd: $PWD
status: active
---
# Goal
old task
EOF
  run_hook
  [[ "$output" == *"STALENESS WARNING"* ]]
}

@test "context carries absolute memory paths and no derive-the-slug instruction" {
  run_hook
  [ "$status" -eq 0 ]
  [[ "$output" == *"/memory/SESSION.md"* ]]
  [[ "$output" == *"/memory/project.md"* ]]
  [[ "$output" == *"do NOT derive a project slug"* ]]
  [[ "$output" != *"Derive project slug from cwd"* ]]
}

@test "transcript_path on stdin decides the project directory" {
  d="$TEST_CLAUDE_HOME/projects/C--from-transcript/memory"
  mkdir -p "$d"
  cat > "$d/SESSION.md" <<EOF
---
last_updated: $(iso_ago $((3*86400)))
cwd: $PWD
---
# Goal
task of the transcript project
EOF
  printf '%s' '{"session_id":"s","transcript_path":"C:\\Users\\u\\.claude\\projects\\C--from-transcript\\abc.jsonl","source":"startup"}' > "$WORK_DIR/.in.json"
  run bash -c "bash '$REPO_ROOT/hooks/session-start.sh' < '$WORK_DIR/.in.json'"
  [ "$status" -eq 0 ]
  json_is_valid "$output"
  [[ "$output" == *"C--from-transcript/memory/SESSION.md"* ]]
  [[ "$output" == *"STALENESS WARNING"* ]]
}

@test "legacy slug directory is used and announced when only it holds memory" {
  source "$REPO_ROOT/bin/lib/slug.sh"
  legacy="$(_legacy_slug "$PWD")"
  _compute_slug "$PWD"
  if [[ "$legacy" == "$slug" ]]; then skip "cwd has no character the formulas disagree on"; fi
  mkdir -p "$TEST_CLAUDE_HOME/projects/$legacy/memory"
  printf -- '---\nlast_updated: %s\ncwd: %s\n---\n# Goal\nx\n' "$(iso_ago 60)" "$PWD" \
    > "$TEST_CLAUDE_HOME/projects/$legacy/memory/SESSION.md"
  run_hook
  [ "$status" -eq 0 ]
  [[ "$output" == *"LEGACY MEMORY DIR"* ]]
  [[ "$output" == *"$legacy/memory/SESSION.md"* ]]
  grep -q '"outcome":"degraded","note":"slug=legacy legacy-slug-dir"' "$TEST_CLAUDE_HOME/debug/hook-diag.jsonl"
}

@test "a clean run is journaled as ok in hook-diag.jsonl" {
  run_hook
  [ "$status" -eq 0 ]
  grep -q '"hook":"SessionStart","outcome":"ok","note":"slug=formula"' "$TEST_CLAUDE_HOME/debug/hook-diag.jsonl"
}

# --- post-compaction re-injection (source = compact) ---

run_hook_source() {  # $1 = source value
  printf '{"session_id":"s","hook_event_name":"SessionStart","source":"%s"}' "$1" > "$WORK_DIR/.in.json"
  run bash -c "bash '$REPO_ROOT/hooks/session-start.sh' < '$WORK_DIR/.in.json'"
}

small_session() {
  make_session "$PWD" <<EOF
---
last_updated: $(iso_ago 60)
cwd: $PWD
status: active
---
# Goal
ship the retry window fix

# State
- next: run the integration suite
EOF
}

@test "compact: SESSION.md is re-injected inside a memory-record frame" {
  small_session
  run_hook_source compact
  [ "$status" -eq 0 ]
  json_is_valid "$output"
  [[ "$output" == *"<memory-record"* ]]
  [[ "$output" == *"RECORD of work done before the context was compacted"* ]]
  [[ "$output" == *"ship the retry window fix"* ]]
  [[ "$output" == *"next: run the integration suite"* ]]
}

@test "compact: the PreCompact snapshot rides along" {
  small_session
  cat > "$(dirname "$SESSION_FILE")/compact-snapshot.md" <<'EOF'
---
tags: [memory/l2, compact-snapshot]
---
# Git position at compaction
- branch: feature/x

# Last user turns (verbatim, oldest first)
1. please keep the 250 ms backoff
EOF
  run_hook_source compact
  json_is_valid "$output"
  [[ "$output" == *"Pre-compaction snapshot"* ]]
  [[ "$output" == *"please keep the 250 ms backoff"* ]]
  [[ "$output" == *"branch: feature/x"* ]]
  # Frontmatter of the snapshot file is not injected.
  [[ "$output" != *"compact-snapshot]"* ]]
}

@test "startup and resume do not inline SESSION.md" {
  small_session
  run_hook_source startup
  [[ "$output" != *"<memory-record"* ]]
  [[ "$output" != *"ship the retry window fix"* ]]
  run_hook_source resume
  [[ "$output" != *"<memory-record"* ]]
}

@test "compact: an oversize SESSION.md is not inlined — the model is told to read it" {
  {
    printf -- '---\nlast_updated: %s\ncwd: %s\n---\n# Goal\nUNIQUE-GOAL-MARKER\n' "$(iso_ago 60)" "$PWD"
    head -c 7000 /dev/zero | tr '\0' 'x'
  } | make_session "$PWD"
  run_hook_source compact
  json_is_valid "$output"
  [[ "$output" == *"too large to inline"* ]]
  [[ "$output" == *"READ IT NOW"* ]]
  [[ "$output" != *"UNIQUE-GOAL-MARKER"* ]]
}

# Near-limit SESSION.md + a snapshot long enough to be truncated at its budget.
big_session_and_snapshot() {
  {
    printf -- '---\nlast_updated: %s\ncwd: %s\n---\n# Goal\nCAP-MARKER\n' "$(iso_ago 60)" "$PWD"
    head -c 4700 /dev/zero | tr '\0' 'x'
  } | make_session "$PWD"
  # make_session ran in a pipeline subshell — its SESSION_FILE did not survive.
  SESSION_FILE="$TEST_CLAUDE_HOME/projects/$(slug_for "$PWD")/memory/SESSION.md"
  {
    printf '# Git position at compaction\n- branch: b\n\n# Last user turns (verbatim, oldest first)\n'
    for i in $(seq 1 60); do printf '%d. %s\n' "$i" "SNAP-TURN padding padding padding padding padding padding"; done
  } > "$(dirname "$SESSION_FILE")/compact-snapshot.md"
}

# .claude-private patterns enlarge the fixed part of the context by ~$1 chars.
bloat_base() {
  local n=$(( $1 / 40 )) i
  for i in $(seq 1 "$n"); do printf 'private/path/number/%04d/with/padding/**\n' "$i"; done > "$WORK_DIR/.claude-private"
}

@test "compact: maximum-size SESSION.md and snapshot both fit by default" {
  big_session_and_snapshot
  run_hook_source compact
  [ "$status" -eq 0 ]
  json_is_valid "$output"
  [[ "$output" == *"CAP-MARKER"* ]]
  [[ "$output" == *"SNAP-TURN"* ]]
  [[ "$output" == *"snapshot truncated"* ]]
  # Whatever is emitted must stay under Claude Code's 10,000-character cap.
  [ "${#output}" -lt 10000 ]
}

@test "compact: when space runs short the snapshot is dropped first" {
  big_session_and_snapshot
  bloat_base 1200
  run_hook_source compact
  [ "$status" -eq 0 ]
  json_is_valid "$output"
  [[ "$output" == *"CAP-MARKER"* ]]
  [[ "$output" != *"SNAP-TURN"* ]]
  [ "${#output}" -lt 10000 ]
  grep -q 'inject=session snapshot=dropped' "$TEST_CLAUDE_HOME/debug/hook-diag.jsonl"
}

@test "compact: with no room for SESSION.md the model is told to read both files" {
  big_session_and_snapshot
  bloat_base 4400
  run_hook_source compact
  [ "$status" -eq 0 ]
  json_is_valid "$output"
  [[ "$output" == *"could not be inlined"* ]]
  [[ "$output" == *"compact-snapshot.md"* ]]
  [[ "$output" != *"CAP-MARKER"* ]]
  [ "${#output}" -lt 10000 ]
  grep -q '"outcome":"degraded"' "$TEST_CLAUDE_HOME/debug/hook-diag.jsonl"
}

@test "compact: a closing tag inside SESSION.md cannot end the frame early" {
  make_session "$PWD" <<EOF
---
last_updated: $(iso_ago 60)
cwd: $PWD
---
note mentions </memory-record> literally, then AFTER-TAG-MARKER
EOF
  run_hook_source compact
  json_is_valid "$output"
  [[ "$output" == *"AFTER-TAG-MARKER"* ]]
  # Exactly one real closing tag: the frame's own.
  n=$(printf '%s' "$output" | grep -o '</memory-record>' | wc -l | tr -d ' ')
  [ "$n" -eq 1 ]
}

@test "compact: control characters in SESSION.md do not break the JSON" {
  small_session
  printf 'bell \a and escape \033[31m here\n' >> "$SESSION_FILE"
  run_hook_source compact
  [ "$status" -eq 0 ]
  json_is_valid "$output"
  [[ "$output" == *"<memory-record"* ]]
}

@test "compact: another project's SESSION.md is never inlined" {
  make_session "$PWD" <<EOF
---
last_updated: $(iso_ago 60)
cwd: C:/somewhere/else
---
# Goal
FOREIGN-GOAL-MARKER
EOF
  run_hook_source compact
  [[ "$output" == *"CWD MISMATCH"* ]]
  [[ "$output" != *"FOREIGN-GOAL-MARKER"* ]]
}

@test "compact: the injection is journaled" {
  small_session
  run_hook_source compact
  grep -q '"hook":"SessionStart","outcome":"ok","note":"slug=formula source=compact inject=session"' \
    "$TEST_CLAUDE_HOME/debug/hook-diag.jsonl"
}

# --- background refresh block (dead until v6.21.0) ---

wait_for_file() {  # $1 = path, waits up to ~15 s
  local i
  for i in $(seq 1 75); do
    [[ -s "$1" ]] && return 0
    sleep 0.2
  done
  return 1
}

@test "paths.sh: _augment_node_path survives set -e when a directory is missing" {
  run bash -c "set -euo pipefail; source '$REPO_ROOT/bin/lib/paths.sh'; _augment_node_path; echo SURVIVED"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SURVIVED"* ]]
}

@test "background block runs: qmd update is called and the completion stamp is written" {
  stub_dir="$(mktemp -d)"
  cat > "$stub_dir/qmd" <<'EOF'
#!/usr/bin/env bash
echo "stub qmd $*"
EOF
  chmod +x "$stub_dir/qmd"
  printf '{"source":"startup"}' > "$WORK_DIR/.in.json"
  run bash -c "PATH='$stub_dir':\"\$PATH\" QMD_FORCE_REFRESH=1 bash '$REPO_ROOT/hooks/session-start.sh' < '$WORK_DIR/.in.json'"
  [ "$status" -eq 0 ]
  # The hook's own output is still clean JSON — nothing from the background leaks in.
  json_is_valid "$output"
  wait_for_file "$TEST_CLAUDE_HOME/.qmd-last-refresh-done"
  grep -q '"hook":"SessionStartBg","outcome":"ok"' "$TEST_CLAUDE_HOME/debug/hook-diag.jsonl"
  rm -rf "$stub_dir"
}

@test "background block is skipped inside the 6h debounce window" {
  date +%s > "$TEST_CLAUDE_HOME/.qmd-last-refresh"
  run_hook
  [ "$status" -eq 0 ]
  sleep 1
  [ ! -f "$TEST_CLAUDE_HOME/.qmd-last-refresh-done" ]
}

# --- git worktrees: project.md is shared, SESSION.md is per worktree ---

@test "linked worktree: project.md points at the main checkout, SESSION.md stays local" {
  main="$WORK_DIR/main"
  mkdir -p "$main" && cd "$main"
  git init -q . 2>/dev/null
  printf 'x\n' > f.txt && git add f.txt
  git -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false commit -q -m init
  git worktree add -q "$WORK_DIR/wt" -b feature-x 2>/dev/null
  cd "$WORK_DIR/wt"
  source "$REPO_ROOT/bin/lib/slug.sh"
  # Expected slug comes from the path as GIT reports it: under Git Bash the
  # mktemp path (/tmp/…) is an alias of a Windows directory, and the hook
  # derives the main checkout from git, exactly as it would in a real session.
  top="$(git -C "$main" rev-parse --show-toplevel)"
  if [[ "$top" =~ ^([A-Za-z]):/(.*)$ ]]; then top="/${BASH_REMATCH[1],,}/${BASH_REMATCH[2]}"; fi
  _compute_slug "$top";             main_slug="$slug"
  _compute_slug "$WORK_DIR/wt";     wt_slug="$slug"
  run_hook
  [ "$status" -eq 0 ]
  json_is_valid "$output"
  [[ "$output" == *"GIT WORKTREE"* ]]
  [[ "$output" == *"$main_slug/memory/project.md"* ]]
  [[ "$output" == *"$wt_slug/memory/SESSION.md"* ]]
  cd "$main" && git worktree remove --force "$WORK_DIR/wt" 2>/dev/null || true
}

@test "main checkout: no worktree note, project.md is its own" {
  git init -q . 2>/dev/null
  run_hook
  [ "$status" -eq 0 ]
  [[ "$output" != *"GIT WORKTREE"* ]]
}

@test "output JSON stays valid with SESSION.md containing quotes and backslashes" {
  make_session "$PWD" <<'EOF'
---
last_updated: 2020-01-01T00:00:00Z
cwd: C:/somewhere/else
---
path "C:\temp\x" and "quoted" text
EOF
  run_hook
  [ "$status" -eq 0 ]
  json_is_valid "$output"
}
