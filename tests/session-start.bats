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
