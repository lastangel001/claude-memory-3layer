#!/usr/bin/env bats
# Tests for bin/onboard-report.sh — full report renders end-to-end.
# Regression: printf leading-dash crash killed sections 4/6-10 on any repo
# with a .gitignore or Makefile (v6.15.0).

load helpers

setup() {
  FIXTURE="$(mktemp -d)"
  cd "$FIXTURE"
  git init -q
  git config user.email test@test.local
  git config user.name test
  printf 'node_modules/\n' > .gitignore
  printf 'all:\n\ttrue\n' > Makefile
  printf '# Fixture\n' > README.md
  mkdir -p src
  printf 'def main():\n    pass\n' > src/main.py
  git add -A
  git commit -qm "fixture: initial"
}

teardown() {
  cd /
  rm -rf "$FIXTURE"
}

@test "report exits 0 on repo with .gitignore and Makefile" {
  run bash "$REPO_ROOT/bin/onboard-report.sh"
  [ "$status" -eq 0 ]
}

@test "entry-points section lists Makefile (printf-dash regression)" {
  run bash "$REPO_ROOT/bin/onboard-report.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"- Makefile"* ]]
}

@test "config section lists .gitignore (printf-dash regression)" {
  run bash "$REPO_ROOT/bin/onboard-report.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"- .gitignore"* ]]
}

@test "sections after the former crash point render (git history, FIXME)" {
  run bash "$REPO_ROOT/bin/onboard-report.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Recent git history"* ]]
  [[ "$output" == *"fixture: initial"* ]]
}
