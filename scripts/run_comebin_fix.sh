#!/usr/bin/env bash
# run_comebin_fix.sh — run a FIXED COMEBin source tree on the demo dataset and
# record the run exactly like the baseline. The default is the current v1.1.0
# optimization worktree; override with SRC_COMEBIN=/path/to/repo.
set -euo pipefail

MM=/vol/data/tools/bin/micromamba
ENV=/vol/data/envs/comebin
SRC=${SRC_COMEBIN:-/vol/data/repos/COMEBin-v11}
DATA=${DATA:-/vol/data/datasets/comebin_test_data}
CONTIGS=${CONTIGS:-"$DATA/BATS_SAMN07137077_METAG.scaffolds.min500.fasta.f1k.fasta"}
BAMDIR=${BAMDIR:-"$DATA/bamfiles"}
MODE=${MODE:-fix}
[ -f "$CONTIGS" ] || { echo "ERROR: contigs file not found: $CONTIGS"; exit 1; }
[ -d "$BAMDIR" ] || { echo "ERROR: bamdir not found: $BAMDIR"; exit 1; }
RUNDIR=$(realpath -m "${1:-/vol/data/benchmark/runs/fix_v11}")
THREADS=${THREADS:-32}
SEED=${SEED:-}
START_LOCK=/tmp/benchmark-start.lock
ACTIVE=/vol/data/benchmark/.active_run
[ -f "$SRC/COMEBin/run_comebin.sh" ] || { echo "ERROR: invalid SRC_COMEBIN repo root: $SRC"; exit 1; }

exec 9>"$START_LOCK"
# Bounded wait: a just-finished run can leave fd 9 briefly open in a lingering
# child, which made the sweep's next cell fail instantly ("another benchmark
# launch holds ...").  Wait for it to clear instead of racing it.
flock -w 300 9 || { echo "ERROR: another benchmark launch holds $START_LOCK (waited 300s)"; exit 1; }
if [ -f "$ACTIVE" ] && [ "${BENCHMARK_WATCHDOG_REPLACE:-0}" != "1" ]; then
  read -r active_pid active_pgid active_log active_dir active_start active_mode active_src < "$ACTIVE" || true
  active_state=$(ps -o stat= -p "${active_pid:-0}" 2>/dev/null | tr -d ' ' || true)
  if [ -n "${active_pid:-}" ] && kill -0 "$active_pid" 2>/dev/null && [[ "$active_state" != Z* ]]; then
    echo "ERROR: benchmark already active: pid=$active_pid dir=$active_dir mode=${active_mode:-baseline}"
    exit 1
  fi
  old_rc=$(grep -m1 '^exit_code:' "${active_dir:-/nonexistent}/run_meta.txt" 2>/dev/null | awk '{print $2}' || true)
  [ "${old_rc:-}" = "0" ] || { echo "ERROR: stale failed run requires benchmark-watchdog triage: $active_dir"; exit 1; }
  rm -f "$ACTIVE"
fi
if [ -f "$RUNDIR/run_meta.txt" ] || [ -d "$RUNDIR/comebin_out" ]; then
  echo "ERROR: refusing to overwrite existing run directory: $RUNDIR"
  exit 1
fi

# Pre-flight free space.  A full filesystem does not fail at launch: it silently
# poisons CheckM's marker tables and then kills get_result hours later.
# cami3_v11_20260926 burned 6,677 s and produced 0 bins because prep leftovers
# (13.8 GB in /tmp) had filled / to 100%.  Fail fast, before the run starts.
# Placed before the .active_run registration, so a refusal cannot be mistaken by
# benchmark-watchdog for a crashed run and restarted.
MIN_FREE_GB=${MIN_FREE_GB:-2}
RUN_FS=$(df -Pk "$(dirname "$RUNDIR")" 2>/dev/null | awk 'NR==2{print int($4/1048576)}')
TMP_FS=$(df -Pk /tmp 2>/dev/null | awk 'NR==2{print int($4/1048576)}')
echo "preflight_free_gb: run_fs=${RUN_FS:-unknown} tmp_fs=${TMP_FS:-unknown} floor=${MIN_FREE_GB}"
for fs_avail in "$RUN_FS" "$TMP_FS"; do
  if [ -n "$fs_avail" ] && [ "$fs_avail" -lt "$MIN_FREE_GB" ]; then
    echo "ERROR: only ${fs_avail} GiB free, need >= ${MIN_FREE_GB} GiB (stale prep leftovers in /tmp are the usual cause)"
    echo "Free space first, or override deliberately with MIN_FREE_GB=0"
    exit 1
  fi
done

mkdir -p "$RUNDIR/logs"
COMMIT=$(git -C "$SRC" rev-parse HEAD)
DIRTY=$(git -C "$SRC" status --porcelain --untracked-files=no | wc -l)
BRANCH=$(git -C "$SRC" branch --show-current)
echo "source: $SRC (branch $BRANCH) commit: $COMMIT (dirty files: $DIRTY)"
[ "$DIRTY" -eq 0 ] || { echo "REFUSING: source tree has uncommitted changes; commit them first"; exit 1; }
COMEBIN_ARGS=(-a "$CONTIGS" -p "$BAMDIR" -o "$RUNDIR/comebin_out" -n "${N_VIEWS:-6}" -t "$THREADS")
if grep -q -- '-d STR.*device' "$SRC/COMEBin/run_comebin.sh"; then
  COMEBIN_ARGS+=(-d cpu)
fi
if [ -n "$SEED" ] && grep -q -- '-s INT.*seed' "$SRC/COMEBin/run_comebin.sh"; then
  COMEBIN_ARGS+=(-s "$SEED")
fi
# ---- issue #25 sweep: forward optional training/compute params ------------ #
# Map env vars -> run_comebin.sh flags ONLY if the invoked copy supports them
# (avoids "illegal option" on older/mismatched sources). Defaults = upstream
# reference values (current medium_v11_20260924 run). `${X:-}` guards set -u.
if [ -n "${TEMP:-}" ]; then
  grep -q -- '-l FLOAT' "$SRC/COMEBin/run_comebin.sh" && COMEBIN_ARGS+=(-l "$TEMP")
fi
if [ -n "${EMB:-}" ]; then
  grep -q -- '-e INT' "$SRC/COMEBin/run_comebin.sh" && COMEBIN_ARGS+=(-e "$EMB")
fi
if [ -n "${EMB_COV:-}" ]; then
  grep -q -- '-c INT' "$SRC/COMEBin/run_comebin.sh" && COMEBIN_ARGS+=(-c "$EMB_COV")
fi
if [ -n "${BATCH:-}" ]; then
  grep -q -- '-b INT' "$SRC/COMEBin/run_comebin.sh" && COMEBIN_ARGS+=(-b "$BATCH")
fi
if [ -n "${MAX_EDGES:-}" ]; then
  grep -q -- '-m INT' "$SRC/COMEBin/run_comebin.sh" && COMEBIN_ARGS+=(-m "$MAX_EDGES")
fi
if [ -n "${LEIDEN_WORKERS:-}" ]; then
  grep -q -- '-w INT' "$SRC/COMEBin/run_comebin.sh" && COMEBIN_ARGS+=(-w "$LEIDEN_WORKERS")
fi
if [ -n "${HMM_EVALUE:-}" ]; then
  grep -q -- '-E FLOAT' "$SRC/COMEBin/run_comebin.sh" && COMEBIN_ARGS+=(-E "$HMM_EVALUE")
fi
CMD_TEXT=$(printf '%q ' "$MM" run -p "$ENV" bash run_comebin.sh "${COMEBIN_ARGS[@]}")
{
  echo "run:        $RUNDIR"
  echo "source:     $SRC (branch $BRANCH)"
  echo "date:       $(date -Is)"
  echo "commit:     $COMMIT"
  echo "contigs:    $CONTIGS"
  echo "bamdir:     $BAMDIR"
  echo "threads:    $THREADS"
  echo "n_views:    ${N_VIEWS:-6}"
  echo "seed:       ${SEED:-unset}"
  echo "allow_zero_bins: ${ALLOW_ZERO_BINS:-0}"
  echo "sweep:      temp=${TEMP:-ref} emb=${EMB:-ref} emb_cov=${EMB_COV:-ref} batch=${BATCH:-ref} max_edges=${MAX_EDGES:-ref} leiden_workers=${LEIDEN_WORKERS:-ref} hmm_evalue=${HMM_EVALUE:-ref} n_views=${N_VIEWS:-6}"
  echo "host:       $(nproc) cores, $(free -g | awk '/Mem:/{print $2}')G RAM, gpu=$(nvidia-smi -L 2>/dev/null || echo none)"
  echo "cmd_wrapper: $CMD_TEXT"
} | tee "$RUNDIR/run_meta.txt"

export MAMBA_ROOT_PREFIX=/vol/data/envs/.mamba
cd "$SRC/COMEBin"   # upstream resolves ../auxiliary relative to CWD

# Fields: pid pgid logfile rundir start_epoch mode source_repo contigs bamdir.
printf '%s %s %s %s %s %s %s %s %s\n' "$$" "$(ps -o pgid= -p $$ | tr -d ' ')" \
  "$RUNDIR/comebin_run.log" "$RUNDIR" "$(date +%s)" "$MODE" "$SRC" "$CONTIGS" "$BAMDIR" > "$ACTIVE.tmp.$$"
mv "$ACTIVE.tmp.$$" "$ACTIVE"

SAMPLER_PID=""
cleanup() {
  rc=$?
  trap - EXIT
  if [ -n "$SAMPLER_PID" ] && kill -0 "$SAMPLER_PID" 2>/dev/null; then
    kill "$SAMPLER_PID" 2>/dev/null || true
    wait "$SAMPLER_PID" 2>/dev/null || true
  fi
  if [ "$rc" -eq 0 ] && [ -f "$ACTIVE" ]; then
    read -r current_pid _ < "$ACTIVE" || true
    [ "${current_pid:-}" = "$$" ] && rm -f "$ACTIVE"
  fi
  exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

sample_resources() {
  printf 'timestamp\tpids\tcpu_pct\trss_gb\tsystem_mem_mb\n'
  while :; do
    read -r pids cpu_pct rss_kb <<<"$(ps -eo pid=,pcpu=,rss=,args= | awk -v out="$RUNDIR/comebin_out" '
      index($0, out) && $4 !~ /^awk/ {
        p = p ? p "," $1 : $1; c += $2; r += $3
      }
      END { printf "%s %.1f %.0f", p, c, r }
    ')"
    system_mem_mb=$(free -m | awk '/Mem:/{print $3}')
    printf '%s\t%s\t%s\t%.3f\t%s\n' "$(date -Is)" "${pids:-none}" \
      "${cpu_pct:-0}" "$(awk -v kb="${rss_kb:-0}" 'BEGIN{print kb/1048576}')" "$system_mem_mb"
    sleep 30 & wait $!
  done
}
sample_resources > "$RUNDIR/logs/resources.tsv" 2> "$RUNDIR/logs/sampler.out" 9>&- &
SAMPLER_PID=$!

# capture the real main.py train command once training starts (non-blocking)
( sleep 12; MCMD=$(pgrep -af 'main.py train' 2>/dev/null | head -1 | cut -d' ' -f2-); \
  [ -n "$MCMD" ] && echo "cmd_train_py: $MCMD" >> "$RUNDIR/run_meta.txt" ) 9>&- &

START=$(date +%s)
set +e
CUDA_VISIBLE_DEVICES= "$MM" run -p "$ENV" bash run_comebin.sh \
  "${COMEBIN_ARGS[@]}" 9>&- 2>&1 | tee "$RUNDIR/comebin_run.log" 9>&-
RC=${PIPESTATUS[0]}
set -e
END=$(date +%s)

# The upstream wrapper can mask a clustering/get_result failure and return 0
# even when it produced no bins. Validate non-empty artifacts before recording
# terminal success; this is especially important for the medium benchmark.
BINS="$RUNDIR/comebin_out/comebin_res/comebin_res_bins"
BIN_COUNT=0
if [ -d "$BINS" ]; then
  BIN_COUNT=$(find -L "$BINS" -maxdepth 1 -type f -size +0c | wc -l)
fi
if [ "$RC" -eq 0 ] && [ "$BIN_COUNT" -eq 0 ]; then
  # Issue #28/#29: a 0-bin result can be a legitimate, verified outcome.  On
  # COMEBin 41606c8 an empty marker-seed set (test_getmarker_2quarter.pl exit
  # 2/3/4) makes main.py log "Reporting 0 bins ... This is an empty result for
  # this input, not an error." and exit 0.  Turning *that* back into a harness
  # failure would re-introduce the exact error issue #28 removed, so a caller
  # may opt in with ALLOW_ZERO_BINS=1.
  #
  # The opt-in is deliberately narrow: it is honoured ONLY when COMEBin's own
  # log carries that explicit empty-result marker.  Any other 0-bin run (lost
  # artifacts, crashed clustering, a real regression) is still a failure, so the
  # medium/large quality gates and the #25 sweep cells keep their strictness.
  if [ "${ALLOW_ZERO_BINS:-0}" = "1" ] \
     && grep -aq 'Reporting 0 bins' "$RUNDIR/comebin_run.log" 2>/dev/null \
     && grep -aq 'not an error' "$RUNDIR/comebin_run.log" 2>/dev/null; then
    echo "NOTE: 0 bins with COMEBin's explicit empty-result marker; ALLOW_ZERO_BINS=1" \
         "-> recording success" | tee -a "$RUNDIR/run_meta.txt"
  else
    echo "ERROR: COMEBin returned 0 but no non-empty bins were produced at $BINS; recording failure" \
      | tee -a "$RUNDIR/run_meta.txt"
    RC=1
  fi
fi
{
  echo "exit_code:  $RC"
  echo "wall_s:     $((END-START))"
  echo "finished:   $(date -Is)"
  if [ "$BIN_COUNT" -gt 0 ]; then
    echo "bins:       $BIN_COUNT  -> $BINS"
  else
    echo "bins:       0  -> $BINS (missing or empty)"
  fi
} | tee -a "$RUNDIR/run_meta.txt"
# record helper-tool commands visible in the log (FragGeneScan/hmmsearch seed genes)
grep -aE 'run_FragGeneScan|hmmsearch' "$RUNDIR/comebin_run.log" 2>/dev/null | head -2 \
  | sed 's/^/cmd_from_log: /' | tee -a "$RUNDIR/run_meta.txt" >/dev/null || true
exit "$RC"
