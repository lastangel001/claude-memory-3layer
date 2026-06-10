#!/usr/bin/env bats
# Tests for install.sh — completeness sanity: every command/*.md, bin/*.sh,
# bin/lib/*.sh and hook in the repo must be mentioned by a dry-run install.
# Catches "file exists in repo but installer forgot it" (the /memstat bug class).

load helpers

setup() {
  TEST_HOME="$(mktemp -d)"
}

teardown() {
  rm -rf "$TEST_HOME"
}

@test "dry-run covers every commands/*.md in the repo" {
  run env CLAUDE_HOME="$TEST_HOME" bash "$REPO_ROOT/install.sh" --dry-run
  [ "$status" -eq 0 ]
  for f in "$REPO_ROOT"/commands/*.md; do
    name="$(basename "$f")"
    [[ "$output" == *"commands/$name"* ]] || {
      echo "installer does not mention commands/$name" >&2
      return 1
    }
  done
}

@test "dry-run covers every bin/*.sh and bin/lib/*.sh in the repo" {
  run env CLAUDE_HOME="$TEST_HOME" bash "$REPO_ROOT/install.sh" --dry-run
  [ "$status" -eq 0 ]
  for f in "$REPO_ROOT"/bin/*.sh "$REPO_ROOT"/bin/lib/*.sh; do
    name="$(basename "$f")"
    [[ "$output" == *"$name"* ]] || {
      echo "installer does not mention bin script $name" >&2
      return 1
    }
  done
}

@test "dry-run covers every hooks/*.sh in the repo" {
  run env CLAUDE_HOME="$TEST_HOME" bash "$REPO_ROOT/install.sh" --dry-run
  [ "$status" -eq 0 ]
  for f in "$REPO_ROOT"/hooks/*.sh; do
    name="$(basename "$f")"
    [[ "$output" == *"hooks/$name"* ]] || {
      echo "installer does not mention hooks/$name" >&2
      return 1
    }
  done
}

@test "dry-run installs templates to CLAUDE_HOME/templates" {
  run env CLAUDE_HOME="$TEST_HOME" bash "$REPO_ROOT/install.sh" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"templates/repo/CLAUDE.md"* ]]
  [[ "$output" == *"templates/project.md.fallback.template"* ]]
}

@test "dry-run writes nothing" {
  run env CLAUDE_HOME="$TEST_HOME" bash "$REPO_ROOT/install.sh" --dry-run
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_HOME/CLAUDE.md" ]
}
