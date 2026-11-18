#!/usr/bin/env bats
# Tests for hooks/pre-compact.sh + bin/compact-snapshot.sh — the compaction
# path: plain-text summary instructions on stdout, and the deterministic
# checkpoint (last user turns verbatim + git position).

load helpers

setup() {
  setup_claude_home
  # The hook calls the INSTALLED snapshot script; give the fake home one.
  cp "$REPO_ROOT/bin/compact-snapshot.sh" "$TEST_CLAUDE_HOME/bin/"
  WORK_DIR="$(mktemp -d)"
  cd "$WORK_DIR"
}

teardown() {
  cd /
  rm -rf "$WORK_DIR"
  teardown_claude_home
  return 0
}

json_is_valid() {
  source "$REPO_ROOT/bin/lib/validate-json.sh"
  printf '%s' "$1" | _validate_json_stream
}

# A transcript in Claude Code's .jsonl shape, living where Claude Code puts it.
make_transcript() {
  source "$REPO_ROOT/bin/lib/slug.sh"
  _compute_slug "$PWD"
  TRANSCRIPT="$TEST_CLAUDE_HOME/projects/$slug/sess-1.jsonl"
  mkdir -p "$(dirname "$TRANSCRIPT")"
  cat > "$TRANSCRIPT" <<'EOF'
{"type":"user","message":{"role":"user","content":"first question about the retry window"}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"answer one"}]}}
{"type":"user","isMeta":true,"message":{"role":"user","content":"meta line that must be skipped"}}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"tool output that must be skipped"}]}}
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"<system-reminder>injected reminder</system-reminder>"}]}}
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"second: use backoff of 250 ms, token <private>sk-secret-9</private> stays out"}]}}
{"type":"user","isSidechain":true,"message":{"role":"user","content":"subagent prompt that must be skipped"}}
{"type":"user","message":{"role":"user","content":"третий вопрос: проверь путь C:\\dev\\app"}}
not json at all
EOF
}

hook_input() {  # JSON the harness would send (mktemp paths hold no backslashes)
  printf '{"session_id":"s","transcript_path":"%s","cwd":"%s","hook_event_name":"PreCompact","trigger":"auto","custom_instructions":null}' "$TRANSCRIPT" "$PWD"
}

run_hook() {
  hook_input > "$WORK_DIR/.in.json"
  run bash -c "bash '$REPO_ROOT/hooks/pre-compact.sh' < '$WORK_DIR/.in.json'"
}

@test "stdout is plain-text summary instructions, not JSON" {
  run bash "$REPO_ROOT/hooks/pre-compact.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Memory-protocol requirements for this summary"* ]]
  [[ "$output" == *"VERBATIM"* ]]
  # JSON output would be discarded by Claude Code for this event.
  [[ "$output" != "{"* ]]
  [[ "$output" != *"systemMessage"* ]]
}

@test "instructions stay under the 10,000-character cap" {
  run bash "$REPO_ROOT/hooks/pre-compact.sh"
  [ "${#output}" -lt 10000 ]
}

@test "without a SESSION.md no snapshot is created and no file path is named" {
  make_transcript
  run_hook
  [ "$status" -eq 0 ]
  [[ "$output" != *"Working state file"* ]]
  [ ! -f "$TEST_CLAUDE_HOME/projects/$slug/memory/compact-snapshot.md" ]
}

@test "with a SESSION.md the summary is told where the working state lives" {
  make_transcript
  make_session "$PWD" <<EOF
---
last_updated: $(iso_ago 60)
cwd: $PWD
---
# Goal
x
EOF
  run_hook
  [ "$status" -eq 0 ]
  [[ "$output" == *"Working state file:"*"/memory/SESSION.md"* ]]
}

@test "snapshot holds the last user turns verbatim and skips noise" {
  make_transcript
  make_session "$PWD" <<EOF
---
last_updated: $(iso_ago 60)
cwd: $PWD
---
# Goal
x
EOF
  run_hook
  [ "$status" -eq 0 ]
  snap="$TEST_CLAUDE_HOME/projects/$slug/memory/compact-snapshot.md"
  [ -f "$snap" ]
  grep -q "first question about the retry window" "$snap"
  grep -q "use backoff of 250 ms" "$snap"
  grep -q 'C:\\dev\\app' "$snap"
  grep -q "trigger: auto" "$snap"
  ! grep -q "meta line that must be skipped" "$snap"
  ! grep -q "tool output that must be skipped" "$snap"
  ! grep -q "injected reminder" "$snap"
  ! grep -q "subagent prompt" "$snap"
  ! grep -q "answer one" "$snap"
}

@test "snapshot strips <private> blocks" {
  make_transcript
  make_session "$PWD" <<EOF
---
last_updated: $(iso_ago 60)
cwd: $PWD
---
EOF
  run_hook
  snap="$TEST_CLAUDE_HOME/projects/$slug/memory/compact-snapshot.md"
  ! grep -q "sk-secret-9" "$snap"
  grep -q "stays out" "$snap"
}

@test "snapshot keeps only the configured number of turns" {
  make_transcript
  make_session "$PWD" <<EOF
---
last_updated: $(iso_ago 60)
cwd: $PWD
---
EOF
  hook_input > "$WORK_DIR/.in.json"
  run bash -c "COMPACT_SNAPSHOT_TURNS=1 bash '$REPO_ROOT/hooks/pre-compact.sh' < '$WORK_DIR/.in.json'"
  snap="$TEST_CLAUDE_HOME/projects/$slug/memory/compact-snapshot.md"
  ! grep -q "first question" "$snap"
  grep -q "третий вопрос" "$snap"
}

@test ".claude-private project: git position only, no user turns" {
  make_transcript
  printf 'secrets/**\n' > "$WORK_DIR/.claude-private"
  make_session "$PWD" <<EOF
---
last_updated: $(iso_ago 60)
cwd: $PWD
---
EOF
  run_hook
  snap="$TEST_CLAUDE_HOME/projects/$slug/memory/compact-snapshot.md"
  [ -f "$snap" ]
  grep -q "not captured: .claude-private" "$snap"
  ! grep -q "retry window" "$snap"
}

@test "snapshot records the git position" {
  make_transcript
  git init -q . 2>/dev/null
  printf 'x\n' > f.txt && git add f.txt
  git -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false commit -q -m "feat: snapshot subject"
  make_session "$PWD" <<EOF
---
last_updated: $(iso_ago 60)
cwd: $PWD
---
EOF
  run_hook
  snap="$TEST_CLAUDE_HOME/projects/$slug/memory/compact-snapshot.md"
  grep -q "feat: snapshot subject" "$snap"
  grep -q "uncommitted files:" "$snap"
}

@test "outcome is journaled with the number of captured turns" {
  make_transcript
  make_session "$PWD" <<EOF
---
last_updated: $(iso_ago 60)
cwd: $PWD
---
EOF
  run_hook
  grep -q '"hook":"PreCompact","outcome":"ok","note":"snapshot=ok turns=3 trigger=auto"' \
    "$TEST_CLAUDE_HOME/debug/hook-diag.jsonl"
}

@test "missing snapshot script does not break the hook" {
  rm "$TEST_CLAUDE_HOME/bin/compact-snapshot.sh"
  make_transcript
  make_session "$PWD" <<EOF
---
last_updated: $(iso_ago 60)
cwd: $PWD
---
EOF
  run_hook
  [ "$status" -eq 0 ]
  [[ "$output" == *"Memory-protocol requirements"* ]]
}
