---
tags: [memory/repo, gotcha]
---

# Gotchas — claude-memory-3layer

Non-obvious foot-guns. Read before editing install/validation scripts.

## install.sh / doctor.sh: false "settings.json invalid JSON" on Windows Git Bash

**Symptom:** `install.sh` and `bin/doctor.sh` report `✗ settings.json invalid JSON` even when the file is perfectly valid JSON.

**Cause:** Both validate via
```bash
node -e "JSON.parse(require('fs').readFileSync('$CLAUDE_HOME/settings.json','utf8'))"
```
On Windows, `$CLAUDE_HOME` is an MSYS path like `/c/Users/User/.claude`. The `node` on PATH is the **Windows-native** build — it cannot resolve `/c/...` paths, so `readFileSync` throws `ENOENT` → validation reports invalid. The JSON is fine; the path handoff is broken. (python3 fallback only kicks in if `node` is absent — when both exist, node runs first and false-fails.)

**Fix:** pipe the file through `cat` (bash resolves the MSYS path) into node stdin, so node never touches the path:
```bash
cat "$CLAUDE_HOME/settings.json" | node -e "JSON.parse(require('fs').readFileSync(0,'utf8'))"
```
`readFileSync(0)` reads fd 0 (stdin). Cross-platform: works on Linux/macOS/Windows. Apply same fix to `bin/doctor.sh` (~line 79).

**Lesson:** never pass an MSYS/Git-Bash path as a string argument to a Windows-native interpreter (node/python from winget). Pipe via stdin, or convert with `cygpath -w`.
