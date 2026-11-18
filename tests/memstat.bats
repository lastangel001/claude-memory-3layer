#!/usr/bin/env bats
# Tests for bin/memstat.sh --refresh (the former /memory refresh), through a qmd stub.

load helpers

setup() {
  setup_claude_home
  STUB_DIR="$(mktemp -d)"
  cat > "$STUB_DIR/qmd" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$1" >> "$QMD_STUB_LOG"
echo "stub qmd $1 done"
EOF
  chmod +x "$STUB_DIR/qmd"
  export QMD_STUB_LOG="$STUB_DIR/calls.log"
}

teardown() {
  rm -rf "$STUB_DIR"
  teardown_claude_home
  return 0
}

@test "--refresh runs update then embed and stamps completion" {
  run env MEMORY_QMD_CMD="$STUB_DIR/qmd" bash "$REPO_ROOT/bin/memstat.sh" --refresh
  [ "$status" -eq 0 ]
  [ "$(sed -n '1p' "$QMD_STUB_LOG")" = "update" ]
  [ "$(sed -n '2p' "$QMD_STUB_LOG")" = "embed" ]
  [ -s "$TEST_CLAUDE_HOME/.qmd-last-refresh-done" ]
  [[ "$output" == *"stub qmd update done"* ]]
}

@test "--refresh without qmd says so and exits non-zero" {
  run env MEMORY_QMD_CMD="$STUB_DIR/no-such-qmd" bash "$REPO_ROOT/bin/memstat.sh" --refresh
  [ "$status" -eq 1 ]
  [[ "$output" == *"qmd not found"* ]]
}
