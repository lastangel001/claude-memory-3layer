#!/usr/bin/env node
// bin/mcp-recall.mjs — minimal MCP server exposing memory search to agents.
//
// Why: /recall is a slash command — subagents, task runners and headless mode
// cannot call slash commands. An MCP tool is callable inside any agentic loop.
//
// Tools:
//   search_memory(query, limit?, collection?) -> qmd BM25 hits (markdown)
//   get_identity()                            -> contents of IDENTITY.md (L0)
//
// Zero dependencies: newline-delimited JSON-RPC over stdio (MCP stdio
// transport), shells out to `qmd search`. No new storage layer.
//
// Register (user scope, all projects):
//   claude mcp add --scope user memory-recall -- node ~/.claude/bin/mcp-recall.mjs

import { execFile } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { delimiter, join } from "node:path";
import { createInterface } from "node:readline";

const CLAUDE_HOME = process.env.CLAUDE_HOME || join(homedir(), ".claude");
const PROTOCOL_VERSION = "2024-11-05";

// How to invoke qmd. On Windows the PATH entry is an npm shim (`qmd` + `qmd.cmd`),
// not a real exe: Node's execFile can't spawn a bare `qmd` (ENOENT), and running
// the `.cmd` needs a shell — unsafe with a free-text query. So on Windows we find
// qmd's JS entry beside the shim and run it with our own node (no shell, argv
// stays safe). Returns { file, prefix } → execFile(file, [...prefix, ...args]).
function resolveQmd() {
  const override = process.env.QMD_BIN;
  if (override) {
    // A JS script → run via node; a real binary (.exe/.cmd/…) → run directly.
    if (existsSync(override) && !/\.(exe|cmd|bat|ps1)$/i.test(override)) {
      return { file: process.execPath, prefix: [override] };
    }
    return { file: override, prefix: [] };
  }
  if (process.platform !== "win32") return { file: "qmd", prefix: [] };
  const dirs = (process.env.PATH || process.env.Path || "").split(delimiter);
  for (const dir of dirs) {
    if (!dir) continue;
    if (existsSync(join(dir, "qmd.cmd")) || existsSync(join(dir, "qmd"))) {
      const entry = join(dir, "node_modules", "@tobilu", "qmd", "bin", "qmd");
      if (existsSync(entry)) return { file: process.execPath, prefix: [entry] };
    }
    const exe = join(dir, "qmd.exe");
    if (existsSync(exe)) return { file: exe, prefix: [] };
  }
  return { file: "qmd", prefix: [] }; // let it ENOENT with the helpful hint below
}

const QMD = resolveQmd();

const TOOLS = [
  {
    name: "search_memory",
    description:
      "Full-text (BM25) search across the 3-layer Claude memory: L0 identity, " +
      "L1-fallback project notes, L2 session files. Returns ranked snippets with file paths. " +
      "Use for: 'did we already hit this gotcha?', past decisions, prior project context.",
    inputSchema: {
      type: "object",
      properties: {
        query: { type: "string", description: "Free-form search query" },
        limit: { type: "number", description: "Max hits (default 5)" },
        collection: {
          type: "string",
          description: "Optional qmd collection scope, e.g. 'claude-l0' or 'claude-projects'",
        },
      },
      required: ["query"],
    },
  },
  {
    name: "get_identity",
    description:
      "Return the L0 identity file (~/.claude/memory/IDENTITY.md): who the user is, " +
      "hard preferences, environment-wide credentials pointers.",
    inputSchema: { type: "object", properties: {} },
  },
];

function reply(id, result) {
  process.stdout.write(JSON.stringify({ jsonrpc: "2.0", id, result }) + "\n");
}

function replyError(id, code, message) {
  process.stdout.write(
    JSON.stringify({ jsonrpc: "2.0", id, error: { code, message } }) + "\n",
  );
}

function toolText(text, isError = false) {
  return { content: [{ type: "text", text }], isError };
}

function searchMemory(args, done) {
  const query = String(args.query || "").trim();
  if (!query) return done(toolText("search_memory: empty query", true));
  const limit = Number.isFinite(args.limit) ? Math.max(1, Math.min(50, args.limit)) : 5;
  const argv = ["search", query, "--md", "-k", String(limit)];
  if (args.collection) argv.push("-c", String(args.collection));
  execFile(QMD.file, [...QMD.prefix, ...argv], { timeout: 30000, maxBuffer: 4 * 1024 * 1024 }, (err, stdout, stderr) => {
    if (err) {
      const hint =
        err.code === "ENOENT"
          ? "qmd not found on PATH — install it (see INSTALL.md) or add its npm dir to PATH."
          : (stderr || err.message || "qmd search failed").trim();
      return done(toolText(`search_memory error: ${hint}`, true));
    }
    done(toolText(stdout.trim() || "(no hits)"));
  });
}

function getIdentity(done) {
  try {
    done(toolText(readFileSync(join(CLAUDE_HOME, "memory", "IDENTITY.md"), "utf8")));
  } catch {
    done(toolText("IDENTITY.md not found — L0 not initialized (run install.sh).", true));
  }
}

function handle(msg) {
  const { id, method, params } = msg;
  switch (method) {
    case "initialize":
      return reply(id, {
        protocolVersion: PROTOCOL_VERSION,
        capabilities: { tools: {} },
        serverInfo: { name: "claude-memory-recall", version: "1.0.0" },
      });
    case "notifications/initialized":
    case "notifications/cancelled":
      return; // notifications get no response
    case "ping":
      return reply(id, {});
    case "tools/list":
      return reply(id, { tools: TOOLS });
    case "tools/call": {
      const name = params?.name;
      const args = params?.arguments || {};
      if (name === "search_memory") return searchMemory(args, (r) => reply(id, r));
      if (name === "get_identity") return getIdentity((r) => reply(id, r));
      return replyError(id, -32602, `unknown tool: ${name}`);
    }
    default:
      if (id !== undefined) replyError(id, -32601, `method not found: ${method}`);
  }
}

const rl = createInterface({ input: process.stdin });
rl.on("line", (line) => {
  if (!line.trim()) return;
  let msg;
  try {
    msg = JSON.parse(line);
  } catch {
    return; // ignore malformed frames
  }
  try {
    handle(msg);
  } catch (e) {
    if (msg?.id !== undefined) replyError(msg.id, -32603, String(e?.message || e));
  }
});
rl.on("close", () => process.exit(0));
