# helpers.bash — shared setup for bats tests.
# Tests run FROM THE REPO against the repo's hook/script files (not ~/.claude/).

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Create an isolated CLAUDE_HOME with the shared libs the hooks source.
setup_claude_home() {
  TEST_CLAUDE_HOME="$(mktemp -d)"
  mkdir -p "$TEST_CLAUDE_HOME/bin/lib" "$TEST_CLAUDE_HOME/debug" \
           "$TEST_CLAUDE_HOME/logs" "$TEST_CLAUDE_HOME/projects"
  cp "$REPO_ROOT/bin/lib/"*.sh "$TEST_CLAUDE_HOME/bin/lib/"
  export CLAUDE_HOME="$TEST_CLAUDE_HOME"
}

teardown_claude_home() {
  [[ -n "${TEST_CLAUDE_HOME:-}" && -d "$TEST_CLAUDE_HOME" ]] && rm -rf "$TEST_CLAUDE_HOME"
}

# Slug for a given cwd, same formula the hooks use.
slug_for() {
  # shellcheck source=../bin/lib/slug.sh
  source "$REPO_ROOT/bin/lib/slug.sh"
  _compute_slug "$1"
  printf '%s' "$slug"
}

# Create a SESSION.md for the slug of the given cwd; content from stdin.
make_session() {
  local cwd="$1" s
  s="$(slug_for "$cwd")"
  SESSION_FILE="$TEST_CLAUDE_HOME/projects/$s/memory/SESSION.md"
  mkdir -p "$(dirname "$SESSION_FILE")"
  cat > "$SESSION_FILE"
}

# ISO timestamp N seconds ago (UTC).
iso_ago() {
  local secs="$1"
  date -u -d "@$(( $(date +%s) - secs ))" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null \
    || date -u -r "$(( $(date +%s) - secs ))" '+%Y-%m-%dT%H:%M:%SZ'
}
