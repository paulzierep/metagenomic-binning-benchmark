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
ACTIVE="$BENCH/.active_run"        # "<pid> <pgid> <logfile> <rundir> <start_ts>"
SLOG="$BENCH/logs/benchmark-watchdog.log"
LOCK=/tmp/benchmark-watchdog.lock
HANG_S=2400                         # 40 min without new log output => hung
MAX_PER_RUN=3                       # max automatic restarts per run
log() { echo "$(date -Is) [bm-watchdog] $*" >>"$SLOG"; }

exec 9>"$LOCK"
flock -n 9 || exit 0
[ -f "$BENCH/TASK_COMPLETE" ] && exit 0
[ -f "$ACTIVE" ] || exit 0

read -r pid pgid logfile rundir start < "$ACTIVE"
name=$(basename "$rundir")

# log age = silence of the run
[ -f "$logfile" ] || logfile="$rundir/comebin_run.log"
if [ -f "$logfile" ]; then
    age=$(( $(date +%s) - $(stat -c %Y "$logfile") ))
else
    age=999999
fi

alive=0
[ -n "${pid:-}" ] && kill -0 "$pid" 2>/dev/null && alive=1

# finished successfully?
rc_done=$(grep -m1 '^exit_code:' "$rundir/run_meta.txt" 2>/dev/null | awk '{print $2}')
if [ "$rc_done" = "0" ]; then
    rm -f "$ACTIVE"
    log "$name finished rc=0 — active-run cleared"
    exit 0
fi

# healthy?
[ "$alive" = "1" ] && [ "$age" -lt "$HANG_S" ] && exit 0

# budget check (rolling 24 h)
restarts=$(find "$BENCH" -maxdepth 1 -name ".hang_restarts.$name.*" -mmin -1440 2>/dev/null | wc -l)
if [ "$restarts" -ge "$MAX_PER_RUN" ]; then
    log "$name needs restart but budget exhausted ($restarts/$MAX_PER_RUN) — leaving to agent"
    exit 0
fi

# kill old tree (best effort)
if [ "$alive" = "1" ]; then
    log "$name HUNG: log silent ${age}s -> killing pid $pid pgid ${pgid:-?}"
    [ -n "${pgid:-}" ] && kill -9 -- -"$pgid" 2>/dev/null
    kill -9 "$pid" 2>/dev/null
    pkill -9 -f "$name" 2>/dev/null
    sleep 3
fi

# restart into a fresh runs/ dir (keeps raw baseline artifacts per attempt intact)
touch "$BENCH/.hang_restarts.$name.$(date +%s)"
new="${name}_autorestart$((restarts+1))"
newdir="$BENCH/runs/$new"
nohup bash /vol/data/repos/metagenomic-binning-benchmark/scripts/run_comebin_baseline.sh "$newdir" \
    >"$BENCH/logs/$new.launch.log" 2>&1 &
log "$name restart #$((restarts+1)) -> $newdir (launcher pid $!; run script re-registers .active_run)"
exit 0