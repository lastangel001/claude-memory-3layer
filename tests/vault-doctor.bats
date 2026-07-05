#!/usr/bin/env bats
# Tests for bin/vault-doctor.sh — memory content health: IDENTITY size,
# SESSION oversize + staleness, and the --fix stale-session wipe.

load helpers

setup() {
  TEST_HOME="$(mktemp -d)"
  mkdir -p "$TEST_HOME/memory" "$TEST_HOME/projects"
  printf 'one line identity\n' > "$TEST_HOME/memory/IDENTITY.md"
  # Neutral cwd with no .claude-docs so the repo-docs section is skipped.
  WORK_DIR="$(mktemp -d)"
  cd "$WORK_DIR"
}

teardown() {
  cd /
  rm -rf "$WORK_DIR" "$TEST_HOME"
}

mk_session() {  # $1=slug  $2=last_updated  $3=extra-bytes
  local d="$TEST_HOME/projects/$1/memory"
  mkdir -p "$d"
  {
    printf -- '---\nlast_updated: %s\ncwd: C:/some/%s\n---\n# Goal\nx\n' "$2" "$1"
    [[ -n "${3:-}" ]] && head -c "$3" /dev/zero | tr '\0' 'y'
  } > "$d/SESSION.md"
  printf '%s' "$d/SESSION.md"
}

@test "vault-doctor passes when memory is healthy (exit 0)" {
  mk_session "C--fresh" "$(iso_ago 3600)" >/dev/null
  run env CLAUDE_HOME="$TEST_HOME" bash "$REPO_ROOT/bin/vault-doctor.sh"
  [ "$status" -eq 0 ]
}

@test "vault-doctor warns on IDENTITY.md over the 25-line cap" {
  seq 1 40 > "$TEST_HOME/memory/IDENTITY.md"
  run env CLAUDE_HOME="$TEST_HOME" bash "$REPO_ROOT/bin/vault-doctor.sh"
  [[ "$output" == *"over"*"line cap"* ]]
}

@test "vault-doctor flags a stale session but does not wipe without --fix" {
  sf="$(mk_session "C--stale" "$(iso_ago $((40*86400)))")"
  run env CLAUDE_HOME="$TEST_HOME" bash "$REPO_ROOT/bin/vault-doctor.sh"
  [[ "$output" == *"stale"* ]]
  # Original goal still present (not wiped).
  grep -q '# Goal' "$sf"
  ! grep -q 'wiped by vault-doctor' "$sf"
}

@test "vault-doctor --fix wipes a stale session and keeps its cwd" {
  sf="$(mk_session "C--stale2" "$(iso_ago $((40*86400)))")"
  run env CLAUDE_HOME="$TEST_HOME" bash "$REPO_ROOT/bin/vault-doctor.sh" --fix
  [ "$status" -eq 0 ]
  grep -q 'wiped by vault-doctor' "$sf"
  grep -q 'cwd: C:/some/C--stale2' "$sf"
  ls "$sf".bak-* >/dev/null
}

@test "vault-doctor leaves a fresh session untouched under --fix" {
  sf="$(mk_session "C--fresh2" "$(iso_ago 3600)")"
  run env CLAUDE_HOME="$TEST_HOME" bash "$REPO_ROOT/bin/vault-doctor.sh" --fix
  [ "$status" -eq 0 ]
  ! grep -q 'wiped by vault-doctor' "$sf"
}

@test "vault-doctor warns on oversize SESSION.md" {
  mk_session "C--big" "$(iso_ago 3600)" 9000 >/dev/null
  run env CLAUDE_HOME="$TEST_HOME" bash "$REPO_ROOT/bin/vault-doctor.sh"
  [[ "$output" == *"SESSION.md"*"prune"* ]]
}
