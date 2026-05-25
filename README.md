# claude-memory-3layer

> Hand-curated, in-repo memory for Claude Code. Three layers, deliberate placement, zero auto-capture. With hybrid retrieval (qmd) and on-demand symbol map (ctags). 100% local.

A replacement for Claude Code's default memory system, battle-tested on ~15 real projects (PHP/mpcmf, Python, TS, reverse-engineering, multi-machine setups).

## Why

After trying the popular options:
- **[CodeGraph](https://github.com/colbymchenry/codegraph)** — code knowledge graph. Live MCP-transport bug at the time of evaluation; correctness bug in module-qualified symbol lookup (silently picks random collisions).
- **[AgentMemory](https://github.com/rohitg00/agentmemory)** — persistent memory via MCP. Issue #522: *"Sessions never created and silent data loss"*. Philosophically opposite to what a coding agent needs (auto-capture vector blob vs explicit curated knowledge).

This system is what crystallized as the alternative: **what you write down, you own. What you don't write down, doesn't exist.** No vector blobs, no auto-capture, no daemons, no MCP servers. Just markdown + a tiny set of tools.

## Design principle

> *"Would a server agent at midnight, with no memory and no human, need this?"*
> — **yes** → put it in the repo (git-tracked, travels with code)
> — **no** → put it in account-local memory (`~/.claude/...`)

Codebase facts go with the codebase. Personal preferences and per-task scratch stay account-local. Don't cross the wires.

## Architecture — three layers, different decay rates

| Layer | Path | Git? | Decay |
|---|---|---|---|
| **L0 Identity** | `~/.claude/memory/IDENTITY.md` | no | permanent (≤25 lines) |
| **L1a Repo entry** | `<repo>/CLAUDE.md` | **yes** | per-project; thin, auto-loaded |
| **L1b Repo docs** | `<repo>/.claude-docs/*.md` | **yes** | per-project; thick, lazy-loaded |
| **L1 fallback** | `~/.claude/projects/<slug>/memory/project.md` | no | for repos where in-repo isn't appropriate |
| **L2 Session** | `~/.claude/projects/<slug>/memory/SESSION.md` | no | per-task; dies when task ends |

`<repo>/CLAUDE.md` is loaded into every session by Claude Code automatically — keep it **thin**. Bulky knowledge lives in `<repo>/.claude-docs/*.md` and is read on demand via the doc index in `CLAUDE.md`.

The killer move is **`<repo>/.claude-docs/gotchas.md`** — every non-obvious footgun goes here. *"Looks right but breaks"* / *"Looks wrong but is intentional"*. One paragraph each. Future sessions hit the same wall and benefit immediately.

## Tools (all local, no daemons)

### `/recall <query>` — hybrid memory search

BM25 + GGUF embeddings + LLM rerank over all your memory files. Backed by [qmd](https://github.com/tobi/qmd) (Tobi Lütke).

```
/recall MongoDB legacy driver mpcmf
/recall гочи WSL DNS IPv6
/recall --here armenia weekly window     # scope to current project
```

### `/codemap def|callers|callees|outline <symbol>` — on-demand symbol map

universal-ctags + ripgrep. Cache at `<repo>/.codemap.tags` (gitignore-able). Auto-rebuilds when source files are newer.

```
/codemap def LlmClient::chat
/codemap callers AgentExecutor
/codemap outline
```

### `/memory status | auto on|off | refresh` — protocol controls

Default mode is **explicit-promotion** — cross-session memory only when the user says "remember"/"запомни". Toggle to auto-capture per-session if you want it.

## Hooks (enforce discipline)

- **SessionStart** — injects protocol reminder + three active checks:
  - *Staleness* — `SESSION.md` >24h old → forces explicit *"continue or reset?"* with user
  - *CWD mismatch* — reads `cwd:` from `SESSION.md` frontmatter; if it doesn't match current project directory, injects a hard reset warning so the agent doesn't continue the wrong task silently
  - *Privacy redaction* — strips `<private>...</private>` blocks from `SESSION.md` in-place before injecting context (backup at `SESSION.md.bak`)
  - Also kicks background `qmd update` debounced 6h
- **PreCompact** — reminds Claude to flush working state to `SESSION.md` before compaction wipes context. Enforces three write rules: privacy (strip `<private>` tags), compression (write terse caveman prose), and CWD (ensure `cwd:` frontmatter is current). `SESSION.md` is the only artifact that survives compaction with full fidelity.

### SESSION.md compression

By default, `SESSION.md` is written in compressed caveman notation (drop articles/filler, fragments OK, code/paths exact). SESSION is read by agents, not humans — terseness reduces context cost on every reload and compact.

**Toggle:**

```bash
touch ~/.claude/.session-compress-disabled   # disable permanently
rm ~/.claude/.session-compress-disabled      # re-enable
CLAUDE_SESSION_COMPRESS=0 claude             # disable for one session
```

Both hooks read the flag on every fire — no restart needed. When disabled, the model is instructed to write prose naturally.

### Privacy: `<private>` tags

Wrap transient secrets inside `<private>...</private>` in any message or note:

```
OAuth token was <private>sk-ant-abc123</private> — stored in env ANTHROPIC_API_KEY.
```

The SessionStart hook strips all `<private>` blocks from `SESSION.md` in-place before the content reaches model context. PreCompact instructs the model to strip tags before writing. Defense-in-depth: even if tagged content slips through, it is removed at the next session boundary. **Never write raw secrets to memory files** — write the env-var name or path instead.

## What's deliberately NOT in it

- ✗ **Auto-capture** of arbitrary tool output into memory — that's exactly the failure mode `AgentMemory` documents in their open issues (silent data loss, runaway logs).
- ✗ **MCP server with 50+ tools** — context-window tax in every request, whether you use those tools or not.
- ✗ **Persistent code-graph daemon** with per-project SQLite — `/codemap` is on-demand instead. Re-scan in ~1s for medium repos.
- ✗ **Vector blob** you can't `diff`. Memory is markdown you can read with your eyes.
- ✗ **Cloud, OpenAI keys, embedding APIs** — qmd uses local GGUF models (embeddinggemma-300M, qwen3-reranker, qmd-query-expansion).

## Quick start

See [INSTALL.md](INSTALL.md) for full instructions across Windows / macOS / Linux. TL;DR:

```bash
# 1. Drop CLAUDE.md, hooks, commands, bin/, templates into ~/.claude/
# 2. Merge settings.snippet.json into ~/.claude/settings.json
# 3. Edit ~/.claude/memory/IDENTITY.md (≤25 lines, who you are)
# 4. For retrieval tools (optional, recommended):
winget install OpenJS.NodeJS.LTS UniversalCtags.Ctags BurntSushi.ripgrep.MSVC
npm install -g @tobilu/qmd
qmd collection add ~/.claude/memory --name claude-l0
qmd collection add ~/.claude/projects --name claude-projects
QMD_LLAMA_GPU=none qmd embed   # one-time, ~2GB of GGUF models download
```

## Obsidian compatibility

All memory files use YAML frontmatter with hierarchical tags (`memory/l0` / `memory/l1` / `memory/l2` / `memory/repo`). Open `~/.claude/` or any repo's root as an Obsidian vault — graph view, tag filtering, full-text search across all your projects.

## Repo layout

```
CLAUDE.md                       — the memory protocol (replaces default; goes to ~/.claude/)
INSTALL.md                      — install instructions, troubleshooting
LICENSE                         — MIT
CHANGELOG.md                    — version history
memory/IDENTITY.md              — L0 template
templates/repo/CLAUDE.md        — L1a template (thin in-repo entry)
templates/repo/.claude-docs/*   — L1b templates (gotchas, architecture, conventions, index)
templates/project.md.fallback.template — L1-fallback template (account-local)
hooks/session-start.sh          — staleness + CWD mismatch + privacy redaction + compression flag + qmd auto-refresh
hooks/pre-compact.sh            — pre-compact flush reminder (privacy, compression, CWD rules)
commands/{recall,codemap,memory}.md — slash command definitions
bin/codemap.sh                  — universal-ctags + ripgrep symbol map
settings.snippet.json           — hooks block for ~/.claude/settings.json
IDEAS.md                        — prioritised backlog of future enhancements
```

## License

MIT — see [LICENSE](LICENSE). Use it, fork it, share it.

## Acknowledgments

- [qmd](https://github.com/tobi/qmd) by Tobi Lütke — the retrieval engine that made `/recall` trivial to build
- [universal-ctags](https://github.com/universal-ctags/ctags) — symbol map backbone
- The folks who built [CodeGraph](https://github.com/colbymchenry/codegraph) and [AgentMemory](https://github.com/rohitg00/agentmemory) — evaluating them clarified what this system needed to be *different*

## Part of [openronin](https://github.com/openronin)

A loose collection of self-hosted AI dev tooling. This protocol is compatible with any tool that runs Claude Code — interactive sessions, headless runs, including `openronin`'s GitHub-issue-driven agents.
