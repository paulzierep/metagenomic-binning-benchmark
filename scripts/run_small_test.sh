#!/usr/bin/env bash
# run_small_test.sh — issue #2 correctness test: run COMEBin's real pipeline on
# /vol/data/datasets/comebin_small with the same bookkeeping as a benchmark.
# It refuses to overlap another registered benchmark and is intentionally
# non-interactive. Usage:
#   bash scripts/run_small_test.sh [rundir] [threads]
# Environment:
#   SRC_COMEBIN=/path/to/repo-root   COMEBin checkout/worktree to test
#                                   (default: the verified small-data fix worktree)
#   SEED=42                          optional reproducible seed (supported CLIs)
#   BATCH_SIZE=256 EMB_SIZE=512      small-data training defaults
#   EPOCHS=30                         training epochs (issue #10; default 30 for
#                                     fast functional tests; passed as -E only
#                                     when the CLI supports it)
set -euo pipefail

MM=/vol/data/tools/bin/micromamba
ENV=/vol/data/envs/comebin
SRC=${SRC_COMEBIN:-/vol/data/repos/COMEBin-small-fix}
DATA=/vol/data/datasets/comebin_small
CONTIGS="$DATA/contigs.fa"
BAMDIR="$DATA/bamfiles"
RUNDIR=$(realpath -m "${1:-/vol/data/benchmark/runs/small_test}")
THREADS=${2:-8}
BATCH_SIZE=${BATCH_SIZE:-256}
EMB_SIZE=${EMB_SIZE:-512}
EPOCHS=${EPOCHS:-30}
SEED=${SEED:-}
START_LOCK=/tmp/benchmark-start.lock
ACTIVE=/vol/data/benchmark/.active_run

[ -f "$CONTIGS" ] || { echo "ERROR: missing small contigs: $CONTIGS"; exit 1; }
[ -f "$BAMDIR/reads.bam" ] || { echo "ERROR: missing small BAM: $BAMDIR/reads.bam"; exit 1; }
[ -f "$SRC/COMEBin/run_comebin.sh" ] || { echo "ERROR: SRC_COMEBIN is not a COMEBin repo root: $SRC"; exit 1; }

# Serialize new launches and refuse overlap with the independently tracked run.
# Checking .active_run is essential: the already-running baseline predates this lock.
exec 9>"$START_LOCK"
flock -n 9 || { echo "ERROR: another benchmark launch holds $START_LOCK"; exit 1; }
if [ -f "$ACTIVE" ] && [ "${BENCHMARK_WATCHDOG_REPLACE:-0}" != "1" ]; then
  read -r active_pid active_pgid active_log active_dir active_start active_mode active_src < "$ACTIVE" || true
  active_state=$(ps -o stat= -p "${active_pid:-0}" 2>/dev/null | tr -d ' ' || true)
  if [ -n "${active_pid:-}" ] && kill -0 "$active_pid" 2>/dev/null && [[ "$active_state" != Z* ]]; then
    echo "ERROR: benchmark already active: pid=$active_pid dir=$active_dir mode=${active_mode:-baseline}"
    echo "Small functional tests and full benchmarks must never overlap; try again after that run finishes."
    exit 1
  fi
  old_rc=$(grep -m1 '^exit_code:' "${active_dir:-/nonexistent}/run_meta.txt" 2>/dev/null | awk '{print $2}' || true)
  if [ "${old_rc:-}" != "0" ]; then
    echo "ERROR: stale failed active run is registered: pid=$active_pid dir=$active_dir"
    echo "Run /vol/data/benchmark/bin/benchmark-watchdog.sh to triage/restart it; not starting a second run."
    exit 1
  fi
  echo "clearing completed stale active-run registration for $active_dir"
  rm -f "$ACTIVE"
fi

if [ -f "$RUNDIR/run_meta.txt" ] || [ -d "$RUNDIR/comebin_out" ]; then
  echo "ERROR: refusing to overwrite an existing run directory: $RUNDIR"
  echo "Choose a fresh rundir (autorestart directories are created by benchmark-watchdog)."
  exit 1
fi

mkdir -p "$RUNDIR/logs"
COMMIT=$(git -C "$SRC" rev-parse HEAD)
BRANCH=$(git -C "$SRC" branch --show-current)
# Ignore generated caches such as __pycache__, but reject every tracked edit.
DIRTY=$(git -C "$SRC" status --porcelain --untracked-files=no | wc -l)
echo "source commit: $COMMIT branch=$BRANCH (tracked dirty files: $DIRTY) — small-dataset test run"
[ "$DIRTY" -eq 0 ] || { echo "REFUSING: source has tracked changes; commit or clean it first"; exit 1; }
COMEBIN_ARGS=(
  -a "$CONTIGS" -p "$BAMDIR" -o "$RUNDIR/comebin_out"
  -n 6 -t "$THREADS" -b "$BATCH_SIZE" -e "$EMB_SIZE" -c "$EMB_SIZE"
)
# v1.1.0+ defaults to CUDA; this VM is CPU-only. Older CLIs do not know -d.
if grep -q -- '-d STR.*device' "$SRC/COMEBin/run_comebin.sh"; then
  COMEBIN_ARGS+=(-d cpu)
fi
if [ -n "$SEED" ] && grep -q -- '-s INT.*seed' "$SRC/COMEBin/run_comebin.sh"; then
  COMEBIN_ARGS+=(-s "$SEED")
fi
# Issue #10: cap epochs for fast functional tests (upstream CLI has no -E).
if grep -q -- '-E INT.*epochs' "$SRC/COMEBin/run_comebin.sh"; then
  COMEBIN_ARGS+=(-E "$EPOCHS")
fi
CMD_TEXT=$(printf '%q ' "$MM" run -p "$ENV" bash run_comebin.sh "${COMEBIN_ARGS[@]}")

{
  echo "run:        $RUNDIR"
  echo "date:       $(date -Is)"
  echo "source:     $SRC"
  echo "branch:     $BRANCH"
  echo "commit:     $COMMIT"
  echo "contigs:    $CONTIGS  ($(grep -c '^>' "$CONTIGS") contigs, $(du -h "$CONTIGS" | cut -f1))"
  echo "bamdir:     $BAMDIR"
  echo "threads:    $THREADS"
  echo "batch_size: $BATCH_SIZE"
  echo "emb_size:   $EMB_SIZE"
  echo "epochs:     $EPOCHS (passed as -E when the CLI supports it)"
  echo "seed:       ${SEED:-unset}"
  echo "host:       $(nproc) cores, $(free -g | awk '/Mem:/{print $2}')G RAM"
  echo "cmd_wrapper: $CMD_TEXT"
} | tee "$RUNDIR/run_meta.txt"

export MAMBA_ROOT_PREFIX=/vol/data/envs/.mamba
cd "$SRC/COMEBin"

# Fields: pid pgid logfile rundir start_epoch mode source_repo. Older baseline
# registrations have five fields and are treated as mode=baseline.
printf '%s %s %s %s %s %s %s\n' "$$" "$(ps -o pgid= -p $$ | tr -d ' ')" \
  "$RUNDIR/comebin_run.log" "$RUNDIR" "$(date +%s)" small "$SRC" > "$ACTIVE.tmp.$$"
mv "$ACTIVE.tmp.$$" "$ACTIVE"

SAMPLER_PID=""
cleanup() {
  rc=$?
  trap - EXIT
  if [ -n "$SAMPLER_PID" ] && kill -0 "$SAMPLER_PID" 2>/dev/null; then
    kill "$SAMPLER_PID" 2>/dev/null || true
    wait "$SAMPLER_PID" 2>/dev/null || true
  fi
  # On normal completion all foreground children are gone. Explicitly release
  # the launch lock before a short functional test exits; a signal exit does not
  # proactively declare the launch area free.
  if [ "$rc" -ne 130 ]; then
    flock -u 9 2>/dev/null || true
    exec 9>&-
  fi
  # A failed run stays registered so benchmark-watchdog can apply its restart
  # budget. Only a successful run clears its own registration.
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
sample_resources > "$RUNDIR/logs/resources.tsv" 2> "$RUNDIR/logs/sampler.out" &
SAMPLER_PID=$!

# No other registered benchmark can exist (checked above), so the first training
# process found is necessarily this run. Failure to capture it is non-fatal.
# Do not let this late helper inherit the launch-lock FD after a short test exits.
( sleep 12; MCMD=$(pgrep -af 'main.py train' 2>/dev/null | head -1 | cut -d' ' -f2-); \
  [ -n "$MCMD" ] && echo "cmd_train_py: $MCMD" >> "$RUNDIR/run_meta.txt" ) 9>&- &

START=$(date +%s)
set +e
CUDA_VISIBLE_DEVICES= "$MM" run -p "$ENV" bash run_comebin.sh \
  "${COMEBIN_ARGS[@]}" 2>&1 | tee "$RUNDIR/comebin_run.log"
RC=${PIPESTATUS[0]}
set -e
END=$(date +%s)

# The upstream COMEBin wrapper can mask a clustering/get_result failure and
# return 0 even when it produced no bins.  A functional gate is not successful
# without at least one non-empty bin, so validate the artifact before recording
# the terminal status consumed by the watchdog and GitHub triage.
BINS="$RUNDIR/comebin_out/comebin_res/comebin_res_bins"
BIN_COUNT=0
if [ -d "$BINS" ]; then
  BIN_COUNT=$(find "$BINS" -maxdepth 1 -type f -size +0c | wc -l)
fi
if [ "$RC" -eq 0 ] && [ "$BIN_COUNT" -eq 0 ]; then
  echo "ERROR: COMEBin returned 0 but no non-empty bins were produced at $BINS; recording failure" \
    | tee -a "$RUNDIR/run_meta.txt"
  RC=1
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

grep -aE 'run_FragGeneScan|hmmsearch' "$RUNDIR/comebin_run.log" 2>/dev/null | head -2 \
  | sed 's/^/cmd_from_log: /' | tee -a "$RUNDIR/run_meta.txt" >/dev/null || true
exit "$RC"
