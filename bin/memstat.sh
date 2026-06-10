#!/usr/bin/env bash
# memstat.sh — "task manager" for the memory subsystem.
# Shows: running memory processes, qmd index progress, refresh schedule,
# recent activity, and a stall/health check.
#
# Usage:
#   memstat.sh            # one-shot snapshot
#   memstat.sh --watch    # live, refresh every 3s (Ctrl-C to exit)
#   memstat.sh --watch 5  # live, custom interval

CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
# Augment PATH with common Node/npm locations (Windows + Unix).
# Resolved relative to this script so it works both from the repo and installed.
# shellcheck source=lib/paths.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/paths.sh"
_augment_node_path
export QMD_LLAMA_GPU="${QMD_LLAMA_GPU:-none}"

WATCH=0; INTERVAL=3
if [[ "${1:-}" == "--watch" ]]; then WATCH=1; [[ -n "${2:-}" ]] && INTERVAL="$2"; fi

c_reset=$'\033[0m'; c_dim=$'\033[2m'; c_bold=$'\033[1m'
c_grn=$'\033[32m'; c_yel=$'\033[33m'; c_red=$'\033[31m'; c_cyn=$'\033[36m'

human_age() {  # seconds -> "1h 2m" / "3m" / "12s"
  local s=$1
  if   (( s >= 3600 )); then printf '%dh %dm' $((s/3600)) $(((s%3600)/60))
  elif (( s >= 60 ));   then printf '%dm' $((s/60))
  else printf '%ds' "$s"; fi
}

# --- gather: memory-related processes (node running qmd, ctags) ---
# NOTE: uses bash DOUBLE-quotes with \" / \$ escaping. Do NOT switch to bash
# single-quotes — embedding '' inside a '...' string silently breaks quoting
# and PowerShell receives a mangled command (returns nothing).
get_procs() {
  powershell.exe -NoProfile -Command "
    Get-CimInstance Win32_Process -Filter \"Name='node.exe' OR Name='ctags.exe'\" |
    Where-Object { \$_.CommandLine -match 'qmd|codemap|\.codemap' -or \$_.Name -eq 'ctags.exe' } |
    ForEach-Object {
      \$ram = [math]::Round(\$_.WorkingSetSize/1MB)
      \$age = if (\$_.CreationDate) { [int]((Get-Date) - \$_.CreationDate).TotalSeconds } else { -1 }
      \$cmd = \$_.CommandLine
      \$kind = if (\$cmd -match 'embed') {'embed'} elseif (\$cmd -match 'update') {'update'} elseif (\$cmd -match 'query|search|vsearch') {'query'} elseif (\$_.Name -eq 'ctags.exe') {'codemap'} else {'node'}
      '{0}|{1}|{2}|{3}' -f \$_.ProcessId, \$ram, \$age, \$kind
    }
  " 2>/dev/null | tr -d '\r' | grep -E '^[0-9]+\|'
}

# --- gather: total CPU time (100ns units) for a PID, for stall detection ---
get_cpu_time() {
  local pid="$1"
  [[ -z "$pid" ]] && { echo 0; return; }
  powershell.exe -NoProfile -Command "
    \$p = Get-CimInstance Win32_Process -Filter \"ProcessId=$pid\" -ErrorAction SilentlyContinue
    if (\$p) { \$p.KernelModeTime + \$p.UserModeTime } else { 0 }
  " 2>/dev/null | tr -d '\r' | grep -oE '^[0-9]+' | head -1
}

# --- gather: qmd index status (vectors / pending) ---
# Retries once if the first call returns nothing (transient SQLite lock during
# a concurrent `qmd update`).
get_qmd_status() {
  local out
  out=$(timeout 25 qmd status 2>/dev/null | tr -d '\r')
  if ! echo "$out" | grep -qiE 'Vectors:'; then
    sleep 1
    out=$(timeout 25 qmd status 2>/dev/null | tr -d '\r')
  fi
  printf '%s' "$out"
}

render() {
  local procs status now
  now=$(date +%s)
  procs=$(get_procs)
  status=$(get_qmd_status)

  printf '%s' "$c_bold$c_cyn"
  echo "╔══ MEMORY DISPATCHER ════════════════════════════════════════╗"
  printf '%s' "$c_reset"
  echo "  $(date '+%Y-%m-%d %H:%M:%S')"
  echo ""

  # --- PROCESSES ---
  printf '%s%sPROCESSES%s\n' "$c_bold" "" "$c_reset"
  if [[ -z "$procs" ]]; then
    printf '  %s○ idle — no memory processes running%s\n' "$c_dim" "$c_reset"
  else
    while IFS='|' read -r pid ram age kind; do
      [[ -z "$pid" ]] && continue
      local agestr; agestr=$(human_age "$age")
      local col=$c_grn
      (( age > 1800 )) && col=$c_yel   # >30min running = worth a look
      printf '  %s● %-7s%s PID %-6s RAM %4sMB  running %s\n' "$col" "$kind" "$c_reset" "$pid" "$ram" "$agestr"
    done <<< "$procs"
  fi
  echo ""

  # --- INDEX ---
  printf '%sINDEX (qmd)%s\n' "$c_bold" "$c_reset"
  local vec pend total pct
  vec=$(echo "$status"  | grep -oiE 'Vectors:[[:space:]]*[0-9]+' | grep -oE '[0-9]+' | head -1)
  pend=$(echo "$status" | grep -oiE 'Pending:[[:space:]]*[0-9]+' | grep -oE '[0-9]+' | head -1)
  vec=${vec:-?}; pend=${pend:-0}
  if [[ "$vec" != "?" ]]; then
    total=$((vec + pend))
    (( total > 0 )) && pct=$((vec * 100 / total)) || pct=100
    local pcol=$c_grn; (( pct < 80 )) && pcol=$c_yel; (( pct < 50 )) && pcol=$c_red
    printf '  vectors: %s%s%s embedded  /  %s pending   %s(%d%% coverage)%s\n' "$c_bold" "$vec" "$c_reset" "$pend" "$pcol" "$pct" "$c_reset"
  else
    printf '  %s(qmd status unavailable — index may be locked by a running embed)%s\n' "$c_dim" "$c_reset"
  fi
  # collections line
  echo "$status" | grep -A6 -iE '^Collections' | grep -iE '\(qmd://|Files:' | sed 's/^/  /' | head -6
  echo ""

  # --- REFRESH SCHEDULE ---
  printf '%sREFRESH (SessionStart hook, 6h debounce)%s\n' "$c_bold" "$c_reset"
  local marker="$CLAUDE_HOME/.qmd-last-refresh"
  if [[ -f "$marker" ]]; then
    local last age_r; last=$(cat "$marker" 2>/dev/null || echo 0); age_r=$((now - last))
    local due="not yet"; (( age_r > 21600 )) && due="${c_yel}due${c_reset}"
    printf '  last refresh: %s ago      next auto: %s\n' "$(human_age "$age_r")" "$due"
  else
    printf '  %sno refresh marker yet (will run on next session start)%s\n' "$c_dim" "$c_reset"
  fi
  echo ""

  # --- ACTIVITY ---
  printf '%sACTIVITY%s\n' "$c_bold" "$c_reset"
  for lg in qmd-refresh.log qmd-embed.log qmd-embed-retry.log; do
    local p="$CLAUDE_HOME/logs/$lg"
    [[ -f "$p" ]] || continue
    local mt; mt=$(stat -c %Y "$p" 2>/dev/null || echo 0)
    local lastline; lastline=$(grep -vE '^\s*$|\[?\?25|^\[2K' "$p" 2>/dev/null | tail -1 | tr -d '\r' | cut -c1-58)
    printf '  %s%-22s%s %s ago  %s%s%s\n' "$c_dim" "$lg" "$c_reset" "$(human_age $((now - mt)))" "$c_dim" "$lastline" "$c_reset"
  done
  echo ""

  # --- HEALTH / STALL CHECK ---
  printf '%sHEALTH%s\n' "$c_bold" "$c_reset"
  if [[ -z "$procs" ]]; then
    if [[ "$vec" == "?" ]]; then
      printf '  %s? index status unknown — qmd status did not respond (retry /memstat)%s\n' "$c_yel" "$c_reset"
    elif [[ "$pend" == "0" ]]; then
      printf '  %s✓ idle, index fully embedded%s\n' "$c_grn" "$c_reset"
    else
      printf '  %s✓ idle (%s chunks pending — run `/memory refresh` for fresh vectors)%s\n' "$c_grn" "$pend" "$c_reset"
    fi
  else
    # A process is running — sample vector delta to detect progress
    local embed_running; embed_running=$(echo "$procs" | grep -c 'embed')
    if (( embed_running > 0 )); then
      local epid
      epid=$(echo "$procs" | grep 'embed' | awk -F'|' '{print $1}' | head -1)
      printf '  %s… embed running — sampling progress (3s)…%s\n' "$c_dim" "$c_reset"
      local v1 v2 cpu1 cpu2
      v1=$(echo "$status" | grep -oiE 'Vectors:[[:space:]]*[0-9]+' | grep -oE '[0-9]+' | head -1)
      cpu1=$(get_cpu_time "$epid")
      sleep 3
      v2=$(get_qmd_status | grep -oiE 'Vectors:[[:space:]]*[0-9]+' | grep -oE '[0-9]+' | head -1)
      cpu2=$(get_cpu_time "$epid")
      v1=${v1:-0}; v2=${v2:-0}; cpu1=${cpu1:-0}; cpu2=${cpu2:-0}
      local delta=$((v2 - v1))
      # CPU time is in 100ns units; >1e8 over 3s ≈ >0.01 core-sec, meaningful work
      local cpu_delta=$((cpu2 - cpu1))
      if (( delta > 0 )); then
        printf '  %s✓ progressing: +%d vectors in 3s (now %d)%s\n' "$c_grn" "$delta" "$v2" "$c_reset"
      elif (( cpu_delta > 100000000 )); then
        # No committed vectors yet, but burning CPU → loading model / computing a batch
        printf '  %s● working: vectors commit per-batch; CPU active (+%ds core-time in 3s) — not hung%s\n' "$c_grn" "$((cpu_delta / 10000000))" "$c_reset"
        printf '    %s(embeddinggemma loads ~30-60s on CPU, then commits batches; let it finish)%s\n' "$c_dim" "$c_reset"
      else
        local oldest_embed_age
        oldest_embed_age=$(echo "$procs" | grep 'embed' | awk -F'|' '{print $3}' | sort -nr | head -1)
        printf '  %s⚠ no vector progress AND no CPU activity in 3s (embed running %s) — likely stalled.%s\n' "$c_red" "$(human_age "$oldest_embed_age")" "$c_reset"
        printf '    %skill: powershell "Stop-Process -Id %s"  (pending chunks retried next refresh)%s\n' "$c_dim" "$epid" "$c_reset"
      fi
    else
      printf '  %s● memory process active (non-embed)%s\n' "$c_grn" "$c_reset"
    fi
  fi
}

if (( WATCH )); then
  trap 'printf "\033[?25h"; exit 0' INT TERM
  printf '\033[?25l'  # hide cursor
  while true; do
    printf '\033[2J\033[H'  # clear + home
    render
    printf '\n%s(live — refresh %ss, Ctrl-C to exit)%s\n' "$c_dim" "$INTERVAL" "$c_reset"
    sleep "$INTERVAL"
  done
else
  render
fi
