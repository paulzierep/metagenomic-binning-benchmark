#!/usr/bin/env bash
# benchmark-watchdog.sh — keep the ACTIVE benchmark run alive INDEPENDENTLY of the
# coding agent (cron */5). If the agent is broken or the run hangs forever, this
# still restarts it.
#
# Rules (conservative, safety-first):
#   - only acts on the run recorded in /vol/data/benchmark/.active_run
#   - HEALTHY  = process alive AND run log written within the last $HANG_S
#   - HUNG     = process alive but log silent for > $HANG_S           -> kill + restart
#   - CRASHED  = process gone, run_meta.txt has no exit_code:0         -> restart
#   - DONE     = run_meta.txt exit_code:0                              -> clear .active_run
#   - rate limit: max $MAX_PER_RUN restarts per run per rolling 24 h
#   - flock-protected; exits immediately on TASK_COMPLETE
set -u
export HOME=/home/ubuntu
BENCH=/vol/data/benchmark
ACTIVE="$BENCH/.active_run"        # pid pgid logfile rundir start_ts mode source [contigs bamdir]
SLOG="$BENCH/logs/benchmark-watchdog.log"
LOCK=${BENCH_WATCHDOG_LOCK:-/tmp/benchmark-watchdog.lock}
HANG_S=${BENCH_HANG_S:-2400}       # 40 min without new log output => hung
MAX_PER_RUN=${BENCH_MAX_RESTARTS:-3}
REPO=/vol/data/repos/metagenomic-binning-benchmark
log() { echo "$(date -Is) [bm-watchdog] $*" >>"$SLOG"; }

exec 9>"$LOCK"
flock -n 9 || exit 0
[ -f "$BENCH/TASK_COMPLETE" ] && exit 0
[ -f "$ACTIVE" ] || exit 0

read -r pid pgid logfile rundir start mode source contigs bamdir < "$ACTIVE"
name=$(basename "$rundir")
root_name=${name%%_autorestart*}
mode=${mode:-baseline}
source=${source:-/vol/data/repos/COMEBin}
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

# log age = silence of the run
[ -f "$logfile" ] || logfile="$rundir/comebin_run.log"
if [ -f "$logfile" ]; then
    age=$(( $(date +%s) - $(stat -c %Y "$logfile") ))
else
    age=999999
fi

# A recorded successful exit is authoritative and safe to clear even if the
# old PID has since been reused; no process signal is sent on this path.
rc_done=$(grep -m1 '^exit_code:' "$rundir/run_meta.txt" 2>/dev/null | awk '{print $2}')
if [ "$rc_done" = "0" ]; then
    rm -f "$ACTIVE"
    log "$name finished rc=0 — active-run cleared"
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
      pid_cmd="orphaned registered process group: $group_pids"
      log "$name wrapper $pid is gone; verified orphaned run group $pgid"
    else
      log "process group $pgid has unrelated members; refusing orphan kill/restart"
      exit 0
    fi
fi

# healthy?
[ "$alive" = "1" ] && [ "$orphaned" = "0" ] && [ "$age" -lt "$HANG_S" ] && exit 0

# budget check (rolling 24 h), keyed to the stable pre-autorestart run name
restarts=$(find "$BENCH" -maxdepth 1 -name ".hang_restarts.$root_name.*" -mmin -1440 2>/dev/null | wc -l)
if [ "$restarts" -ge "$MAX_PER_RUN" ]; then
    log "$name needs restart but budget exhausted ($restarts/$MAX_PER_RUN) — leaving to agent"
    exit 0
fi

# Kill only the registered process group and wrapper. Never use pkill -f on a
# run name: prompts and status commands may contain that text too.
if [ "$alive" = "1" ]; then
    log "$name HUNG: log silent ${age}s -> killing pid $pid pgid $pgid"
    kill -9 -- -"$pgid" 2>/dev/null || true
    kill -9 "$pid" 2>/dev/null || true
    sleep 3
fi

# Restart into a fresh directory (keeps every attempt's raw artifacts). New
# registrations carry mode + source; legacy five-field baseline registrations
# default to mode=baseline above.
touch "$BENCH/.hang_restarts.$root_name.$(date +%s)"
new="${root_name}_autorestart$((restarts+1))"
newdir="$BENCH/runs/$new"
# Keep the old registration until the replacement atomically overwrites it;
# BENCHMARK_WATCHDOG_REPLACE=1 tells guarded runners that this is an authorized
# handoff rather than a second independent launch.
launch_env=(SRC_COMEBIN="$source" BENCHMARK_WATCHDOG_REPLACE=1)
case "$mode" in
  baseline)
    launch=(bash "$REPO/scripts/run_comebin_baseline.sh" "$newdir")
    ;;
  small)
    launch=(bash "$REPO/scripts/run_small_test.sh" "$newdir")
    ;;
  *)
    launch=(bash "$REPO/scripts/run_comebin_fix.sh" "$newdir")
    launch_env+=(MODE="$mode")
    if [ -n "${contigs:-}" ]; then launch_env+=(CONTIGS="$contigs"); fi
    if [ -n "${bamdir:-}" ]; then launch_env+=(BAMDIR="$bamdir"); fi
    ;;
esac
nohup env "${launch_env[@]}" "${launch[@]}" \
    >"$BENCH/logs/$new.launch.log" 2>&1 9>&- &
log "$name restart #$((restarts+1)) mode=$mode source=$source -> $newdir (launcher pid $!; run script re-registers .active_run)"
exit 0
