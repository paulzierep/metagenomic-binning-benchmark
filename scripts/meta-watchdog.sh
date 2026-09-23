#!/usr/bin/env bash
# meta-watchdog.sh — supervisor of the whole automation (cron every 10 min).
# Runs deterministic health checks, performs safe automatic repairs, publishes
# status/meta, and escalates unresolved broken/degraded checks to an LLM.
# A NEW/updated issue is marked handled only after a successful supervisor run;
# this prevents a failed/over-budget escalation from being silently lost.
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
LOCK=${META_WATCHDOG_LOCK:-/tmp/meta-watchdog.lock}
AGENT_LOCK=/tmp/agent-watchdog.lock
REPO_LOCK=${BENCH_REPO_LOCK:-/tmp/bench-repo.lock}
COMPLETE="$BENCH/TASK_COMPLETE"
REPO_URL=paulzierep/metagenomic-binning-benchmark
SESSION_ID=ses_f31799c77ffeTq9gcYgqc4hBhg

STALE_S=900
RATE_WINDOW_MIN=360
MAX_ESCAL=3
HANG_S=2400
# Test hook: run every health check but never launch an LLM.
NO_LLM=${META_WATCHDOG_NO_LLM:-0}

mkdir -p "$META" "$SEEN" "$ESCAL" "$REPO/status/meta"
log() { echo "$(date -Is) [meta] $*" >>"$LOG"; }

exec 9>"$LOCK"
flock -n 9 || exit 0
[ -f "$COMPLETE" ] && exit 0

now=$(date +%s)
now_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
: > "$META/checks.tsv"
check() { printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$META/checks.tsv"; }
fixes=0
note_fix() { fixes=$((fixes + 1)); log "AUTO-FIX: $*"; }

service_pid() {
  local info pid
  opencode service status >/dev/null 2>&1 || return 1
  info=$(opencode api get /api/info 2>/dev/null) || return 1
  pid=$(printf '%s' "$info" | sed -n 's/.*"pid":\([0-9][0-9]*\).*/\1/p')
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null || return 1
  printf '%s' "$pid"
}

# ---- C1: exact cron jobs + executable installed scripts --------------------- #
cron_bad=""
cron_text=$(crontab -l 2>/dev/null || true)
while IFS='|' read -r expected job; do
  count=$(printf '%s\n' "$cron_text" | grep -Fxc -- "$expected" || true)
  count=${count:-0}
  [ "$count" -eq 1 ] || cron_bad="$cron_bad $job(cron=$count)"
  [ -x "/vol/data/benchmark/bin/$job" ] || cron_bad="$cron_bad $job(not-executable)"
done <<'EOF'
*/5 * * * * /vol/data/benchmark/bin/agent-watchdog.sh|agent-watchdog.sh
*/2 * * * * /vol/data/benchmark/bin/status-heartbeat.sh|status-heartbeat.sh
*/5 * * * * /vol/data/benchmark/bin/benchmark-watchdog.sh|benchmark-watchdog.sh
3,13,23,33,43,53 * * * * /vol/data/benchmark/bin/meta-watchdog.sh|meta-watchdog.sh
EOF
if ! systemctl is-active --quiet cron.service; then cron_bad="$cron_bad cron.service(inactive)"; fi
if [ -z "$cron_bad" ]; then
  check C1_cron ok "all 4 exact jobs present; scripts executable; cron active"
else
  chmod +x /vol/data/benchmark/bin/agent-watchdog.sh \
    /vol/data/benchmark/bin/status-heartbeat.sh \
    /vol/data/benchmark/bin/benchmark-watchdog.sh \
    /vol/data/benchmark/bin/meta-watchdog.sh 2>/dev/null || true
  { printf '%s\n' "$cron_text" | grep -vE 'agent-watchdog\.sh|status-heartbeat\.sh|benchmark-watchdog\.sh|meta-watchdog\.sh' || true
    echo '*/5 * * * * /vol/data/benchmark/bin/agent-watchdog.sh'
    echo '*/2 * * * * /vol/data/benchmark/bin/status-heartbeat.sh'
    echo '*/5 * * * * /vol/data/benchmark/bin/benchmark-watchdog.sh'
    echo '3,13,23,33,43,53 * * * * /vol/data/benchmark/bin/meta-watchdog.sh'
  } | crontab -
  cron_rc=$?
  systemctl is-active --quiet cron.service || sudo -n systemctl restart cron.service
  scripts_ok=1
  for job in agent-watchdog.sh status-heartbeat.sh benchmark-watchdog.sh meta-watchdog.sh; do
    [ -x "/vol/data/benchmark/bin/$job" ] || scripts_ok=0
  done
  if [ "$cron_rc" -eq 0 ] && [ "$scripts_ok" -eq 1 ] && systemctl is-active --quiet cron.service; then
    note_fix "reinstalled cron jobs and verified cron.service (was:$cron_bad)"
    check C1_cron ok "reinstalled: 4 exact jobs, cron active"
  else
    check C1_cron broken "cron repair failed (was:$cron_bad)"
  fi
fi

# ---- C2: OpenCode service status + real API health -------------------------- #
if service_pid=$(service_pid); then
  check C2_service ok "pid $service_pid; service status + /api/info healthy"
else
  opencode service restart >/dev/null 2>&1 || true
  sleep 3
  if service_pid=$(service_pid); then
    note_fix "restarted unhealthy OpenCode service (pid $service_pid)"
    check C2_service ok "restarted; API healthy (pid $service_pid)"
  else
    check C2_service broken "service status/API unhealthy after restart"
  fi
fi

# ---- C3: primary agent driver / scoped run / heartbeat ---------------------- #
run_alive=0
if ps -eo args= | awk -v p="opencode run --auto --session $SESSION_ID" 'index($0,p)==1{found=1} END{exit !found}'; then
  run_alive=1
fi
drv_alive=0
# A busy lock is the authoritative signal that a driver owns the flock.
if ! flock -n "$AGENT_LOCK" -c true 2>/dev/null; then drv_alive=1; fi
hb_age=999999; [ -f "$BENCH/.heartbeat" ] && hb_age=$((now - $(stat -c %Y "$BENCH/.heartbeat")))
tl_age=999999; [ -f "$BENCH/logs/agent-run.log" ] && tl_age=$((now - $(stat -c %Y "$BENCH/logs/agent-run.log")))
if [ "$run_alive" -eq 1 ] || [ "$drv_alive" -eq 1 ]; then
  check C3_agent ok "run_alive=$run_alive driver=$drv_alive hb=${hb_age}s transcript=${tl_age}s"
else
  bash "$BENCH/bin/agent-watchdog.sh" >/dev/null 2>&1 &
  launched=$!
  sleep 2
  if kill -0 "$launched" 2>/dev/null || ! flock -n "$AGENT_LOCK" -c true 2>/dev/null; then
    run_alive=0; drv_alive=1
    note_fix "agent idle with no driver -> relaunched agent-watchdog.sh (pid $launched)"
    check C3_agent ok "auto-relaunched driver pid $launched"
  else
    check C3_agent broken "agent idle and driver relaunch failed"
  fi
fi

# ---- C4: crash-guard is not deadlocked ------------------------------------- #
attempts=$(find "$BENCH/.watchdog_attempts" -type f -mmin "-$RATE_WINDOW_MIN" 2>/dev/null | wc -l)
if [ "$attempts" -ge 6 ]; then
  if [ "$run_alive" -eq 1 ] || [ "$drv_alive" -eq 1 ]; then
    find "$BENCH/.watchdog_attempts" -type f -delete 2>/dev/null || true
    note_fix "cleared $attempts stale crash-guard markers while driver/run is healthy"
    check C4_ratelimit ok "cleared stale markers=$attempts; driver/run alive"
  else
    check C4_ratelimit broken "$attempts failed launches in window and no driver; preserving crash guard"
  fi
else
  check C4_ratelimit ok "failed-launch markers=$attempts in ${RATE_WINDOW_MIN}min window"
fi

# ---- C5: actual local/origin parity and pending status sync ----------------- #
fetch_ok=0
git -C "$REPO" fetch -q origin main && fetch_ok=1
head_sha=$(git -C "$REPO" rev-parse HEAD 2>/dev/null || echo none)
remote_sha=$(git -C "$REPO" rev-parse refs/remotes/origin/main 2>/dev/null || echo none)
pending=$(git -C "$REPO" status --porcelain -- README.md status runs 2>/dev/null || true)
last_age=$((now - $(git -C "$REPO" log -1 --format=%ct 2>/dev/null || echo "$now")))
if [ "$fetch_ok" -eq 1 ] && [ "$head_sha" = "$remote_sha" ] && [ -z "$pending" ]; then
  check C5_github ok "HEAD=origin/main ${head_sha:0:12}; status artifacts clean; last commit ${last_age}s"
else
  bash "$BENCH/bin/status-heartbeat.sh" >/dev/null 2>&1 || true
  git -C "$REPO" fetch -q origin main || true
  head_sha=$(git -C "$REPO" rev-parse HEAD 2>/dev/null || echo none)
  remote_sha=$(git -C "$REPO" rev-parse refs/remotes/origin/main 2>/dev/null || echo none)
  pending=$(git -C "$REPO" status --porcelain -- README.md status runs 2>/dev/null || true)
  if [ "$head_sha" = "$remote_sha" ] && [ -z "$pending" ]; then
    note_fix "GitHub/status sync repaired (HEAD=origin/main ${head_sha:0:12})"
    check C5_github ok "auto-repaired local/origin parity and pending status files"
  else
    check C5_github broken "HEAD=${head_sha:0:12} origin=${remote_sha:0:12}; pending=$(printf '%s' "$pending" | wc -l) file(s)"
  fi
fi

# ---- C6: registered benchmark alive, correct process, and progressing ------- #
if [ -f "$BENCH/.active_run" ]; then
  read -r bid bpgid blog bdir bstart bmode bsource < "$BENCH/.active_run" || true
  b_alive=0
  b_stat=$(ps -o stat= -p "${bid:-0}" 2>/dev/null | tr -d ' ' || true)
  b_cmd=""
  if [ -n "$b_stat" ] && kill -0 "${bid:-0}" 2>/dev/null && [[ "$b_stat" != Z* ]]; then
    b_alive=1
    b_cmd=$(tr '\0' ' ' < "/proc/${bid:-0}/cmdline" 2>/dev/null || true)
  fi
  b_age=999999; [ -n "${blog:-}" ] && [ -f "$blog" ] && b_age=$((now - $(stat -c %Y "$blog")))
  runner_ok=0
  case "$b_cmd" in *run_comebin_baseline.sh*|*run_comebin_fix.sh*|*run_small_test.sh*) runner_ok=1 ;; esac
  if [ "$b_alive" -eq 1 ] && [ "$runner_ok" -eq 0 ]; then
    check C6_benchmark broken "pid $bid alive but command is not a registered COMEBin runner; refusing kill"
  elif [ "$b_alive" -eq 0 ]; then
    done_rc=$(grep -m1 '^exit_code:' "${bdir:-/nonexistent}/run_meta.txt" 2>/dev/null | awk '{print $2}' || true)
    if [ "${done_rc:-}" = "0" ]; then
      bash "$BENCH/bin/benchmark-watchdog.sh" >/dev/null 2>&1 || true
      if [ ! -f "$BENCH/.active_run" ]; then
        note_fix "completed benchmark registration cleared"
        check C6_benchmark ok "run completed rc=0; stale active registration cleared"
      else
        check C6_benchmark broken "run completed rc=0 but active registration remains"
      fi
    else
      bash "$BENCH/bin/benchmark-watchdog.sh" >/dev/null 2>&1 &
      sleep 3
      new_bid=0
      [ -f "$BENCH/.active_run" ] && read -r new_bid _ < "$BENCH/.active_run" || true
      if [ -n "$new_bid" ] && [ "$new_bid" != "${bid:-0}" ] && kill -0 "$new_bid" 2>/dev/null; then
        note_fix "benchmark absent -> watchdog registered replacement pid $new_bid"
        check C6_benchmark ok "auto-restarted benchmark as pid $new_bid"
      else
        check C6_benchmark broken "benchmark pid ${bid:-?} gone; restart not verified"
      fi
    fi
  elif [ "$b_age" -lt "$HANG_S" ]; then
    check C6_benchmark ok "pid $bid mode=${bmode:-baseline} alive, log ${b_age}s fresh"
  else
    bash "$BENCH/bin/benchmark-watchdog.sh" >/dev/null 2>&1 &
    sleep 7
    new_bid=0
    [ -f "$BENCH/.active_run" ] && read -r new_bid _ < "$BENCH/.active_run" || true
    if [ -n "$new_bid" ] && [ "$new_bid" != "${bid:-0}" ] && kill -0 "$new_bid" 2>/dev/null; then
      note_fix "benchmark hung -> watchdog registered replacement pid $new_bid"
      check C6_benchmark ok "auto-restarted hung benchmark as pid $new_bid"
    else
      check C6_benchmark broken "benchmark pid $bid hung; restart not verified"
    fi
  fi
else
  check C6_benchmark ok "no active run (idle is fine)"
fi

# ---- C7: disk ---------------------------------------------------------------- #
avail_kb=$(df -Pk /vol/data 2>/dev/null | awk 'NR==2{print $4}')
if [ -n "${avail_kb:-0}" ] && [ "$avail_kb" -gt 5242880 ]; then
  check C7_disk ok "$((avail_kb / 1024 / 1024)) GiB free"
else
  check C7_disk broken "$(( ${avail_kb:-0} / 1024 / 1024 )) GiB free on /vol/data"
fi

# ---- C8: GitHub issues (new/updated; markers advance only after triage) ----- #
: > "$META/issues.tsv"
new_issue=""
issue_list_ok=0
if gh issue list -R "$REPO_URL" --state open --json number,title,updatedAt \
    -q '.[] | [.number, .title, .updatedAt] | @tsv' > "$META/issues.tsv" 2>/dev/null; then
  issue_list_ok=1
fi
candidate_nums=()
if [ "$issue_list_ok" -eq 1 ]; then
  while IFS=$'\t' read -r num title updated; do
    [ -n "${num:-}" ] || continue
    up_epoch=$(date -d "$updated" +%s 2>/dev/null || echo 0)
    seen=$(cat "$SEEN/$num" 2>/dev/null || echo 0)
    [ -n "$seen" ] || seen=0
    if [ "$up_epoch" -gt "$seen" ]; then
      candidate_nums+=("$num")
      new_issue="$new_issue #$num ($title) updated=$updated"
    fi
  done < "$META/issues.tsv"
fi
if [ "$issue_list_ok" -eq 0 ]; then
  check C8_issues broken "gh issue list failed; update state unknown"
elif [ -n "$new_issue" ]; then
  check C8_issues broken "new/updated:$new_issue"
else
  check C8_issues ok "$(wc -l < "$META/issues.tsv") open, none new"
fi

{ echo "# Meta-supervisor check — $now_utc — $fixes auto-fix(es) applied"; echo
  column -t -s $'\t' "$META/checks.tsv" 2>/dev/null || cat "$META/checks.tsv"; } > "$META/last.txt"

# ---- publish meta artifacts to GitHub ---------------------------------------- #
publish_ok=0
(
  exec 8>"$REPO_LOCK"
  flock -w 20 8 || exit 0
  cd "$REPO" || exit 0
  mkdir -p status/meta
  cp "$META/last.txt" "$META/issues.tsv" status/meta/ 2>/dev/null || true
  git add status/meta
  if ! git diff --cached --quiet -- status/meta; then
    git commit -q --only -m "meta: supervise tick $now_utc — $fixes fix(es)" -- status/meta || exit 0
  fi
  git push -q || exit 0
)
# Verify outside the publish subshell: a failed commit/push must not look healthy
# merely because an older local commit already equals origin/main.
if [ "$(git -C "$REPO" rev-parse HEAD 2>/dev/null || echo none)" = "$(git -C "$REPO" rev-parse refs/remotes/origin/main 2>/dev/null || echo none)" ] \
   && [ -z "$(git -C "$REPO" status --porcelain -- status/meta 2>/dev/null || true)" ]; then
  publish_ok=1
fi
[ "$publish_ok" -eq 1 ] || log "WARN: meta artifact commit/push not verified"
if [ "$publish_ok" -eq 1 ]; then
  check C9_repo_publish ok "meta artifacts committed and HEAD=origin/main"
else
  check C9_repo_publish broken "meta artifacts failed to commit/push cleanly"
fi

# ---- escalate unresolved broken OR degraded checks --------------------------- #
need_llm=0
if grep -Eq $'\t(degraded|broken)\t' "$META/checks.tsv"; then need_llm=1; fi
escalations=$(find "$ESCAL" -type f -mmin "-$RATE_WINDOW_MIN" 2>/dev/null | wc -l)
if [ "$need_llm" -eq 1 ] && [ "$NO_LLM" = "1" ]; then
  log "verification run: unresolved checks present but LLM escalation disabled"
elif [ "$need_llm" -eq 1 ] && [ "$escalations" -lt "$MAX_ESCAL" ]; then
  touch "$ESCAL/$(date +%s)"
  bundle="$META/escalate-$(date +%s).txt"
  {
    echo "META-SUPERVISOR ESCALATION — $now_utc"
    echo "Automatic fixes applied this tick: $fixes"
    echo
    echo "--- health checks ---"
    column -t -s $'\t' "$META/checks.tsv" 2>/dev/null || cat "$META/checks.tsv"
    echo
    echo "--- recent watchdog log ---"
    tail -15 "$BENCH/logs/watchdog.log" 2>/dev/null
    echo
    echo "--- open issues ---"
    cat "$META/issues.tsv" 2>/dev/null
    for num in "${candidate_nums[@]}"; do
      echo
      echo "--- issue #$num details ---"
      gh issue view "$num" -R "$REPO_URL" --json number,title,updatedAt,body,comments,url 2>/dev/null || true
    done
  } > "$bundle"
  log "escalating to LLM supervisor (esc #$((escalations + 1))/$MAX_ESCAL): $bundle"
  prompt="You are the SUPERVISOR agent for the metagenomic-binning-benchmark automation on this VM. Inspect the diagnostics below, then FIX everything broken or degraded. Edit source under /vol/data/repos/metagenomic-binning-benchmark and deploy to /vol/data/benchmark/bin; restart only unhealthy drivers/services; clear stale state; reinstall cron only when C1 says so; re-run watchdogs safely. For NEW/updated GitHub issues, inspect their full details, avoid duplicate comments, and post a concise response when useful. Verify every fix, append one timestamped line to /vol/data/benchmark/logs/supervisor-actions.log, and push the repo. Do NOT touch the active benchmark training run. Diagnostics: $(cat "$bundle")"
  opencode run --auto --title "supervisor-fix" "$prompt" >>"$SUPLOG" 2>&1
  supervisor_rc=$?
  log "supervisor agent exited rc=$supervisor_rc"
  if [ "$supervisor_rc" -eq 0 ]; then
    # Refresh only successfully triaged issues. This also absorbs the response
    # comment itself, preventing the watchdog from escalating its own comment.
    for num in "${candidate_nums[@]}"; do
      updated=$(gh issue view "$num" -R "$REPO_URL" --json updatedAt --jq .updatedAt 2>/dev/null || true)
      if [ -n "$updated" ]; then
        updated_epoch=$(date -d "$updated" +%s 2>/dev/null || true)
        [ -n "$updated_epoch" ] && printf '%s\n' "$updated_epoch" > "$SEEN/$num"
      fi
    done
    bash "$BENCH/bin/status-heartbeat.sh" >/dev/null 2>&1 || true
  fi
elif [ "$need_llm" -eq 1 ]; then
  log "unresolved checks present but escalation budget exhausted ($escalations/$MAX_ESCAL); issue markers left pending"
fi

broken_count=$(grep -c $'\tbroken\t' "$META/checks.tsv" || true)
degraded_count=$(grep -c $'\tdegraded\t' "$META/checks.tsv" || true)
echo "$(date -Is) tick done: fixes=$fixes broken=$broken_count degraded=$degraded_count escalated=$need_llm" >>"$LOG"
exit 0
