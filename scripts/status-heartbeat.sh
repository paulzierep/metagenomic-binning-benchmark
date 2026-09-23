#!/usr/bin/env bash
# status-heartbeat.sh — push "agent is alive + what it is doing right now"
# to GitHub every 10 minutes (cron */10). Outputs, all pushed:
#   1. README.md line 1      — status banner (marker-replaced, never duplicates)
#   2. status/current.md     — overwritten each tick
#   3. status/status.log     — 1-line-per-tick liveness + mem/load timeline
#   4. status/agent-activity.log — VERBOSE agent action log (agent appends lines)
#   +  runs/<run>/           — per-run detailed logs synced from /vol/data/benchmark/runs/
#   +  status/agent-run.log  — FULL transcript of every `opencode run` (all agent
#                              commands, tool results, "Turn complete" summaries)
#   +  status/watchdog.log   — agent/watchdog restart history
#
# Honesty rule: liveness is read from the REAL agent heartbeat, not assumed.
#   - heartbeat fresh            -> "alive: yes" + /vol/data/benchmark/.activity
#   - heartbeat stale            -> "alive: no — watchdog will restart within ~5 min"
#   - TASK_COMPLETE exists       -> "alive: no — task done"
# Concurrency: flock + retry; if the repo is mid-commit elsewhere, skip this
# tick and try next (10 min later).
set -u
export HOME=/home/ubuntu
cd /vol/data/repos/metagenomic-binning-benchmark || exit 1

BENCH=/vol/data/benchmark
HB="$BENCH/.heartbeat"
ACT="$BENCH/.activity"
COMPLETE="$BENCH/TASK_COMPLETE"
LOCK=/tmp/status-heartbeat.lock
SLOG="$BENCH/logs/status-heartbeat.log"
STALE_S=900
MARKER='<!--AGENT-STATUS-->'

exec 9>"$LOCK"
flock -n 9 || { echo "$(date -Is) skipped: lock held" >>"$SLOG"; exit 0; }
mkdir -p status

now_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)   # full precision, UTC (internal/log)
now=$(TZ=Europe/Berlin date +'%Y-%m-%dT%H:%M %Z')   # German local time, minute precision (display)
lastcommit=$(git log --oneline -1 2>/dev/null | cut -c1-80)

if [ -f "$COMPLETE" ]; then
    alive=no; text="TASK COMPLETE — benchmark done, sentinel present"
elif [ -f "$HB" ]; then
    age=$(( $(date +%s) - $(stat -c %Y "$HB") ))
    if [ "$age" -lt "$STALE_S" ]; then
        alive=yes
        text=$(cat "$ACT" 2>/dev/null || echo "working (no activity note set)")
    else
        alive=no; text="heartbeat stale ${age}s — agent dead/idle, watchdog should restart within ~5 min"
    fi
else
    alive=no; text="no heartbeat file — agent not started"
fi

# ---- mirror full agent transcript + watchdog + supervisor logs into repo ---- #
# agent-run.log = stdout/stderr of every `opencode run` (whole turns: prompts,
# every $ command, tool output, "Turn complete" summaries); watchdog.log =
# restart decisions; supervisor-run.log = meta-watchdog escalations. Must run
# BEFORE current.md/status.log because those report the sizes.
sync_agent_logs() {
    mkdir -p status status/meta
    cp "$BENCH/logs/agent-run.log"      status/agent-run.log      2>/dev/null || true
    cp "$BENCH/logs/watchdog.log"       status/watchdog.log       2>/dev/null || true
    cp "$BENCH/logs/supervisor-run.log" status/supervisor-run.log 2>/dev/null || true
    cp "$BENCH/meta/"*.txt "$BENCH/meta/"*.jsonl status/meta/ 2>/dev/null || true
}
sync_agent_logs
tsize=$(wc -c < status/agent-run.log 2>/dev/null || echo 0)
wsize=$(wc -c < status/watchdog.log 2>/dev/null || echo 0)

# ---- 1. README first line: status banner (marker-replaced) ----------------- #
case "$alive" in
  yes) dot="🟢"; state="running" ;;
  no)  if [ -f "$COMPLETE" ]; then dot="✅"; state="done"; else dot="🔴"; state="stopped (watchdog will restart)"; fi ;;
esac
# Banner block (L1 invisible marker, L3 visible status line, per user spec):
#   <!--AGENT-STATUS-->
#   (blank)
#   > 🟢 Agent status: running · ⏱ 2026-... CEST (Europe/Berlin) · [status.log](status/status.log)
# Strip any existing banner: canonical 4-line block at top AND any legacy
# inline line (marker + text on one line) anywhere else.
if [ "$(head -1 README.md)" = "$MARKER" ]; then
    sed '1,4d' README.md > README.tmp
else
    cp README.md README.tmp
fi
grep -v "^$MARKER" README.tmp > README.new || true
rm -f README.tmp
{
  echo "$MARKER"
  echo
  echo "> $dot **Agent status:** \`$state\` · ⏱ \`$now\` · [status.log](status/status.log)"
  echo
  cat README.new
} > README.staged && mv README.staged README.md
rm -f README.new README.staged

# ---- 2. status/current.md -------------------------------------------------- #
load=$(cut -d' ' -f1-3 /proc/loadavg)
mem=$(free -m | awk '/Mem:/{printf "%d/%d MB", $3, $2}')
upt=$(uptime -p 2>/dev/null | sed 's/^up //')
session="ses_f31799c77ffeTq9gcYgqc4hBhg"
{
  echo "# 🤖 Agent status"
  echo
  echo "| | |"
  echo "|---|---|"
  echo "| Status | $dot \`$state\` |"
  echo "| ⏱ Updated (Europe/Berlin) | \`$now\` |"
  echo "| 📌 Current work | $text |"
  echo "| ⚙️ Load · uptime | \`$load\` · $upt — 32 cores, 62 GiB, no GPU |"
  echo "| 💾 RAM used/total | \`$mem\` |"
  echo "| 🔗 Session | \`$session\` (default model; watchdog rotates to free models on quota) |"
  echo "| 📄 Full state | [PROGRESS.md](PROGRESS.md) · last push \`$lastcommit\` |"
  echo "| 📜 Agent transcript | [status/agent-run.log](status/agent-run.log) · \`${tsize} B\` — every run, command & tool result |"
  echo "| 📈 Timeline | [status/status.log](status/status.log) |"
} > status/current.md

# ---- 3. timeline ----------------------------------------------------------- #
printf '%s\talive=%s\tmem=%s\tload=%s\ttranscript=%sB\twatchdog=%sB\t%s\n' "$now" "$alive" "$mem" "$load" "$tsize" "$wsize" "$text" >> status/status.log

# ---- 4. sync per-run detailed logs into the repo (small files only) ------- #
sync_run_logs() {
    for d in /vol/data/benchmark/runs/*/; do
        [ -d "$d" ] || continue
        name=$(basename "$d")
        m() { mkdir -p "runs/$name/$(dirname "$1")" && cp "$d/$2" "runs/$name/$1"; }
        m run_meta.txt run_meta.txt 2>/dev/null
        m comebin_run.log comebin_run.log 2>/dev/null
        m logs/resources.tsv logs/resources.tsv 2>/dev/null
        m logs/sampler.out logs/sampler.out 2>/dev/null
        m comebin_res/comebin.log comebin_out/comebin_res/comebin.log 2>/dev/null
        m comebin_res/training.log comebin_out/comebin_res/training.log 2>/dev/null
        m comebin_res/config.yml comebin_out/comebin_res/config.yml 2>/dev/null
    done
}
sync_run_logs

ok=0
for i in 1 2 3; do
    git add README.md status/current.md status/status.log status/agent-activity.log runs
    [ -e status/agent-run.log ] && git add status/agent-run.log
    [ -e status/watchdog.log ] && git add status/watchdog.log
    [ -e status/supervisor-run.log ] && git add status/supervisor-run.log
    [ -n "$(find status/meta -maxdepth 1 -type f 2>/dev/null | head -1)" ] && git add status/meta
    git commit -q -m "status: $alive — $(echo "$text" | cut -c1-60)"
    if git push -q; then ok=1; break; fi
    sleep 3
done
[ "$ok" = "1" ] || echo "$(date -Is) push failed after 3 tries" >>"$SLOG"
echo "$(date -Is) alive=$alive text='$text' pushed=$ok" >>"$SLOG"
exit 0