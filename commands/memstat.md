# /memstat — memory subsystem status & index refresh

Shows what the memory subsystem is doing right now — running processes (qmd embed/update, codemap/ctags), index progress (vectors embedded vs pending), refresh schedule, recent activity logs, a health/stall check — and forces an index refresh on request.

Use when: `node.exe` is eating CPU and you want to know what it is doing; `/recall` looks stale; or you want fresh vectors for `--hybrid` search.

## Usage

- `/memstat` — one-shot snapshot
- `/memstat --watch` — live view, refresh every 3 s (Ctrl-C to exit)
- `/memstat --watch 5` — live view, custom interval
- `/memstat --refresh` — run `qmd update` (BM25 index) and `qmd embed` (vectors) NOW. The embed step is CPU-heavy and can take minutes; `/recall` plain search needs only the first step, which `recall.sh` also does by itself when the index is over 6 hours old.

## How to execute

Run via Bash:
```bash
bash ~/.claude/bin/memstat.sh            # or: --watch [seconds] | --refresh
```
In a non-interactive context prefer the one-shot form — `--watch` never returns.

Pass the output through verbatim — it is already formatted as a dashboard (ANSI colors, sections). Then add a one-line plain-English read of the HEALTH section for the user.

## What it reports

- **PROCESSES** — live qmd/ctags processes with PID, RAM, how long they have been running. Yellow if a process has run >30 min.
- **INDEX** — vectors embedded / pending, % coverage, per-collection file counts.
- **REFRESH** — when the SessionStart hook last kicked a refresh, when one last *completed*, whether the next auto-refresh is due (>6 h).
- **ACTIVITY** — last line + age of each qmd log (`qmd-refresh.log`, `qmd-embed.log`, `qmd-embed-retry.log`).
- **HEALTH** — if a process is running, samples the vector count over 3 s to confirm forward progress; flags a possible stall if an embed has run >2 min with zero vector delta. If idle, confirms index state.

## Interpreting common states

- `○ idle — no memory processes running` + high coverage → normal. The CPU spike you saw was a finished embed.
- `● embed running … ✓ progressing: +N vectors in 3s` → working, just slow on CPU. Let it finish.
- `⚠ no vector progress in 3s and embed running 15m` → possible stall. If it persists >10 min with zero delta, kill it (`powershell "Stop-Process -Id <PID>"` on Windows, `kill <PID>` elsewhere). Pending chunks are retried on the next refresh.

## Why embed is CPU-heavy

The vector index uses local GGUF models via node-llama-cpp. Where the GPU path is unavailable (the script defaults `QMD_LLAMA_GPU=none`, because the Vulkan default crashes on some Windows GPUs) embedding runs on CPU — roughly 1–3 s per chunk, so a full re-embed of a large memory store can take tens of minutes. That is why it is never started automatically: only `/memstat --refresh` runs it.

## Note

This command replaces the former `/memory status | refresh` (removed in v6.21.0 — `/memory` is a Claude Code built-in for editing CLAUDE.md files and toggling native auto memory).
