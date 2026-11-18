#!/usr/bin/env node
// bin/mcp-recall.mjs — minimal MCP server exposing memory search to agents.
//
// Why: /recall is a slash command — subagents, task runners and headless mode
// cannot call slash commands. An MCP tool is callable inside any agentic loop.
//
// Tools:
//   search_memory(query, limit?, collection?) -> ranked hits (markdown): qmd BM25 when
//                                                qmd is installed, a built-in literal
//                                                scan otherwise; plus the current
//                                                repo's .claude-docs / CLAUDE.md
//   get_identity()                            -> contents of IDENTITY.md (L0)
//
// Zero dependencies: newline-delimited JSON-RPC over stdio (MCP stdio
// transport). Shells out to `qmd search` when qmd is installed; otherwise scans
// the memory files itself (same ranking idea as bin/recall.sh). No new storage
// layer. MEMORY_RECALL_ENGINE=scan forces the built-in scan.
//
// Register (user scope, all projects):
//   claude mcp add --scope user memory-recall -- node ~/.claude/bin/mcp-recall.mjs

import { execFile } from "node:child_process";
import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
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
      "Search the 3-layer Claude memory (L0 identity, L1-fallback project notes, L2 session " +
      "files) and the current repo's .claude-docs / CLAUDE.md. Works with or without qmd. " +
      "Returns ranked snippets with file paths. " +
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

// ---- Built-in scan -----------------------------------------------------------
// Used when qmd is not installed, and for the current repo's docs in every case
// (qmd does not index a repo's .claude-docs unless a collection was registered).

const MAX_FILE_BYTES = 2 * 1024 * 1024;

function listMarkdown(dir, depth, out) {
  if (depth < 0) return out;
  let entries;
  try {
    entries = readdirSync(dir, { withFileTypes: true });
  } catch {
    return out;
  }
  for (const e of entries) {
    const p = join(dir, e.name);
    if (e.isDirectory()) listMarkdown(p, depth - 1, out);
    else if (e.isFile() && e.name.toLowerCase().endsWith(".md")) out.push(p);
  }
  return out;
}

function memoryFiles() {
  const out = listMarkdown(join(CLAUDE_HOME, "memory"), 2, []);
  let projects = [];
  try {
    projects = readdirSync(join(CLAUDE_HOME, "projects"), { withFileTypes: true });
  } catch {
    /* no projects yet */
  }
  // Only <project>/memory/** — the project directories also hold transcripts
  // (.jsonl) and other files that are not memory.
  for (const p of projects) {
    if (p.isDirectory()) listMarkdown(join(CLAUDE_HOME, "projects", p.name, "memory"), 4, out);
  }
  return out;
}

function repoDocFiles() {
  const cwd = process.cwd();
  const out = listMarkdown(join(cwd, ".claude-docs"), 2, []);
  for (const f of ["CLAUDE.md", "AGENTS.md"]) {
    if (existsSync(join(cwd, f))) out.push(join(cwd, f));
  }
  return out;
}

// Rank files by literal, case-insensitive matches: 1000 per distinct term found
// + total occurrences (capped) — a file with every query word beats one that
// repeats a single word. Curated memory is listed before verbatim transcripts.
function scan(files, query, limit) {
  const terms = query
    .split(/\s+/)
    .filter((t) => t.length >= 2)
    .map((t) => t.toLowerCase());
  if (!terms.length) terms.push(query.toLowerCase());
  const hits = [];
  for (const file of files) {
    let text;
    try {
      if (statSync(file).size > MAX_FILE_BYTES) continue;
      text = readFileSync(file, "utf8");
    } catch {
      continue;
    }
    const lower = text.toLowerCase();
    let distinct = 0;
    let total = 0;
    for (const t of terms) {
      const n = lower.split(t).length - 1;
      if (n > 0) {
        distinct++;
        total += Math.min(n, 50);
      }
    }
    if (!distinct) continue;
    const lines = [];
    const src = text.split(/\r?\n/);
    for (let i = 0; i < src.length && lines.length < 3; i++) {
      const l = src[i].toLowerCase();
      if (terms.some((t) => l.includes(t))) lines.push(`    ${i + 1}:${src[i].slice(0, 240)}`);
    }
    hits.push({
      file: file.replace(/\\/g, "/"),
      score: distinct * 1000 + total,
      transcript: /[\\/]raw[\\/]transcripts[\\/]/.test(file),
      lines,
    });
  }
  hits.sort((a, b) => Number(a.transcript) - Number(b.transcript) || b.score - a.score || a.file.localeCompare(b.file));
  return hits.slice(0, limit).map((h) => `### ${h.file}\n${h.lines.join("\n")}`);
}

function repoDocsSection(query, limit) {
  const files = repoDocFiles();
  if (!files.length) return "";
  const found = scan(files, query, limit);
  return `\n\n## Repo docs (${process.cwd().replace(/\\/g, "/")})\n\n${found.length ? found.join("\n\n") : "(no hits)"}`;
}

function scanSection(query, limit) {
  const found = scan(memoryFiles(), query, limit);
  return (
    `## Memory\n\n${found.length ? found.join("\n\n") : "(no hits)"}\n\n` +
    "_(engine: built-in literal scan — install qmd for ranked BM25)_"
  );
}

// Can qmd be started at all? Decided synchronously, so that without qmd the
// answer does not depend on a child process failing first.
function qmdAvailable() {
  if (process.env.MEMORY_RECALL_ENGINE === "scan") return false;
  if (QMD.file !== "qmd") return existsSync(QMD.file) && QMD.prefix.every((p) => existsSync(p));
  const dirs = (process.env.PATH || process.env.Path || "").split(delimiter);
  return dirs.some((d) => d && (existsSync(join(d, "qmd")) || existsSync(join(d, "qmd.exe"))));
}

function searchMemory(args, done) {
  const query = String(args.query || "").trim();
  if (!query) return done(toolText("search_memory: empty query", true));
  const limit = Number.isFinite(args.limit) ? Math.max(1, Math.min(50, args.limit)) : 5;
  const repo = repoDocsSection(query, limit);
  if (!qmdAvailable()) return done(toolText(scanSection(query, limit) + repo));
  // `-n`, not `-k`: qmd ignores unknown flags, so `-k` silently returned the default 5.
  const argv = ["search", query, "--md", "-n", String(limit)];
  if (args.collection) argv.push("-c", String(args.collection));
  execFile(QMD.file, [...QMD.prefix, ...argv], { timeout: 30000, maxBuffer: 4 * 1024 * 1024 }, (err, stdout, stderr) => {
    if (err) {
      // qmd is there but did not answer — the scan still can.
      const why = (err.code === "ENOENT" ? "qmd could not be started" : stderr || err.message || "qmd search failed").trim();
      return done(toolText(`_(qmd failed: ${why.split("\n")[0]} — built-in scan used)_\n\n` + scanSection(query, limit) + repo));
    }
    done(toolText(`## Memory\n\n${stdout.trim() || "(no hits)"}\n\n_(engine: qmd BM25)_` + repo));
  });
}

function getIdentity(done) {
  try {
    done(toolText(readFileSync(join(CLAUDE_HOME, "memory", "IDENTITY.md"), "utf8")));
  } catch {
    done(toolText("IDENTITY.md not found — L0 not initialized (run install.sh).", true));
  }
}

// A reply may still be on its way when stdin closes (qmd is a child process):
// exit only when the input is closed AND nothing is pending.
let pending = 0;
let closed = false;

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
      if (name === "search_memory") {
        pending++;
        return searchMemory(args, (r) => {
          reply(id, r);
          pending--;
          if (closed && pending === 0) process.exit(0);
        });
      }
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
rl.on("close", () => {
  closed = true;
  if (pending === 0) process.exit(0);
});
