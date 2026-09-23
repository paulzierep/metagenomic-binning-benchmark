#!/usr/bin/env bash
# make_small_dataset.sh — build a small, self-contained COMEBin benchmark dataset
# from the official demo data (GitHub issue #2). Real bioinformatics tools
# (samtools + BioPython), real data provenance, real pipeline logic preserved.
#
#   dataset/issue:  https://github.com/paulzierep/metagenomic-binning-benchmark/issues/2
#   demo source:    BATS_SAMN07137077_METAG.scaffolds.min500.fasta.f1k.fasta + SRR5720343.bam
#
# Design choices:
#   - top-N contigs BY LENGTH (longest contigs carry the marker genes that
#     COMEBin's seed-gene step (FragGeneScan+HMMER) needs -> keeps REAL logic)
#   - reads = those overlapping the chosen contigs (samtools view -L) -> real
#     coverage/alignment, not simulated
#   - default settings run identically; only the data shrinks
# Usage: make_small_dataset.sh [out_dir] [N_contigs]
set -euo pipefail
MM=/vol/data/tools/bin/micromamba
ENV=/vol/data/envs/comebin
DATA=/vol/data/datasets/comebin_test_data
SRC_FA="$DATA/BATS_SAMN07137077_METAG.scaffolds.min500.fasta.f1k.fasta"
SRC_BAM="$DATA/bamfiles/SRR5720343.bam"
OUT=${1:-/vol/data/datasets/comebin_small}
N=${2:-300}

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
print(f"selected {len(recs)} contigs, {sum(len(r) for r in recs):,} bp, "
      f"min {min(len(r) for r in recs):,} max {max(len(r) for r in recs):,}")
PY

echo "=== 2) extract reads overlapping those contigs (keeps real alignment) ==="
MAMBA_ROOT_PREFIX=/vol/data/envs/.mamba "$MM" run -p "$ENV" \
  samtools view -h -b -@ 32 -L "$OUT/contig_names.txt" "$SRC_BAM" > "$OUT/bamfiles/reads.bam"
MAMBA_ROOT_PREFIX=/vol/data/envs/.mamba "$MM" run -p "$ENV" \
  samtools index -@ 32 "$OUT/bamfiles/reads.bam"

echo "=== result ==="
du -sh "$OUT" "$OUT/bamfiles/reads.bam"
ls -la "$OUT"