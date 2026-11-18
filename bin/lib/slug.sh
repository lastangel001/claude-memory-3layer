#!/usr/bin/env bash
# bin/lib/slug.sh — sourced library: locate the Claude Code project directory
# (~/.claude/projects/<slug>) for the current session.
#
# Usage: source "${CLAUDE_HOME}/bin/lib/slug.sh"
#   _resolve_project [hook_stdin_json] [cwd]   # preferred — see below
#   _compute_slug [cwd]                        # formula only
#
# After _resolve_project returns:
#   $slug                  — project directory name under $CLAUDE_HOME/projects
#   $project_dir           — $CLAUDE_HOME/projects/$slug (where memory/ is read)
#   $canonical_slug        — Claude Code's own directory name (transcripts);
#                            differs from $slug only when $slug_source = legacy
#   $current_cwd_canonical — Windows-style canonical cwd (C:/dev/foo) or $PWD
#   $slug_source           — transcript | formula | legacy
#
# Resolution order (never ask the MODEL to derive a slug — it gets it wrong and
# memory splits across two directories, see gotchas.md):
#   1. transcript — hook stdin JSON carries "transcript_path"; its parent
#      directory name IS the slug Claude Code uses. Exact, no formula needed.
#   2. formula    — Claude Code replaces every non-alphanumeric character of the
#      native cwd with "-":  C:\dev\my_app -> C--dev-my-app,
#      /home/dev/my.app -> -home-dev-my-app. Best effort for non-ASCII paths
#      (per-character vs per-UTF-16-unit) and paths over 200 chars (Claude Code
#      truncates + hashes) — those rely on (1).
#   3. legacy     — the pre-v6.19.0 formula (only "/" and "_" mapped, leading
#      "-" stripped on unix). Used ONLY when the directory from (1)/(2) holds no
#      SESSION.md but the legacy one does, so an upgrade never hides existing
#      memory. doctor.sh reports such directories for a manual move.

# Echo the "transcript_path" value from a hook stdin JSON blob with every path
# separator normalized to "/" (C:/Users/u/.claude/projects/<slug>/<id>.jsonl),
# or nothing. Pure bash on purpose: hooks run on every event, an interpreter
# spawn costs 100+ ms on Git Bash.
#
# The substitutions below are deliberately UNQUOTED assignments with the
# separator kept in a variable: backslash patterns inside "${var//…}" are
# parsed differently across bash versions and inside eval.
_transcript_path_from_json() {
  local json="${1:-}" tp="" sep=$'\x01'
  local re='"transcript_path"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)"'
  if [[ "$json" =~ $re ]]; then
    tp=${BASH_REMATCH[1]}
    # JSON "\\" is one path backslash. Park it first: in C:\\users\\… the pair
    # followed by "u" is NOT a \uXXXX escape and must not be mistaken for one.
    tp=${tp//\\\\/$sep}
    # A real \uXXXX escape can't be decoded here — let the caller fall back.
    if [[ $tp == *\\u* ]]; then
      tp=""
    else
      tp=${tp//\\\///}        # JSON "\/" -> "/"
      tp=${tp//$sep//}        # parked backslash -> "/"
    fi
  fi
  printf '%s' "$tp"
}

# Pre-v6.19.0 formula, kept only for the legacy-directory fallback.
_legacy_slug() {
  local _cwd="${1:-$PWD}" s=""
  if [[ "$_cwd" =~ ^/([a-zA-Z])/(.*)$ ]]; then
    local _rest="${BASH_REMATCH[2]}"
    s="${BASH_REMATCH[1]^^}--${_rest//\//-}"
  elif [[ "$_cwd" =~ ^/([a-zA-Z])/?$ ]]; then
    s="${BASH_REMATCH[1]^^}-"
  else
    s="${_cwd//\//-}"
    s="${s#-}"
  fi
  printf '%s' "${s//_/-}"
}

# Formula slug. Sets $slug and $current_cwd_canonical.
# shellcheck disable=SC2034  # slug + current_cwd_canonical are set FOR the sourcing script
_compute_slug() {
  local _cwd="${1:-$PWD}"
  slug=""
  current_cwd_canonical=""

  if [[ "$_cwd" =~ ^/([a-zA-Z])/(.*)$ ]]; then
    # MSYS /c/dev/foo == native C:\dev\foo -> "C" + ":" + "\" + rest
    local _drive="${BASH_REMATCH[1]^^}"
    local _rest="${BASH_REMATCH[2]}"
    slug="${_drive}--${_rest//[^a-zA-Z0-9]/-}"
    current_cwd_canonical="${_drive}:/${_rest}"
  elif [[ "$_cwd" =~ ^/([a-zA-Z])/?$ ]]; then
    local _drive="${BASH_REMATCH[1]^^}"
    slug="${_drive}--"
    current_cwd_canonical="${_drive}:/"
  else
    slug="${_cwd//[^a-zA-Z0-9]/-}"
    current_cwd_canonical="$_cwd"
  fi
}

# Resolve the project directory. $1 = hook stdin JSON (may be empty), $2 = cwd.
# shellcheck disable=SC2034  # outputs are consumed by the sourcing script
_resolve_project() {
  local _json="${1:-}" _cwd="${2:-$PWD}"
  local _home="${CLAUDE_HOME:-$HOME/.claude}"
  _compute_slug "$_cwd"
  slug_source="formula"

  local _tp _dir _name
  _tp=$(_transcript_path_from_json "$_json")
  if [[ -n "$_tp" ]]; then
    _dir="${_tp%/*}"             # drop the <session-id>.jsonl component
    _name="${_dir##*/}"
    # A real slug holds only alphanumerics and dashes; anything else means the
    # path was not what we expected — keep the formula result.
    if [[ -n "$_name" && "$_name" =~ ^[A-Za-z0-9-]+$ ]]; then
      slug="$_name"
      slug_source="transcript"
    fi
  fi

  # The directory Claude Code itself uses (transcripts live here) — stays put
  # even when memory is read from a legacy directory below.
  canonical_slug="$slug"
  project_dir="$_home/projects/$slug"

  if [[ ! -f "$project_dir/memory/SESSION.md" ]]; then
    local _legacy
    _legacy=$(_legacy_slug "$_cwd")
    if [[ -n "$_legacy" && "$_legacy" != "$slug" \
          && -f "$_home/projects/$_legacy/memory/SESSION.md" ]]; then
      slug="$_legacy"
      project_dir="$_home/projects/$slug"
      slug_source="legacy"
    fi
  fi
}

# For a LINKED git worktree, echo the root of the MAIN worktree (in the same
# path form `_compute_slug` accepts); echo nothing for a main checkout, a bare
# repository or a non-repository. Used to share project.md — project-level
# knowledge — across worktrees, while SESSION.md stays per worktree.
_main_worktree_root() {
  local cwd="${1:-$PWD}" common gitdir root rest
  common=$(git -C "$cwd" rev-parse --git-common-dir 2>/dev/null) || return 0
  gitdir=$(git -C "$cwd" rev-parse --git-dir 2>/dev/null) || return 0
  [[ -n "$common" && "$common" != "$gitdir" ]] || return 0
  case "$common" in
    /*|[A-Za-z]:*) ;;
    *) common="$cwd/$common" ;;   # relative to cwd
  esac
  common=${common//\\//}
  [[ "${common##*/}" == ".git" ]] || return 0
  root="${common%/.git}"
  if [[ "$root" =~ ^([A-Za-z]):/(.*)$ ]]; then
    rest=${BASH_REMATCH[2]}
    root="/${BASH_REMATCH[1],,}/${rest}"
  fi
  printf '%s' "$root"
}

# Echo a path in the form the model's file tools accept on this platform:
# /c/Users/x -> C:/Users/x under Git Bash/MSYS, unchanged elsewhere.
_native_path() {
  local p="$1"
  if [[ "$p" =~ ^/([a-zA-Z])/(.*)$ ]]; then
    case "$(uname -s 2>/dev/null || echo unknown)" in
      MINGW*|MSYS*|CYGWIN*) p="${BASH_REMATCH[1]^^}:/${BASH_REMATCH[2]}" ;;
    esac
  fi
  printf '%s' "$p"
}
