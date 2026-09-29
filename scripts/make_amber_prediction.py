#!/usr/bin/env python3
"""make_amber_prediction.py — build an AMBER genome-binning prediction TSV.

Issue #25 follow-on: AMBER needs a `@@SEQUENCEID BINID` binning file plus the
CAMI `@Version` / `@SampleID` metadata header. COMEBin already writes one FASTA
per final bin, so this script just walks a `comebin_res_bins` directory

  python3 make_amber_prediction.py <run_dir> <sample_id> > out.binning

The mapped contig ids are the FASTA record names (no leading `>`); bin ids are
`bin_<filename-without-ext>`. Output is written to stdout; the header block is
`@Version:0.9.1`, `@SampleID:<sample_id>`, `@@SEQUENCEID\tBINID` (matches what
AMBER's `read_metadata` expects and what the CAMI gold standards carry).

Usage example (marine, done 2026-09-29):
  python3 make_amber_prediction.py runs/marine_v11_20260925 marine \
      > /vol/data/benchmark/amber/marine_comebin.binning
  micromamba run -p /vol/data/envs/amber python3 CAMI-AMBER/amber.py \
      <that file> -g <binning_gs.tsv> -o output_marine -l comebin_v11
"""
import os
import sys


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: make_amber_prediction.py <run_dir> <sample_id>")
    run_dir, sample_id = sys.argv[1], sys.argv[2]
    bins_dir = os.path.join(run_dir, "comebin_out", "comebin_res",
                            "comebin_res_bins")
    if not os.path.isdir(bins_dir):
        sys.exit(f"ERROR: no comebin_res_bins under {run_dir}")
    fastas = sorted(os.path.join(bins_dir, n) for n in os.listdir(bins_dir)
                    if n.endswith(".fa"))
    if not fastas:
        sys.exit(f"ERROR: no .fa final bins in {bins_dir}")

    out = [f"@Version:0.9.1", f"@SampleID:{sample_id}", "@@SEQUENCEID\tBINID"]
    n_contigs = 0
    n_bins = len(fastas)
    for fa in fastas:
        bin_id = "bin_" + os.path.splitext(os.path.basename(fa))[0]
        with open(fa, encoding="utf-8") as f:
            for line in f:
                if line.startswith(">"):
                    out.append(f"{line[1:].strip()}\t{bin_id}")
                    n_contigs += 1
    sys.stdout.write("\n".join(out) + "\n")
    print(f"# {n_bins} bins, {n_contigs} contigs mapped",
          file=sys.stderr)


if __name__ == "__main__":
    main()