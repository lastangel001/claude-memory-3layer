#!/usr/bin/env bash
# bin/recall.sh — memory search behind /recall. One entry point that works with
# or without qmd, and always looks at the current repo's own docs.
#
#   recall.sh [options] <query words...>
#     -n N | -k N     max hits per section (default 5)
#     --here          only this project's memory (+ this repo's docs)
#     --hybrid        qmd hybrid search (BM25 + vectors + rerank); needs `qmd embed`
#     -c NAME         restrict qmd to one collection (claude-l0 | claude-projects)
#     --no-repo       skip the current repo's .claude-docs / CLAUDE.md
#     --engine rg     force the ripgrep path even when qmd is installed
#
# Sections printed (markdown):
#   ## Memory      — account memory: ~/.claude/memory + ~/.claude/projects/*/memory
#                    via qmd when installed, ripgrep/grep ranking otherwise
#   ## Repo docs   — <repo>/.claude-docs/*.md, CLAUDE.md, AGENTS.md (ripgrep/grep)
#
# Why a script and not instructions in the command file: the instructions had
# drifted from the tool — `-k` is not a qmd flag (silently ignored), `--filter`
# does not exist, and the suggested `export PATH=…$APPDATA/npm…` broke qmd on
# Git Bash. And repo docs — where the protocol puts gotchas — were never
# searched at all unless a per-repo collection had been registered by hand.
#
# Index freshness: if the last completed `qmd update` is older than 6 h (or
# unknown), one is run inline first — recall must not depend on the SessionStart
# background refresh having worked. Disable with RECALL_NO_REFRESH=1.
#
# A query with no hits anywhere is appended to logs/recall-misses.log — the list
# of things memory was asked for and did not have.

set -uo pipefail

CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/paths.sh
source "$_here/lib/paths.sh"
_augment_node_path
# shellcheck source=lib/slug.sh
source "$_here/lib/slug.sh"
# shellcheck source=lib/diag.sh
[[ -f "$_here/lib/diag.sh" ]] && source "$_here/lib/diag.sh"
export QMD_LLAMA_GPU="${QMD_LLAMA_GPU:-none}"   # Vulkan default crashes on some Windows GPUs

limit=5; here=0; hybrid=0; collection=""; with_repo=1; engine="auto"
words=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|-k)      limit="${2:-5}"; shift 2 ;;
    --here)     here=1; shift ;;
    --hybrid)   hybrid=1; shift ;;
    -c)         collection="${2:-}"; shift 2 ;;
    --no-repo)  with_repo=0; shift ;;
    --engine)   engine="${2:-auto}"; shift 2 ;;
    -h|--help)  grep -E '^#( |$)' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    --)         shift; while [[ $# -gt 0 ]]; do words+=("$1"); shift; done ;;
    *)          words+=("$1"); shift ;;
  esac
done
[[ "$limit" =~ ^[0-9]+$ && "$limit" -gt 0 ]] || limit=5

query="${words[*]:-}"
if [[ -z "${query// /}" ]]; then
  echo "recall: empty query. Usage: recall.sh [-n N] [--here] [--hybrid] <query words...>" >&2
  exit 2
fi

# Search terms for the ripgrep/grep path: whitespace-split, 2+ characters.
terms=()
read -r -a _split <<< "$query"   # split on whitespace without glob expansion
for _w in "${_split[@]}"; do
  [[ ${#_w} -ge 2 ]] && terms+=("$_w")
done
[[ ${#terms[@]} -eq 0 ]] && terms=("$query")

have_rg=0; command -v rg >/dev/null 2>&1 && have_rg=1
# MEMORY_QMD_CMD overrides the qmd command (tests point it at a stub; PATH is
# augmented above, so a stub earlier on PATH would not win otherwise).
qmd_cmd="${MEMORY_QMD_CMD:-qmd}"
have_qmd=0; command -v "$qmd_cmd" >/dev/null 2>&1 && have_qmd=1
[[ "$engine" == "rg" ]] && have_qmd=0

# --- ranked literal search over files/directories ---------------------------
# Prints "score<TAB>path", best first. Score = 1000 per distinct term found in
# the file + total occurrences (capped) — a file mentioning every query word
# outranks one repeating a single word.
_count_term() {  # $1 = term, rest = paths   ->  "path:count" lines
  local t="$1"; shift
  if [[ $have_rg -eq 1 ]]; then
    rg -c -i -F --no-messages -g '*.md' -- "$t" "$@" 2>/dev/null
  else
    grep -r -i -F -c --include='*.md' -- "$t" "$@" 2>/dev/null | grep -v ':0$'
  fi
}
_rank() {  # $@ = paths
  local t
  for t in "${terms[@]}"; do
    _count_term "$t" "$@"
  done | awk '
    {
      # "path:count" — split on the LAST colon (Windows paths carry a drive colon).
      i = match($0, /:[0-9]+$/); if (!i) next
      p = substr($0, 1, i - 1); c = substr($0, i + 1) + 0
      gsub(/\\/, "/", p)   # ripgrep on Windows mixes separators
      if (c > 0) { nterm[p]++; tot[p] += (c > 50 ? 50 : c) }
    }
    END { for (p in nterm) printf "%d\t%s\n", nterm[p] * 1000 + tot[p], p }
  ' | sort -t "$(printf '\t')" -k1,1nr -k2,2
}
_show_hits() {  # stdin: "score<TAB>path" lines; $1 = max files
  local max="$1" n=0 score path args=() t
  for t in "${terms[@]}"; do args+=(-e "$t"); done
  while IFS="$(printf '\t')" read -r score path; do
    [[ -z "$path" ]] && continue
    n=$((n + 1)); [[ $n -gt $max ]] && break
    printf '### %s\n' "$path"
    if [[ $have_rg -eq 1 ]]; then
      rg -n -i -F -m 3 --no-messages "${args[@]}" -- "$path" 2>/dev/null
    else
      grep -n -i -F -m 3 "${args[@]}" -- "$path" 2>/dev/null
    fi | cut -c1-240 | sed 's/^/    /'
    printf '\n'
  done
  return 0
}

total_hits=0

# --- Section 1: account memory ----------------------------------------------
_resolve_project
mem_scope_label="all projects"
mem_paths=()
# shellcheck disable=SC2154  # project_dir set by sourced _resolve_project
if [[ $here -eq 1 ]]; then
  mem_scope_label="this project"
  [[ -d "$project_dir/memory" ]] && mem_paths+=("$project_dir/memory")
else
  [[ -d "$CLAUDE_HOME/memory" ]]   && mem_paths+=("$CLAUDE_HOME/memory")
  [[ -d "$CLAUDE_HOME/projects" ]] && mem_paths+=("$CLAUDE_HOME/projects")
fi

_qmd_section() {
  # Self-heal a stale index: the SessionStart background refresh may never
  # have completed on this machine.
  if [[ "${RECALL_NO_REFRESH:-0}" != "1" ]]; then
    local done_stamp="$CLAUDE_HOME/.qmd-last-refresh-done" last now
    last=$(cat "$done_stamp" 2>/dev/null || echo 0)
    now=$(date +%s)
    [[ "$last" =~ ^[0-9]+$ ]] || last=0
    if [[ $((now - last)) -ge 21600 ]]; then
      if "$qmd_cmd" update >/dev/null 2>&1; then
        printf '%s\n' "$now" > "$done_stamp" 2>/dev/null || true
        echo "_(index was stale — refreshed before searching)_"
      fi
    fi
  fi
  local out rc=0 mode="BM25" cargs=()
  [[ -n "$collection" ]] && cargs=(-c "$collection")
  if [[ $hybrid -eq 1 ]]; then
    mode="hybrid"
    out=$("$qmd_cmd" query "$query" --md -n "$limit" ${cargs[@]+"${cargs[@]}"} 2>&1) || rc=$?
    if [[ $rc -ne 0 || "$out" == *"Error loading model"* || "$out" == *"ErrorExtensionNotPresent"* ]]; then
      echo "_(hybrid search failed — falling back to BM25)_"
      mode="BM25"; rc=0
      out=$("$qmd_cmd" search "$query" --md -n "$limit" ${cargs[@]+"${cargs[@]}"} 2>&1) || rc=$?
    fi
  else
    out=$("$qmd_cmd" search "$query" --md -n "$limit" ${cargs[@]+"${cargs[@]}"} 2>&1) || rc=$?
  fi
  if [[ $rc -ne 0 ]]; then
    echo "_(qmd failed, rc=$rc — using ripgrep instead)_"
    return 1
  fi
  if ! printf '%s' "$out" | grep -q 'docid'; then
    echo "(no hits)"
    return 0
  fi
  printf '%s\n' "$out"
  # The markdown view names documents by title only — add the paths.
  local files
  files=$("$qmd_cmd" search "$query" --files -n "$limit" ${cargs[@]+"${cargs[@]}"} 2>/dev/null | grep '^#' || true)
  if [[ -n "$files" ]]; then
    printf '\n**Files** (docid, score, path):\n'
    printf '%s\n' "$files" | sed 's/^/- /'
  fi
  total_hits=$((total_hits + $(printf '%s' "$out" | grep -c 'docid' || true)))
  echo "_(engine: qmd $mode)_"
  return 0
}

_rg_memory_section() {
  if [[ ${#mem_paths[@]} -eq 0 ]]; then echo "(no memory directory)"; return 0; fi
  local ranked
  # Curated memory first; verbatim transcripts only fill the remaining slots.
  ranked=$(_rank "${mem_paths[@]}" | grep -v '/raw/transcripts/' || true)
  local n; n=$(printf '%s' "$ranked" | grep -c . || true)
  if [[ "$n" -lt "$limit" ]]; then
    ranked="${ranked}${ranked:+$'\n'}$(_rank "${mem_paths[@]}" | grep '/raw/transcripts/' || true)"
    n=$(printf '%s' "$ranked" | grep -c . || true)
  fi
  if [[ "$n" -eq 0 ]]; then echo "(no hits)"; return 0; fi
  printf '%s\n' "$ranked" | _show_hits "$limit"
  total_hits=$((total_hits + (n > limit ? limit : n)))
  if [[ $have_rg -eq 1 ]]; then echo "_(engine: ripgrep, literal match)_"; else echo "_(engine: grep, literal match)_"; fi
}

printf '## Memory (%s)\n\n' "$mem_scope_label"
if [[ $have_qmd -eq 1 && $here -eq 0 ]]; then
  _qmd_section || _rg_memory_section
else
  # --here goes through ripgrep on purpose: the scope is one small directory,
  # and qmd has no path filter.
  _rg_memory_section
  [[ $have_qmd -eq 0 && $here -eq 0 && "$engine" != "rg" ]] && echo "_(qmd not installed — see INSTALL.md for ranked BM25 / hybrid search)_"
fi
printf '\n'

# --- Section 2: the current repo's own docs ---------------------------------
if [[ $with_repo -eq 1 ]]; then
  repo_root=""
  if git rev-parse --show-toplevel >/dev/null 2>&1; then
    repo_root=$(git rev-parse --show-toplevel 2>/dev/null)
  fi
  repo_paths=()
  if [[ -n "$repo_root" ]]; then
    [[ -d "$repo_root/.claude-docs" ]] && repo_paths+=("$repo_root/.claude-docs")
    [[ -f "$repo_root/CLAUDE.md" ]]    && repo_paths+=("$repo_root/CLAUDE.md")
    [[ -f "$repo_root/AGENTS.md" ]]    && repo_paths+=("$repo_root/AGENTS.md")
  fi
  if [[ ${#repo_paths[@]} -gt 0 ]]; then
    printf '## Repo docs (%s)\n\n' "$repo_root"
    _ranked=$(_rank "${repo_paths[@]}")
    _n=$(printf '%s' "$_ranked" | grep -c . || true)
    if [[ "$_n" -eq 0 ]]; then
      echo "(no hits)"
    else
      printf '%s\n' "$_ranked" | _show_hits "$limit"
      total_hits=$((total_hits + (_n > limit ? limit : _n)))
    fi
    printf '\n'
  fi
fi

# --- Misses: what memory was asked for and did not have ----------------------
if [[ $total_hits -eq 0 ]]; then
  mkdir -p "$CLAUDE_HOME/logs" 2>/dev/null || true
  printf '%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$mem_scope_label" "$query" \
    >> "$CLAUDE_HOME/logs/recall-misses.log" 2>/dev/null || true
  declare -F _diag >/dev/null 2>&1 && _diag Recall empty "scope=${mem_scope_label// /-}"
fi
exit 0
