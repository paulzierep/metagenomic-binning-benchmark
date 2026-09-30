#!/usr/bin/env bash
# run_eval_chain.sh <run_dir> <dataset> [max_wait_s] [threads]
#
# Detached follow-on chain for a finished (or still-running) COMEBin benchmark
# run. It NEVER overlaps the registered benchmark run: the evaluation only
# starts once the run has recorded `exit_code:` in its run_meta.txt AND the
# wrapper process has been released from /vol/data/benchmark/.active_run
# (run_eval.sh re-checks .active_run itself).
#
# Steps, each logged and non-fatal for the next:
#   1. wait for the run to finish (default cap 8 h, then abort)
#   2. run_eval.sh           -> CheckM2 + CheckM v1, results CSV, per-bin CSV and
#                               plots, Zenodo release (wired into run_eval.sh)
#   3. AMBER official CAMI scoring, if a gold standard exists for <dataset>
#   4. biobox export (CAMI v0.9.1 .binning + bins.fasta.gz + tar.gz) and
#      structural validation of the .binning file
#
# dataset: marine | human | cami3 | none
#
# Usage (detached, as with every long job here):
#   cd /vol/data/benchmark && nohup setsid bash followups/run_eval_chain.sh \
#       /vol/data/benchmark/runs/<run> cami3 28800 \
#       > /vol/data/benchmark/logs/<run>.chain.log 2>&1 &
#
# DEDUP: always `pgrep -f run_eval_chain.sh` first — a restart turn must not
# start a second chain for the same run (CheckM2/CheckM would collide on the
# same eval directory).
set -uo pipefail

RUN=${1:?usage: run_eval_chain.sh <run_dir> <marine|human|cami3|none> [max_wait_s] [threads]}
DATASET=${2:?usage: run_eval_chain.sh <run_dir> <marine|human|cami3|none> [max_wait_s] [threads]}
MAX_WAIT_S=${3:-28800}
THREADS=${4:-32}

B=/vol/data/benchmark
BIN=$B/bin
REPO=/vol/data/repos/metagenomic-binning-benchmark
META="$RUN/run_meta.txt"
RUN_NAME=$(basename "$RUN")
LOG=$B/status/${RUN_NAME}.eval_chain.log
AMBER_DIR=$B/amber
MM=/vol/data/tools/bin/micromamba

case "$DATASET" in
  marine) GOLD=/vol/data/datasets/cami_II/marine_sample0_input/binning_gs_subset.tsv
          AMBER_SAMPLE=marine; BIOBOX_SAMPLE=marine_sample0 ;;
  human)  GOLD=/vol/data/datasets/cami_II_human/gold_standard/human_binning_gs.tsv
          AMBER_SAMPLE=human;  BIOBOX_SAMPLE=human_sample0 ;;
  cami3)  GOLD=/vol/data/datasets/cami_III/gold_standard/cami3_toy_binning_gs.tsv
          AMBER_SAMPLE=cami3_toy_human_gut; BIOBOX_SAMPLE=toy_human_2samples ;;
  none)   GOLD=""; AMBER_SAMPLE=""; BIOBOX_SAMPLE=unknown_sample ;;
  *) echo "ERROR: unknown dataset '$DATASET' (marine|human|cami3|none)" >&2; exit 2 ;;
esac

log() { printf '%s chain[%s]: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$RUN_NAME" "$*" >>"$LOG"; }
log "START dataset=$DATASET max_wait=${MAX_WAIT_S}s threads=$THREADS gold=${GOLD:-none}"

# ---------------------------------------------------------------- 1. wait
waited=0
while :; do
  if grep -q '^exit_code:' "$META" 2>/dev/null; then
    log "run finished: $(grep -E '^(exit_code|wall_s|bins):' "$META" | tr '\n' ' ')"
    break
  fi
  [ "$waited" -ge "$MAX_WAIT_S" ] && { log "ABORT: still no exit_code after ${waited}s"; exit 1; }
  if [ $((waited % 900)) -eq 0 ]; then
    log "waiting: $(grep -o 'epoch=[0-9]*/200' "$RUN/comebin_run.log" 2>/dev/null | tail -1) (waited ${waited}s)"
  fi
  sleep 60
  waited=$((waited + 60))
done

# The harness writes exit_code just before exiting; wait for .active_run to be
# released so run_eval.sh does not refuse on a still-live pid.
for _ in $(seq 1 30); do
  live=""
  if [ -f "$B/.active_run" ]; then
    read -r apid _ <"$B/.active_run" || true
    [ -n "${apid:-}" ] && kill -0 "$apid" 2>/dev/null && live=$apid
  fi
  [ -z "$live" ] && break
  log "wrapper pid $live still live; waiting for .active_run release"
  sleep 20
done

exit_code=$(sed -n 's/^exit_code:[[:space:]]*//p' "$META" | tr -d ' ' | tail -1)
[ "${exit_code:-1}" = 0 ] || log "NOTE: non-zero exit_code=${exit_code:-?} — evaluating anyway (evidence first)"

# ---------------------------------------------------------------- 2. eval
log "run_eval.sh starting"
"$BIN/run_eval.sh" "$RUN" "$THREADS" >>"$LOG" 2>&1 \
  && log "run_eval.sh OK" || log "run_eval.sh FAILED rc=$?"

# ---------------------------------------------------------------- 3. AMBER
if [ -n "$GOLD" ] && [ -f "$GOLD" ] \
   && [ -d "$RUN/comebin_out/comebin_res/comebin_res_bins" ]; then
  PRED=$AMBER_DIR/${RUN_NAME}.binning
  OUT_DIR=$AMBER_DIR/output_${RUN_NAME}
  if python3 "$BIN/make_amber_prediction.py" "$RUN" "$AMBER_SAMPLE" >"$PRED" 2>>"$LOG"; then
    log "AMBER: scoring $RUN_NAME (out $OUT_DIR)"
    ( cd "$AMBER_DIR" && "$MM" run -p /vol/data/envs/amber python3 \
        /vol/data/repos/CAMI-AMBER/amber.py "$(basename "$PRED")" \
        -g "$GOLD" -o "$(basename "$OUT_DIR")" -l comebin ) >>"$LOG" 2>&1 \
      && log "AMBER OK rc=0" || log "AMBER FAILED rc=$?"
    REPO_AMBER=$REPO/results/amber/$DATASET
    mkdir -p "$REPO_AMBER"
    [ -f "$OUT_DIR/results.tsv" ] && cp -f "$OUT_DIR/results.tsv" "$REPO_AMBER/amber_results_${RUN_NAME}.tsv"
    [ -f "$OUT_DIR/bin_metrics.tsv" ] && cp -f "$OUT_DIR/bin_metrics.tsv" "$REPO_AMBER/bin_metrics_${RUN_NAME}.tsv"
    [ -f "$OUT_DIR/index.html" ] && cp -f "$OUT_DIR/index.html" "$REPO_AMBER/amber_report_${RUN_NAME}.html"
    [ -f "$OUT_DIR/heatmap_bar.png" ] && cp -f "$OUT_DIR/heatmap_bar.png" "$REPO_AMBER/heatmap_${RUN_NAME}.png"
    log "AMBER artifacts copied to $REPO_AMBER/${RUN_NAME}.*"
  else
    log "AMBER: prediction build FAILED"
  fi
else
  log "AMBER: skipped (no gold standard for '$DATASET' or no bins dir)"
fi

# ---------------------------------------------------------------- 4. biobox
log "biobox export starting"
if ENGINE=comebin VERSION="${DATASET}_v11" SAMPLE="$BIOBOX_SAMPLE" \
     bash "$BIN/export_biobox.sh" "$RUN" >>"$LOG" 2>&1; then
  log "biobox export OK"
  # shellcheck disable=SC2086
  python3 "$BIN/validate_binning.py" "$RUN"/biobox/*.binning >>"$LOG" 2>&1 \
    && log "biobox .binning validation OK" || log "biobox .binning validation FAILED rc=$?"
else
  log "biobox export FAILED rc=$?"
fi

log "CHAIN COMPLETE run=$RUN dataset=$DATASET"
