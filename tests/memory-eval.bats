#!/usr/bin/env bats
# Tests for bin/memory-eval.sh — closed-book retrieval coverage of a repo's docs.

load helpers

setup() {
  setup_claude_home
  REPO_DIR="$(mktemp -d)"
  cd "$REPO_DIR"
  git init -q . 2>/dev/null
  mkdir -p .claude-docs
  printf -- '---\ndescription: g\n---\n# Gotchas\n\n## Retry window is capped\nThe uploader retries with a backoff capped at 250 ms (see retry_window).\n' > .claude-docs/gotchas.md
  printf -- '---\ndescription: a\n---\n# Architecture\nThe queue worker lives in worker/main.py.\n' > .claude-docs/architecture.md
}

teardown() {
  cd /
  rm -rf "$REPO_DIR"
  teardown_claude_home
  return 0
}

questions() { cat > .claude-docs/eval-questions.md; }

@test "all questions answered: coverage N/N, exit 0" {
  questions <<'EOF'
# Questions
- q: uploader retry backoff
  expect: 250 ms
- q: queue worker location
  expect: worker/main.py
EOF
  run bash "$REPO_ROOT/bin/memory-eval.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Retrieval coverage: 2/2"* ]]
}

@test "a question the docs cannot answer fails the run and names what recall returned" {
  questions <<'EOF'
- q: uploader retry backoff
  expect: 250 ms
- q: uploader retry backoff
  expect: exponential jitter
EOF
  run bash "$REPO_ROOT/bin/memory-eval.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Retrieval coverage: 1/2"* ]]
  [[ "$output" == *'expected "exponential jitter"'* ]]
  [[ "$output" == *"gotchas.md"* ]]
}

@test "--report never fails the run" {
  questions <<'EOF'
- q: uploader retry backoff
  expect: nothing-like-this
EOF
  run bash "$REPO_ROOT/bin/memory-eval.sh" --report
  [ "$status" -eq 0 ]
  [[ "$output" == *"Retrieval coverage: 0/1"* ]]
}

@test "the question file itself never counts as an answer" {
  # The expected text exists ONLY in the question file.
  questions <<'EOF'
- q: uploader retry backoff
  expect: only-in-the-question-file-xyz
EOF
  run bash "$REPO_ROOT/bin/memory-eval.sh"
  [ "$status" -eq 1 ]
}

@test "expect: a | b accepts either, case-insensitively" {
  questions <<'EOF'
- q: queue worker location
  expect: nope-nope | WORKER/MAIN.PY
EOF
  run bash "$REPO_ROOT/bin/memory-eval.sh"
  [ "$status" -eq 0 ]
}

@test "questions inside a fenced code block are examples" {
  questions <<'EOF'
```
- q: uploader retry backoff
  expect: never-present
```
- q: uploader retry backoff
  expect: 250 ms
EOF
  run bash "$REPO_ROOT/bin/memory-eval.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Retrieval coverage: 1/1"* ]]
}

@test "missing or empty question file is a usage error (exit 2)" {
  run bash "$REPO_ROOT/bin/memory-eval.sh"
  [ "$status" -eq 2 ]
  printf '# nothing here\n' > .claude-docs/eval-questions.md
  run bash "$REPO_ROOT/bin/memory-eval.sh"
  [ "$status" -eq 2 ]
}

@test "eval runs do not write to the recall misses log" {
  questions <<'EOF'
- q: zzzqqq nothing matches this
  expect: x
EOF
  run bash "$REPO_ROOT/bin/memory-eval.sh" --report
  [ ! -f "$TEST_CLAUDE_HOME/logs/recall-misses.log" ]
}

@test "this repository's own docs answer its eval questions" {
  cd "$REPO_ROOT"
  run bash "$REPO_ROOT/bin/memory-eval.sh"
  echo "$output"
  [ "$status" -eq 0 ]
}
