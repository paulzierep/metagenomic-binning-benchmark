#!/usr/bin/env bash
# supervise-alive.sh — last-resort guarantee that the benchmark agent keeps running.
#
# WHY THIS EXISTS (2026-09-28):
#   The agent stack silently stopped itself and the benchmark repo went quiet for
#   ~2 days. Three separate causes were fixed inside the individual scripts:
#     1. an empty agent-written TASK_COMPLETE latched the watchdog + heartbeat off
#        (both are now only honoured when user-armed with ARMED-BY-USER);
#     2. quota/504 failures were counted as crashes, so the crash-loop guard
#        suppressed every relaunch (they are now excluded from the budget);
#     3. model fallback rotation replaced big-pickle (now removed: we always wait
#        and retry big-pickle instead).
#   This script is the belt-and-braces layer on top of those fixes: whatever else
#   goes wrong, if NO agent is alive it clears the crash-loop markers and starts
#   one. It is deliberately dumb — it makes no judgement about what the agent
#   should be doing, only whether anything is running.
#
# SAFETY: it can never run two agents at once.
#   * it defers to agent-watchdog.sh's own flock, which it never touches;
#   * it exits immediately if that flock is held (a driver is mid-loop, possibly
#     sleeping in a quota backoff — that must not be disturbed);
#   * it exits if an `opencode run` process is in flight;
#   * it exits if the transcript is still fresh (the agent is legitimately
#     between turns: TURN_GAP_S / IDLE_GAP_S, or the tail of a long turn).
# Run from cron every 5 minutes, offset from agent-watchdog.sh to avoid racing it.
set -u
export HOME=/home/ubuntu
export PATH=/home/ubuntu/.opencode/bin:/home/ubuntu/.local/bin:/usr/local/bin:/usr/bin:/bin

BENCH=${BENCH_ROOT:-/vol/data/benchmark}
AGENT_LOCK=/tmp/agent-watchdog.lock
LOG="$BENCH/logs/supervise-alive.log"
ATTDIR="$BENCH/.watchdog_attempts"
LOCK=${SUPERVISE_ALIVE_LOCK:-/tmp/supervise-alive.lock}
COMPLETE="$BENCH/TASK_COMPLETE"
AGENT_LOG="$BENCH/logs/agent-run.log"
STALE_S=${KEEPALIVE_STALE_S:-1200}   # 20 min without transcript output => dead

log() { echo "$(date -Is) [keepalive] $*" >>"$LOG"; }
mkdir -p "$BENCH/logs"

# One keepalive at a time.
exec 9>"$LOCK"
flock -n 9 || exit 0

# A user-armed completion sentinel still wins: it is the one intended off switch.
if [ -s "$COMPLETE" ] && grep -q 'ARMED-BY-USER' "$COMPLETE" 2>/dev/null; then
    exit 0
fi

# A driver holds the agent flock => it is alive, possibly waiting out a backoff.
if ! flock -n "$AGENT_LOCK" -c true 2>/dev/null; then
    exit 0
fi

# A turn is in flight (any opencode run, fresh or continuing session).
if ps -eo args= | awk 'index($0,"opencode run --auto")==1{found=1} END{exit !found}'; then
    exit 0
fi

# Nothing alive. A fresh transcript means the agent is just between turns.
tl=999999
[ -f "$AGENT_LOG" ] && tl=$(( $(date +%s) - $(stat -c %Y "$AGENT_LOG") ))
if [ "$tl" -lt "$STALE_S" ]; then
    exit 0
fi

# Nothing alive AND the transcript is stale. This is exactly the silent-stop
# failure we exist to prevent. Clear the crash-loop budget and relaunch; the
# crash guard must never be the reason the project stays dark.
n=$(find "$ATTDIR" -type f 2>/dev/null | wc -l)
find "$ATTDIR" -type f -delete 2>/dev/null
log "no agent alive and transcript ${tl}s stale -> cleared ${n} crash marker(s), relaunching agent-watchdog.sh"
setsid nohup /vol/data/benchmark/bin/agent-watchdog.sh >/dev/null 2>&1 </dev/null &
exit 0
