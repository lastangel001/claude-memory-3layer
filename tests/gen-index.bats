#!/usr/bin/env bats
# Tests for bin/gen-index.sh — regenerate .claude-docs/index.md routing table
# from each doc's description: frontmatter, preserving the manual block.

load helpers

setup() {
  DOCS="$(mktemp -d)/.claude-docs"
  mkdir -p "$DOCS"
  printf -- '---\ntags: [x]\ndescription: How the thing is built\n---\n# Arch\n' > "$DOCS/architecture.md"
  printf -- '---\ntags: [x]\n---\n# Conventions doc heading\n' > "$DOCS/conventions.md"
}

teardown() {
  rm -rf "$(dirname "$DOCS")"
}

@test "gen-index scaffolds index.md with a row per doc" {
  run bash "$REPO_ROOT/bin/gen-index.sh" --dir "$DOCS"
  [ "$status" -eq 0 ]
  [ -f "$DOCS/index.md" ]
  grep -q '\[architecture.md\](architecture.md)' "$DOCS/index.md"
  grep -q '\[conventions.md\](conventions.md)' "$DOCS/index.md"
}

@test "gen-index uses description: frontmatter for the row text" {
  bash "$REPO_ROOT/bin/gen-index.sh" --dir "$DOCS" >/dev/null
  grep -q 'How the thing is built' "$DOCS/index.md"
}

@test "gen-index falls back to first heading when no description" {
  bash "$REPO_ROOT/bin/gen-index.sh" --dir "$DOCS" >/dev/null
  grep -q 'Conventions doc heading' "$DOCS/index.md"
}

@test "gen-index never lists index.md itself" {
  bash "$REPO_ROOT/bin/gen-index.sh" --dir "$DOCS" >/dev/null
  ! grep -q '\[index.md\](index.md)' "$DOCS/index.md"
}

@test "gen-index --check succeeds when up to date, fails when stale" {
  bash "$REPO_ROOT/bin/gen-index.sh" --dir "$DOCS" >/dev/null
  run bash "$REPO_ROOT/bin/gen-index.sh" --dir "$DOCS" --check
  [ "$status" -eq 0 ]
  # New doc makes it stale.
  printf -- '---\ndescription: new one\n---\n# New\n' > "$DOCS/newdoc.md"
  run bash "$REPO_ROOT/bin/gen-index.sh" --dir "$DOCS" --check
  [ "$status" -eq 1 ]
}

@test "gen-index refuses to clobber a markerless index.md (no --force)" {
  printf -- '---\ntags: [x]\n---\n# Hand-written\nimportant human notes\n' > "$DOCS/index.md"
  run bash "$REPO_ROOT/bin/gen-index.sh" --dir "$DOCS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no AUTO-INDEX markers"* ]]
  # Original content intact.
  grep -q 'important human notes' "$DOCS/index.md"
}

@test "gen-index --force scaffolds over a markerless index.md" {
  printf -- '---\ntags: [x]\n---\n# Hand-written\n' > "$DOCS/index.md"
  run bash "$REPO_ROOT/bin/gen-index.sh" --dir "$DOCS" --force
  [ "$status" -eq 0 ]
  grep -q 'AUTO-INDEX:START' "$DOCS/index.md"
}

@test "gen-index preserves the manual block across regeneration" {
  bash "$REPO_ROOT/bin/gen-index.sh" --dir "$DOCS" >/dev/null
  printf '\n- hand-written routing note ZZZ\n' >> "$DOCS/index.md"
  bash "$REPO_ROOT/bin/gen-index.sh" --dir "$DOCS" >/dev/null
  grep -q 'hand-written routing note ZZZ' "$DOCS/index.md"
}
