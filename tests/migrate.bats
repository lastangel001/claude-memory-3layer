#!/usr/bin/env bats
# Tests for migrate.sh — Pass B (HTML-comment marker → YAML frontmatter) and
# Pass A (legacy MEMORY.md / typed-prefix detection). Pass B was silently dead
# for multiple releases (local at top level under set -e, fixed v6.16.0) with
# zero test coverage — these lock the behavior in.

load helpers

setup() {
  TEST_HOME="$(mktemp -d)"
  mkdir -p "$TEST_HOME/memory" "$TEST_HOME/projects"
}

teardown() {
  rm -rf "$TEST_HOME"
}

@test "Pass B: line-1 HTML marker is rewritten to YAML frontmatter" {
  f="$TEST_HOME/memory/gotchas.md"
  printf '<!-- last_updated: 2026-01-02T03:04:05Z -->\n# Gotchas\nbody line\n' > "$f"
  run env CLAUDE_HOME="$TEST_HOME" bash "$REPO_ROOT/migrate.sh"
  [ "$status" -eq 0 ]
  # File actually rewritten (this is what "runs fine, does nothing" hid).
  [ "$(head -n1 "$f")" = "---" ]
  grep -q '^last_updated: 2026-01-02T03:04:05Z' "$f"
  grep -q '^tags: \[memory/l1, gotcha\]' "$f"
  grep -q 'body line' "$f"
  # Backup preserved.
  ls "$TEST_HOME/memory/"gotchas.md.bak-* >/dev/null
}

@test "Pass B: --dry-run rewrites nothing" {
  f="$TEST_HOME/memory/project.md"
  printf '<!-- last_updated: 2026-01-02T03:04:05Z -->\nbody\n' > "$f"
  run env CLAUDE_HOME="$TEST_HOME" bash "$REPO_ROOT/migrate.sh" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry]"* ]]
  # Untouched.
  [ "$(head -n1 "$f")" = "<!-- last_updated: 2026-01-02T03:04:05Z -->" ]
  ! ls "$TEST_HOME/memory/"project.md.bak-* 2>/dev/null
}

@test "Pass B: a file already in YAML frontmatter is left alone" {
  f="$TEST_HOME/memory/already.md"
  printf -- '---\nlast_updated: 2026-01-01T00:00:00Z\ntags: [memory/l1]\n---\nbody\n' > "$f"
  before="$(cat "$f")"
  run env CLAUDE_HOME="$TEST_HOME" bash "$REPO_ROOT/migrate.sh"
  [ "$status" -eq 0 ]
  [ "$(cat "$f")" = "$before" ]
}

@test "Pass A: legacy MEMORY.md is detected, not auto-converted" {
  d="$TEST_HOME/projects/C--proj/memory"
  mkdir -p "$d"
  printf 'old memory format\n' > "$d/MEMORY.md"
  run env CLAUDE_HOME="$TEST_HOME" bash "$REPO_ROOT/migrate.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"/migrate-legacy-memory"* ]]
  # Not touched — MEMORY.md still there, no new project.md fabricated.
  [ -f "$d/MEMORY.md" ]
  [ ! -f "$d/project.md" ]
}

@test "Pass A: typed-prefix legacy files are detected" {
  d="$TEST_HOME/projects/C--proj2/memory"
  mkdir -p "$d"
  printf 'x\n' > "$d/feedback_style.md"
  run env CLAUDE_HOME="$TEST_HOME" bash "$REPO_ROOT/migrate.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Pass A"* ]]
  [[ "$output" == *"legacy"* ]]
}

@test "Pass A: already-migrated dir (legacy/ present) is skipped" {
  d="$TEST_HOME/projects/C--proj3/memory"
  mkdir -p "$d/legacy"
  printf 'x\n' > "$d/MEMORY.md"
  run env CLAUDE_HOME="$TEST_HOME" bash "$REPO_ROOT/migrate.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no legacy"* ]]
}
