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

@test "vault-doctor does not call a closed (status: done) session stale" {
  d="$TEST_HOME/projects/C--closed/memory"
  mkdir -p "$d"
  printf -- '---\nlast_updated: %s\ncwd: C:/some/closed\nstatus: done\n---\n# Goal\n(none)\n' \
    "$(iso_ago $((90*86400)))" > "$d/SESSION.md"
  run env CLAUDE_HOME="$TEST_HOME" bash "$REPO_ROOT/bin/vault-doctor.sh" --fix
  [ "$status" -eq 0 ]
  [[ "$output" != *"C--closed"* ]]
  ! ls "$d"/SESSION.md.bak-* >/dev/null 2>&1
}

@test "vault-doctor fails on a dead link in the repo CLAUDE.md doc index" {
  mkdir -p "$WORK_DIR/.claude-docs"
  printf -- '---\ndescription: g\n---\n# Gotchas\n' > "$WORK_DIR/.claude-docs/gotchas.md"
  printf '# Repo\n\n| Task | Read |\n|---|---|\n| a | [g](.claude-docs/gotchas.md) |\n| b | [x](.claude-docs/architecture.md) |\n' \
    > "$WORK_DIR/CLAUDE.md"
  run env CLAUDE_HOME="$TEST_HOME" bash "$REPO_ROOT/bin/vault-doctor.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"CLAUDE.md: broken link"*"architecture.md"* ]]
  [[ "$output" != *"gotchas.md (target file missing)"* ]]
}

@test "vault-doctor passes when every CLAUDE.md doc-index link resolves" {
  mkdir -p "$WORK_DIR/.claude-docs"
  printf -- '---\ndescription: g\n---\n# Gotchas\n' > "$WORK_DIR/.claude-docs/gotchas.md"
  printf '# Repo\n\n[g](.claude-docs/gotchas.md) and [site](https://example.invalid/x.md)\n' > "$WORK_DIR/CLAUDE.md"
  run env CLAUDE_HOME="$TEST_HOME" bash "$REPO_ROOT/bin/vault-doctor.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"All relative links resolve"* ]]
}

@test "vault-doctor warns on oversize SESSION.md" {
  mk_session "C--big" "$(iso_ago 3600)" 9000 >/dev/null
  run env CLAUDE_HOME="$TEST_HOME" bash "$REPO_ROOT/bin/vault-doctor.sh"
  [[ "$output" == *"SESSION.md"*"prune"* ]]
}
