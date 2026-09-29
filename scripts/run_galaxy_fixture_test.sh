#!/usr/bin/env bash
# run_galaxy_fixture_test.sh — run the Galaxy IUC 40-contig fixture (issue #29)
# end-to-end on a pinned COMEBin source tree and record it like any other run.
#
# Fixture: /vol/data/datasets/galaxy_comebin_fixture (from
# galaxyproject/tools-iuc tools/comebin/test-data) — 40 contigs x exactly
# 20,000 bp = 800 kb, coordinate-sorted BAM whose 40 @SQ refs are identical to
# the FASTA ids, 2,000 reads / 94 mapped, no .bai (bedtools genomecov -bga does
# not need one). Galaxy's own test uses max_edges=20 for this input, so we do
# too: the default 100 > contig count makes clustering raise ValueError.
#
# This is a plumbing/exit-code smoke test, NOT a quality benchmark:
#   * MINIMUM_FINAL_BIN_SIZE = 200 kb vs an 800 kb assembly => at most ~4 bins,
#     usually 0 — Galaxy's assertion passes on 0 bins as well.
#   * on a pre-#28-fix checkout the empty marker seed is a hard RuntimeError;
#     on 41606c8 it exits 0 with "Reporting 0 bins".
#
# Usage:  scripts/run_galaxy_fixture_test.sh [rundir]
# Env:    SRC_COMEBIN (default /vol/data/repos/COMEBin-v11), THREADS, SEED
#
# The harness refuses to launch while a registered run is active, so this can
# only be used when the #25 sweep has finished (or between cells).
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
FIXTURE=/vol/data/datasets/galaxy_comebin_fixture
BIN=/vol/data/benchmark/bin/run_comebin_fix.sh
SRC=${SRC_COMEBIN:-/vol/data/repos/COMEBin-v11}
SHORT=$(git -C "$SRC" rev-parse --short HEAD 2>/dev/null || echo unknown)
RUNDIR=${1:-/vol/data/benchmark/runs/galaxy_fixture_${SHORT}}

[ -f "$FIXTURE/input_single.fasta" ] || { echo "ERROR: fixture FASTA missing"; exit 1; }
[ -f "$FIXTURE/input_single.bam" ]   || { echo "ERROR: fixture BAM missing"; exit 1; }
[ -x "$BIN" ] || { echo "ERROR: harness $BIN not found/executable"; exit 1; }
[ -f "$SRC/COMEBin/run_comebin.sh" ] || { echo "ERROR: bad SRC_COMEBIN=$SRC"; exit 1; }

# The harness passes -p <dir>, so give it a bamfiles/ dir (one symlink, so the
# fixture copy stays a single source of truth).
mkdir -p "$FIXTURE/bamfiles"
[ -e "$FIXTURE/bamfiles/input_single.bam" ] ||
  ln -s "$FIXTURE/input_single.bam" "$FIXTURE/bamfiles/input_single.bam"

echo "galaxy fixture: src=$SRC @ $SHORT -> $RUNDIR"
exec env SRC_COMEBIN="$SRC" \
         CONTIGS="$FIXTURE/input_single.fasta" \
         BAMDIR="$FIXTURE/bamfiles" \
         MODE=galaxy_fixture \
         THREADS="${THREADS:-4}" \
         SEED="${SEED:-42}" \
         MAX_EDGES=20 \
         "$BIN" "$RUNDIR"
