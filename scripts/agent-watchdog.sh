#!/usr/bin/env bash
# agent-watchdog.sh — keep the OpenCode agent working on the benchmark task.
#
# WHY THIS FILE EXISTS / WHAT CHANGED (2026-09-23):
#   `opencode run --auto` is a SINGLE-TURN command in v2: it sends the prompt,
#   the agent completes ONE assistant turn, prints "Turn complete" and exits 0.
#   The old design launched one run per cron tick and then waited for the
#   heartbeat to go stale — so the agent effectively never got more than one
#   turn per ~20 min, and after 6 launches it hit the crash-loop rate limit
#   and stayed stopped for hours ("agent is always stopped").
#
#   Now the watchdog drives a PERSISTENT LOOP (see run_driver below): each
#   cron invocation that finds the agent idle starts a driver that keeps
#   calling `opencode run --auto --session <id>` — one turn per call, same
#   session, so context carries over — until the task is done, the agent
#   crashes, or a hard time/turn budget is hit. A flock guarantees only ONE
#   driver exists at a time; the next cron tick just skips while it's alive.
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
LOCK=${AGENT_WATCHDOG_LOCK:-/tmp/agent-watchdog.lock}
SESSION_ID="ses_f31799c77ffeTq9gcYgqc4hBhg"
STALE_S=900            # heartbeat/transcript older than 15 min => agent presumed idle
WINDOW_MIN=360         # crash-loop rate-limit window
MAX_ATTEMPTS=6         # max driver LAUNCHES per window
MAX_TURNS=200          # hard cap per driver (avoids a runaway forever-loop)
MAX_RUNTIME_S=28800    # hard cap per driver: 8 h; next cron tick relaunches
TURN_TIMEOUT_S=3600    # hard cap for one opencode turn; prevents a hung child
TURN_GAP_S=30          # pause between turns
IDLE_GAP_S=600         # longer pause when the agent says it is waiting/idle
QUOTA_RETRIES=3        # consecutive quota-limited runs before giving up to cron

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

# ---- single driver at a time ---------------------------------------------- #
exec 9>"$LOCK"
flock -n 9 || { log "skipped: another driver holds the lock"; exit 0; }

# ---- is the agent already alive? ------------------------------------------ #
hb_age=999999
[ -f "$HEARTBEAT" ] && hb_age=$(( $(date +%s) - $(stat -c %Y "$HEARTBEAT") ))
tl_age=999999
[ -f "$AGENT_LOG" ] && tl_age=$(( $(date +%s) - $(stat -c %Y "$AGENT_LOG") ))
run_alive=0
# Match only the primary session's argv prefix. A broad "opencode run --auto"
# search also matches supervisor runs and can falsely suppress the agent driver.
if ps -eo args= | awk -v p="opencode run --auto --session $SESSION_ID" 'index($0,p)==1{found=1} END{exit !found}'; then
    run_alive=1
fi

alive=0
[ "$run_alive" = "1" ] && alive=1
# Once this script owns the lock, no legitimate driver exists. A fresh global
# heartbeat/transcript can be left by a dead driver (or the supervisor), so it
# must not suppress a restart; the scoped live child is the reliable evidence.
[ "$alive" = "1" ] && exit 0

# ---- crash-loop guard (counts DRIVER LAUNCHES, not turns) ------------------- #
n=$(find "$ATTDIR" -type f -mmin "-$WINDOW_MIN" 2>/dev/null | wc -l)
if [ "$n" -ge "$MAX_ATTEMPTS" ]; then
    log "rate-limited: $n launches in last ${WINDOW_MIN}min, not restarting"
    exit 0
fi

# ---- classify the previous run's failure (if any) -------------------------- #
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

# ---- pick start model ------------------------------------------------------- #
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
    rm -f "$FORCE_MODEL"   # healthy run -> default model
elif [ -f "$FORCE_MODEL" ]; then
    ix=0
    [ -f "$MODELIX" ] && ix=$(cat "$MODELIX" 2>/dev/null || echo 0)
    pick="${FREE_MODELS[$(( ix % ${#FREE_MODELS[@]} ))]}"
    echo $(( (ix + 1) % ${#FREE_MODELS[@]} )) >"$MODELIX"
    MODEL_ARGS=(--model "$pick")
    log "rotating free model after failure: $pick"
fi

# ---- launch ONE driver (it loops turns itself) ------------------------------ #
# Count a launch toward the crash-loop budget only after a FAILED run, so
# healthy steady-state relaunches never accumulate markers (issue #4 fix).
[ "$last" = "0" ] || touch "$ATTDIR/$(date +%s)"
age=$(( hb_age < tl_age ? hb_age : tl_age ))
log "agent idle (hb ${hb_age}s, transcript ${tl_age}s, run_alive=$run_alive) -> launching driver (model_args='${MODEL_ARGS[*]:-default}')"

CONT_PPT="Continue the metagenomic-binning-benchmark task you were working on; you may have been interrupted. First read /vol/data/benchmark/PROGRESS.md, verify the 'Current state' section against what is actually on disk, then check NEW/updated issues with: gh issue list -R paulzierep/metagenomic-binning-benchmark --state open --json number,title,updatedAt and gh issue list -R paulzierep/COMEBin --state open --json number,title,updatedAt. Triage and comment on actionable updates without duplicating an existing response. Resume from the first unfinished step. Update PROGRESS.md and /vol/data/benchmark/.activity, touch /vol/data/benchmark/.heartbeat in shell commands while active, and append one timestamped line per meaningful action to /vol/data/repos/metagenomic-binning-benchmark/status/agent-activity.log. Before final git stage/commit/push, acquire /tmp/bench-repo.lock and commit only intended paths. Never overlap the registered benchmark run. If /vol/data/benchmark/TASK_COMPLETE exists, do nothing and exit."
FRESH_PPT="You are resuming the metagenomic-binning-benchmark project after an agent restart (the previous session may have crashed, run out of context, or exhausted model tokens). Read /vol/data/benchmark/PROGRESS.md FIRST, then check NEW/updated issues in paulzierep/metagenomic-binning-benchmark and paulzierep/COMEBin with gh issue list --state open --json number,title,updatedAt; triage and comment without duplicating an existing response. Verify state on disk and continue from the first unfinished step. Update PROGRESS.md and /vol/data/benchmark/.activity, touch /vol/data/benchmark/.heartbeat in shell commands while active, and append one timestamped line per meaningful action to /vol/data/repos/metagenomic-binning-benchmark/status/agent-activity.log. Before final git stage/commit/push, acquire /tmp/bench-repo.lock and commit only intended paths. Never overlap the registered benchmark run. If /vol/data/benchmark/TASK_COMPLETE exists, do nothing and exit."

run_driver() {
    local turns=0 start rc=0 quota_hits=0 healthy_turns=0 before after
    start=$(date +%s)
    while :; do
        [ $(date +%s) -ge $(( start + MAX_RUNTIME_S )) ] && { log "driver hit ${MAX_RUNTIME_S}s runtime cap"; break; }
        [ "$turns" -ge "$MAX_TURNS" ] && { log "driver hit turns cap ($MAX_TURNS)"; break; }
        [ -f "$COMPLETE" ] && { log "driver: TASK_COMPLETE present, exiting"; break; }

        # first iteration after a previous failure starts a fresh session once
        if [ "$turns" = "0" ] && [ "$last" != "0" ]; then
            prompt="$FRESH_PPT"; sargs=()
        else
            prompt="$CONT_PPT"; sargs=(--session "$SESSION_ID")
        fi
        [ -f "$FORCE_MODEL" ] || MODEL_ARGS=()

        before=$(wc -c < "$AGENT_LOG" 2>/dev/null || echo 0)
        log "driver turn #$((turns+1)): model=${MODEL_ARGS[*]:-default} | opencode run ${sargs[*]:-fresh}"
        timeout --foreground --kill-after=30s "${TURN_TIMEOUT_S}s" \
            opencode run --auto "${sargs[@]}" "${MODEL_ARGS[@]}" --title "watchdog-restart" \
            "$prompt" >>"$AGENT_LOG" 2>&1 9>&-
        rc=$?
        after=$(wc -c < "$AGENT_LOG" 2>/dev/null || echo 0)
        log "driver turn #$((turns+1)) exited rc=$rc (transcript ${before}->${after}B)"
        turns=$((turns + 1))

        # a successful turn cleared the forced-model flag so the default model resumes
        [ "$rc" = "0" ] && rm -f "$FORCE_MODEL"

        if [ "$rc" = "0" ]; then
            if [ "$after" -gt "$before" ]; then
                healthy_turns=$((healthy_turns + 1))
                quota_hits=0
            fi
            # done with a turn that made progress — keep going (next turn shortly)
            # if the agent ended the turn saying it is waiting, back off longer
            gap=$TURN_GAP_S
            if tail -c 6000 "$AGENT_LOG" | grep -Eiq 'nothing (else )?(to do|left)|waiting for|just waiting|idle until|no new (issues|work)|nothing pending'; then
                gap=$IDLE_GAP_S
            fi
            log "driver turn #$((turns+1)) healthy; next turn in ${gap}s"
            sleep "$gap"
            continue
        else
            # classify: quota/context exhaustion -> rotate model and retry a bit
            if tail -c 200000 "$AGENT_LOG" 2>/dev/null | grep -Eiq \
                'rate.?limit|quota|too many requests|429|token[s]? (are |is )?(exhausted|exceeded)|context.{0,20}(length|window).{0,20}(exceed|too long)|insufficient.{0,10}credit'; then
                quota_hits=$((quota_hits + 1))
                ix=0; [ -f "$MODELIX" ] && ix=$(cat "$MODELIX" 2>/dev/null || echo 0)
                pick="${FREE_MODELS[$(( ix % ${#FREE_MODELS[@]} ))]}"
                echo $(( (ix + 1) % ${#FREE_MODELS[@]} )) >"$MODELIX"
                MODEL_ARGS=(--model "$pick")
                touch "$FORCE_MODEL"
                log "turn rc=$rc looks quota-limited -> rotate to $pick (hit $quota_hits/$QUOTA_RETRIES)"
                if [ "$quota_hits" -ge "$QUOTA_RETRIES" ]; then
                    log "driver giving up after $quota_hits quota-limited runs; cron will retry"
                    break
                fi
                continue
            fi
            log "driver: run failed rc=$rc; stopping, cron will relaunch"
            break
        fi

        sleep "$TURN_GAP_S"
    done
    # Only verified successful, progress-producing turns clear crash history;
    # failed/quota turns must never reset the guard by merely being counted.
    if [ "$healthy_turns" -ge 2 ]; then
        find "$ATTDIR" -type f -delete 2>/dev/null
        log "driver healthy after $healthy_turns successful turns: crash-guard markers cleared"
    fi
    echo "$rc" >"$STATUS"
    log "driver ended after $turns turns ($healthy_turns successful; rc=$rc)"
}

run_driver
exit 0
