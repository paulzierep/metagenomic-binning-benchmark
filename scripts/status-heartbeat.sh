#!/usr/bin/env bash
# status-heartbeat.sh — push "agent is alive + what is ACTUALLY happening" to
# GitHub every 2 minutes (cron */2). Outputs, all pushed:
#   1. README.md            — status banner (marker-replaced, never duplicates)
#                            + the "Benchmark runs — performance" table Status
#                            cell refreshed from the LIVE training log so the
#                            README never shows a frozen epoch
#   2. status/current.md    — overwritten when the status actually changes
#   3. status/status.log    — append-only timeline of CHANGES (not beeps): the
#                            model= used, live epoch=/loss=/acc= of the benchmark
#   4. status/agent-activity.log — VERBOSE agent action log (agent appends lines)
#   +  runs/<run>/          — per-run detailed logs synced from /vol/data/benchmark/runs/
#   +  status/agent-run.log — FULL transcript of every `opencode run` (all agent
#                              commands, tool results, "Turn complete" summaries)
#   +  status/watchdog.log  — agent/watchdog restart history
#   +  status/supervisor-run.log, status/meta/ — supervisor artifacts
#
# Truthfulness: the headline numbers (epoch/loss/accuracy, model, mem/load) are
# derived from REAL files (the live training.log, the run transcript, /proc) —
# never assumed. The agent's .activity note is shown age-tagged ("agent note ·
# N min old") so a stale note can never disguise itself as ground truth.
#
# Skip-if-unchanged: generated files are only rewritten + committed when the
# *meaningful* status changed (state/note/transcript growth/live epoch/model),
# so at 2-min cadence the history stays clean while the agent is idle and only
# records real progress.
#
# Concurrency: per-script flock; repo lock taken around commit/push (the running
# agent also pushes). If the repo is mid-commit elsewhere, retry, else skip tick.
set -u
export HOME=/home/ubuntu
cd /vol/data/repos/metagenomic-binning-benchmark || exit 1

BENCH=/vol/data/benchmark
HB="$BENCH/.heartbeat"
ACT="$BENCH/.activity"
COMPLETE="$BENCH/TASK_COMPLETE"
SIGFILE="$BENCH/.status_sig"
LOCK=${STATUS_HEARTBEAT_LOCK:-/tmp/status-heartbeat.lock}
REPO_LOCK=${BENCH_REPO_LOCK:-/tmp/bench-repo.lock}
SLOG="$BENCH/logs/status-heartbeat.log"
STALE_S=900
MARKER='<!--AGENT-STATUS-->'

exec 9>"$LOCK"
flock -n 9 || { echo "$(date -Is) skipped: status lock held" >>"$SLOG"; exit 0; }
# Hold the shared repository lock before generating files as well as during git.
# This prevents status/meta publishers from interleaving writes with each other.
exec 8>"$REPO_LOCK"
flock -n 8 || { echo "$(date -Is) skipped: repository lock held" >>"$SLOG"; exit 0; }
mkdir -p status status/meta

now_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)   # full precision, UTC (internal/log)
now=$(TZ=Europe/Berlin date +'%Y-%m-%dT%H:%M %Z')   # German local time, minute precision (display)
lastcommit=$(git log --oneline -1 2>/dev/null | cut -c1-80)
primary_alive=0
if ! flock -n /tmp/agent-watchdog.lock -c true 2>/dev/null; then
  primary_alive=1
elif ps -eo args= | awk -v p="opencode run --auto --session ses_f31799c77ffeTq9gcYgqc4hBhg" 'index($0,p)==1{found=1} END{exit !found}'; then
  primary_alive=1
fi
transcript_age=999999
[ -f "$BENCH/logs/agent-run.log" ] && transcript_age=$(( $(date +%s) - $(stat -c %Y "$BENCH/logs/agent-run.log") ))

if [ -f "$COMPLETE" ]; then
    alive=no; dot="✅"; state="done"; text="TASK COMPLETE — benchmark done, sentinel present"
elif [ -f "$HB" ]; then
    age=$(( $(date +%s) - $(stat -c %Y "$HB") ))
    if [ "$age" -lt "$STALE_S" ] && [ "$primary_alive" -eq 1 ]; then
        alive=yes; state="running"; dot="🟢"
        text=$(cat "$ACT" 2>/dev/null || echo "working (no activity note set)")
    elif [ "$transcript_age" -lt "$STALE_S" ] && [ "$primary_alive" -eq 1 ]; then
        alive=yes; state="running"; dot="🟢"
        text="agent driver alive; transcript fresh (${transcript_age}s) while heartbeat is stale (${age}s)"
    elif [ "$age" -lt "$STALE_S" ] && [ "$primary_alive" -eq 0 ]; then
        alive=no; state="stopped (watchdog will restart)"; dot="🔴"
        text="heartbeat is fresh (${age}s) but no primary driver/run owns it — supervisor/maintenance heartbeat ignored"
    else
        alive=no; state="stopped (watchdog will restart)"; dot="🔴"
        text="heartbeat stale ${age}s — agent dead/idle, watchdog should restart within ~5 min"
    fi
else
    alive=no; state="not started"; dot="🔴"
    text="no heartbeat file — agent not started"
fi

# ---- mirror full agent transcript + watchdog + supervisor logs into repo ---- #
sync_agent_logs() {
    cp "$BENCH/logs/agent-run.log"      status/agent-run.log      2>/dev/null || true
    cp "$BENCH/logs/watchdog.log"       status/watchdog.log       2>/dev/null || true
    cp "$BENCH/logs/supervisor-run.log" status/supervisor-run.log 2>/dev/null || true
    cp "$BENCH/meta/"*.txt "$BENCH/meta/"*.jsonl status/meta/ 2>/dev/null || true
}
sync_agent_logs
tsize=$(wc -c < status/agent-run.log 2>/dev/null || echo 0)
wsize=$(wc -c < status/watchdog.log 2>/dev/null || echo 0)

# ---- which model is the (last) agent actually running on? -------------------- #
# OpenCode's transcript prints one "> <agent> · <model>" line per turn — the
# most recent one is the live model (reflects watchdog rotation to free models).
last_model=$(grep -aoE '^> [^·]+ · [^ ]+' status/agent-run.log 2>/dev/null \
             | tail -1 | sed -E 's/^> [^·]+ · //')
if [ -z "$last_model" ]; then
    last_model=$(sed -n 's/.*"modelID":"\([^"]*\)".*/\1/p' \
                 /home/ubuntu/.local/state/opencode/model.json 2>/dev/null | head -1)
fi
last_model="${last_model:-unknown}"

# ---- age of the agent's note (so it can't masquerade as ground truth) ------- #
act_age_min=""
[ -f "$ACT" ] && act_age_min=$(( ( $(date +%s) - $(stat -c %Y "$ACT") ) / 60 ))
note="${text:-}"

# ---- LIVE benchmark truth: epoch/loss/acc from the actual training.log ------- #
# Run root comes from .active_run (field 4); fall back to the newest config.yml
# under runs/<run>/comebin_out/<stage>/ for a last-run summary.  A fallback is
# explicitly non-live: terminal failures must not keep appearing as a running
# benchmark after .active_run has been cleared.
run_epoch="" run_total="" run_loss="" run_acc="" run_name="" train_log_age=""
run_dir="" run_registered=0
if [ -f "$BENCH/.active_run" ]; then
    run_dir=$(awk '{print $4}' "$BENCH/.active_run" 2>/dev/null)
    [ -n "$run_dir" ] && run_registered=1
fi
if [ -z "$run_dir" ] || [ ! -d "$run_dir" ]; then
    run_registered=0
    newest=""
    for cfg in "$BENCH"/runs/*/comebin_out/*/config.yml; do
        [ -f "$cfg" ] || continue
        if [ -z "$newest" ] || [ "$(stat -c %Y "$cfg")" -gt "$(stat -c %Y "$newest")" ]; then
            newest="$cfg"
        fi
    done
    [ -n "$newest" ] && run_dir=$(dirname "$(dirname "$(dirname "$newest")")")
fi
if [ -n "$run_dir" ] && [ -d "$run_dir" ]; then
    run_name=$(basename "$run_dir")
    tlog=""
    for f in "$run_dir"/comebin_out/*/training.log; do
        [ -f "$f" ] || continue
        if [ -z "$tlog" ] || [ "$(stat -c %Y "$f")" -gt "$(stat -c %Y "$tlog")" ]; then
            tlog="$f"
        fi
    done
    if [ -n "$tlog" ]; then
        train_log_age=$(( $(date +%s) - $(stat -c %Y "$tlog") ))
        run_epoch=$(grep -aoE 'Epoch: [0-9]+' "$tlog" | tail -1 | grep -oE '[0-9]+$')
        run_loss=$(grep -aoE 'Loss: [0-9.]+' "$tlog" | tail -1 | grep -oE '[0-9.]+$')
        run_acc=$(grep -aoE 'Top1 accuracy: [0-9.]+' "$tlog" | tail -1 | grep -oE '[0-9.]+$')
        run_total=$(grep -aoE '^epochs: *[0-9]+' "$(dirname "$tlog")/config.yml" 2>/dev/null | grep -oE '[0-9]+$')
    fi
fi

# ---- did the *meaningful* status change since the last tick? ----------------- #
sig="alive=$alive|state=$state|note=$note|tsize=$tsize|wsize=$wsize|model=$last_model|epoch=$run_epoch|loss=$run_loss|acc=$run_acc|run=$run_name|run_registered=$run_registered"
old_sig=$(cat "$SIGFILE" 2>/dev/null || echo "")
changed=0
[ "$sig" != "$old_sig" ] && changed=1

if [ "$changed" = "1" ]; then
    # ---- 1. README banner ------------------------------------------------ #
    if [ -n "$run_epoch" ] && [ "$run_registered" -eq 1 ]; then
        perf="train ${run_name}: epoch ${run_epoch}/${run_total:-200} · loss ${run_loss:-—} · top1 ${run_acc:-—}"
    elif [ -n "$run_epoch" ]; then
        perf="last run ${run_name}: epoch ${run_epoch}/${run_total:-200} · not active"
    else
        perf="no active benchmark"
    fi
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
      echo "> $dot **Agent status:** \`$state\` · ⏱ \`$now\` · 🏃 $perf · 🧠 \`$last_model\` · [status.log](status/status.log)"
      echo
      cat README.new
    } > README.staged && mv README.staged README.md
    rm -f README.new README.staged

    # ---- 1b. README "Benchmark runs — performance" table Status cell ------ #
    # Replace ONLY the final (Status) cell of the row for the observed run.
    if [ -n "$run_epoch" ]; then
        if [ "$run_registered" -eq 1 ]; then
            st="⏳ running · epoch ${run_epoch}/${run_total:-200} · loss ${run_loss:-—} · top1 ${run_acc:-—}"
        else
            st="⏹ not active · last observed epoch ${run_epoch}/${run_total:-200}"
        fi
        awk -v rn="$run_name" -v st="$st" '
          $0 ~ "^\\| *`" rn "` *\\|" {
            n = split($0, a, "|")
            # The performance table has 11 columns. Do not rewrite same-named
            # rows in the narrower run-history table.
            if (n != 13) { print; next }
            out = a[1]
            for (i = 2; i <= n - 2; i++) out = out "|" a[i]
            out = out "| " st " |"
            print out
            next
          }
          { print }
        ' README.md > README.tbl && mv README.tbl README.md
    fi

    # ---- 2. status/current.md -------------------------------------------- #
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
      if [ -n "$run_epoch" ] && [ "$run_registered" -eq 1 ]; then
          echo "| 🏃 Live benchmark | \`$run_name\` — **epoch ${run_epoch}/${run_total:-200}** · loss \`${run_loss:-—}\` · top1 acc \`${run_acc:-—}\` (log ${train_log_age:-?}s fresh) |"
      elif [ -n "$run_epoch" ]; then
          echo "| 🏃 Last benchmark (not active) | \`$run_name\` — last observed **epoch ${run_epoch}/${run_total:-200}** (log ${train_log_age:-?}s old) |"
      else
          echo "| 🏃 Benchmark | no active run |"
      fi
      echo "| 🧠 Model (last turn) | \`$last_model\` (watchdog rotates to free models on quota) |"
      if [ -n "$act_age_min" ]; then
          echo "| 📌 Agent note · **${act_age_min} min old** | $note |"
      else
          echo "| 📌 Agent note | $note |"
      fi
      echo "| ⚙️ Load · uptime | \`$load\` · $upt — 32 cores, 62 GiB, no GPU |"
      echo "| 💾 RAM used/total | \`$mem\` |"
      echo "| 🔗 Session | \`$session\` |"
      echo "| 📄 Full state | [PROGRESS.md](PROGRESS.md) · last push \`$lastcommit\` |"
      echo "| 📜 Agent transcript | [status/agent-run.log](status/agent-run.log) · \`${tsize} B\` — every run, command & tool result |"
      echo "| 📈 Timeline | [status/status.log](status/status.log) |"
    } > status/current.md

    # ---- 3. timeline (one line PER CHANGE, not per tick) ------------------- #
    printf '%s\talive=%s\tmem=%s\tload=%s\ttranscript=%sB\twatchdog=%sB\tmodel=%s\tepoch=%s/%s\tloss=%s\tacc=%s\t%s\n' \
        "$now" "$alive" "${mem:-?}" "${load:-?}" "$tsize" "$wsize" "$last_model" \
        "${run_epoch:--}" "${run_total:--}" "${run_loss:--}" "${run_acc:--}" "$note" >> status/status.log

    echo "$sig" > "$SIGFILE"
fi

# ---- 4. sync per-run detailed logs into the repo (small files only) ------- #
sync_run_logs() {
    for d in "$BENCH"/runs/*/; do
        [ -d "$d" ] || continue
        name=$(basename "$d")
        # Do not create empty repo-side run directories for refused/aborted
        # launches whose optional evidence files were never produced.
        m() {
          local src="$d/$2"
          [ -f "$src" ] || return 0
          mkdir -p "runs/$name/$(dirname "$1")" && cp "$src" "runs/$name/$1"
        }
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

# ---- commit + push ONLY if something actually changed ------------------------ #
git add README.md status/current.md status/status.log status/agent-activity.log runs
[ -e status/agent-run.log ] && git add status/agent-run.log
[ -e status/watchdog.log ] && git add status/watchdog.log
[ -e status/supervisor-run.log ] && git add status/supervisor-run.log
[ -n "$(find status/meta -maxdepth 1 -type f 2>/dev/null | head -1)" ] && git add status/meta

if git diff --cached --quiet -- README.md status runs; then
    echo "$(date -Is) no change to commit (alive=$alive epoch=${run_epoch:-—} model=$last_model)" >>"$SLOG"
    exit 0
fi

ok=0
for i in 1 2 3; do
    ready=0
    if git diff --cached --quiet -- README.md status runs; then
        ready=1
    elif git commit -q --only -m "status: $alive — ${run_name:-agent} epoch ${run_epoch:-—}/${run_total:-200} loss ${run_loss:-—} acc ${run_acc:-—} model $last_model — $(echo "$note" | cut -c1-40)" -- README.md status runs; then
        ready=1
    fi
    if [ "$ready" -eq 1 ] && git push -q; then
        head=$(git rev-parse HEAD)
        remote=$(git ls-remote origin refs/heads/main 2>/dev/null | awk 'NR==1{print $1}')
        [ -n "$remote" ] && [ "$head" = "$remote" ] && { ok=1; break; }
    fi
    sleep 3
done
if [ "$ok" = "1" ]; then
  echo "$(date -Is) pushed (or nothing to push): alive=$alive epoch=${run_epoch:-—} model=$last_model" >>"$SLOG"
else
  echo "$(date -Is) push failed after 3 tries" >>"$SLOG"
fi
exit 0
