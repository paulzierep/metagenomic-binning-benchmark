#!/usr/bin/env bash
# agent-watchdog.sh — restart the OpenCode agent if the benchmark session aborted
#                      or the model ran out of tokens; rotate to a free model on quota errors.
#
# Runs from cron every 5 minutes. Logic:
#   1. exit if TASK_COMPLETE sentinel exists
#   2. exit if too many restarts in the last 6 h (rate limit, crash-loop guard)
#   3. exit if the agent heartbeat is fresh (< 15 min)  => agent is alive
#   4. classify the previous failure from the log tail:
#        - quota/rate-limit/context exhausted -> force a FREE model via --model
#        - any other non-zero exit           -> rotate model after repeated failures too
#   5. restart the agent:
#        - first choice: continue the original session (keeps conversation context)
#        - if continuation failed before: start fresh with a resume-from-PROGRESS.md prompt
#   Tokens refresh: cron simply retries every 5 min; a successful run clears the
#   forced-model flag so the next restart goes back to the default model.
#
# Full documentation: docs/05-agent-restart.md
# Design doc / resume state: /vol/data/benchmark/PROGRESS.md
set -u
export HOME=/home/ubuntu
export PATH=/home/ubuntu/.opencode/bin:/home/ubuntu/.local/bin:/usr/local/bin:/usr/bin:/bin
cd /home/ubuntu || exit 1

BENCH=/vol/data/benchmark
HEARTBEAT="$BENCH/.heartbeat"
LOG="$BENCH/logs/watchdog.log"
AGENT_LOG="$BENCH/logs/agent-run.log"   # stdout/stderr of `opencode run` attempts
ATTDIR="$BENCH/.watchdog_attempts"
STATUS="$BENCH/.watchdog_last_status"
MODELIX="$BENCH/.watchdog_model_ix"
FORCE_MODEL="$BENCH/.watchdog_force_model"
COMPLETE="$BENCH/TASK_COMPLETE"
SESSION_ID="ses_f31799c77ffeTq9gcYgqc4hBhg"
STALE_S=900      # heartbeat older than 15 min => agent presumed dead
WINDOW_MIN=360   # rate-limit window
MAX_ATTEMPTS=6   # max restarts per window

# Free models, tried in order when the default model is quota-limited.
FREE_MODELS=(
  "opencode/mimo-v2.6-flash-free"
  "opencode/muse-spark-1.3-contributor-free"
  "opencode/ling-3.0-flash-fin-free"
  "opencode/nemotron-3.5-lightning-free"
)

mkdir -p "$BENCH/logs" "$ATTDIR"
log() { echo "$(date -Is) [watchdog] $*" >>"$LOG"; }

[ -f "$COMPLETE" ] && exit 0

n=$(find "$ATTDIR" -type f -mmin "-$WINDOW_MIN" 2>/dev/null | wc -l)
if [ "$n" -ge "$MAX_ATTEMPTS" ]; then
    log "rate-limited: $n restarts in last ${WINDOW_MIN}min, not restarting"
    exit 0
fi

if [ -f "$HEARTBEAT" ]; then
    age=$(( $(date +%s) - $(stat -c %Y "$HEARTBEAT") ))
else
    age=999999
fi
[ "$age" -lt "$STALE_S" ] && exit 0   # agent alive, nothing to do

# ---- classify previous failure (if any) ---------------------------------- #
last=0
[ -f "$STATUS" ] && last=$(cat "$STATUS" 2>/dev/null || echo 0)
quota=0
if [ "$last" != "0" ] && [ -f "$AGENT_LOG" ]; then
    if tail -c 200000 "$AGENT_LOG" 2>/dev/null | grep -Eiq \
        'rate.?limit|quota|too many requests|429|token[s]? (are |is )?(exhausted|exceeded)|context.{0,20}(length|window).{0,20}(exceed|too long)|insufficient.{0,10}credit'; then
        quota=1
        log "previous failure looks like quota/context exhaustion"
    fi
fi

# ---- pick model ----------------------------------------------------------- #
MODEL_ARGS=()
if [ "$quota" = "1" ]; then
    ix=0
    [ -f "$MODELIX" ] && ix=$(cat "$MODELIX" 2>/dev/null || echo 0)
    pick="${FREE_MODELS[$(( ix % ${#FREE_MODELS[@]} ))]}"
    echo $(( (ix + 1) % ${#FREE_MODELS[@]} )) >"$MODELIX"
    MODEL_ARGS=(--model "$pick")
    touch "$FORCE_MODEL"
    log "forcing free model: $pick"
elif [ "$last" = "0" ]; then
    rm -f "$FORCE_MODEL"   # healthy run -> back to default model next time
elif [ -f "$FORCE_MODEL" ]; then
    # previous non-quota failure while forced: keep rotating through free models
    ix=0
    [ -f "$MODELIX" ] && ix=$(cat "$MODELIX" 2>/dev/null || echo 0)
    pick="${FREE_MODELS[$(( ix % ${#FREE_MODELS[@]} ))]}"
    echo $(( (ix + 1) % ${#FREE_MODELS[@]} )) >"$MODELIX"
    MODEL_ARGS=(--model "$pick")
    log "rotating free model after failure: $pick"
fi

# ---- session vs fresh ----------------------------------------------------- #
if [ "$last" = "0" ]; then
    MODE=continue
else
    MODE=fresh
fi

touch "$ATTDIR/$(date +%s)"
log "heartbeat stale ${age}s -> restarting agent (mode=$MODE model_args='${MODEL_ARGS[*]:-default}')"

CONT_PPT="Continue the metagenomic-binning-benchmark task you were working on; you may have been interrupted. First read /vol/data/benchmark/PROGRESS.md, verify the 'Current state' section against what is actually on disk, then resume from the first unfinished step. Update PROGRESS.md as you go, touch /vol/data/benchmark/.heartbeat in your shell commands while active, and append one timestamped line per meaningful action to /vol/data/repos/metagenomic-binning-benchmark/status/agent-activity.log. If /vol/data/benchmark/TASK_COMPLETE exists, do nothing and exit."
FRESH_PPT="You are resuming the metagenomic-binning-benchmark project after an agent restart (the previous session may have crashed, run out of context, or exhausted model tokens). Read /vol/data/benchmark/PROGRESS.md FIRST — it contains the full task definition and current state — then verify state on disk and continue from the first unfinished step. Update PROGRESS.md as you go, touch /vol/data/benchmark/.heartbeat in your shell commands while active, and append one timestamped line per meaningful action to /vol/data/repos/metagenomic-binning-benchmark/status/agent-activity.log. If /vol/data/benchmark/TASK_COMPLETE exists, do nothing and exit."

if [ "$MODE" = "continue" ]; then
    opencode run --auto --session "$SESSION_ID" --title "watchdog-restart" \
        "${MODEL_ARGS[@]}" "$CONT_PPT" >>"$AGENT_LOG" 2>&1
else
    opencode run --auto --title "watchdog-restart" \
        "${MODEL_ARGS[@]}" "$FRESH_PPT" >>"$AGENT_LOG" 2>&1
fi
rc=$?
echo "$rc" >"$STATUS"
log "agent run (mode=$MODE) exited rc=$rc"
exit 0
