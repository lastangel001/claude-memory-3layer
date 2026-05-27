#!/usr/bin/env bash
# onboard-report.sh — collect repo data for Claude Code memory bootstrap.
#
# Run from repo root before /onboard:
#   bash ~/.claude/bin/onboard-report.sh
#
# Output: structured markdown to stdout. Claude reads it, then creates
# CLAUDE.md + .claude-docs/ scaffold via the /onboard slash command.

set -euo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$REPO_ROOT"

sep() { printf '\n---\n\n## %s\n\n' "$1"; }

printf '# Onboard report — %s\n' "$(basename "$REPO_ROOT")"
printf '_Generated: %s_\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

# ─── 1. Stack detection ───────────────────────────────────────────────────────
sep "Stack files"
_found_stack=0
for f in package.json composer.json pyproject.toml go.mod Cargo.toml \
          build.gradle build.gradle.kts pom.xml Gemfile; do
  if [[ -f "$f" ]]; then
    _found_stack=1
    printf '### %s\n```\n' "$f"
    head -60 "$f"
    printf '```\n\n'
  fi
done
[[ $_found_stack -eq 0 ]] && printf '(no recognised stack files found)\n'

# ─── 2. Directory structure ───────────────────────────────────────────────────
sep "Directory structure (depth 2)"
_IGNORE='.git|node_modules|vendor|__pycache__|.venv|dist|build|.next|coverage|.idea|.vscode'
if command -v tree >/dev/null 2>&1; then
  tree -L 2 -I "$_IGNORE" 2>/dev/null || true
else
  find . -maxdepth 2 \
    ! -path './.git/*' ! -path './node_modules/*' ! -path './vendor/*' \
    ! -path './__pycache__/*' ! -path './.venv/*' ! -path './dist/*' \
    ! -path './build/*' | sort | sed 's|^\./||'
fi

# ─── 3. Entry points ─────────────────────────────────────────────────────────
sep "Likely entry points"
_found_ep=0
for f in \
  index.php public/index.php bootstrap/app.php artisan \
  index.ts src/index.ts main.ts src/main.ts \
  index.js src/index.js main.js server.js app.js \
  main.py app.py manage.py wsgi.py asgi.py run.py \
  main.go cmd/main.go \
  Makefile Dockerfile docker-compose.yml docker-compose.yaml; do
  if [[ -f "$f" ]]; then
    _found_ep=1
    printf '- %s\n' "$f"
  fi
done
[[ $_found_ep -eq 0 ]] && printf '(none of the common entry points found)\n'

# ─── 4. Config / env files ───────────────────────────────────────────────────
sep "Config and env files"
_found_cfg=0
for f in \
  .env.example .env.dist .env.test .env.sample \
  tsconfig.json tsconfig.base.json \
  .eslintrc.json .eslintrc.js .eslintrc.yaml .eslintrc.yml \
  .prettierrc .prettierrc.json \
  phpunit.xml phpunit.xml.dist phpstan.neon psalm.xml \
  pytest.ini setup.cfg .coveragerc \
  .editorconfig .gitignore; do
  if [[ -f "$f" ]]; then
    _found_cfg=1
    printf '- %s\n' "$f"
  fi
done
[[ $_found_cfg -eq 0 ]] && printf '(no common config files found)\n'

# ─── 5. Git history ──────────────────────────────────────────────────────────
sep "Recent git history (last 50 commits)"
git log --oneline -50 2>/dev/null || printf '(no git history)\n'

# ─── 6. Hot files ────────────────────────────────────────────────────────────
sep "Most-changed files (last 6 months)"
git log --since='6 months ago' --format=format: --name-only 2>/dev/null \
  | grep -v '^[[:space:]]*$' \
  | sort | uniq -c | sort -rg \
  | head -20 \
  || printf '(no history in last 6 months)\n'

# ─── 7. Gotcha patterns ──────────────────────────────────────────────────────
sep "Inline comments: FIXME / HACK / WORKAROUND / DO NOT / XXX"
grep -rEn 'FIXME|HACK|WORKAROUND|DO NOT|XXX[^X]|IMPORTANT:' \
  --include='*.php' --include='*.ts' --include='*.tsx' \
  --include='*.js'  --include='*.jsx' \
  --include='*.py'  --include='*.go'  --include='*.rb' \
  --include='*.java' --include='*.kt' --include='*.rs' --include='*.cs' \
  --exclude-dir='.git' --exclude-dir='node_modules' --exclude-dir='vendor' \
  --exclude-dir='__pycache__' --exclude-dir='.venv' --exclude-dir='dist' \
  . 2>/dev/null | head -60 \
  || printf '(none found)\n'

# ─── 8. Deprecated / annotated TODOs ─────────────────────────────────────────
sep "@deprecated and TODO with context"
grep -rEn '@deprecated|TODO\s*\(' \
  --include='*.php' --include='*.ts' --include='*.tsx' \
  --include='*.js'  --include='*.py'  --include='*.go' \
  --exclude-dir='.git' --exclude-dir='node_modules' --exclude-dir='vendor' \
  . 2>/dev/null | head -30 \
  || printf '(none found)\n'
