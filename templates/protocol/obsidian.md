---
tags: [memory/protocol, obsidian]
---

# Obsidian compatibility — memory protocol reference

Memory files use YAML frontmatter (`last_updated`, `tags`) so vaults work out of the box.

## Vault options

- `~/.claude/` as vault → L0 + all L2 sessions + L1-fallback project.md files (cross-project graph)
- `<repo>/` as vault → focused on one project's CLAUDE.md + .claude-docs/ (deep dive into one codebase)

## Conventions

- **Frontmatter, not wikilinks.** Use standard markdown links `[text](path)` everywhere — wikilinks `[[note]]` don't work outside Obsidian, and the model needs to follow real paths.
- **Hierarchical tags**: `memory/l0`, `memory/l1`, `memory/l2`, `memory/repo` (in-repo L1 docs). Add semantic tags freely (`gotcha`, `decision`, `roadmap`).
- **Don't add `.obsidian/` config to memory files** — leave per-vault settings to the user.
- **Frontmatter is parsed by the staleness hook** via regex match on `last_updated:` anywhere in the file — legacy HTML-comment format `<!-- last_updated: ... -->` still works.
- Session filtering: `dataview TABLE last_updated WHERE status = "active"` separates live sessions from distilled ones (`status: done`).
