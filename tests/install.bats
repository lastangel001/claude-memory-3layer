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

@test "memory hooks merged even when other tools' hooks occupy same events (regression v6.15.1)" {
  mkdir -p "$TEST_HOME"
  cat > "$TEST_HOME/settings.json" <<'EOF'
{
  "hooks": {
    "SessionStart": [
      {"matcher": "*", "hooks": [{"type": "command", "command": "bash ~/other-tool/hook.sh"}]}
    ],
    "PreCompact": [
      {"matcher": "*", "hooks": [{"type": "command", "command": "bash ~/other-tool/pc.sh"}]}
    ],
    "PostToolUse": [
      {"matcher": "*", "hooks": [{"type": "command", "command": "bash ~/other-tool/ptu.sh"}]}
    ]
  }
}
EOF
  run env CLAUDE_HOME="$TEST_HOME" bash "$REPO_ROOT/install.sh"
  [ "$status" -eq 0 ]
  grep -q 'hooks/session-start.sh' "$TEST_HOME/settings.json"
  grep -q 'hooks/pre-compact.sh'   "$TEST_HOME/settings.json"
  grep -q 'hooks/post-tool-use.sh' "$TEST_HOME/settings.json"
  grep -q 'other-tool/hook.sh'     "$TEST_HOME/settings.json"
}

@test "fresh-install settings.json contains our hook commands" {
  run env CLAUDE_HOME="$TEST_HOME" bash "$REPO_ROOT/install.sh"
  [ "$status" -eq 0 ]
  grep -q 'hooks/session-start.sh' "$TEST_HOME/settings.json"
}

@test "update.sh --dry-run pulls nothing and writes nothing" {
  src_clone="$(mktemp -d)/repo"
  git clone -q "$REPO_ROOT" "$src_clone"
  env CLAUDE_HOME="$TEST_HOME" bash "$src_clone/install.sh" >/dev/null

  head_before="$(git -C "$src_clone" rev-parse HEAD)"
  ver_before="$(cat "$TEST_HOME/.memory-version")"
  # Run the WORKING-TREE update.sh (the installed copy in TEST_HOME comes from
  # the clone's committed HEAD and may lag behind uncommitted changes under test).
  run env CLAUDE_HOME="$TEST_HOME" bash "$REPO_ROOT/bin/update.sh" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Skipping git pull"* ]]
  [ "$(git -C "$src_clone" rev-parse HEAD)" = "$head_before" ]
  [ "$(cat "$TEST_HOME/.memory-version")" = "$ver_before" ]
  rm -rf "$(dirname "$src_clone")"
}
