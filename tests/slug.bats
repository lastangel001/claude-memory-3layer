#!/usr/bin/env bats
# Tests for bin/lib/slug.sh — project directory resolution: transcript path
# (exact), formula (every non-alphanumeric -> "-"), legacy-directory fallback.

load helpers

setup() {
  setup_claude_home
  source "$REPO_ROOT/bin/lib/slug.sh"
}

teardown() {
  teardown_claude_home
}

@test "formula: underscore, dot and space all map to a dash" {
  _compute_slug "/c/dev/my_app"
  [ "$slug" = "C--dev-my-app" ]
  _compute_slug "/c/Users/Jo/My Docs 2026/site.com"
  [ "$slug" = "C--Users-Jo-My-Docs-2026-site-com" ]
}

@test "formula: unix path keeps the leading dash" {
  _compute_slug "/home/dev/my.app"
  [ "$slug" = "-home-dev-my-app" ]
  [ "$current_cwd_canonical" = "/home/dev/my.app" ]
}

@test "formula: MSYS drive path yields Windows-style canonical cwd" {
  _compute_slug "/c/dev/foo"
  [ "$current_cwd_canonical" = "C:/dev/foo" ]
}

@test "transcript_path (Windows, JSON-escaped backslashes) gives the slug" {
  _resolve_project '{"session_id":"s","transcript_path":"C:\\Users\\u\\.claude\\projects\\C--real-slug\\abc.jsonl","cwd":"C:\\x"}' "/c/somewhere/else"
  [ "$slug" = "C--real-slug" ]
  [ "$slug_source" = "transcript" ]
  [ "$project_dir" = "$TEST_CLAUDE_HOME/projects/C--real-slug" ]
}

@test "escaped backslash followed by u is a path, not a unicode escape" {
  # C:\\Users\\user\\… contains the characters \\u — must not trip the \uXXXX guard.
  _resolve_project '{"transcript_path":"C:\\Users\\user\\.claude\\projects\\C--real-slug\\abc.jsonl"}' "/c/else"
  [ "$slug" = "C--real-slug" ]
  [ "$slug_source" = "transcript" ]
}

@test "a real unicode escape in transcript_path falls back to the formula" {
  _resolve_project '{"transcript_path":"/home/\u0444/.claude/projects/-home-x/abc.jsonl"}' "/c/dev/foo"
  [ "$slug" = "C--dev-foo" ]
  [ "$slug_source" = "formula" ]
}

@test "JSON-escaped forward slashes are accepted" {
  _resolve_project '{"transcript_path":"\/home\/u\/.claude\/projects\/-home-u-proj\/abc.jsonl"}' "/other"
  [ "$slug" = "-home-u-proj" ]
}

@test "transcript_path (unix) gives the slug, leading dash intact" {
  _resolve_project '{"transcript_path":"/home/u/.claude/projects/-home-u-proj/abc.jsonl"}' "/other"
  [ "$slug" = "-home-u-proj" ]
  [ "$slug_source" = "transcript" ]
}

@test "no transcript_path falls back to the formula" {
  _resolve_project '{"tool_name":"Read"}' "/c/dev/my_app"
  [ "$slug" = "C--dev-my-app" ]
  [ "$slug_source" = "formula" ]
}

@test "implausible transcript directory name is ignored" {
  _resolve_project '{"transcript_path":"/weird/dir with space/abc.jsonl"}' "/c/dev/foo"
  [ "$slug" = "C--dev-foo" ]
  [ "$slug_source" = "formula" ]
}

@test "legacy directory is used when only it holds SESSION.md" {
  mkdir -p "$TEST_CLAUDE_HOME/projects/home-dev-my.app/memory"
  printf '# Goal\nx\n' > "$TEST_CLAUDE_HOME/projects/home-dev-my.app/memory/SESSION.md"
  _resolve_project "" "/home/dev/my.app"
  [ "$slug" = "home-dev-my.app" ]
  [ "$slug_source" = "legacy" ]
}

@test "canonical directory wins when it already holds SESSION.md" {
  mkdir -p "$TEST_CLAUDE_HOME/projects/home-dev-my.app/memory" \
           "$TEST_CLAUDE_HOME/projects/-home-dev-my-app/memory"
  printf 'old\n' > "$TEST_CLAUDE_HOME/projects/home-dev-my.app/memory/SESSION.md"
  printf 'new\n' > "$TEST_CLAUDE_HOME/projects/-home-dev-my-app/memory/SESSION.md"
  _resolve_project "" "/home/dev/my.app"
  [ "$slug" = "-home-dev-my-app" ]
  [ "$slug_source" = "formula" ]
}
