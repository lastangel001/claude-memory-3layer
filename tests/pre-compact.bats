#!/usr/bin/env bats
# Tests for hooks/pre-compact.sh — compression rule wording (enabled/disabled)
# and JSON validity of the emitted systemMessage.

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
  return 0
}

json_is_valid() {
  # Use the repo's own validator so the test picks a WORKING parser (dodges the
  # Windows Store python3 stub — presence-only checks pick it and it exits 49).
  source "$REPO_ROOT/bin/lib/validate-json.sh"
  printf '%s' "$1" | _validate_json_stream
}

@test "compression enabled: rule covers SESSION.md and project.md" {
  run bash "$REPO_ROOT/hooks/pre-compact.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Applies to SESSION.md and project.md"* ]]
}

@test "compression disabled via env var" {
  CLAUDE_SESSION_COMPRESS=0 run bash "$REPO_ROOT/hooks/pre-compact.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"COMPRESSION — disabled"* ]]
}

@test "emits valid JSON" {
  run bash "$REPO_ROOT/hooks/pre-compact.sh"
  [ "$status" -eq 0 ]
  json_is_valid "$output"
}
