#!/usr/bin/env bash
# prep_cami2_marine.sh — build the COMEBin input for the CAMI II marine
# benchmark, sample 0 (short-read, anonymous). Strategy (documented in
# docs/01-datasets.md + docs/06-benchmark-commands.md):
#   - contigs: anonymous_gsa.fasta.gz subset to contigs >= $MINLEN bp
#     (41,988 contigs at 2,000 bp → COMEBin-feasible; real CAMI data)
#   - reads:   anonymous_reads.fq.gz (sample-0 pooled reads, interleaved PE)
#   - coverage BAM: bwa mem -p (interleaved) → samtools sort+index
#     Reads of unkept contigs simply produce no alignment; filenames stay S0C*.
# Ground truth for later eval: binning_gs.tsv (S0C* -> Otu genome).
# Usage: bash scripts/prep_cami2_marine.sh [minlen=2000]
set -euo pipefail

MM=/vol/data/tools/bin/micromamba
ENV=/vol/data/envs/comebin
SRC=/vol/data/datasets/cami_II/marine_reads
SAMPLE="simulation_short_read/2018.08.15_09.49.32_sample_0"
GSA="$SRC/contigs_0/$SAMPLE/contigs/anonymous_gsa.fasta.gz"
GT="$SRC/contigs_0/$SAMPLE/contigs/binning_gs.tsv"
CONT="$SRC/reads_0/$SAMPLE/reads"
READS="$CONT/anonymous_reads.fq.gz"
MAPPING="$CONT/reads_mapping.tsv.gz"
OUT=${OUT:-/vol/data/datasets/cami_II/marine_sample0_input}
MINLEN=${1:-2000}

mkdir -p "$OUT/bamfiles" "$OUT/logs"
echo "== marine sample-0 input: contigs >= ${MINLEN} bp =="

# ---- 1. subset contigs by length (streamed) -------------------------------- #
zcat "$GSA" | awk -v L="$MINLEN" '
  /^>/ { if (name != "" && len >= L) print ">" name "\n" seq;
         name = substr($0, 2); seq = ""; len = 0; next }
  { seq = seq $0; len += length($0) }
  END { if (name != "" && len >= L) print ">" name "\n" seq }' \
  > "$OUT/contigs.fa"
N=$(grep -c '^>' "$OUT/contigs.fa")
echo "contigs kept: $N"
[ "$N" -gt 0 ] || { echo "ERROR: empty contig subset"; exit 1; }

# ---- 2. bwa index + map all reads (interleaved) + sort --------------------- #
export MAMBA_ROOT_PREFIX=/vol/data/envs/.mamba
"$MM" run -p "$ENV" bwa index "$OUT/contigs.fa" 2>&1 | tail -2
"$MM" run -p "$ENV" bash -c "bwa mem -p -t 32 '$OUT/contigs.fa' '$READS' 2>'$OUT/logs/bwa.log' | samtools sort -@ 32 -o '$OUT/bamfiles/marine.bam' -"
"$MM" run -p "$ENV" samtools index "$OUT/bamfiles/marine.bam"
"$MM" run -p "$ENV" samtools quickcheck "$OUT/bamfiles/marine.bam" && echo "bam OK"

# ---- 3. ground-truth subset + input metadata ------------------------------- #
grep -v '^@' "$GT" | awk -v K="$OUT/contigs.fa" '
  BEGIN{ while ((getline line < K) > 0) { n=substr(line,2); keep[n]=1 } }
  ($1 in keep)' > "$OUT/binning_gs_subset.tsv" || true
{
  echo "cami2_marine_sample0_input:"
  echo "  contigs:        $OUT/contigs.fa ($N contigs, >=${MINLEN} bp)"
  echo "  reads:          $READS ($(du -h "$READS" | cut -f1) gz, interleaved PE)"
  echo "  bam:            $OUT/bamfiles/marine.bam"
  echo "  ground truth:   $OUT/binning_gs_subset.tsv ($(wc -l < "$OUT/binning_gs_subset.tsv" 2>/dev/null) S0C* lines)"
  echo "  md5s:"
  md5sum "$OUT/contigs.fa" "$OUT/bamfiles/marine.bam" "$OUT/binning_gs_subset.tsv" \
    | sed 's/^/    /'
} | tee "$OUT/logs/input_meta.txt"
echo "DONE -> $OUT"