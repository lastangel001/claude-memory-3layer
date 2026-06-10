#!/usr/bin/env bats
# Tests for hooks/post-tool-use.sh — selective auto-capture patterns.

load helpers

setup() {
  setup_claude_home
  WORK_DIR="$(mktemp -d)"
  cd "$WORK_DIR"
  make_session "$PWD" <<EOF
---
last_updated: $(iso_ago 60)
cwd: $PWD
---
# Recent turns
EOF
}

teardown() {
  cd /
  rm -rf "$WORK_DIR"
  teardown_claude_home
}

run_hook_with() {
  run bash -c "printf '%s' '$1' | bash '$REPO_ROOT/hooks/post-tool-use.sh'"
}

@test "git commit via Bash is captured" {
  run_hook_with '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"fix: test message\""}}'
  [ "$status" -eq 0 ]
  grep -q "\[auto\] git commit" "$SESSION_FILE"
}

@test "Write to repo CLAUDE.md captured as L1a" {
  run_hook_with '{"tool_name":"Write","tool_input":{"file_path":"/c/dev/proj/CLAUDE.md"}}'
  [ "$status" -eq 0 ]
  grep -q "\[auto\] L1a updated" "$SESSION_FILE"
}

@test "bare CLAUDE.md path captured only for Write (precedence regression v6.15.0)" {
  run_hook_with '{"tool_name":"Bash","tool_input":{"file_path":"CLAUDE.md","command":"cat CLAUDE.md"}}'
  [ "$status" -eq 0 ]
  ! grep -q "\[auto\] L1a updated" "$SESSION_FILE"
}

@test "Write to .claude-docs/*.md captured as L1b" {
  run_hook_with '{"tool_name":"Write","tool_input":{"file_path":"/c/dev/proj/.claude-docs/gotchas.md"}}'
  [ "$status" -eq 0 ]
  grep -q "\[auto\] L1b updated" "$SESSION_FILE"
}

@test "unrelated tool events are ignored" {
  run_hook_with '{"tool_name":"Read","tool_input":{"file_path":"/c/dev/proj/src/main.py"}}'
  [ "$status" -eq 0 ]
  ! grep -q "\[auto\]" "$SESSION_FILE"
}

@test "no SESSION.md - exits cleanly without creating one" {
  rm "$SESSION_FILE"
  run_hook_with '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"x\""}}'
  [ "$status" -eq 0 ]
  [ ! -f "$SESSION_FILE" ]
}

@test "empty stdin - exits cleanly" {
  run bash -c "printf '' | bash '$REPO_ROOT/hooks/post-tool-use.sh'"
  [ "$status" -eq 0 ]
}
