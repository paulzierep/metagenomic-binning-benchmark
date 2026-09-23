#!/usr/bin/env bash
# run_comebin_baseline.sh — run UNMODIFIED COMEBin on the demo dataset.
# All inputs/outputs on /vol/data. Prints per-stage timing to stdout + log file.
set -euo pipefail

MM=/vol/data/tools/bin/micromamba
ENV=/vol/data/envs/comebin
SRC=/vol/data/repos/COMEBin
DATA=/vol/data/datasets/comebin_test_data
CONTIGS="$DATA/BATS_SAMN07137077_METAG.scaffolds.min500.fasta.f1k.fasta"
BAMDIR="$DATA/bamfiles"
RUNDIR=${1:-/vol/data/benchmark/runs/baseline_unmodified}
THREADS=${THREADS:-32}

mkdir -p "$RUNDIR"
COMMIT=$(git -C "$SRC" rev-parse HEAD)
DIRTY=$(git -C "$SRC" status --porcelain | wc -l)
echo "source commit: $COMMIT (dirty files: $DIRTY)"
[ "$DIRTY" -eq 0 ] || { echo "REFUSING: baseline source is modified; use pristine upstream"; exit 1; }
{
  echo "run:        $RUNDIR"
  echo "date:       $(date -Is)"
  echo "commit:     $COMMIT"
  echo "contigs:    $CONTIGS"
  echo "bamdir:     $BAMDIR"
  echo "threads:    $THREADS"
  echo "host:       $(nproc) cores, $(free -g | awk '/Mem:/{print $2}')G RAM, gpu=$(nvidia-smi -L 2>/dev/null || echo none)"
  echo "cmd_wrapper: bash run_comebin.sh -a $CONTIGS -p $BAMDIR -o $RUNDIR/comebin_out -n 6 -t $THREADS  # via: micromamba run -p $ENV"
} | tee "$RUNDIR/run_meta.txt"

export MAMBA_ROOT_PREFIX=/vol/data/envs/.mamba
cd "$SRC/COMEBin"   # upstream resolves ../auxiliary relative to CWD

# register this run for the benchmark watchdog (scripts/benchmark-watchdog.sh)
printf '%s %s %s %s %s\n' "$$" "$(ps -o pgid= -p $$ | tr -d ' ')" "$RUNDIR/comebin_run.log" "$RUNDIR" "$(date +%s)" > /vol/data/benchmark/.active_run

# capture the real main.py train command once training starts (non-blocking)
( sleep 12; MCMD=$(pgrep -af 'main.py' 2>/dev/null | head -1 | cut -d' ' -f2-); \
  [ -n "$MCMD" ] && echo "cmd_train_py: $MCMD" >> "$RUNDIR/run_meta.txt" ) &

START=$(date +%s)
set +e
CUDA_VISIBLE_DEVICES= "$MM" run -p "$ENV" bash run_comebin.sh \
  -a "$CONTIGS" -p "$BAMDIR" -o "$RUNDIR/comebin_out" \
  -n 6 -t "$THREADS" 2>&1 | tee "$RUNDIR/comebin_run.log"
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
