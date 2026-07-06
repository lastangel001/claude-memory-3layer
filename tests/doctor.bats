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
  # Register session-start.sh twice under SessionStart. Build the fixture with a
  # WORKING interpreter — Win11's python3 alias stub is on PATH but exits 49, so
  # raw `python3` here would fail the test regardless of doctor's behavior.
  source "$REPO_ROOT/bin/lib/validate-json.sh"
  case "$(_json_parser)" in
    python3)
      python3 - "$TEST_HOME/settings.json" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))
grp = d["hooks"]["SessionStart"][0]
d["hooks"]["SessionStart"].append({"matcher": "*", "hooks": list(grp["hooks"])})
json.dump(d, open(sys.argv[1], "w"), indent=2)
PYEOF
      ;;
    node)
      node - "$TEST_HOME/settings.json" <<'JSEOF'
const fs = require('fs');
const f = process.argv[2];
const d = JSON.parse(fs.readFileSync(f, 'utf8'));
const grp = d.hooks.SessionStart[0];
d.hooks.SessionStart.push({ matcher: "*", hooks: [...grp.hooks] });
fs.writeFileSync(f, JSON.stringify(d, null, 2));
JSEOF
      ;;
    *) skip "no working JSON parser to build fixture" ;;
  esac
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
