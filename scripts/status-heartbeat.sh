#!/usr/bin/env bash
# status-heartbeat.sh — push "agent is alive + what it is doing right now"
# to GitHub every 10 minutes (cron */10). Three outputs, all pushed:
#   1. README.md line 1  — status banner (marker-replaced, never duplicates)
#   2. status/current.md — overwritten each tick
#   3. status/status.log — append-only timeline
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

now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
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

# ---- 1. README first line: status banner (marker-replaced) ----------------- #
BANNER="$MARKER **Agent status** \`$now UTC\` · alive=\`$alive\` · $text"
if head -1 README.md | grep -q "^$MARKER"; then
    # replace existing banner line
    { echo "$BANNER"; sed '1d' README.md; } > README.new && mv README.new README.md
else
    { echo "$BANNER"; cat README.md; } > README.new && mv README.new README.md
fi

# ---- 2. status/current.md -------------------------------------------------- #
load=$(cut -d' ' -f1-3 /proc/loadavg)
upt=$(uptime -p 2>/dev/null | sed 's/^up //')
session="ses_f31799c77ffeTq9gcYgqc4hBhg"
{
  echo "# Agent status"
  echo
  echo "_updated ${now} UTC_ — machine: \`$(hostname)\`"
  echo
  echo "- **Alive:** \`$alive\`"
  echo "- **Activity:** $text"
  echo "- **Load / uptime:** $load / $upt (32 cores, 62 GiB, no GPU)"
  echo "- **Session:** \`$session\` (default model; watchdog rotates to free models on quota)"
  echo "- **Full state:** [PROGRESS.md](PROGRESS.md) — last push: \`$lastcommit\`"
  echo "- **Timeline:** [status/status.log](status/status.log)"
} > status/current.md

# ---- 3. timeline ----------------------------------------------------------- #
printf '%s\talive=%s\t%s\n' "$now" "$alive" "$text" >> status/status.log

ok=0
for i in 1 2 3; do
    git add README.md status/current.md status/status.log
    git commit -q -m "status: $alive — $(echo "$text" | cut -c1-60)"
    if git push -q; then ok=1; break; fi
    sleep 3
done
[ "$ok" = "1" ] || echo "$(date -Is) push failed after 3 tries" >>"$SLOG"
echo "$(date -Is) alive=$alive text='$text' pushed=$ok" >>"$SLOG"
exit 0