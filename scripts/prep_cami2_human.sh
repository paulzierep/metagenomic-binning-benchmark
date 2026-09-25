#!/usr/bin/env bash
# prep_cami2_human.sh — build the COMEBin input for the CAMI II **human
# host-associated** benchmark (issue #18: "a human based benchmark set from
# cami that is like 1/6 the size of the big one").
#
# Source: CAMI II Toy Human Microbiome, gastrointestinal + oral block,
#   frl:6425518  (https://frl.publisso.de/data/frl:6425518/)
#   gastrooral/sample_0.tar.gz  9,738,621,091 B  md5 60e04c041c38ea168af03fc55dff15d6
#   extracted members: contigs/anonymous_gsa.fasta.gz (68,417 contigs),
#                      reads/anonymous_reads.fq (interleaved PE), reads_mapping.tsv.gz
#
# Strategy (same real-data method as comebin_small/medium and the marine prep):
#   - contigs: anonymous_gsa.fasta.gz subset to the TOP $N contigs by length.
#     N defaults to 4,900 = 29,434 (COMEBin demo) / 6  → expected wall time
#     ≈ 1/6 of the 6.9 h large run (≈ 1 h). The 4,900th contig is 4,733 bp.
#   - coverage BAM: bwa mem -p (interleaved) over ALL reads → sort + index.
#     Reads from unkept contigs simply produce no alignment; S0R* names kept.
#
# Ground truth binning (binning_gs.tsv) is NOT inside sample_0.tar.gz (only
# gsa_mapping*.tsv); quality is therefore scored with CheckM2 + CheckM v1 like
# every other run, and the gold-standard binning is a documented TODO (it ships
# in setup.tar.gz / the CAMI goldstandard bundle).
#
# Usage: bash scripts/prep_cami2_human.sh [N_contigs=4900]
set -euo pipefail

MM=/vol/data/tools/bin/micromamba
ENV=/vol/data/envs/comebin
SRC=/vol/data/datasets/cami_II_human/extract/2017.12.04_18.45.54_sample_0
GSA="$SRC/contigs/anonymous_gsa.fasta.gz"
READS="$SRC/reads/anonymous_reads.fq"
MAPPING="$SRC/reads/reads_mapping.tsv.gz"
OUT=${OUT:-/vol/data/datasets/cami_II_human/human_sample0_input}
N=${1:-4900}
THREADS=${THREADS:-32}

mkdir -p "$OUT/bamfiles" "$OUT/logs"
[ -f "$GSA" ] || { echo "ERROR: missing $GSA"; exit 1; }
[ -f "$READS" ] || { echo "ERROR: missing $READS"; exit 1; }
if [ -e "$OUT/contigs.fa" ] || [ -e "$OUT/bamfiles/human.bam" ]; then
  echo "ERROR: refusing to overwrite an existing input build in $OUT"
  exit 1
fi
echo "== human sample-0 input: top $N contigs by length (GSA has 68,417) =="

# ---- 1. subset to the N longest contigs ------------------------------------ #
export MAMBA_ROOT_PREFIX=/vol/data/envs/.mamba
"$MM" run -p "$ENV" python - "$GSA" "$OUT/contigs.fa" "$N" "$OUT/contigs.bed" <<'PY'
import gzip, sys
from Bio import SeqIO
gsa, out, n, bed = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
op = gzip.open if gsa.endswith(".gz") else open
recs = sorted(SeqIO.parse(op(gsa, "rt"), "fasta"), key=lambda r: len(r), reverse=True)[:n]
with open(out, "w") as fh:
    SeqIO.write(recs, fh, "fasta")
with open(bed, "w") as fh:
    for r in recs:
        fh.write(f"{r.id}\t0\t{len(r)}\n")
print(f"kept {len(recs)} contigs, {sum(len(r) for r in recs):,} bp, "
      f"min {min(len(r) for r in recs):,} max {max(len(r) for r in recs):,}")
PY
NN=$(grep -c '^>' "$OUT/contigs.fa")
echo "contigs kept: $NN"
[ "$NN" -gt 0 ] || { echo "ERROR: empty contig subset"; exit 1; }

# ---- 2. bwa index + map all reads (interleaved PE) + sort/index ------------ #
"$MM" run -p "$ENV" bwa index "$OUT/contigs.fa" 2>&1 | tail -2
"$MM" run -p "$ENV" bash -c "bwa mem -p -t $THREADS '$OUT/contigs.fa' '$READS' 2>'$OUT/logs/bwa.log' | samtools view -b -u -F 4 | samtools sort -@ 8 -m 1G -o '$OUT/bamfiles/human.bam' -"
"$MM" run -p "$ENV" samtools index "$OUT/bamfiles/human.bam"
"$MM" run -p "$ENV" samtools quickcheck "$OUT/bamfiles/human.bam" && echo "bam OK"

# ---- 3. input metadata ------------------------------------------------------ #
{
  echo "cami2_human_sample0_input (issue #18: ~1/6 of the 29,434-contig demo):"
  echo "  source:         frl:6425518 gastrooral/sample_0.tar.gz md5 60e04c041c38ea168af03fc55dff15d6"
  echo "  contigs:        $OUT/contigs.fa ($NN longest of 68,417 GSA contigs)"
  echo "  reads:          $READS ($(du -h "$READS" | cut -f1), interleaved PE, mapped with bwa mem -p -t $THREADS)"
  echo "  reads->genome:  $MAPPING"
  echo "  bam:            $OUT/bamfiles/human.bam (secondary/supplementary kept, unmapped dropped)"
  echo "  threads:        $THREADS"
  echo "  date:           $(date -Is)"
  echo "  md5s:"
  md5sum "$OUT/contigs.fa" "$OUT/bamfiles/human.bam" | sed 's/^/    /'
} | tee "$OUT/logs/input_meta.txt"
echo "DONE -> $OUT"
