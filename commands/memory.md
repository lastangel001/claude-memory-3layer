# /memory — Memory status & index refresh

Inspect the memory subsystem and refresh the search index. The protocol has one promotion mode — **explicit** (the user says "запомни"/"remember"); gotchas are the single always-write exception. There is no auto-capture mode to toggle.

## Sub-commands

`/memory` (no args, or `/memory status`) — collection health + last index times.

`/memory refresh` — force `qmd update && qmd embed` for all collections NOW (use if hooks didn't fire).

## How to execute

1. For **status**: run `qmd status` and `qmd collection list` via Bash. Report concisely.

2. For **`refresh`**: `qmd update && qmd embed`. Report counts (`N new, M updated`).

PATH note: prepend `export PATH="/c/Program Files/nodejs:$APPDATA/npm:$PATH" &&` to qmd commands if needed (Windows; adjust path to your npm global bin).

## Removed in v6.19.0: `/memory auto on|off`

The toggle wrote `~/.claude/.memory-auto`, a global flag no hook ever read: it "worked" only while this command's text was still in context, and it contradicted the protocol's explicit-promotion rule. If the user asks for it, say it was removed, delete a leftover flag (`rm -f ~/.claude/.memory-auto`), and point to the rule that already covers the need — gotchas are written immediately, without "запомни".
