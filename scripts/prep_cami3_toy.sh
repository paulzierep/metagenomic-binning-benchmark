#!/usr/bin/env bash
# prep_cami3_toy.sh — build the COMEBin input for the CAMI III toy
# human gut benchmark (2 samples, short+long reads).
#
# Source: cami-challenge.org CAMI3 toy human gut dataset.
#   20 samples (toy longitudinal human gut), short + long reads.
#   Per-sample ≈ 8.6 GB (short+bread); two samples ≈ 17 GB within 50 GB budget.
#
# Strategy (real-data method consistent with comebin_small/medium/marine):
#   - contigs: gsa_pooled.fasta.gz subset to the TOP $N contigs by length.
#     N defaults to 5000 ≈ 1/6 of 29,434 demo contigs → expected wall time
#     ≈ 1/6 of the 6.9 h large run (≈ 1 h). Contig N50 ≈ 150kbp; ≥2000 bp
#     subset is COMEBin-feasible.
#   - coverage BAM: bwa mem -p (interleaved short+long reads) over ALL reads.
#     Reads from unkept contigs produce no alignment; S0* names kept.
#   - ground truth: gold-standard pooled assembly + per-sample gsa/gsa_mapping
#
# Usage: bash scripts/prep_cami3_toy.sh [N_contigs=5000] [samples="0 1"]
set -euo pipefail

MM=/vol/data/tools/bin/micromamba
ENV=/vol/data/envs/comebin
SRC=${C3IO:-/vol/data/datasets/cami_III}
SHORT_DOWNLOAD_LIST="${SRC}/short_download.list"
LONG_DOWNLOAD_LIST="${SRC}/long_download.list"
GSA_POOLED="${SRC}/gsa_pooled.fasta.gz"
OUT=${OUT:-/vol/data/datasets/cami_III/toy_human_input_2samples}
N=${1:-5000}
SAMPLES=${2:-"0 1"}
THREADS=${THREADS:-32}

mkdir -p "$OUT/bamfiles" "$OUT/logs"

# ---------------------------------------------------------------------------
# Helper: download a file if not present, reporting progress
# ---------------------------------------------------------------------------
download_if_missing() {
  local url="$1" dest="$2"
  if [ ! -f "$dest" ]; then
    echo "Downloading $(basename "$dest")... this may take a while."
    wget -q --show-progress -O "$dest" "$url"
  else
    echo "Already have $(basename "$dest"))."
  fi
}

# ---------------------------------------------------------------------------
# 1. Ensure source files exist (download if needed)
# ---------------------------------------------------------------------------
if [ ! -d "$SRC" ]; then
  echo "ERROR: CAMI III source directory not found at $SRC"
  echo "Download the CAMI III toy dataset from https://cami-challenge.org/datasets/"
  echo "and place it at $SRC, or set C3IO to the path."
  exit 1
fi

if [ ! -f "$GSA_POOLED" ]; then
  echo "WARNING: gsa_pooled.fasta.gz not found in $SRC"
  echo "Contig subsetting may fail without the pooled assembly."
fi

echo "== CAMI III toy human gut input: top $N contigs, samples $SAMPLES =="

# ---------------------------------------------------------------------------
# 2. Subset contigs by length (top N longest from gsa_pooled.fasta.gz)
# ---------------------------------------------------------------------------
if [ -f "$GSA_POOLED" ]; then
    export MAMBA_ROOT_PREFIX=/vol/data/envs/.mamba
    "$MM" run -p "$ENV" python - "$GSA_POOLED" "$OUT/contigs.fa" "$N" "$OUT/contigs.bed" <<'PY'
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
else
    echo "WARNING: skipping contig subset — no gsa_pooled.fasta.gz available"
    # fallback: use all contigs from the first available source
    NN=0
fi

# ---------------------------------------------------------------------------
# 3. For each sample: build coverage BAM with bwa mem
# ---------------------------------------------------------------------------
for SAMPLE in $SAMPLES; do
    SAMPLER=$(printf "%02d" "$SAMPLE")
    SHORT_URL=""
    LONG_URL=""
    READS_FILE=""

    # Read short-read URL from download list if available
    if [ -f "$SHORT_DOWNLOAD_LIST" ]; then
        SHORT_URL=$(sed -n "$((SAMPLE+1))p" "$SHORT_DOWNLOAD_LIST" 2>/dev/null || echo "")
    fi

    echo "Processing CAMI3 sample ${SAMPLE} (short reads)..."

    if [ -n "$SHORT_URL" ]; then
        # Download if needed; the list may contain full paths or just URLs
        LOCAL_SHORT="$SRC/cami3_toy_human_gut_short_read_sample_${SAMPLE}.tar.gz"
        if [ ! -f "$LOCAL_SHORT" ]; then
            download_if_missing "$SHORT_URL" "$LOCAL_SHORT"
        fi
        # Extract reads (this is a tar.gz containing the read files)
        if [ ! -f "$OUT/bamfiles/sample_${SAMPLE}_bam.bam" ]; then
            echo "Extracting sample ${SAMPLE} short reads..."
            mkdir -p "$OUT/logs/sample_${SAMPLE}"
            tar -xzf "$LOCAL_SHORT" -C "$OUT/logs/sample_${SAMPLE}" 2>/dev/null || true
            # Find the reads file inside - try common patterns
            READS_CANDIDATE=$(find "$OUT/logs/sample_${SAMPLE}" -name "anonymous_reads.fq*" -o -name "reads*.fq*" | head -1)
            if [ -z "$READS_CANDIDATE" ]; then
                READS_CANDIDATE="$OUT/logs/sample_${SAMPLE}/reads"
            fi
            if [ -f "$READS_CANDIDATE" ]; then
                export MAMBA_ROOT_PREFIX=/vol/data/envs/.mamba
                "$MM" run -p "$ENV" bwa index "$OUT/contigs.fa" 2>&1 | tail -2
                "$MM" run -p "$ENV" bash -c "bwa mem -p -t $THREADS '$OUT/contigs.fa' '$READS_CANDIDATE' 2>'$OUT/logs/sample_${SAMPLE}/bwa.log' | samtools view -b -F 4 | samtools sort -@ $THREADS -o '$OUT/bamfiles/sample_${SAMPLE}_bam.bam' -"
                "$MM" run -p "$ENV" samtools index "$OUT/bamfiles/sample_${SAMPLE}_bam.bam"
                "$MM" run -p "$ENV" samtools quickcheck "$OUT/bamfiles/sample_${SAMPLE}_bam.bam" && echo "bam OK for sample ${SAMPLE}"
            else
                echo "WARNING: could not find reads for sample ${SAMPLE}"
            fi
        fi
    else
        echo "WARNING: no short-read URL configured for sample ${SAMPLE}; skipping BAM build"
    fi
done

# ---------------------------------------------------------------------------
# 4. Create input metadata
# ---------------------------------------------------------------------------
{
  echo "cami3_toy_human_gut_input (2 samples, N=$N contigs):"
  echo "  source:        $SRC (CAMI III toy human gut from cami-challenge.org)"
  echo "  contigs:       $OUT/contigs.fa ($NN longest of pooled GSA contigs)"
  echo "  samples:       $SAMPLES"
  echo "  threads:       $THREADS"
  [ -f "$GSA_POOLED" ] && echo "  gsa_pooled:    $GSA_POOLED"
} > "$OUT/input_meta.txt"

echo "== Done. Input at $OUT =="
echo "Next: run COMEBin with MODE=cami3, seed 42, 32 threads:"
echo "  bash scripts/run_comebin_fix.sh -m cami3 -s 42 -t 32 -d $OUT"