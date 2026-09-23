#!/usr/bin/env bash
# meta-watchdog.sh — supervisor of the whole automation (cron every 10 min).
#   Watches the WATCHERS. Runs deterministic health checks against the
#   automation architecture (cron jobs, opencode service, agent driver,
#   watchdog rate-limiter, GitHub push, benchmark run, disk, GitHub issues).
#   It auto-fixes the cheap deterministic breakages and, when something needs
#   judgement (or a fix failed), escalates to an LLM supervisor agent
#   (`opencode run --auto --title supervisor-fix`), whose transcript is logged
#   and pushed to GitHub.
#
# Check results are pushed to the repo under status/meta/ (checks.tsv +
# last.txt + issues.tsv), so the whole ops history is public on GitHub.
#
# Issues checking: every open issue is compared against
#   $BENCH/meta/.issues_seen/<number>   (epoch of last known updatedAt)
# A NEW or UPDATED issue triggers an LLM escalation (triage / respond). The
# marker is refreshed after escalation so the same issue is not re-fired.
set -u
export HOME=/home/ubuntu
export PATH=/home/ubuntu/.opencode/bin:/home/ubuntu/.local/bin:/usr/local/bin:/usr/bin:/bin
export GIT_TERMINAL_PROMPT=0

BENCH=/vol/data/benchmark
REPO=/vol/data/repos/metagenomic-binning-benchmark
META="$BENCH/meta"
SEEN="$META/.issues_seen"
ESCAL="$META/.escalations"
LOG="$BENCH/logs/meta-watchdog.log"
SUPLOG="$BENCH/logs/supervisor-run.log"
LOCK=/tmp/meta-watchdog.lock
REPO_LOCK=/tmp/bench-repo.lock
COMPLETE="$BENCH/TASK_COMPLETE"
REPO_URL=paulzierep/metagenomic-binning-benchmark

STALE_S=900
RATE_WINDOW_MIN=360
MAX_ESCAL=3          # LLM escalations per window (cost guard)
ISSUE_ESCAL_MIN=120  # don't re-escalate the same issue update within 2 h
HANG_S=2400

mkdir -p "$META" "$SEEN" "$ESCAL" "$META" "$REPO/status/meta"
log() { echo "$(date -Is) [meta] $*" >>"$LOG"; }

exec 9>"$LOCK"
flock -n 9 || exit 0
[ -f "$COMPLETE" ] && exit 0

now=$(date +%s)
now_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
: > "$META/checks.tsv"   # name<TAB>ok|degraded|broken<TAB>evidence

check() { printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$META/checks.tsv"; }

fixes=0
note_fix() { fixes=$((fixes+1)); log "AUTO-FIX: $*"; }

# ---- C1: cron jobs installed ----------------------------------------------- #
missing=()
for job in agent-watchdog.sh status-heartbeat.sh benchmark-watchdog.sh meta-watchdog.sh; do
    crontab -l 2>/dev/null | grep -q "$job" || missing+=("$job")
done
if [ "${#missing[@]}" -eq 0 ]; then
    check C1_cron ok "all 4 jobs present"
else
    check C1_cron broken "missing: ${missing[*]}"
    # idempotent reinstall (drops stale duplicate lines first)
    { crontab -l 2>/dev/null | grep -vE 'agent-watchdog\.sh|status-heartbeat\.sh|benchmark-watchdog\.sh|meta-watchdog\.sh'
      echo '*/5 * * * * /vol/data/benchmark/bin/agent-watchdog.sh'
      echo '*/10 * * * * /vol/data/benchmark/bin/status-heartbeat.sh'
      echo '*/5 * * * * /vol/data/benchmark/bin/benchmark-watchdog.sh'
      echo '3,13,23,33,43,53 * * * * /vol/data/benchmark/bin/meta-watchdog.sh'
    } | crontab -
    [ $? -eq 0 ] && note_fix "reinstalled cron jobs (${missing[*]})"
fi

# ---- C2: opencode service alive -------------------------------------------- #
if pgrep -f "opencode serve --service" >/dev/null 2>&1; then
    check C2_service ok "pid $(pgrep -f 'opencode serve --service' | head -1)"
else
    check C2_service broken "no 'opencode serve --service' process"
    opencode service start >/dev/null 2>&1 || opencode service restart >/dev/null 2>&1
    sleep 3
    pgrep -f "opencode serve --service" >/dev/null 2>&1 && note_fix "restarted opencode service"
fi

# ---- C3: agent driver / agent activity ------------------------------------- #
run_alive=0; pgrep -f "[o]pencode run --auto" >/dev/null 2>&1 && run_alive=1
drv_alive=0; pgrep -f "[a]gent-watchdog.sh" >/dev/null 2>&1 && drv_alive=1
hb_age=999999; [ -f "$BENCH/.heartbeat" ] && hb_age=$(( now - $(stat -c %Y "$BENCH/.heartbeat") ))
tl_age=999999; [ -f "$BENCH/logs/agent-run.log" ] && tl_age=$(( now - $(stat -c %Y "$BENCH/logs/agent-run.log") ))
if [ "$run_alive" = "1" ] || [ "$hb_age" -lt "$STALE_S" ] || [ "$tl_age" -lt "$STALE_S" ]; then
    check C3_agent ok "run_alive=$run_alive hb=${hb_age}s transcript=${tl_age}s"
elif [ "$drv_alive" = "1" ]; then
    check C3_agent degraded "driver alive but between turns (hb=${hb_age}s transcript=${tl_age}s)"
else
    check C3_agent broken "no driver; hb=${hb_age}s transcript=${tl_age}s"
    bash "$BENCH/bin/agent-watchdog.sh" >/dev/null 2>&1 &
    note_fix "agent idle with no driver -> relaunched agent-watchdog.sh"
fi

# ---- C4: watchdog not rate-locked ------------------------------------------ #
attempts=$(find "$BENCH/.watchdog_attempts" -type f -mmin "-$RATE_WINDOW_MIN" 2>/dev/null | wc -l)
if [ "$attempts" -ge 6 ]; then
    if [ "$run_alive" = "1" ] || [ "$drv_alive" = "1" ]; then
        check C4_ratelimit degraded "attempts=$attempts but a driver/run is alive"
    else
        check C4_ratelimit broken "attempts=$attempts and nothing running -> deadlock"
        rm -f "$BENCH/.watchdog_attempts"/*
        note_fix "cleared crash-guard markers ($attempts) with no driver alive"
        bash "$BENCH/bin/agent-watchdog.sh" >/dev/null 2>&1 &
    fi
else
    check C4_ratelimit ok "attempts=$attempts in ${RATE_WINDOW_MIN}min window"
fi

# ---- C5: GitHub push freshness --------------------------------------------- #
push_age=$(( now - $(git -C "$REPO" log -1 --format=%ct 2>/dev/null || echo "$now") ))
if [ "$push_age" -lt 1500 ]; then
    check C5_github ok "last push ${push_age}s ago"
else
    check C5_github broken "last push ${push_age}s ago"
    bash "$BENCH/bin/status-heartbeat.sh" >/dev/null 2>&1 &
    note_fix "github push stale -> ran status-heartbeat.sh"
fi

# ---- C6: benchmark run alive & progressing --------------------------------- #
if [ -f "$BENCH/.active_run" ]; then
    read -r bid bpgid blog bdir bstart < "$BENCH/.active_run"
    b_alive=0; [ -n "${bid:-}" ] && kill -0 "$bid" 2>/dev/null && b_alive=1
    b_age=999999
    [ -f "${blog:-}" ] && b_age=$(( now - $(stat -c %Y "$blog") ))
    if [ "$b_alive" = "1" ] && [ "$b_age" -lt "$HANG_S" ]; then
        check C6_benchmark ok "pid $bid alive, log ${b_age}s fresh"
    elif [ "$b_alive" = "1" ]; then
        check C6_benchmark broken "pid $bid alive but hung ${b_age}s"
        bash "$BENCH/bin/benchmark-watchdog.sh" >/dev/null 2>&1 &
        note_fix "benchmark run hung -> invoked benchmark-watchdog.sh"
    else
        check C6_benchmark broken "pid $bid gone"
        bash "$BENCH/bin/benchmark-watchdog.sh" >/dev/null 2>&1 &
        note_fix "benchmark pid gone -> invoked benchmark-watchdog.sh"
    fi
else
    check C6_benchmark ok "no active run (idle is fine)"
fi

# ---- C7: disk ---------------------------------------------------------------- #
avail_kb=$(df -Pk /vol/data 2>/dev/null | awk 'NR==2{print $4}')
if [ -n "${avail_kb:-0}" ] && [ "$avail_kb" -gt 5242880 ]; then
    check C7_disk ok "$(( avail_kb / 1024 / 1024 )) GiB free"
else
    check C7_disk broken "$(( avail_kb / 1024 / 1024 )) GiB free on /vol/data"
fi

# ---- C8: GitHub issues (new / updated?) -------------------------------------- #
new_issue=""
gh issue list -R "$REPO_URL" --state open --json number,title,updatedAt \
    -q '.[] | [.number, .title, .updatedAt] | @tsv' 2>/dev/null > "$META/issues.tsv"
while IFS=$'\t' read -r num title updated; do
    [ -n "${num:-}" ] || continue
    up_epoch=$(date -d "$updated" +%s 2>/dev/null || echo 0)
    seen=$(cat "$SEEN/$num" 2>/dev/null || echo 0)
    if [ -z "$seen" ]; then seen=0; fi
    if [ "$up_epoch" -gt "$seen" ]; then
        if [ "$seen" = "0" ] || [ $(( now - seen )) -gt "$ISSUE_ESCAL_MIN" ]; then
            new_issue="$new_issue #$num ($title) updated=$updated"
        fi
        echo "$up_epoch" > "$SEEN/$num"
    fi
done < "$META/issues.tsv"
if [ -z "$new_issue" ]; then
    check C8_issues ok "$(wc -l < "$META/issues.tsv") open, none new"
else
    check C8_issues broken "new/updated:$new_issue"
fi

# ---- publish meta artifacts to GitHub ---------------------------------------- #
mkdir -p "$REPO/status/meta"
cp "$META/issues.tsv" "$REPO/status/meta/issues.tsv" 2>/dev/null || true
{ echo "# Meta-supervisor check — $now_utc — $fixes auto-fix(es) applied"; echo
  column -t -s $'\t' "$META/checks.tsv" 2>/dev/null || cat "$META/checks.tsv"; } > "$META/last.txt"
( exec 8>"$REPO_LOCK"
  flock -w 20 8 || exit 0
  cd "$REPO" || exit 0
  cp "$META/last.txt" "$META/issues.tsv" status/meta/ 2>/dev/null || true
  git add status/meta
  git commit -q -m "meta: supervise tick $now_utc — $fixes fix(es)" 2>/dev/null || true
  git push -q 2>/dev/null || true )

# ---- escalate to the LLM supervisor when needed ------------------------------- #
need_llm=0
grep -q '	broken	' "$META/checks.tsv" && need_llm=1
escalations=$(find "$ESCAL" -type f -mmin "-$RATE_WINDOW_MIN" 2>/dev/null | wc -l)
if [ "$need_llm" = "1" ] && [ "$escalations" -lt "$MAX_ESCAL" ]; then
    touch "$ESCAL/$(date +%s)"
    bundle="$META/escalate-$(date +%s).txt"
    {
        echo "META-SUPERVISOR ESCALATION — $now_utc"
        echo "Automatic fixes applied this tick: $fixes"
        echo
        echo "--- health checks ---"
        column -t -s $'\t' "$META/checks.tsv" 2>/dev/null
        echo
        echo "--- recent watchdog log ---"
        tail -15 "$BENCH/logs/watchdog.log" 2>/dev/null
        echo
        echo "--- open issues ---"
        cat "$META/issues.tsv" 2>/dev/null
    } > "$bundle"
    log "escalating to LLM supervisor (esc #$((escalations+1))/$MAX_ESCAL): $bundle"
    prompt="You are the SUPERVISOR agent for the metagenomic-binning-benchmark automation on this VM. Inspect the diagnostics below, then FIX everything that is broken or degraded (edit scripts under /vol/data/benchmark/bin, restart drivers/services, clear stale state, reinstall cron jobs, re-run watchdogs, and for NEW/updated GitHub issues triage them and post a comment if that is the right fix). Verify each fix, append one timestamped line about what you did to /vol/data/benchmark/logs/supervisor-actions.log, and push changes to GitHub (repo at /vol/data/repos/metagenomic-binning-benchmark). Do NOT touch the active benchmark training run. If everything is actually fine, reply with a short OK. Diagnostics: $(cat "$bundle")"
    opencode run --auto --title "supervisor-fix" "$prompt" >>"$SUPLOG" 2>&1
    log "supervisor agent exited rc=$?"
elif [ "$need_llm" = "1" ]; then
    log "broken checks present but escalation budget exhausted ($escalations/$MAX_ESCAL) — skipping"
fi

echo "$(date -Is) tick done: fixes=$fixes broken=$(grep -c '	broken	' "$META/checks.tsv") escalated=$need_llm" >>"$LOG"
exit 0