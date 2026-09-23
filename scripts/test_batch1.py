#!/usr/bin/env python3
"""Quick functional test for fix batch 1 (commit 03670d6a on comebin-optimizations).

Exercises the two changed behaviours directly against the worktree source,
without running COMEBin:
  1. gen_bins: bins written as 0.fa, 1.fa, ... (sequential PER BIN, not per
     contig); missing contigs skipped without leaving empty stray files.
  2. gen_cov: fractional per-base depth preserved (float, not int-truncated).

Usage: SRC=/vol/data/repos/COMEBin-opt python3 scripts/test_batch1.py
"""
import importlib.util
import os
import shutil
import sys
import tempfile

SRC = os.environ.get("SRC", "/vol/data/repos/COMEBin-opt")

def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod

def test_bin_numbering(tmp):
    fsb = load("fsb", os.path.join(SRC, "COMEBin/filter_small_bins.py"))
    fasta = os.path.join(tmp, "contigs.fa")
    with open(fasta, "w") as f:
        f.write(">c1\nAAAA\n>c2\nCCCC\n>c3\nGGGG\n>c4\nTTTT\n>orphan\nNNNN\n")
    result = os.path.join(tmp, "result.tsv")
    # cluster0: c1,c2 ; cluster1: c3 ; cluster2: missing-contig mX + c4
    with open(result, "w") as f:
        f.write("c1\tcluster0\nc2\tcluster0\nc3\tcluster1\nmX\tcluster2\nc4\tcluster2\n")
    out = os.path.join(tmp, "bins")
    fsb.gen_bins(fasta, result, out)
    files = sorted(os.listdir(out))
    assert files == ["0.fa", "1.fa", "2.fa"], f"unexpected bin files: {files}"
    b0 = open(os.path.join(out, "0.fa")).read()
    b2 = open(os.path.join(out, "2.fa")).read()
    assert ">c1" in b0 and ">c2" in b0 and ">c3" not in b0, "bin0 wrong content"
    assert ">c3" in open(os.path.join(out, "1.fa")).read(), "bin1 wrong content"
    assert ">c4" in b2 and ">mX" not in b2 and ">orphan" not in b2, "bin2 wrong content (missing-contig must be skipped)"
    # empty files check
    empty = [f for f in files if os.path.getsize(os.path.join(out, f)) == 0]
    assert not empty, f"empty bin files present: {empty}"
    print("PASS bin_numbering: sequential files 0.fa,1.fa,2.fa; missing/orphan contigs skipped; no empty files")

def test_float_coverage(tmp):
    gcv = load("gcv", os.path.join(SRC, "COMEBin/data_aug/gen_cov.py"))
    import logging
    logger = logging.getLogger("t")
    depth = os.path.join(tmp, "d_depth.txt")
    with open(depth, "w") as f:
        f.write("c1\t0\t2\t1.5\nc1\t2\t4\t2.5\n")  # per-base: 1.5,1.5,2.5,2.5 -> mean 2.0
    gcv.calculate_coverage(depth, logger, edge=0, contig_threshold=1)
    csv = depth + "_aug0_data_cov.csv"
    assert os.path.exists(csv), f"missing {csv}"
    line = open(csv).read().strip().split("\n")[1]  # header, then data
    assert "2.0" in line, f"float coverage lost (got '{line}'); int-truncation would give 1.5"
    print(f"PASS float_coverage: fractional depth kept (mean '2.0' in {os.path.basename(csv)}), int-truncation would have given 1.5")

def main():
    tmp = tempfile.mkdtemp(prefix="comebin_batch1_test_", dir="/tmp/opencode")
    try:
        test_bin_numbering(tmp)
        test_float_coverage(tmp)
        print("ALL BATCH-1 TESTS PASSED")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

if __name__ == "__main__":
    main()