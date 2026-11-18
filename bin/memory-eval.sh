#!/usr/bin/env bash
# bin/memory-eval.sh — closed-book retrieval check for a repo's memory.
#
#   memory-eval.sh [--file PATH] [-n N] [--report]
#
# Question file (default: <repo>/.claude-docs/eval-questions.md):
#
#     - q: how is the project directory found
#       expect: transcript_path
#     - q: what must be updated on every commit
#       expect: CHANGELOG.md | IDEAS.md        <- any of these
#
# For every question the script asks /recall as an agent would — but over the
# REPO DOCS ONLY (`recall.sh --no-memory`, literal engine: deterministic, no
# qmd, no model, same result on a laptop and in CI) — and checks that at least
# one of the top N files it returns contains the expected text. Repo docs are
# what a fresh clone has; account memory is not part of the contract. That is the question "would an agent that searches memory for this land
# on a file holding the answer?" — retrieval coverage, not answer quality.
#
# The question file itself is excluded from the candidates (it contains every
# question and every answer).
#
# Exit: 0 when every question passes (or with --report), 1 otherwise, 2 on usage
# errors. Meant for a pre-commit hook or CI: memory that stops answering a
# canned question is a regression like any other.

set -uo pipefail

_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

file=""; top=5; report=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --file)   file="${2:-}"; shift 2 ;;
    -n)       top="${2:-5}"; shift 2 ;;
    --report) report=1; shift ;;
    -h|--help) grep -E '^#( |$)' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) printf 'Unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done
[[ "$top" =~ ^[0-9]+$ && "$top" -gt 0 ]] || top=5

if [[ -z "$file" ]]; then
  if git rev-parse --show-toplevel >/dev/null 2>&1; then
    file="$(git rev-parse --show-toplevel)/.claude-docs/eval-questions.md"
  else
    file="$PWD/.claude-docs/eval-questions.md"
  fi
fi
if [[ ! -f "$file" ]]; then
  printf 'memory-eval: no question file: %s\n' "$file" >&2
  printf 'Create it with entries of the form:\n  - q: <question as you would ask /recall>\n    expect: <text that must be in a returned file>\n' >&2
  exit 2
fi
file_base="$(basename "$file")"

# Literal -> basic regular expression (never `grep -i -F`: GNU grep 3.0 aborts on it).
_bre() { printf '%s' "$1" | sed 's/[][\\.*^$]/\\&/g'; }

pass=0; fail=0; total=0
printf '=== memory-eval: %s (top %s files per question) ===\n\n' "$file" "$top"

while IFS="$(printf '\t')" read -r q expect; do
  [[ -z "$q" || -z "$expect" ]] && continue
  total=$((total + 1))
  read -r -a qwords <<< "$q"
  # Files /recall would hand an agent for this question.
  hits=$(RECALL_NO_REFRESH=1 RECALL_NO_MISS_LOG=1 bash "$_here/recall.sh" --no-memory --engine rg -n "$top" -- "${qwords[@]}" 2>/dev/null \
           | sed -n 's/^### //p' | grep -v "/${file_base}\$" || true)
  found=""
  if [[ -n "$hits" ]]; then
    IFS='|' read -r -a alts <<< "$expect"
    while IFS= read -r f; do
      [[ -f "$f" ]] || continue
      for alt in "${alts[@]}"; do
        alt="${alt#"${alt%%[![:space:]]*}"}"; alt="${alt%"${alt##*[![:space:]]}"}"
        [[ -z "$alt" ]] && continue
        if grep -q -i -e "$(_bre "$alt")" -- "$f" 2>/dev/null; then found="$f"; break 2; fi
      done
    done <<< "$hits"
  fi
  if [[ -n "$found" ]]; then
    pass=$((pass + 1))
    printf '  \033[32m✓\033[0m %s  →  %s\n' "$q" "${found##*/}"
  else
    fail=$((fail + 1))
    got="$(printf '%s' "$hits" | sed 's|.*/||' | tr '\n' ' ')"
    printf '  \033[31m✗\033[0m %s\n      expected "%s" in one of the top %s files; recall returned: %s\n' \
      "$q" "$expect" "$top" "${got:-(nothing)}"
  fi
done < <(
  # "- q: …" followed by "expect: …"  ->  "q<TAB>expect"; fenced code blocks are examples.
  awk '
    /^[[:space:]]*```/ { fence = !fence; next }
    fence { next }
    /^[[:space:]]*-[[:space:]]*q:[[:space:]]*/ { q = $0; sub(/^[[:space:]]*-[[:space:]]*q:[[:space:]]*/, "", q); next }
    /^[[:space:]]*expect:[[:space:]]*/ && q != "" { e = $0; sub(/^[[:space:]]*expect:[[:space:]]*/, "", e); printf "%s\t%s\n", q, e; q = "" }
  ' "$file" | tr -d '\r'
)

printf '\n'
if [[ $total -eq 0 ]]; then
  printf 'No questions found in %s (expected "- q: …" lines followed by "expect: …").\n' "$file"
  exit 2
fi
printf 'Retrieval coverage: %d/%d\n' "$pass" "$total"
[[ $fail -gt 0 && $report -eq 0 ]] && exit 1
exit 0
