#!/usr/bin/env bats
# Tests for bin/codemap.sh against a tiny fixture repo. Would have caught the
# dead `grep -F "^sym\t"` lookup (command ran fine, returned nothing).
# Skips cleanly when ctags/ripgrep are not installed (optional tools).

load helpers

setup() {
  command -v ctags >/dev/null 2>&1 || skip "ctags not installed"
  command -v rg    >/dev/null 2>&1 || skip "ripgrep not installed"
  FIX="$(mktemp -d)"
  cat > "$FIX/lib.py" <<'PY'
def my_special_func(x):
    return x + 1
PY
  cat > "$FIX/app.py" <<'PY'
from lib import my_special_func

def run():
    return my_special_func(41)
PY
  cd "$FIX"
}

teardown() {
  cd /
  [[ -n "${FIX:-}" ]] && rm -rf "$FIX"
  return 0  # never let a skipped test (FIX unset → && chain exits 1) fail here
}

@test "codemap def locates a symbol definition" {
  run bash "$REPO_ROOT/bin/codemap.sh" def my_special_func
  [ "$status" -eq 0 ]
  [[ "$output" == *"lib.py"* ]]
}

@test "codemap def returns nothing for an unknown symbol (no crash)" {
  run bash "$REPO_ROOT/bin/codemap.sh" def does_not_exist_symbol
  [ "$status" -eq 0 ]
  [[ "$output" != *"lib.py"* ]]
}

@test "codemap outline lists defined symbols" {
  run bash "$REPO_ROOT/bin/codemap.sh" outline
  [ "$status" -eq 0 ]
  [[ "$output" == *"my_special_func"* ]]
}

@test "codemap callers finds the call site, excludes the definition" {
  run bash "$REPO_ROOT/bin/codemap.sh" callers my_special_func
  [ "$status" -eq 0 ]
  [[ "$output" == *"app.py"* ]]
}

@test "codemap refresh rebuilds the tags file" {
  run bash "$REPO_ROOT/bin/codemap.sh" refresh
  [ "$status" -eq 0 ]
  [[ "$output" == *"Rebuilt"* ]]
  [ -f "$FIX/.codemap.tags" ]
}
