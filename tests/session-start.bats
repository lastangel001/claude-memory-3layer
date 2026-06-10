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
  if command -v python3 >/dev/null 2>&1; then
    printf '%s' "$1" | python3 -c 'import sys,json; json.load(sys.stdin)'
  else
    printf '%s' "$1" | node -e "JSON.parse(require('fs').readFileSync(0,'utf8'))"
  fi
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
