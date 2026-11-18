#!/usr/bin/env bats
# Tests for hooks/post-tool-use.sh — selective auto-capture patterns.

load helpers

setup() {
  setup_claude_home
  WORK_DIR="$(mktemp -d)"
  cd "$WORK_DIR"
  make_session "$PWD" <<EOF
---
last_updated: $(iso_ago 60)
cwd: $PWD
---
# Recent turns
EOF
}

teardown() {
  cd /
  rm -rf "$WORK_DIR"
  teardown_claude_home
}

# Feed a JSON event on stdin. Goes through a file so the JSON may contain
# single quotes, backslashes and newlines without shell-quoting games.
run_hook_with() {
  printf '%s' "$1" > "$WORK_DIR/.event.json"
  run bash -c "bash '$REPO_ROOT/hooks/post-tool-use.sh' < '$WORK_DIR/.event.json'"
}

# Real repository with one fresh commit in $WORK_DIR.
make_commit() {  # $1 = subject
  git init -q . 2>/dev/null
  printf '%s\n' "$1" >> tracked.txt
  git add tracked.txt
  git -c user.name=test -c user.email=test@example.invalid -c commit.gpgsign=false \
    commit -q -m "$1"
}

@test "a real git commit via Bash is captured with sha and subject from git" {
  make_commit "fix: test message"
  run_hook_with '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"fix: test message\""}}'
  [ "$status" -eq 0 ]
  grep -q "\[auto\] git commit: [0-9a-f]\{7,\} fix: test message" "$SESSION_FILE"
}

@test "heredoc-style commit command still yields the real subject" {
  make_commit "feat: real subject"
  run_hook_with '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"$(cat <<'"'"'EOF'"'"'\nfeat: real subject\nEOF\n)\""}}'
  [ "$status" -eq 0 ]
  grep -q "\[auto\] git commit: [0-9a-f]\{7,\} feat: real subject" "$SESSION_FILE"
  ! grep -q "see git log" "$SESSION_FILE"
}

@test "command that only mentions git commit is NOT captured (no new commit)" {
  git init -q . 2>/dev/null
  run_hook_with '{"tool_name":"Bash","tool_input":{"command":"grep -rn \"git commit\" docs/"}}'
  [ "$status" -eq 0 ]
  ! grep -q "\[auto\]" "$SESSION_FILE"
}

@test "echo git commit outside a repository is NOT captured" {
  run_hook_with '{"tool_name":"Bash","tool_input":{"command":"echo git commit"}}'
  [ "$status" -eq 0 ]
  ! grep -q "\[auto\]" "$SESSION_FILE"
}

@test "the same commit is captured only once" {
  make_commit "chore: once"
  run_hook_with '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}'
  run_hook_with '{"tool_name":"Bash","tool_input":{"command":"git commit --amend --no-edit; git commit -m x"}}'
  [ "$(grep -c "\[auto\] git commit" "$SESSION_FILE")" -eq 1 ]
}

@test "git commit via the PowerShell tool is captured" {
  make_commit "docs: from powershell"
  run_hook_with '{"tool_name":"PowerShell","tool_input":{"command":"git commit -m \"docs: from powershell\""}}'
  [ "$status" -eq 0 ]
  grep -q "\[auto\] git commit: .* docs: from powershell" "$SESSION_FILE"
}

@test "Write to repo CLAUDE.md captured as L1a" {
  run_hook_with '{"tool_name":"Write","tool_input":{"file_path":"/c/dev/proj/CLAUDE.md"}}'
  [ "$status" -eq 0 ]
  grep -q "\[auto\] L1a updated" "$SESSION_FILE"
}

@test "bare CLAUDE.md path captured only for edit tools (precedence regression v6.15.0)" {
  run_hook_with '{"tool_name":"Bash","tool_input":{"file_path":"CLAUDE.md","command":"cat CLAUDE.md"}}'
  [ "$status" -eq 0 ]
  ! grep -q "\[auto\] L1a updated" "$SESSION_FILE"
}

@test "Write to .claude-docs/*.md captured as L1b" {
  run_hook_with '{"tool_name":"Write","tool_input":{"file_path":"/c/dev/proj/.claude-docs/gotchas.md"}}'
  [ "$status" -eq 0 ]
  grep -q "\[auto\] L1b updated" "$SESSION_FILE"
}

@test "Edit and MultiEdit are captured too (most doc updates are edits)" {
  run_hook_with '{"tool_name":"Edit","tool_input":{"file_path":"/c/dev/proj/.claude-docs/gotchas.md"}}'
  grep -q "\[auto\] L1b updated" "$SESSION_FILE"
  run_hook_with '{"tool_name":"MultiEdit","tool_input":{"file_path":"/c/dev/proj/CLAUDE.md"}}'
  grep -q "\[auto\] L1a updated" "$SESSION_FILE"
}

@test "Windows backslash path to .claude-docs is captured" {
  run_hook_with '{"tool_name":"Edit","tool_input":{"file_path":"C:\\dev\\proj\\.claude-docs\\gotchas.md"}}'
  [ "$status" -eq 0 ]
  grep -q "\[auto\] L1b updated: C:/dev/proj/.claude-docs/gotchas.md" "$SESSION_FILE"
}

@test "repeated edits of one doc produce a single capture line" {
  run_hook_with '{"tool_name":"Edit","tool_input":{"file_path":"/c/dev/proj/.claude-docs/gotchas.md"}}'
  run_hook_with '{"tool_name":"Edit","tool_input":{"file_path":"/c/dev/proj/.claude-docs/gotchas.md"}}'
  [ "$(grep -c "\[auto\] L1b updated" "$SESSION_FILE")" -eq 1 ]
}

@test "transcript_path on stdin selects that project's SESSION.md" {
  other="$TEST_CLAUDE_HOME/projects/C--from-transcript/memory"
  mkdir -p "$other"
  printf '# Recent turns\n' > "$other/SESSION.md"
  run_hook_with '{"transcript_path":"C:\\Users\\u\\.claude\\projects\\C--from-transcript\\abc.jsonl","tool_name":"Write","tool_input":{"file_path":"/c/dev/proj/CLAUDE.md"}}'
  [ "$status" -eq 0 ]
  grep -q "\[auto\] L1a updated" "$other/SESSION.md"
  ! grep -q "\[auto\]" "$SESSION_FILE"
}

@test "unrelated tool events are ignored" {
  run_hook_with '{"tool_name":"Read","tool_input":{"file_path":"/c/dev/proj/src/main.py"}}'
  [ "$status" -eq 0 ]
  ! grep -q "\[auto\]" "$SESSION_FILE"
}

@test "Read of CLAUDE.md is ignored (tool-name gate)" {
  run_hook_with '{"tool_name":"Read","tool_input":{"file_path":"/c/dev/proj/CLAUDE.md"}}'
  [ "$status" -eq 0 ]
  ! grep -q "\[auto\]" "$SESSION_FILE"
}

@test "no SESSION.md - exits cleanly without creating one" {
  rm "$SESSION_FILE"
  make_commit "x"
  run_hook_with '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"x\""}}'
  [ "$status" -eq 0 ]
  [ ! -f "$SESSION_FILE" ]
}

@test "empty stdin - exits cleanly" {
  run bash -c "printf '' | bash '$REPO_ROOT/hooks/post-tool-use.sh'"
  [ "$status" -eq 0 ]
}

@test "a capture is journaled in hook-diag.jsonl" {
  run_hook_with '{"tool_name":"Write","tool_input":{"file_path":"/c/dev/proj/CLAUDE.md"}}'
  grep -q '"hook":"PostToolUse","outcome":"ok","note":"captured=L1a-updated"' \
    "$TEST_CLAUDE_HOME/debug/hook-diag.jsonl"
}
