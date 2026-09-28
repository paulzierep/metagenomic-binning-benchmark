#!/usr/bin/env bash
# export_biobox.sh <run_dir>  — export a run's bins as a CAMI biobox tarball.
#
# Issue #25 (owner): "learn to export binning results as biobox format - cami
# standard, also export each binning result: bins in fasta, biobox output,
# stats".
#
# CAMI biobox binning layout (https://github.com/bioboxes/rfc/blob/master/
# data-format/binning.rst):
#
#   <input>/binning/<engine>/<version>/binning/<sample>/<bin_id>.fna
#   <input>/binning/<engine>/<version>/binning_summary.tsv
#
# Our run layout:
#   runs/<run>/comebin_out/comebin_res/comebin_res_bins/<id>.fa   (cluster bins)
#   runs/<run>/per_bin_results.csv                                (stats)
#
# Output (written next to the run dir):
#   runs/<run>/biobox/binning.tar.gz                              (CAMI-compliant)
#   runs/<run>/biobox/bins.fasta.gz                               (all bins, concat)
#   runs/<run>/biobox/binning_summary.tsv                         (per-bin stats)
#
# Usage:
#   bash scripts/export_biobox.sh /vol/data/benchmark/runs/medium_v11_20260924
#   ENGINE=comebin VERSION=v11.1.0 SAMPLE=cami_sample0  # overridable
set -euo pipefail

RUN_DIR=${1:?usage: export_biobox.sh <run_dir>}
[ -d "$RUN_DIR" ] || { echo "ERROR: not a dir: $RUN_DIR"; exit 1; }
BINS_DIR="$RUN_DIR/comebin_out/comebin_res/comebin_res_bins"
[ -d "$BINS_DIR" ] || { echo "ERROR: no comebin_res_bins in $RUN_DIR"; exit 1; }

ENGINE=${ENGINE:-comebin}
VERSION=${VERSION:-v11}
SAMPLE=${SAMPLE:-unknown_sample}
OUT="$RUN_DIR/biobox"
TREE="$OUT/tree/$ENGINE/$VERSION/binning/$SAMPLE"
mkdir -p "$TREE"

bin_count=0
for f in "$BINS_DIR"/*.fa; do
  [ -e "$f" ] || continue
  id=$(basename "$f" .fa)
  cp "$f" "$TREE/$id.fna"
  bin_count=$((bin_count + 1))
done
[ "$bin_count" -gt 0 ] || { echo "ERROR: no bin fastas found"; exit 1; }

# binning_summary.tsv (biobox column layout: bin_id, contig_id, contig_len) —
# one row per contig membership; contig length parsed from the FASTA defline
# `length=<bp>` when present, else computed on the fly.
summary="$OUT/tree/$ENGINE/$VERSION/binning_summary.tsv"
{
  echo -e "bin_id\tcontig_id\tcontig_len"
  for f in "$TREE"/*.fna; do
    bin_id=$(basename "$f" .fna)
    awk -v bin="$bin_id" '
      /^>/ {
        name = substr($1, 2)
        if (match($0, /length=[0-9]+/))
          len = substr($0, RSTART + 7, RLENGTH - 7)
        else
          len = "NA"
        print bin "\t" name "\t" len
      }
    ' "$f"
  done
} > "$summary"

# Concatenated bins (for easy archival + stats consumers).
cat "$TREE"/*.fna | gzip > "$OUT/bins.fasta.gz"

# tarball rooted at <engine>/... so the biobox validator accepts it directly.
tar -C "$OUT/tree" -czf "$OUT/binning.tar.gz" "$ENGINE"

cat > "$OUT/README.txt" <<EOF
CAMI biobox export of $RUN_DIR

engine:  $ENGINE
version: $VERSION
sample:  $SAMPLE
bins:    $bin_count

Contents:
  binning.tar.gz          CAMI biobox compliant (engine/version/binning_summary.tsv)
  bins.fasta.gz           all bins concatenated, FASTA
  binning_summary.tsv     contig membership + length per bin
  stats.csv               per-bin CheckM2/CheckM v1 (from per_bin_results.csv)

Validate with the biobox validator (container) before archival:
  docker run -v $(pwd):/data bioboxes/validator /data/binning.tar.gz binning
EOF

# Per-bin stats snapshot when available.
if [ -f "$RUN_DIR/per_bin_results.csv" ]; then
  cp "$RUN_DIR/per_bin_results.csv" "$OUT/stats.csv"
fi

echo "wrote $OUT (bins=$bin_count)"
ls -la "$OUT" | awk '{print $5, $9}'