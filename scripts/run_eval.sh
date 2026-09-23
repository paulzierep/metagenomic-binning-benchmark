#!/usr/bin/env bash
# run_eval.sh <rundir> [threads] — CheckM2 + CheckM v1 bin-quality evaluation for a
# finished COMEBin run. Appends the exact command lines + rc/wall times to
# <rundir>/run_meta.txt and writes outputs to <rundir>/eval/.
set -euo pipefail
MM=/vol/data/tools/bin/micromamba
export MAMBA_ROOT_PREFIX=/vol/data/envs/.mamba
RUN=${1:?usage: run_eval.sh <rundir> [threads]}
THREADS=${2:-32}
exec 9>/tmp/benchmark-start.lock
flock -n 9 || { echo "ERROR: another benchmark launch/evaluation holds /tmp/benchmark-start.lock"; exit 1; }
if [ -f /vol/data/benchmark/.active_run ]; then
  read -r active_pid _ < /vol/data/benchmark/.active_run || true
  active_state=$(ps -o stat= -p "${active_pid:-0}" 2>/dev/null | tr -d ' ' || true)
  if [ -n "${active_pid:-}" ] && kill -0 "$active_pid" 2>/dev/null && [[ "$active_state" != Z* ]]; then
    echo "ERROR: refusing CheckM evaluation while benchmark pid $active_pid is active"
    exit 1
  fi
fi
BINS="$RUN/comebin_out/comebin_res/comebin_res_bins"
[ -d "$BINS" ] || { echo "ERROR: no bins dir: $BINS"; exit 1; }
CK2DB=${CHECKM2DB:-/vol/data/benchmark/checkm2db/CheckM2_database/uniref100.KO.1.dmnd}
[ -f "$CK2DB" ] || { echo "WARNING: checkm2 db not found at $CK2DB (set CHECKM2DB)"; }
mkdir -p "$RUN/eval/checkm2" "$RUN/eval/checkm/tmp"

echo "=== CheckM2 (predict) ==="
CMD2="$MM run -p /vol/data/envs/checkm2 checkm2 predict --threads $THREADS --database_path $CK2DB --input $BINS --output-directory $RUN/eval/checkm2 -x fasta"
echo "cmd_checkm2: $CMD2" | tee -a "$RUN/run_meta.txt"
T=$(date +%s); bash -c "$CMD2" 9>&-; rc2=$?
echo "checkm2_rc: $rc2 checkm2_wall_s: $(( $(date +%s) - T ))" | tee -a "$RUN/run_meta.txt"
[ -f "$RUN/eval/checkm2/quality_report.tsv" ] && echo "checkm2 report: $RUN/eval/checkm2/quality_report.tsv"

echo "=== CheckM v1 (lineage_wf) ==="
CMD1="$MM run -p /vol/data/envs/checkm checkm lineage_wf -x fasta -t $THREADS --tmpdir $RUN/eval/checkm/tmp $BINS $RUN/eval/checkm/out"
echo "cmd_checkm: $CMD1" | tee -a "$RUN/run_meta.txt"
T=$(date +%s); bash -c "$CMD1" 9>&-; rc1=$?
echo "checkm_rc: $rc1 checkm_wall_s: $(( $(date +%s) - T ))" | tee -a "$RUN/run_meta.txt"
[ -f "$RUN/eval/checkm/out/storage/bin_stats_ext.tsv" ] && echo "checkm statistics: $RUN/eval/checkm/out/storage/bin_stats_ext.tsv"

echo "=== summary ==="
python3 "$(dirname "$0")/parse_eval.py" "$RUN" 9>&-
echo "done (checkm2 rc=$rc2, checkm rc=$rc1)"
