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
flock -n 9 || { echo "ERROR: another benchmark launch holds $START_LOCK"; exit 1; }
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

mkdir -p "$RUNDIR/logs"
COMMIT=$(git -C "$SRC" rev-parse HEAD)
DIRTY=$(git -C "$SRC" status --porcelain --untracked-files=no | wc -l)
BRANCH=$(git -C "$SRC" branch --show-current)
echo "source: $SRC (branch $BRANCH) commit: $COMMIT (dirty files: $DIRTY)"
[ "$DIRTY" -eq 0 ] || { echo "REFUSING: source tree has uncommitted changes; commit them first"; exit 1; }
COMEBIN_ARGS=(-a "$CONTIGS" -p "$BAMDIR" -o "$RUNDIR/comebin_out" -n 6 -t "$THREADS")
if grep -q -- '-d STR.*device' "$SRC/COMEBin/run_comebin.sh"; then
  COMEBIN_ARGS+=(-d cpu)
fi
if [ -n "$SEED" ] && grep -q -- '-s INT.*seed' "$SRC/COMEBin/run_comebin.sh"; then
  COMEBIN_ARGS+=(-s "$SEED")
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
  echo "seed:       ${SEED:-unset}"
  echo "host:       $(nproc) cores, $(free -g | awk '/Mem:/{print $2}')G RAM, gpu=$(nvidia-smi -L 2>/dev/null || echo none)"
  echo "cmd_wrapper: $CMD_TEXT"
} | tee "$RUNDIR/run_meta.txt"

export MAMBA_ROOT_PREFIX=/vol/data/envs/.mamba
cd "$SRC/COMEBin"   # upstream resolves ../auxiliary relative to CWD

# Fields: pid pgid logfile rundir start_epoch mode source_repo.
printf '%s %s %s %s %s %s %s\n' "$$" "$(ps -o pgid= -p $$ | tr -d ' ')" \
  "$RUNDIR/comebin_run.log" "$RUNDIR" "$(date +%s)" "$MODE" "$SRC" > "$ACTIVE"

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
sample_resources > "$RUNDIR/logs/resources.tsv" 2> "$RUNDIR/logs/sampler.out" &
SAMPLER_PID=$!

# capture the real main.py train command once training starts (non-blocking)
( sleep 12; MCMD=$(pgrep -af 'main.py train' 2>/dev/null | head -1 | cut -d' ' -f2-); \
  [ -n "$MCMD" ] && echo "cmd_train_py: $MCMD" >> "$RUNDIR/run_meta.txt" ) &

START=$(date +%s)
set +e
CUDA_VISIBLE_DEVICES= "$MM" run -p "$ENV" bash run_comebin.sh \
  "${COMEBIN_ARGS[@]}" 2>&1 | tee "$RUNDIR/comebin_run.log"
RC=${PIPESTATUS[0]}
set -e
END=$(date +%s)

{
  echo "exit_code:  $RC"
  echo "wall_s:     $((END-START))"
  echo "finished:   $(date -Is)"
} | tee -a "$RUNDIR/run_meta.txt"

if [ "$RC" -eq 0 ]; then
  BINS="$RUNDIR/comebin_out/comebin_res/comebin_res_bins"
  if [ -d "$BINS" ]; then
    echo "bins: $(ls "$BINS" | wc -l)  -> $BINS" | tee -a "$RUNDIR/run_meta.txt"
  fi
fi
# record helper-tool commands visible in the log (FragGeneScan/hmmsearch seed genes)
grep -aE 'run_FragGeneScan|hmmsearch' "$RUNDIR/comebin_run.log" 2>/dev/null | head -2 \
  | sed 's/^/cmd_from_log: /' | tee -a "$RUNDIR/run_meta.txt" >/dev/null || true
exit "$RC"
