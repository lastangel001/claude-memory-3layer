#!/usr/bin/env bats
# Tests for bin/vault-doctor.sh — memory content health: IDENTITY size,
# SESSION oversize + staleness, and the --fix stale-session wipe.

load helpers

setup() {
  TEST_HOME="$(mktemp -d)"
  mkdir -p "$TEST_HOME/memory" "$TEST_HOME/projects"
  printf 'one line identity\n' > "$TEST_HOME/memory/IDENTITY.md"
  # Neutral cwd with no .claude-docs so the repo-docs section is skipped.
  WORK_DIR="$(mktemp -d)"
  cd "$WORK_DIR"
}

teardown() {
  cd /
  rm -rf "$WORK_DIR" "$TEST_HOME"
}

mk_session() {  # $1=slug  $2=last_updated  $3=extra-bytes
  local d="$TEST_HOME/projects/$1/memory"
  mkdir -p "$d"
  {
    printf -- '---\nlast_updated: %s\ncwd: C:/some/%s\n---\n# Goal\nx\n' "$2" "$1"
    [[ -n "${3:-}" ]] && head -c "$3" /dev/zero | tr '\0' 'y'
  } > "$d/SESSION.md"
  printf '%s' "$d/SESSION.md"
}

@test "vault-doctor passes when memory is healthy (exit 0)" {
  mk_session "C--fresh" "$(iso_ago 3600)" >/dev/null
  run env CLAUDE_HOME="$TEST_HOME" bash "$REPO_ROOT/bin/vault-doctor.sh"
  [ "$status" -eq 0 ]
}

@test "vault-doctor warns on IDENTITY.md over the 25-line cap" {
  seq 1 40 > "$TEST_HOME/memory/IDENTITY.md"
  run env CLAUDE_HOME="$TEST_HOME" bash "$REPO_ROOT/bin/vault-doctor.sh"
  [[ "$output" == *"over"*"line cap"* ]]
}

@test "vault-doctor flags a stale session but does not wipe without --fix" {
  sf="$(mk_session "C--stale" "$(iso_ago $((40*86400)))")"
  run env CLAUDE_HOME="$TEST_HOME" bash "$REPO_ROOT/bin/vault-doctor.sh"
  [[ "$output" == *"stale"* ]]
  # Original goal still present (not wiped).
  grep -q '# Goal' "$sf"
  ! grep -q 'wiped by vault-doctor' "$sf"
}

@test "vault-doctor --fix wipes a stale session and keeps its cwd" {
  sf="$(mk_session "C--stale2" "$(iso_ago $((40*86400)))")"
  run env CLAUDE_HOME="$TEST_HOME" bash "$REPO_ROOT/bin/vault-doctor.sh" --fix
  [ "$status" -eq 0 ]
  grep -q 'wiped by vault-doctor' "$sf"
  grep -q 'cwd: C:/some/C--stale2' "$sf"
  ls "$sf".bak-* >/dev/null
}

@test "vault-doctor leaves a fresh session untouched under --fix" {
  sf="$(mk_session "C--fresh2" "$(iso_ago 3600)")"
  run env CLAUDE_HOME="$TEST_HOME" bash "$REPO_ROOT/bin/vault-doctor.sh" --fix
  [ "$status" -eq 0 ]
  ! grep -q 'wiped by vault-doctor' "$sf"
}

@test "vault-doctor does not call a closed (status: done) session stale" {
  d="$TEST_HOME/projects/C--closed/memory"
  mkdir -p "$d"
  printf -- '---\nlast_updated: %s\ncwd: C:/some/closed\nstatus: done\n---\n# Goal\n(none)\n' \
    "$(iso_ago $((90*86400)))" > "$d/SESSION.md"
  run env CLAUDE_HOME="$TEST_HOME" bash "$REPO_ROOT/bin/vault-doctor.sh" --fix
  [ "$status" -eq 0 ]
  [[ "$output" != *"C--closed"* ]]
  ! ls "$d"/SESSION.md.bak-* >/dev/null 2>&1
}

@test "vault-doctor fails on a dead link in the repo CLAUDE.md doc index" {
  mkdir -p "$WORK_DIR/.claude-docs"
  printf -- '---\ndescription: g\n---\n# Gotchas\n' > "$WORK_DIR/.claude-docs/gotchas.md"
  printf '# Repo\n\n| Task | Read |\n|---|---|\n| a | [g](.claude-docs/gotchas.md) |\n| b | [x](.claude-docs/architecture.md) |\n' \
    > "$WORK_DIR/CLAUDE.md"
  run env CLAUDE_HOME="$TEST_HOME" bash "$REPO_ROOT/bin/vault-doctor.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"CLAUDE.md: broken link"*"architecture.md"* ]]
  [[ "$output" != *"gotchas.md (target file missing)"* ]]
}

@test "vault-doctor passes when every CLAUDE.md doc-index link resolves" {
  mkdir -p "$WORK_DIR/.claude-docs"
  printf -- '---\ndescription: g\n---\n# Gotchas\n' > "$WORK_DIR/.claude-docs/gotchas.md"
  printf '# Repo\n\n[g](.claude-docs/gotchas.md) and [site](https://example.invalid/x.md)\n' > "$WORK_DIR/CLAUDE.md"
  run env CLAUDE_HOME="$TEST_HOME" bash "$REPO_ROOT/bin/vault-doctor.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"All relative links resolve"* ]]
}

# --- citations (src: path#symbol @ sha) ---

# A git repo in WORK_DIR with src/a.sh committed; prints the commit's short sha.
make_repo_with_code() {
  git init -q . 2>/dev/null
  mkdir -p src .claude-docs
  printf 'retry_window() { echo 250; }\n' > src/a.sh
  git add src/a.sh
  git -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false commit -q -m "add a.sh"
  git rev-parse --short HEAD
}

touch_code() {  # $1 = how many more commits change src/a.sh
  local i
  for i in $(seq 1 "$1"); do
    printf '# change %s\n' "$i" >> src/a.sh
    git -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false commit -q -am "change $i"
  done
}

gotcha_with() {  # $1 = the src: line
  printf -- '---\ndescription: g\n---\n# Gotchas\n\n## Retry window\nconfidence: verified\n%s\n\nThe window is 250 ms.\n' "$1" \
    > .claude-docs/gotchas.md
}

@test "citation: existing file + symbol at a recent commit is current" {
  sha="$(make_repo_with_code)"
  gotcha_with "src: src/a.sh#retry_window @ $sha"
  run env CLAUDE_HOME="$TEST_HOME" bash "$REPO_ROOT/bin/vault-doctor.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Citations: 1 checked, all current"* ]]
}

@test "citation: a cited file that is gone is flagged" {
  sha="$(make_repo_with_code)"
  gotcha_with "src: src/removed.sh#thing @ $sha"
  run env CLAUDE_HOME="$TEST_HOME" bash "$REPO_ROOT/bin/vault-doctor.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"cited file is gone"*"src/removed.sh"* ]]
  [[ "$output" == *"1 of 1 need re-verification"* ]]
}

@test "citation: a cited symbol that is no longer in the file is flagged" {
  sha="$(make_repo_with_code)"
  gotcha_with "src: src/a.sh#old_function_name @ $sha"
  run env CLAUDE_HOME="$TEST_HOME" bash "$REPO_ROOT/bin/vault-doctor.sh"
  [[ "$output" == *"cited symbol 'old_function_name' is no longer in src/a.sh"* ]]
}

@test "citation: file changed in N commits since the cited one is flagged" {
  sha="$(make_repo_with_code)"
  touch_code 3
  gotcha_with "src: src/a.sh#retry_window @ $sha"
  run env CLAUDE_HOME="$TEST_HOME" VAULT_CITE_COMMITS=3 bash "$REPO_ROOT/bin/vault-doctor.sh"
  [[ "$output" == *"src/a.sh changed in 3 commits since $sha"* ]]
  # Below the threshold it is still current.
  run env CLAUDE_HOME="$TEST_HOME" VAULT_CITE_COMMITS=4 bash "$REPO_ROOT/bin/vault-doctor.sh"
  [[ "$output" == *"Citations: 1 checked, all current"* ]]
}

@test "citation: several per line, backticks tolerated, file-only form accepted" {
  sha="$(make_repo_with_code)"
  gotcha_with "src: \`src/a.sh#retry_window\` @ $sha, src/a.sh"
  run env CLAUDE_HOME="$TEST_HOME" bash "$REPO_ROOT/bin/vault-doctor.sh"
  [[ "$output" == *"Citations: 2 checked, all current"* ]]
}

@test "citation: an unknown commit is flagged" {
  make_repo_with_code >/dev/null
  gotcha_with "src: src/a.sh @ deadbee"
  run env CLAUDE_HOME="$TEST_HOME" bash "$REPO_ROOT/bin/vault-doctor.sh"
  [[ "$output" == *"cited commit deadbee is not in this repository"* ]]
}

@test "citation: src: lines inside a fenced code block are examples, not citations" {
  make_repo_with_code >/dev/null
  printf -- '---\ndescription: g\n---\n# Format\n\n```\nsrc: no/such/file.sh#x @ abc1234\n```\n' > .claude-docs/gotchas.md
  run env CLAUDE_HOME="$TEST_HOME" bash "$REPO_ROOT/bin/vault-doctor.sh"
  [ "$status" -eq 0 ]
  [[ "$output" != *"cited file is gone"* ]]
  [[ "$output" != *"Citations:"* ]]
}

# --- L1a diet ---

@test "diet: an over-long CLAUDE.md is flagged" {
  mkdir -p .claude-docs
  printf -- '---\ndescription: g\n---\n# G\n' > .claude-docs/gotchas.md
  { printf '# Repo\n'; seq 1 250 | sed 's/^/- rule /'; } > CLAUDE.md
  run env CLAUDE_HOME="$TEST_HOME" bash "$REPO_ROOT/bin/vault-doctor.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"CLAUDE.md is 251 lines"* ]]
}

@test "diet: README prose copied into CLAUDE.md is flagged" {
  mkdir -p .claude-docs
  printf -- '---\ndescription: g\n---\n# G\n' > .claude-docs/gotchas.md
  for i in 1 2 3 4 5 6; do
    printf 'This is overview sentence number %s and it is comfortably longer than sixty characters.\n' "$i"
  done > README.md
  { printf '# Repo\n'; cat README.md; } > CLAUDE.md
  run env CLAUDE_HOME="$TEST_HOME" bash "$REPO_ROOT/bin/vault-doctor.sh"
  [[ "$output" == *"CLAUDE.md repeats 6 long lines of README.md"* ]]
}

@test "diet: a thin CLAUDE.md raises nothing" {
  mkdir -p .claude-docs
  printf -- '---\ndescription: g\n---\n# G\n' > .claude-docs/gotchas.md
  printf '# Repo\n- run make test\n' > CLAUDE.md
  printf '# Project\nA completely different and reasonably long sentence about the project lives in here.\n' > README.md
  run env CLAUDE_HOME="$TEST_HOME" bash "$REPO_ROOT/bin/vault-doctor.sh"
  [[ "$output" != *"CLAUDE.md is"* ]]
  [[ "$output" != *"CLAUDE.md repeats"* ]]
}

@test "vault-doctor warns on oversize SESSION.md" {
  mk_session "C--big" "$(iso_ago 3600)" 9000 >/dev/null
  run env CLAUDE_HOME="$TEST_HOME" bash "$REPO_ROOT/bin/vault-doctor.sh"
  [[ "$output" == *"SESSION.md"*"prune"* ]]
}
