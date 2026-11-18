#!/usr/bin/env bats
# Tests for bin/recall.sh — the ripgrep/grep path (no qmd), the qmd path via a
# stub, repo-docs search, --here scoping and the misses log.

load helpers

setup() {
  setup_claude_home
  mkdir -p "$TEST_CLAUDE_HOME/memory" \
           "$TEST_CLAUDE_HOME/projects/C--dev-alpha/memory/raw/transcripts" \
           "$TEST_CLAUDE_HOME/projects/C--dev-beta/memory"
  printf '# Identity\n- prefers terse answers\n' > "$TEST_CLAUDE_HOME/memory/IDENTITY.md"
  printf '# Goal\nfix the retry backoff window in the uploader\n# Decisions\n- backoff capped at 250 ms\n' \
    > "$TEST_CLAUDE_HOME/projects/C--dev-alpha/memory/SESSION.md"
  printf '# Project beta\nretry is not used here; only a queue\n' \
    > "$TEST_CLAUDE_HOME/projects/C--dev-beta/memory/project.md"
  printf '# Transcript\n**User:**\nretry retry retry backoff backoff window window uploader\n' \
    > "$TEST_CLAUDE_HOME/projects/C--dev-alpha/memory/raw/transcripts/s1.md"

  REPO_DIR="$(mktemp -d)"
  cd "$REPO_DIR"
  git init -q . 2>/dev/null
  mkdir -p .claude-docs
  printf -- '---\ndescription: g\n---\n# Gotchas\n## zebra-crossing footgun\nthe uploader retries twice\n' > .claude-docs/gotchas.md
  printf '# Repo\nrun make test\n' > CLAUDE.md
  export RECALL_NO_REFRESH=1
}

teardown() {
  cd /
  rm -rf "$REPO_DIR"
  teardown_claude_home
  return 0
}

recall() { run bash "$REPO_ROOT/bin/recall.sh" "$@"; }

@test "no qmd: ranked literal search finds memory across projects" {
  recall --engine rg retry backoff window
  [ "$status" -eq 0 ]
  [[ "$output" == *"## Memory (all projects)"* ]]
  [[ "$output" == *"C--dev-alpha/memory/SESSION.md"* ]]
  [[ "$output" == *"literal match"* ]]
}

@test "a file matching more query words outranks one matching fewer" {
  recall --engine rg retry backoff window
  alpha=$(printf '%s\n' "$output" | grep -n 'C--dev-alpha/memory/SESSION.md' | head -1 | cut -d: -f1)
  beta=$(printf '%s\n' "$output" | grep -n 'C--dev-beta/memory/project.md' | head -1 | cut -d: -f1)
  [ -n "$alpha" ] && [ -n "$beta" ]
  [ "$alpha" -lt "$beta" ]
}

@test "curated memory is listed before verbatim transcripts" {
  recall --engine rg retry backoff window
  sess=$(printf '%s\n' "$output" | grep -n 'memory/SESSION.md' | head -1 | cut -d: -f1)
  tr=$(printf '%s\n' "$output" | grep -n 'raw/transcripts/s1.md' | head -1 | cut -d: -f1)
  [ -n "$sess" ] && [ -n "$tr" ]
  [ "$sess" -lt "$tr" ]
}

@test "the current repo's .claude-docs are searched every time" {
  recall --engine rg zebra-crossing
  [ "$status" -eq 0 ]
  [[ "$output" == *"## Repo docs"* ]]
  [[ "$output" == *"gotchas.md"* ]]
  [[ "$output" == *"zebra-crossing footgun"* ]]
}

@test "--no-repo skips repo docs" {
  recall --engine rg --no-repo zebra-crossing
  [[ "$output" != *"## Repo docs"* ]]
}

@test "-n and -k both limit the number of hits" {
  recall --engine rg -n 1 retry
  [ "$(printf '%s\n' "$output" | sed -n '/## Memory/,/## Repo docs/p' | grep -c '^### ')" -eq 1 ]
  recall --engine rg -k 1 retry
  [ "$(printf '%s\n' "$output" | sed -n '/## Memory/,/## Repo docs/p' | grep -c '^### ')" -eq 1 ]
}

@test "--here searches only the current project's memory" {
  source "$REPO_ROOT/bin/lib/slug.sh"
  _compute_slug "$PWD"
  mkdir -p "$TEST_CLAUDE_HOME/projects/$slug/memory"
  printf '# Goal\nHERE-ONLY-MARKER retry\n' > "$TEST_CLAUDE_HOME/projects/$slug/memory/SESSION.md"
  recall --here retry
  [ "$status" -eq 0 ]
  [[ "$output" == *"## Memory (this project)"* ]]
  [[ "$output" == *"HERE-ONLY-MARKER"* ]]
  [[ "$output" != *"C--dev-alpha"* ]]
}

@test "a query with no hits is logged to recall-misses.log and journaled" {
  recall --engine rg qqqzzzxxx-nothing
  [ "$status" -eq 0 ]
  [[ "$output" == *"(no hits)"* ]]
  grep -q "qqqzzzxxx-nothing" "$TEST_CLAUDE_HOME/logs/recall-misses.log"
  grep -q '"hook":"Recall","outcome":"empty"' "$TEST_CLAUDE_HOME/debug/hook-diag.jsonl"
}

@test "a query with hits is not logged as a miss" {
  recall --engine rg retry
  [ ! -f "$TEST_CLAUDE_HOME/logs/recall-misses.log" ]
}

@test "empty query is a usage error" {
  recall --engine rg
  [ "$status" -eq 2 ]
}

@test "non-ASCII query words work" {
  printf '# Заметка\nпроверка отката миграции\n' > "$TEST_CLAUDE_HOME/projects/C--dev-beta/memory/SESSION.md"
  recall --engine rg миграции
  [[ "$output" == *"C--dev-beta/memory/SESSION.md"* ]]
}

# --- qmd path, through a stub that records how it was called ---

make_qmd_stub() {
  STUB_DIR="$(mktemp -d)"
  cat > "$STUB_DIR/qmd" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$QMD_STUB_LOG"
case "$1" in
  update) exit 0 ;;
  query)  [[ -n "${QMD_STUB_FAIL_HYBRID:-}" ]] && { echo "Error loading model"; exit 1; } ;;
esac
for a in "$@"; do
  if [[ "$a" == "--files" ]]; then echo "#abc123,0.90,qmd://claude-projects/C--dev-alpha/memory/SESSION.md"; exit 0; fi
done
printf -- '---\n# Goal\n**docid:** `#abc123`\n\n@@ -1,2 @@\nfix the retry backoff window\n'
EOF
  chmod +x "$STUB_DIR/qmd"
  export QMD_STUB_LOG="$STUB_DIR/calls.log"
  export MEMORY_QMD_CMD="$STUB_DIR/qmd"
}

@test "qmd path: uses -n (not -k) and appends file paths" {
  make_qmd_stub
  recall -k 3 retry backoff
  [ "$status" -eq 0 ]
  [[ "$output" == *"engine: qmd BM25"* ]]
  [[ "$output" == *"qmd://claude-projects/C--dev-alpha/memory/SESSION.md"* ]]
  grep -q '^search retry backoff --md -n 3$' "$QMD_STUB_LOG"
  ! grep -q -- ' -k ' "$QMD_STUB_LOG"
  rm -rf "$STUB_DIR"
}

@test "qmd path: -c is passed through" {
  make_qmd_stub
  recall -c claude-l0 retry
  grep -q -- '--md -n 5 -c claude-l0$' "$QMD_STUB_LOG"
  rm -rf "$STUB_DIR"
}

@test "qmd path: hybrid failure falls back to BM25 and says so" {
  make_qmd_stub
  export QMD_STUB_FAIL_HYBRID=1
  recall --hybrid retry
  [ "$status" -eq 0 ]
  [[ "$output" == *"hybrid search failed"* ]]
  [[ "$output" == *"engine: qmd BM25"* ]]
  unset QMD_STUB_FAIL_HYBRID
  rm -rf "$STUB_DIR"
}

@test "qmd path: a stale index is refreshed inline and stamped" {
  make_qmd_stub
  unset RECALL_NO_REFRESH
  recall retry
  [[ "$output" == *"index was stale"* ]]
  grep -q '^update$' "$QMD_STUB_LOG"
  [ -s "$TEST_CLAUDE_HOME/.qmd-last-refresh-done" ]
  # Fresh stamp: no second refresh.
  : > "$QMD_STUB_LOG"
  recall retry
  ! grep -q '^update$' "$QMD_STUB_LOG"
  rm -rf "$STUB_DIR"
}

# --- --timeline ---

seed_timelines() {
  printf '# Project alpha\n\n## Timeline\n\n- 2026-03-10: retry window fix — shipped v1.2\n- 2026-01-05: initial import — done\n' \
    > "$TEST_CLAUDE_HOME/projects/C--dev-alpha/memory/project.md"
  printf '# Project beta\n\n## Timeline\n- 2026-02-20: queue rewrite — merged\nnot a dated line\n' \
    > "$TEST_CLAUDE_HOME/projects/C--dev-beta/memory/project.md"
}

@test "--timeline lists dated lines of every project, newest first" {
  seed_timelines
  recall --timeline
  [ "$status" -eq 0 ]
  [[ "$output" == *"## Timeline (all projects)"* ]]
  first=$(printf '%s\n' "$output" | grep -n '2026-03-10' | cut -d: -f1)
  second=$(printf '%s\n' "$output" | grep -n '2026-02-20' | cut -d: -f1)
  third=$(printf '%s\n' "$output" | grep -n '2026-01-05' | cut -d: -f1)
  [ "$first" -lt "$second" ] && [ "$second" -lt "$third" ]
  [[ "$output" == *"C--dev-beta"*"queue rewrite"* ]]
  [[ "$output" != *"not a dated line"* ]]
}

@test "--timeline filters by query words and honours -n" {
  seed_timelines
  recall --timeline queue
  [[ "$output" == *"queue rewrite"* ]]
  [[ "$output" != *"retry window fix"* ]]
  recall --timeline -n 1
  [ "$(printf '%s\n' "$output" | grep -c '^- \*\*')" -eq 1 ]
  [[ "$output" == *"2026-03-10"* ]]
}

@test "--timeline with nothing to show says so" {
  recall --timeline zzz-nothing
  [ "$status" -eq 0 ]
  [[ "$output" == *"no dated timeline lines"* || "$output" == *"no project.md files"* ]]
}

# --- plain-grep path (no ripgrep on PATH) ---

# A PATH that still has the basic tools but no `rg`.
path_without_rg() {
  local d out=""
  IFS=':' read -r -a _dirs <<< "$PATH"
  for d in "${_dirs[@]}"; do
    [[ -x "$d/rg" || -x "$d/rg.exe" ]] && continue
    out="${out:+$out:}$d"
  done
  printf '%s' "$out"
}

@test "grep path: works when ripgrep is absent (and never uses grep -i -F)" {
  ! grep -nE 'grep [^|;]*-i [^|;]*-F|grep [^|;]*-F [^|;]*-i' "$REPO_ROOT/bin/recall.sh"
  printf '# Notes\nthe a.b*c token appears here\nAnd Retry Backoff too\n' > "$TEST_CLAUDE_HOME/projects/C--dev-beta/memory/SESSION.md"
  run env PATH="$(path_without_rg)" MEMORY_QMD_CMD=/nonexistent/qmd bash "$REPO_ROOT/bin/recall.sh" retry backoff
  [ "$status" -eq 0 ]
  [[ "$output" == *"engine: grep, literal match"* ]]
  [[ "$output" == *"C--dev-alpha/memory/SESSION.md"* ]]
  # case-insensitive, and regex metacharacters in a term are literal
  run env PATH="$(path_without_rg)" MEMORY_QMD_CMD=/nonexistent/qmd bash "$REPO_ROOT/bin/recall.sh" "a.b*c"
  [[ "$output" == *"C--dev-beta/memory/SESSION.md"* ]]
  [[ "$output" == *"a.b*c token"* ]]
}

@test "--no-memory searches repo docs only" {
  recall --engine rg --no-memory retry
  [ "$status" -eq 0 ]
  [[ "$output" != *"## Memory"* ]]
  [[ "$output" != *"C--dev-alpha"* ]]
  [[ "$output" == *"## Repo docs"* ]]
}
