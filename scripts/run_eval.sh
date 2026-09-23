#!/usr/bin/env bash
# run_eval.sh — score a bin directory with CheckM2 AND CheckM v1, emit a CSV row.
# Usage: run_eval.sh <bins_dir> <out_prefix> [threads]
set -euo pipefail

BINS=${1:?bins_dir}
OUT=${2:?out_prefix}
THREADS=${3:-32}
MM=/vol/data/tools/bin/micromamba
ENV_C2=/vol/data/envs/checkm2
ENV_C1=/vol/data/envs/checkm
mkdir -p "$OUT"

echo "[eval] CheckM2 -> $OUT/checkm2"
MAMBA_ROOT_PREFIX=/vol/data/envs/.mamba "$MM" run -p "$ENV_C2" \
  checkm2 predict --threads "$THREADS" --input "$BINS" \
  --output-directory "$OUT/checkm2"

echo "[eval] CheckM v1 -> $OUT/checkm_out"
MAMBA_ROOT_PREFIX=/vol/data/envs/.mamba "$MM" run -p "$ENV_C1" \
  checkm lineage_wf -t "$THREADS" -f "$OUT/checkm_v1.tsv" --tab_table \
  "$BINS" "$OUT/checkm_out"

echo "[eval] done: $OUT/checkm2/quality_report.tsv and $OUT/checkm_v1.tsv"
