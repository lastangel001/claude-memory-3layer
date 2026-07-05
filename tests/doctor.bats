#!/usr/bin/env bats
# Tests for bin/doctor.sh — smoke run over a real install, plus the v6.17.0
# checks: duplicate hook registration, CRLF in installed hooks, dynamic
# session-start/post-tool-use self-test.

load helpers

setup() {
  TEST_HOME="$(mktemp -d)"
  env CLAUDE_HOME="$TEST_HOME" bash "$REPO_ROOT/install.sh" >/dev/null 2>&1
  WORK_DIR="$(mktemp -d)"
  cd "$WORK_DIR"
}

teardown() {
  cd /
  rm -rf "$WORK_DIR" "$TEST_HOME"
}

@test "doctor passes on a fresh install (exit 0)" {
  run env CLAUDE_HOME="$TEST_HOME" bash "$REPO_ROOT/bin/doctor.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"All critical checks passed"* ]]
}

@test "doctor: dynamic self-test reports session-start.sh runs clean" {
  run env CLAUDE_HOME="$TEST_HOME" bash "$REPO_ROOT/bin/doctor.sh"
  [[ "$output" == *"session-start.sh runs clean"* ]]
  [[ "$output" == *"post-tool-use.sh runs clean"* ]]
}

@test "doctor: no CRLF reported on a clean checkout" {
  run env CLAUDE_HOME="$TEST_HOME" bash "$REPO_ROOT/bin/doctor.sh"
  [[ "$output" == *"No CRLF line endings"* ]]
}

@test "doctor: CRLF-contaminated hook is flagged" {
  printf 'echo x\r\n' >> "$TEST_HOME/hooks/session-start.sh"
  run env CLAUDE_HOME="$TEST_HOME" bash "$REPO_ROOT/bin/doctor.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"CRLF line endings"* ]]
}

@test "doctor: no duplicate hook registrations on a fresh install" {
  run env CLAUDE_HOME="$TEST_HOME" bash "$REPO_ROOT/bin/doctor.sh"
  [[ "$output" == *"No duplicate hook registrations"* ]]
}

@test "doctor: duplicate hook command is detected" {
  # Register session-start.sh twice under SessionStart.
  python3 - "$TEST_HOME/settings.json" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))
grp = d["hooks"]["SessionStart"][0]
d["hooks"]["SessionStart"].append({"matcher": "*", "hooks": list(grp["hooks"])})
json.dump(d, open(sys.argv[1], "w"), indent=2)
PYEOF
  run env CLAUDE_HOME="$TEST_HOME" bash "$REPO_ROOT/bin/doctor.sh"
  [[ "$output" == *"Duplicate hook registrations"* ]]
}

@test "doctor: broken runtime copy fails the self-test" {
  # Corrupt the installed session-start.sh so it exits non-zero.
  printf '\nexit 3\n' >> "$TEST_HOME/hooks/session-start.sh"
  run env CLAUDE_HOME="$TEST_HOME" bash "$REPO_ROOT/bin/doctor.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"self-test FAILED"* ]]
}
