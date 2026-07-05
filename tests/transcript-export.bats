#!/usr/bin/env bats
# Tests for bin/transcript-export.sh — verbatim recall layer (v6.16.0).

load helpers

setup() {
  setup_claude_home
  SLUG="C--dev-proj"
  PROJ_DIR="$TEST_CLAUDE_HOME/projects/$SLUG"
  mkdir -p "$PROJ_DIR"
  WORK_DIR="$(mktemp -d)"
}

teardown() {
  teardown_claude_home
  rm -rf "$WORK_DIR"
}

make_jsonl() {
  cat > "$PROJ_DIR/sess-1.jsonl" <<'EOF'
{"type":"user","message":{"role":"user","content":"fix the login bug please"}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Found it: token expiry uses < not <=."},{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"grep -r expiry"}}]}}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"noise from tool"}]}}
{"type":"user","isMeta":true,"message":{"role":"user","content":"meta line skipped"}}
{"type":"user","message":{"role":"user","content":"key is <private>sk-secret-123</private> ok"}}
EOF
}

run_export() {
  (cd "$WORK_DIR" && run_export_inner)
}

run_export_inner() {
  CLAUDE_HOME="$TEST_CLAUDE_HOME" bash "$REPO_ROOT/bin/transcript-export.sh" "$SLUG"
}

@test "exports user+assistant text, skips tool noise and meta lines" {
  make_jsonl
  cd "$WORK_DIR"
  run env CLAUDE_HOME="$TEST_CLAUDE_HOME" bash "$REPO_ROOT/bin/transcript-export.sh" "$SLUG"
  [ "$status" -eq 0 ]
  out="$PROJ_DIR/memory/raw/transcripts/sess-1.md"
  [ -f "$out" ]
  grep -q "fix the login bug" "$out"
  grep -q "token expiry uses" "$out"
  ! grep -q "noise from tool" "$out"
  ! grep -q "meta line skipped" "$out"
}

@test "strips <private> blocks from export" {
  make_jsonl
  cd "$WORK_DIR"
  run env CLAUDE_HOME="$TEST_CLAUDE_HOME" bash "$REPO_ROOT/bin/transcript-export.sh" "$SLUG"
  [ "$status" -eq 0 ]
  out="$PROJ_DIR/memory/raw/transcripts/sess-1.md"
  [ -f "$out" ]
  ! grep -q "sk-secret-123" "$out"
}

@test "opt-out flag file disables export" {
  make_jsonl
  touch "$TEST_CLAUDE_HOME/.transcript-export-disabled"
  cd "$WORK_DIR"
  run env CLAUDE_HOME="$TEST_CLAUDE_HOME" bash "$REPO_ROOT/bin/transcript-export.sh" "$SLUG"
  [ "$status" -eq 0 ]
  [ ! -e "$PROJ_DIR/memory/raw/transcripts/sess-1.md" ]
}

@test ".claude-private in project root skips export entirely" {
  make_jsonl
  touch "$WORK_DIR/.claude-private"
  cd "$WORK_DIR"
  run env CLAUDE_HOME="$TEST_CLAUDE_HOME" bash "$REPO_ROOT/bin/transcript-export.sh" "$SLUG"
  [ "$status" -eq 0 ]
  [ ! -e "$PROJ_DIR/memory/raw/transcripts/sess-1.md" ]
}

@test "incremental: unchanged jsonl is not re-exported" {
  make_jsonl
  cd "$WORK_DIR"
  run env CLAUDE_HOME="$TEST_CLAUDE_HOME" bash "$REPO_ROOT/bin/transcript-export.sh" "$SLUG"
  [ "$status" -eq 0 ]
  out="$PROJ_DIR/memory/raw/transcripts/sess-1.md"
  [ -f "$out" ]
  # Mark the export, re-run, marker must survive (file not rewritten).
  echo "MARKER-DO-NOT-REWRITE" >> "$out"
  touch -d "2020-01-01" "$PROJ_DIR/sess-1.jsonl" 2>/dev/null || touch -t 202001010000 "$PROJ_DIR/sess-1.jsonl"
  run env CLAUDE_HOME="$TEST_CLAUDE_HOME" bash "$REPO_ROOT/bin/transcript-export.sh" "$SLUG"
  [ "$status" -eq 0 ]
  grep -q "MARKER-DO-NOT-REWRITE" "$out"
}
