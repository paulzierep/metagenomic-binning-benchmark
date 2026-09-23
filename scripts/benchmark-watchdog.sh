#!/usr/bin/env bash
# benchmark-watchdog.sh — keep the ACTIVE benchmark run alive INDEPENDENTLY of the
# coding agent (cron */5). If the agent is broken or the run hangs forever, this
# still restarts it.
#
# Rules (conservative, safety-first):
#   - only acts on the run recorded in /vol/data/benchmark/.active_run
#   - HEALTHY  = process alive AND run log written within the last $HANG_S
#   - HUNG     = process alive but log silent for > $HANG_S -> kill + restart
#   - CRASHED  = process gone with no terminal evidence       -> restart
#   - FAILED   = terminal failure evidence                    -> record + clear
#   - DONE     = run_meta.txt exit_code:0                    -> clear .active_run
#   - deterministic failures are never retried in a tight loop
#   - replacement runners are immutable snapshots from the committed repo
#   - rate limit: max $MAX_PER_RUN restarts per run per rolling 24 h
#   - flock-protected; exits immediately on TASK_COMPLETE
set -u
export HOME=/home/ubuntu
BENCH=${BENCH_ROOT:-/vol/data/benchmark}
ACTIVE="$BENCH/.active_run"        # pid pgid logfile rundir start_ts mode source [contigs bamdir]
SLOG="$BENCH/logs/benchmark-watchdog.log"
LOCK=${BENCH_WATCHDOG_LOCK:-/tmp/benchmark-watchdog.lock}
HANG_S=${BENCH_HANG_S:-2400}       # 40 min without new log output => hung
MAX_PER_RUN=${BENCH_MAX_RESTARTS:-3}
REPO=${BENCHMARK_REPO:-/vol/data/repos/metagenomic-binning-benchmark}
RUNNER_REF=${BENCH_RUNNER_REF:-HEAD}
SNAPSHOT_ROOT="$BENCH/.runner-snapshots"
log() { echo "$(date -Is) [bm-watchdog] $*" >>"$SLOG"; }

exec 9>"$LOCK"
flock -n 9 || exit 0
[ -f "$BENCH/TASK_COMPLETE" ] && exit 0
[ -f "$ACTIVE" ] || exit 0
mkdir -p "$BENCH/logs" "$SNAPSHOT_ROOT"

read -r pid pgid logfile rundir start mode source contigs bamdir < "$ACTIVE"
name=$(basename "${rundir:-}")
root_name=${name%%_autorestart*}
mode=${mode:-baseline}
source=${source:-/vol/data/repos/COMEBin}
[[ "$name" =~ ^[A-Za-z0-9._-]+$ ]] || { log "unsafe active-run directory '${rundir:-}'; refusing state change"; exit 0; }
case "$rundir" in
  "$BENCH"/runs/*) ;;
  *) log "active-run directory is outside $BENCH/runs: $rundir; refusing state change"; exit 0 ;;
esac
[[ "$mode" =~ ^[A-Za-z0-9._-]+$ ]] || { log "unsafe active-run mode '$mode'; refusing state change"; exit 0; }
if [ "$mode" != "baseline" ] && [ ! -f "$source/COMEBin/run_comebin.sh" ]; then
  log "registered $mode source is missing run_comebin.sh: $source; refusing state change"
  exit 0
fi

case "$pid:$pgid" in
  *[!0-9:]*|:*|*:) log "invalid active-run pid/pgid '${pid:-}/${pgid:-}'; refusing process action"; exit 0 ;;
esac
[ "$pid" -gt 0 ] && [ "$pgid" -gt 1 ] || { log "unsafe active-run pid/pgid $pid/$pgid; refusing process action"; exit 0; }
own_pgid=$(ps -o pgid= -p $$ 2>/dev/null | tr -d ' ' || true)
[ "$pgid" != "${own_pgid:-0}" ] || { log "registered pgid $pgid equals watchdog group; refusing process action"; exit 0; }
registered_pgid=$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ' || true)
if [ -n "$registered_pgid" ] && [ "$registered_pgid" != "$pgid" ]; then
  log "registered pgid $pgid does not match pid $pid current pgid $registered_pgid; refusing process action"
  exit 0
fi
if [ -n "$registered_pgid" ] && [[ "$start" =~ ^[0-9]+$ ]]; then
  pid_started=$(date -d "$(ps -o lstart= -p "$pid" 2>/dev/null)" +%s 2>/dev/null || echo 0)
  if [ "$pid_started" -gt 0 ] && [ $((pid_started - start)) -gt 5 ] && [ $((start - pid_started)) -gt 5 ]; then
    log "pid start mismatch: registered=$start actual=$pid_started; refusing process action"
    exit 0
  fi
fi

# Never clear a registration that changed while this watchdog was inspecting it.
active_matches() {
  local cur_pid cur_pgid cur_log cur_dir cur_start rest
  [ -f "$ACTIVE" ] || return 1
  read -r cur_pid cur_pgid cur_log cur_dir cur_start rest < "$ACTIVE" || return 1
  [ "$cur_pid" = "$pid" ] && [ "$cur_dir" = "$rundir" ] && [ "$cur_start" = "$start" ]
}

clear_active() {
  if active_matches; then
    rm -f "$ACTIVE"
    return 0
  fi
  log "$name registration changed while watchdog was inspecting it; leaving current state untouched"
  return 1
}

# A terminal failure is deliberately not treated as a transient crash.  This is
# important for deterministic COMEBin/data/dependency errors: retrying them
# wastes hours and can overwrite the only useful diagnostics.
record_terminal_failure() {
  local reason=$1 stamp
  stamp=$(date -Is)
  reason=$(printf '%s' "$reason" | tr '\r\n\t' '   ' | cut -c1-400)
  if [ -f "$rundir/run_meta.txt" ]; then
    printf 'watchdog_terminal: %s\n' "$stamp $reason" >> "$rundir/run_meta.txt" 2>/dev/null || true
  fi
  printf '%s\n' "$stamp $reason" > "$rundir/.watchdog_terminal" 2>/dev/null || true
  printf '%s\t%s\t%s\n' "$stamp" "$rundir" "$reason" > "$BENCH/.last_benchmark_failure" 2>/dev/null || true
  if clear_active; then
    # A terminal failure consumes no retry budget.  Remove only markers for
    # this stable run family, and only after the registered process is gone.
    if [[ "$root_name" =~ ^[A-Za-z0-9._-]+$ ]]; then
      find "$BENCH" -maxdepth 1 -name ".hang_restarts.$root_name.*" -mmin -1440 -delete 2>/dev/null || true
    fi
    log "$name terminal failure: $reason — active-run cleared; no automatic retry"
  else
    log "$name terminal failure: $reason — registration changed; not clearing a replacement"
  fi
}

# A committed snapshot prevents a source edit made while a long benchmark is
# executing from changing the script text Bash has not read yet.
make_snapshot() {
  local rel=$1 dst tmp
  dst="$SNAPSHOT_ROOT/${name}_$(date +%s%N).sh"
  tmp="$dst.tmp.$$"
  if ! git -C "$REPO" show "$RUNNER_REF:$rel" > "$tmp" 2>/dev/null; then
    rm -f "$tmp"
    log "cannot read committed runner $RUNNER_REF:$rel; refusing launch"
    return 1
  fi
  [ -s "$tmp" ] || { rm -f "$tmp"; log "committed runner $RUNNER_REF:$rel is empty; refusing launch"; return 1; }
  chmod 755 "$tmp"
  mv -f "$tmp" "$dst"
  printf '%s\n' "$dst"
}

# log age = silence of the run
[ -f "$logfile" ] || logfile="$rundir/comebin_run.log"
if [ -f "$logfile" ]; then
    age=$(( $(date +%s) - $(stat -c %Y "$logfile") ))
else
    age=999999
fi

# A recorded successful exit is authoritative and safe to clear even if the
# old PID has since been reused; no process signal is sent on this path.
rc_done=$(grep -m1 '^exit_code:' "$rundir/run_meta.txt" 2>/dev/null | awk '{print $2}' || true)
if [ "$rc_done" = "0" ]; then
    if clear_active; then
      rm -f "$BENCH/.last_benchmark_failure" 2>/dev/null || true
      log "$name finished rc=0 — active-run cleared"
    fi
    exit 0
fi

alive=0
orphaned=0
pid_stat=$(ps -o stat= -p "$pid" 2>/dev/null | tr -d ' ' || true)
if [ -n "$pid_stat" ] && kill -0 "$pid" 2>/dev/null && [[ "$pid_stat" != Z* ]]; then
    pid_cmd=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || true)
    case "$pid_cmd" in
      *run_comebin_baseline.sh*|*run_comebin_fix.sh*|*run_small_test.sh*) alive=1 ;;
      *) log "pid $pid is alive but is not a registered COMEBin runner; refusing kill/restart: $pid_cmd" ; exit 0 ;;
    esac
elif group_pids=$(pgrep -g "$pgid" 2>/dev/null) && [ -n "$group_pids" ]; then
    # Wrapper gone but descendants remain. Only treat the group as the run when
    # every member is recognizably part of this rundir/runner; otherwise avoid
    # creating a duplicate or killing an unrelated process group.
    group_safe=1
    for child_pid in $group_pids; do
      child_cmd=$(tr '\0' ' ' < "/proc/$child_pid/cmdline" 2>/dev/null || true)
      case "$child_cmd" in
        *"$rundir"*|*run_comebin_baseline.sh*|*run_comebin_fix.sh*|*run_small_test.sh*|*micromamba*) ;;
        *) group_safe=0; break ;;
      esac
    done
    if [ "$group_safe" -eq 1 ]; then
      alive=1
      orphaned=1
      log "$name wrapper $pid is gone; verified orphaned run group $pgid"
    else
      log "process group $pgid has unrelated members; refusing orphan kill/restart"
      exit 0
    fi
fi

# Look for terminal evidence only after establishing that the registered
# process/group is gone.  A live process is never killed merely because its log
# contains an error; that could destroy a still-running cleanup phase.
terminal_reason=""
if [ "$alive" -eq 0 ]; then
  if [[ "$rc_done" =~ ^[0-9]+$ ]] && [ "$rc_done" != "0" ]; then
    terminal_reason="run_meta exit_code=$rc_done"
  elif [ -s "$rundir/.watchdog_terminal" ]; then
    terminal_reason=$(tail -n 1 "$rundir/.watchdog_terminal" 2>/dev/null || true)
  else
    candidates=("$logfile" "$BENCH/logs/${name}.launch.log")
    # The original pre-watchdog baseline used this shared launch log.  Consult
    # it only for that exact run, never as evidence for a replacement attempt.
    if [ "$name" = "baseline_unmodified" ] && [ -f "/vol/data/logs/baseline_launch.log" ]; then
      candidates+=("/vol/data/logs/baseline_launch.log")
    fi
    for candidate in "${candidates[@]}"; do
      [ -f "$candidate" ] || continue
      failure_line=$(tail -n 300 "$candidate" 2>/dev/null \
        | grep -aE 'Something went wrong with running|Traceback \(most recent call last\):|ModuleNotFoundError|FileNotFoundError|No such file or directory|syntax error near unexpected token' \
        | tail -n 1 || true)
      if [ -n "$failure_line" ]; then
        terminal_reason="terminal log evidence: $failure_line"
        break
      fi
    done
  fi
  if [ -n "$terminal_reason" ]; then
    record_terminal_failure "$terminal_reason"
    exit 0
  fi
fi

# A live process with a fresh log is healthy.  A live orphan/hung process is
# handled conservatively below; terminal evidence while it is still alive is
# left for manual inspection rather than killing an active run.
[ "$alive" -eq 1 ] && [ "$orphaned" -eq 0 ] && [ "$age" -lt "$HANG_S" ] && exit 0
if [ "$alive" -eq 1 ] && [ -n "$terminal_reason" ]; then
  log "$name has terminal-looking evidence but its registered process is still alive; refusing to signal it"
  exit 0
fi

# budget check (rolling 24 h), keyed to the stable pre-autorestart run name
restarts=$(find "$BENCH" -maxdepth 1 -name ".hang_restarts.$root_name.*" -mmin -1440 2>/dev/null | wc -l)
if [ "$restarts" -ge "$MAX_PER_RUN" ]; then
    log "$name needs restart but budget exhausted ($restarts/$MAX_PER_RUN) — leaving to agent"
    exit 0
fi

# Kill only the registered process group and wrapper. Never use pkill -f on a
# run name: prompts and status commands may contain that text too.
if [ "$alive" -eq 1 ]; then
    log "$name HUNG: log silent ${age}s -> killing pid $pid pgid $pgid"
    kill -9 -- -"$pgid" 2>/dev/null || true
    kill -9 "$pid" 2>/dev/null || true
    sleep 3
fi

# Restart into a fresh directory (keeps every attempt's raw artifacts). New
# registrations carry mode + source; legacy five-field baseline registrations
# default to mode=baseline above.
marker="$BENCH/.hang_restarts.$root_name.$(date +%s)"
touch "$marker"
new="${root_name}_autorestart$((restarts+1))"
newdir="$BENCH/runs/$new"
# Keep the old registration until the replacement atomically overwrites it;
# BENCHMARK_WATCHDOG_REPLACE=1 tells guarded runners that this is an authorized
# handoff rather than a second independent launch.
launch_env=(SRC_COMEBIN="$source" BENCHMARK_WATCHDOG_REPLACE=1)
case "$mode" in
  baseline) rel=scripts/run_comebin_baseline.sh; launch_env+=(PYTHONDONTWRITEBYTECODE=1) ;;
  small) rel=scripts/run_small_test.sh; launch_env+=(PYTHONDONTWRITEBYTECODE=1) ;;
  *) rel=scripts/run_comebin_fix.sh; launch_env+=(MODE="$mode" PYTHONDONTWRITEBYTECODE=1)
     if [ -n "${contigs:-}" ]; then launch_env+=("CONTIGS=$contigs"); fi
     if [ -n "${bamdir:-}" ]; then launch_env+=("BAMDIR=$bamdir"); fi
     ;;
esac
snapshot=$(make_snapshot "$rel") || { rm -f "$marker"; exit 0; }
launch=(bash "$snapshot" "$newdir")
nohup env "${launch_env[@]}" "${launch[@]}" \
    >"$BENCH/logs/$new.launch.log" 2>&1 9>&- &
log "$name restart #$((restarts+1)) mode=$mode source=$source -> $newdir (runner=$RUNNER_REF:$rel snapshot=$(basename "$snapshot"); launcher pid $!)"
exit 0
