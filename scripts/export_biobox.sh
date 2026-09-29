#!/usr/bin/env bash
# export_biobox.sh <run_dir>  — export a run's bins as a CAMI biobox tarball.
#
# Issue #25 (owner): "learn to export binning results as biobox format - cami
# standard, also export each binning result: bins in fasta, biobox output,
# stats".
#
# CAMI binning output format v0.9.1 (authoritative, bioboxes/rfc data-format/
# binning.mkd): a single TAB-delimited `<sample>.binning` text file with a
# header (`@Version:0.9.1`, `@SampleID:<sample>`) and columns
# `@@SEQUENCEID	BINID`. This is exactly what AMBER consumes.
#
# We additionally ship the per-bin FASTA (owner #25: "bins in fasta") and a
# convenience `binning_summary.tsv` (bin_id, contig_id, contig_len) whose
# contig_len is computed from the FASTA sequence.
#
# Our run layout:
#   runs/<run>/comebin_out/comebin_res/comebin_res_bins/<id>.fa   (cluster bins)
#   runs/<run>/per_bin_results.csv                                (stats)
#
# Output (written next to the run dir):
#   runs/<run>/biobox/<sample>.binning                            (CAMI v0.9.1)
#   runs/<run>/biobox/binning.tar.gz                              (tree of bins)
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

# binning_summary.tsv (convenience: bin_id, contig_id, contig_len) and the
# authoritative CAMI v0.9.1 `<sample>.binning` (SEQUENCEID -> BINID), built in
# one pass. contig_len is computed from the FASTA sequence (COMEBin bin deflines
# carry no `length=` tag; the sequence is authoritative anyway).
summary="$OUT/tree/$ENGINE/$VERSION/binning_summary.tsv"
binning="$OUT/$SAMPLE.binning"
{
  echo -e "bin_id\tcontig_id\tcontig_len"
  for f in "$TREE"/*.fna; do
    bin_id=$(basename "$f" .fna)
    awk -v bin="$bin_id" '
      /^>/ {
        if (name != "") print bin "\t" name "\t" len
        name = substr($1, 2)
        len = 0
        next
      }
      { len += length($0) }
      END { if (name != "") print bin "\t" name "\t" len }
    ' "$f"
  done
} > "$summary"

{
  printf '@Version:0.9.1\n@SampleID:%s\n' "$SAMPLE"
  printf '@@SEQUENCEID\tBINID\n'
  tail -n +2 "$summary" | awk -F'\t' '{print $2 "\t" $1}'
} > "$binning"

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
  $SAMPLE.binning        CAMI binning format v0.9.1 (SEQUENCEID -> BINID)
  binning.tar.gz          per-bin FASTA tree (engine/version/binning/sample/*.fna)
  bins.fasta.gz           all bins concatenated, FASTA
  tree/.../binning_summary.tsv  contig membership + computed length per bin
  stats.csv               per-bin CheckM2/CheckM v1 (from per_bin_results.csv)

CAMI binning format v0.9.1: https://github.com/bioboxes/rfc (data-format/binning.mkd).
This is the same file AMBER consumes (scripts/make_amber_prediction.py).
Validate structurally before archival:
  python3 scripts/validate_binning.py $OUT/$SAMPLE.binning
EOF

# Per-bin stats snapshot when available.
if [ -f "$RUN_DIR/per_bin_results.csv" ]; then
  cp "$RUN_DIR/per_bin_results.csv" "$OUT/stats.csv"
fi

echo "wrote $OUT (bins=$bin_count)"
ls -la "$OUT" | awk '{print $5, $9}'