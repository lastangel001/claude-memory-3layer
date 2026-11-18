#!/usr/bin/env bats
# Tests for bin/mcp-recall.mjs — MCP stdio JSON-RPC protocol smoke.
# Covers the synchronous handlers (initialize, tools/list, get_identity, error
# path) which reply before stdin closes — no qmd needed, so it runs in CI.
# search_memory is covered through the built-in scan (MEMORY_RECALL_ENGINE=scan)
# and through a slow qmd stub (QMD_BIN) for the reply-after-stdin-close case.

load helpers

setup() {
  command -v node >/dev/null 2>&1 || skip "node not available"
  TEST_HOME="$(mktemp -d)"
  mkdir -p "$TEST_HOME/memory"
  printf 'IDENTITY-MARKER-42\n' > "$TEST_HOME/memory/IDENTITY.md"
}

teardown() {
  [[ -n "${TEST_HOME:-}" && -d "$TEST_HOME" ]] && rm -rf "$TEST_HOME"
  return 0  # skipped test (TEST_HOME unset → && chain exits 1) must not fail here
}

# Feed each argument as one JSON-RPC line; capture the server's stdout.
rpc() {
  printf '%s\n' "$@" | env CLAUDE_HOME="$TEST_HOME" node "$REPO_ROOT/bin/mcp-recall.mjs"
}

@test "initialize returns protocol version + serverInfo" {
  run rpc '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}'
  [ "$status" -eq 0 ]
  [[ "$output" == *'"protocolVersion":"2024-11-05"'* ]]
  [[ "$output" == *'claude-memory-recall'* ]]
}

@test "tools/list exposes search_memory and get_identity" {
  run rpc '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
  [ "$status" -eq 0 ]
  [[ "$output" == *'search_memory'* ]]
  [[ "$output" == *'get_identity'* ]]
}

@test "get_identity returns IDENTITY.md contents" {
  run rpc '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"get_identity","arguments":{}}}'
  [ "$status" -eq 0 ]
  [[ "$output" == *'IDENTITY-MARKER-42'* ]]
  [[ "$output" == *'"isError":false'* ]]
}

@test "get_identity flags a missing IDENTITY.md as an error" {
  rm -f "$TEST_HOME/memory/IDENTITY.md"
  run rpc '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"get_identity","arguments":{}}}'
  [ "$status" -eq 0 ]
  [[ "$output" == *'"isError":true'* ]]
  [[ "$output" == *'not found'* ]]
}

@test "unknown tool yields a JSON-RPC error" {
  run rpc '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"nope","arguments":{}}}'
  [ "$status" -eq 0 ]
  [[ "$output" == *'unknown tool'* ]]
}

@test "malformed JSON frame is ignored, not fatal" {
  run rpc 'this is not json' '{"jsonrpc":"2.0","id":9,"method":"ping","params":{}}'
  [ "$status" -eq 0 ]
  [[ "$output" == *'"id":9'* ]]
}

# --- search_memory ---

seed_memory() {
  mkdir -p "$TEST_HOME/projects/C--dev-alpha/memory/raw/transcripts" "$TEST_HOME/projects/C--dev-beta/memory"
  printf '# Goal\nfix the retry backoff window\n- backoff capped at 250 ms\n' > "$TEST_HOME/projects/C--dev-alpha/memory/SESSION.md"
  printf '# beta\nretry is unused here\n' > "$TEST_HOME/projects/C--dev-beta/memory/project.md"
  printf 'retry retry backoff backoff window window\n' > "$TEST_HOME/projects/C--dev-alpha/memory/raw/transcripts/s1.md"
  printf '{}\n' > "$TEST_HOME/projects/C--dev-alpha/not-memory.jsonl"
}

search() {  # $1 = query; runs with the built-in scan from the current directory
  printf '%s\n' "{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"tools/call\",\"params\":{\"name\":\"search_memory\",\"arguments\":{\"query\":\"$1\"}}}" \
    | env CLAUDE_HOME="$TEST_HOME" MEMORY_RECALL_ENGINE=scan node "$REPO_ROOT/bin/mcp-recall.mjs"
}

@test "search_memory works without qmd (built-in scan) and ranks by distinct terms" {
  seed_memory
  cd "$TEST_HOME"
  run search "retry backoff window"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"isError":false'* ]]
  [[ "$output" == *"C--dev-alpha/memory/SESSION.md"* ]]
  [[ "$output" == *"built-in literal scan"* ]]
  # all three words (alpha) before one word (beta); curated before transcripts
  a="${output%%C--dev-alpha/memory/SESSION.md*}"
  b="${output%%C--dev-beta/memory/project.md*}"
  tr="${output%%raw/transcripts/s1.md*}"
  [ "${#a}" -lt "${#b}" ]
  [ "${#a}" -lt "${#tr}" ]
}

@test "search_memory also searches the current repo's .claude-docs" {
  seed_memory
  repo="$(mktemp -d)"
  mkdir -p "$repo/.claude-docs"
  printf '# Gotchas\n## zebra-crossing footgun\n' > "$repo/.claude-docs/gotchas.md"
  cd "$repo"
  run search "zebra-crossing"
  [ "$status" -eq 0 ]
  [[ "$output" == *"## Repo docs"* ]]
  [[ "$output" == *"zebra-crossing footgun"* ]]
  cd / && rm -rf "$repo"
}

@test "search_memory with no hits says so and is not an error" {
  seed_memory
  cd "$TEST_HOME"
  run search "qqqzzz-nothing"
  [[ "$output" == *"(no hits)"* ]]
  [[ "$output" == *'"isError":false'* ]]
}

@test "a reply still pending when stdin closes is delivered" {
  seed_memory
  stub="$TEST_HOME/slow-qmd.js"
  cat > "$stub" <<'EOF'
setTimeout(() => { console.log("---\n# Goal\n**docid:** `#abc`\nSLOW-QMD-ANSWER"); }, 400);
EOF
  cd "$TEST_HOME"
  run bash -c "printf '%s\n' '{\"jsonrpc\":\"2.0\",\"id\":8,\"method\":\"tools/call\",\"params\":{\"name\":\"search_memory\",\"arguments\":{\"query\":\"retry\"}}}' | env CLAUDE_HOME='$TEST_HOME' QMD_BIN='$stub' node '$REPO_ROOT/bin/mcp-recall.mjs'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SLOW-QMD-ANSWER"* ]]
  [[ "$output" == *"engine: qmd BM25"* ]]
}
