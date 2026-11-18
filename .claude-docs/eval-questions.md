---
tags: [memory/repo, eval]
description: Canned questions for bin/memory-eval.sh — what this repo's docs must keep answering
---

# Memory eval questions — claude-memory-3layer

Run `bash bin/memory-eval.sh`. Each `q:` is what an agent would type after `/recall`; `expect:` is literal text that must be in one of the files recall returns. `tests/memory-eval.bats` runs this file in CI, so a doc edit that loses an answer fails the build. Add a question whenever a session had to rediscover something these docs should have told it.

## Questions

- q: project slug derive transcript
  expect: transcript_path
- q: PreCompact systemMessage flush model
  expect: discards
- q: hook additionalContext cap characters
  expect: 10,000
- q: shellcheck disable directive scope
  expect: next command
- q: background refresh never ran errexit
  expect: _add_path
- q: commit README CHANGELOG IDEAS mandatory
  expect: no exceptions
- q: python3 Windows Store alias stub
  expect: _cmd_runs
- q: merge-settings matcher existing installs
  expect: sync pass
- q: grep case-insensitive fixed string abort
  expect: grep 3.0
- q: citation commit squash merge
  expect: merge commit
