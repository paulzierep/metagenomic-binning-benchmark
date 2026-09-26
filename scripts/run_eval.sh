#!/usr/bin/env bash
# run_eval.sh <rundir> [threads] — CheckM2 + CheckM v1 bin-quality evaluation for a
# finished COMEBin run. Appends the exact command lines + rc/wall times to
# <rundir>/run_meta.txt and writes outputs to <rundir>/eval/.
set -euo pipefail
MM=/vol/data/tools/bin/micromamba
CHECKM2_ENV=${CHECKM2_ENV:-/vol/data/envs/checkm2}
# The standalone checkm environment currently uses Python 3.14, whose
# forkserver/pickling behaviour breaks CheckM v1's private worker methods.
# The COMEBin environment contains the same CheckM v1 workflow on Python 3.10;
# use it by default and keep the override for a repaired standalone env.
CHECKM_ENV=${CHECKM_ENV:-/vol/data/envs/comebin}
# pplacer in the Python-3.10 environment needs the OpenBLAS shared object
# installed in the standalone checkm environment.
CHECKM_LD_LIBRARY_PATH=${CHECKM_LD_LIBRARY_PATH:-/vol/data/envs/checkm/lib:/vol/data/envs/comebin/lib}
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
BIN_COUNT=$(find -L "$BINS" -maxdepth 1 -type f -size +0c | wc -l)
[ "$BIN_COUNT" -gt 0 ] || { echo "ERROR: bins dir contains no non-empty files: $BINS"; exit 1; }
# COMEBin writes .fa files. CheckM2 matches the extension literally, so the
# previous -x fasta value silently selected zero bins. Detect common variants.
BIN_EXT=fa
for candidate_ext in fasta fna fa; do
  shopt -s nullglob
  candidate_files=("$BINS"/*."$candidate_ext")
  shopt -u nullglob
  if [ "${#candidate_files[@]}" -gt 0 ]; then
    BIN_EXT=$candidate_ext
    break
  fi
done
CK2DB=${CHECKM2DB:-/vol/data/benchmark/checkm2db/CheckM2_database/uniref100.KO.1.dmnd}
[ -f "$CK2DB" ] || { echo "WARNING: checkm2 db not found at $CK2DB (set CHECKM2DB)"; }
CHECKM2_OUT="$RUN/eval/checkm2"
CHECKM_ROOT="$RUN/eval/checkm"
CHECKM_OUT="$CHECKM_ROOT/out"
CHECKM_TMP="$CHECKM_ROOT/tmp"
mkdir -p "$CHECKM2_OUT" "$CHECKM_TMP"

# CheckM2 ---------------------------------------------------------------------
# CheckM2 1.1.0 has a parallel gene-calling race that scales with bin count:
# on cami3_v11_20260926_rerun (492 bins) `predict --threads 32` died after 343 s
# with "cannot create protein_files/*.gff.NN" followed by "List of protein files
# does not match internal reference", while the same 492 bins succeeded at 16
# threads (1,137 s).  Smaller sets (marine 152 bins, human ~40) never hit it.
# Two guards: cap threads once the bin count reaches the observed-bad range, and
# retry once at a lower thread count into a fresh output directory so a single
# race never costs the whole evaluation.  Both thresholds are env-overridable.
CK2_BIN_THRESHOLD=${CHECKM2_BIN_THREAD_THRESHOLD:-400}
CK2_MAX_THREADS=${CHECKM2_MAX_THREADS:-16}
CK2_RETRY_THREADS=${CHECKM2_RETRY_THREADS:-16}
CK2_THREADS=$THREADS
if [ "$BIN_COUNT" -ge "$CK2_BIN_THRESHOLD" ] && [ "$CK2_THREADS" -gt "$CK2_MAX_THREADS" ]; then
  CK2_THREADS=$CK2_MAX_THREADS
  echo "checkm2_thread_cap: bins=$BIN_COUNT >= $CK2_BIN_THRESHOLD -> threads $THREADS capped to $CK2_THREADS (gene-calling race guard)" \
    | tee -a "$RUN/run_meta.txt"
fi

run_checkm2() {  # $1 = thread count; sets rc2
  local th=$1 r=0
  CMD2="$MM run -p $CHECKM2_ENV checkm2 predict --threads $th --database_path $CK2DB --input $BINS --output-directory $CHECKM2_OUT -x $BIN_EXT --force"
  echo "cmd_checkm2: $CMD2" | tee -a "$RUN/run_meta.txt"
  T=$(date +%s)
  bash -c "$CMD2" 9>&- || r=$?
  if [ "$r" -eq 0 ] && [ ! -s "$CHECKM2_OUT/quality_report.tsv" ]; then
    echo "ERROR: CheckM2 returned 0 but quality_report.tsv is missing/empty; recording failure" \
      | tee -a "$RUN/run_meta.txt"
    r=1
  fi
  echo "checkm2_rc: $r checkm2_wall_s: $(( $(date +%s) - T )) checkm2_threads: $th" | tee -a "$RUN/run_meta.txt"
  rc2=$r
}

echo "=== CheckM2 (predict; extension=$BIN_EXT; bins=$BIN_COUNT; threads=$CK2_THREADS) ==="
run_checkm2 "$CK2_THREADS"

# One automatic retry at a genuinely lower thread count.  The failed output is
# preserved (same convention as the CheckM v1 block below) so the evidence of
# the race is never overwritten by its own retry.
if [ "$rc2" -ne 0 ]; then
  CK2_RETRY_T=$CK2_RETRY_THREADS
  [ "$CK2_RETRY_T" -ge "$CK2_THREADS" ] && CK2_RETRY_T=$(( CK2_THREADS / 2 ))
  [ "$CK2_RETRY_T" -lt 1 ] && CK2_RETRY_T=1
  stale_ck2="$RUN/eval/checkm2.incomplete.$(date +%s)"
  if [ -e "$CHECKM2_OUT" ]; then
    mv "$CHECKM2_OUT" "$stale_ck2" 2>/dev/null || rm -rf "$CHECKM2_OUT"
    echo "preserved failed CheckM2 output: $stale_ck2" | tee -a "$RUN/run_meta.txt"
  fi
  mkdir -p "$CHECKM2_OUT"
  echo "checkm2_retry: rc=$rc2 at $CK2_THREADS threads -> retrying once at $CK2_RETRY_T threads (gene-calling race guard)" \
    | tee -a "$RUN/run_meta.txt"
  run_checkm2 "$CK2_RETRY_T"
  echo "checkm2_retry_rc: $rc2  checkm2_retry_threads: $CK2_RETRY_T" | tee -a "$RUN/run_meta.txt"
fi
[ -f "$CHECKM2_OUT/quality_report.tsv" ] && echo "checkm2 report: $CHECKM2_OUT/quality_report.tsv"

# CheckM v1 -------------------------------------------------------------------
# Preserve an incomplete prior output instead of overwriting evidence. This is
# important when upgrading from the broken Python-3.14 standalone environment.
if [ -e "$CHECKM_OUT" ] && [ ! -s "$CHECKM_OUT/storage/bin_stats_ext.tsv" ]; then
  stale_out="$CHECKM_ROOT/out.incomplete.$(date +%s)"
  mv "$CHECKM_OUT" "$stale_out"
  echo "preserved incomplete CheckM output: $stale_out"
fi
mkdir -p "$CHECKM_TMP"
echo "=== CheckM v1 (lineage_wf; extension=$BIN_EXT; env=$CHECKM_ENV) ==="
CMD1="LD_LIBRARY_PATH=$CHECKM_LD_LIBRARY_PATH $MM run -p $CHECKM_ENV checkm lineage_wf -x $BIN_EXT -t $THREADS --tmpdir $CHECKM_TMP $BINS $CHECKM_OUT"
echo "cmd_checkm: $CMD1" | tee -a "$RUN/run_meta.txt"
T=$(date +%s)
set +e
bash -c "$CMD1" 9>&-
rc1=$?
set -e
if [ "$rc1" -eq 0 ] && [ ! -s "$CHECKM_OUT/storage/bin_stats_ext.tsv" ]; then
  echo "ERROR: CheckM returned 0 but bin_stats_ext.tsv is missing/empty; recording failure" \
    | tee -a "$RUN/run_meta.txt"
  rc1=1
fi
if [ "$rc1" -eq 0 ] && grep -q 'Controlled exit resulting from an unrecoverable error' "$CHECKM_OUT/checkm.log" 2>/dev/null; then
  echo "ERROR: CheckM log contains a controlled-error exit; recording failure" \
    | tee -a "$RUN/run_meta.txt"
  rc1=1
fi
echo "checkm_rc: $rc1 checkm_wall_s: $(( $(date +%s) - T ))" | tee -a "$RUN/run_meta.txt"
[ -f "$CHECKM_OUT/storage/bin_stats_ext.tsv" ] && echo "checkm statistics: $CHECKM_OUT/storage/bin_stats_ext.tsv"

# Summary and final status ----------------------------------------------------
echo "=== summary ==="
python3 "$(dirname "$0")/parse_eval.py" "$RUN" 9>&-
if [ "$rc2" -eq 0 ] && [ "$rc1" -eq 0 ]; then
  # Automatic reporting (issues #12/#15): aggregate CSV + per-bin CSV + plots,
  # regenerated after every successfully evaluated run. Best-effort: a report
  # failure must not turn a successful evaluation into a failed one.
  echo "=== auto-reporting: results/<run>.csv, runs/<run>/per_bin_results.csv, per_bins.png ==="
  python3 "$(dirname "$0")/make_results_csv.py" "$RUN" 9>&- \
    || echo "WARNING: make_results_csv.py failed (rc=$?)" >&2
  python3 "$(dirname "$0")/make_per_bin_csv.py" "$RUN" 9>&- \
    || echo "WARNING: make_per_bin_csv.py failed (rc=$?)" >&2
  "$MM" run -p "$CHECKM_ENV" python3 "$(dirname "$0")/make_per_bin_plots.py" --all "$RUN" 9>&- \
    || echo "WARNING: make_per_bin_plots.py failed (rc=$?)" >&2
  # Issue #12: combined bar plot for the three main datasets + its stats table
  # (README embeds both; regenerated after every successful eval).
  "$MM" run -p "$CHECKM_ENV" python3 "$(dirname "$0")/make_combined_bar_plot.py" 9>&- \
    || echo "WARNING: make_combined_bar_plot.py failed (rc=$?)" >&2
  # Issue #8: continuously store the newly generated benchmark data as a new
  # version of the same Zenodo record (no-op when content is unchanged).
  bash "$(dirname "$0")/zenodo_update.sh" 9>&- \
    || echo "WARNING: zenodo_update.sh failed (rc=$?)" >&2
fi
echo "done (checkm2 rc=$rc2, checkm rc=$rc1)"
if [ "$rc2" -ne 0 ] || [ "$rc1" -ne 0 ]; then
  exit 1
fi
