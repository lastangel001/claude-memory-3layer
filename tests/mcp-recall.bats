#!/usr/bin/env bats
# Tests for bin/mcp-recall.mjs — MCP stdio JSON-RPC protocol smoke.
# Covers the synchronous handlers (initialize, tools/list, get_identity, error
# path) which reply before stdin closes — no qmd needed, so it runs in CI.
# search_memory is async (shells out to qmd) and is exercised manually, not here.

load helpers

setup() {
  command -v node >/dev/null 2>&1 || skip "node not available"
  TEST_HOME="$(mktemp -d)"
  mkdir -p "$TEST_HOME/memory"
  printf 'IDENTITY-MARKER-42\n' > "$TEST_HOME/memory/IDENTITY.md"
}

teardown() {
  [[ -n "${TEST_HOME:-}" && -d "$TEST_HOME" ]] && rm -rf "$TEST_HOME"
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
