#!/usr/bin/env bash
# make_medium_dataset.sh — build the MEDIUM derived benchmark (issue #2 workflow,
# recorded in docs/06 + docs/07 + docs/08): run this ONLY after the small-data
# end-to-end test passes, and only reserve the large demo/cami benchmarks for
# post-major-commit runs.
#
# Same real-tool methodology as make_small_dataset.sh (top-N contigs by length
# from the official demo BATS metagenome + overlapping reads via samtools view
# -L), now N=3000. Hard cap 5 GB per the documented plan.
# Usage: make_medium_dataset.sh [out_dir] [N_contigs]
set -euo pipefail
MM=/vol/data/tools/bin/micromamba
ENV=/vol/data/envs/comebin
DATA=/vol/data/datasets/comebin_test_data
SRC_FA="$DATA/BATS_SAMN07137077_METAG.scaffolds.min500.fasta.f1k.fasta"
SRC_BAM="$DATA/bamfiles/SRR5720343.bam"
OUT=${1:-/vol/data/datasets/comebin_medium}
N=${2:-3000}
CAP_GB=5

mkdir -p "$OUT/bamfiles"
echo "=== 1) select top-$N contigs by length ==="
MAMBA_ROOT_PREFIX=/vol/data/envs/.mamba "$MM" run -p "$ENV" python - "$OUT" "$SRC_FA" "$N" <<'PY'
import sys
from Bio import SeqIO
out, fa, n = sys.argv[1], sys.argv[2], int(sys.argv[3])
recs = sorted(SeqIO.parse(fa, "fasta"), key=lambda r: len(r), reverse=True)[:n]
with open(f"{out}/contigs.fa", "w") as fh:
    SeqIO.write(recs, fh, "fasta")
with open(f"{out}/contig_names.txt", "w") as fh:
    for r in recs:
        fh.write(f"{r.id}\n")
with open(f"{out}/contigs.bed", "w") as fh:
    for r in recs:
        fh.write(f"{r.id}\t0\t{len(r)}\n")
print(f"selected {len(recs)} contigs, {sum(len(r) for r in recs):,} bp, "
      f"min {min(len(r) for r in recs):,} max {max(len(r) for r in recs):,}")
PY

echo "=== 2) extract reads overlapping those contigs (keeps real alignment) ==="
# samtools -L expects BED/region records, not a one-contig-per-line name file.
# The BED interval is emitted above and also documents the exact reference span.
MAMBA_ROOT_PREFIX=/vol/data/envs/.mamba "$MM" run -p "$ENV" \
  samtools view -h -b -@ 32 -L "$OUT/contigs.bed" "$SRC_BAM" > "$OUT/bamfiles/reads.bam"
MAMBA_ROOT_PREFIX=/vol/data/envs/.mamba "$MM" run -p "$ENV" \
  samtools index -@ 32 "$OUT/bamfiles/reads.bam"

echo "=== 3) provenance + size check (hard cap ${CAP_GB} GB) ==="
SIZE=$(du -sb "$OUT" | awk '{print $1}')
SIZE_GB=$(awk -v b="$SIZE" 'BEGIN{printf "%.2f", b/1e9}')
{
  echo "dataset:        $OUT (medium, derived from BATS demo)"
  echo "contigs:        top-$N by length, $(grep -c '^>' "$OUT/contigs.fa") selected"
  echo "source_fasta:   $SRC_FA"
  echo "source_bam:     $SRC_BAM (reads overlapping selected contigs)"
  echo "size_bytes:     $SIZE"
  echo "size_gb:        $SIZE_GB (cap ${CAP_GB} GB)"
  echo "md5_contigs_fa: $(md5sum "$OUT/contigs.fa" | cut -d' ' -f1)"
  echo "md5_reads_bam:  $(md5sum "$OUT/bamfiles/reads.bam" | cut -d' ' -f1)"
} | tee "$OUT/PROVENANCE.txt"

awk -v b="$SIZE" -v cap=$((CAP_GB * 1000000000)) 'BEGIN{ if (b > cap) { print "ERROR: dataset exceeds cap"; exit 1 } }'
echo "DONE -> $OUT (${SIZE_GB} GB)"