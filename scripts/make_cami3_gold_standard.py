#!/usr/bin/env python3
"""make_cami3_gold_standard.py — CAMI binning gold standard for our CAMI III subset.

Issue #25 follow-on: the owner asked for official CAMI-standard (AMBER) scoring
of every dataset. CAMI II marine and CAMI II human already have gold standards
(docs/14, docs/15). For the CAMI III toy human gut dataset the official file
`gsa_pooled_mapping.tsv.gz` (downloaded from
https://s3.bi.denbi.de/swift/v1/cami/cami3_toydata/human-gut-toy/) is keyed by
the *anonymous* pooled-assembly contig ids (PC0, PC1, …), whereas our benchmark
input (`cami_III/toy_human_input_2samples/contigs.fa`, the 5,000 longest pooled
GSA contigs) is keyed by the reference-derived header
`NZ_<accession>.<ver>_from_<start>_to_<end>_total_<len>`. The two are joined on
the reference contig id (the part before `_from_`, i.e. column 5 of the
mapping), which is present for **all** contigs of our subset.

Output: CAMI/AMBER gold-standard TSV

    @Version:0.9.1
    @SampleID:<sample>
    @@SEQUENCEID<TAB>BINID<TAB>TAXID<TAB>_LENGTH
    <contig id><TAB><genome id><TAB><taxid><TAB><contig length>

Usage:
  python3 make_cami3_gold_standard.py \
      --mapping /vol/data/datasets/cami_III/gold_standard/gsa_pooled_mapping.tsv.gz \
      --contigs /vol/data/datasets/cami_III/toy_human_input_2samples/contigs.fa \
      --sample  cami3_toy_human_gut \
      -o /vol/data/datasets/cami_III/gold_standard/cami3_toy_binning_gs.tsv
"""
import argparse
import gzip
import sys


def open_maybe_gzip(path):
    return gzip.open(path, "rt") if path.endswith(".gz") else open(path, encoding="utf-8")


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--mapping", required=True,
                    help="gsa_pooled_mapping.tsv.gz from the CAMI III toy dataset")
    ap.add_argument("--contigs", required=True, help="assembly FASTA we benchmarked")
    ap.add_argument("--sample", default="cami3_toy_human_gut")
    ap.add_argument("-o", "--out", required=True)
    args = ap.parse_args()

    # reference contig id -> (genome/bin id, taxid). The mapping has ~6.1 M rows
    # and ~53 k distinct reference contigs, so one streaming pass is enough.
    # The file starts with `@SampleID:…` metadata, then the `@@SEQUENCEID …`
    # column declaration, then the rows; take the column positions from that
    # declaration so a future re-release with a different column order still
    # parses.
    ref2bin = {}
    with open_maybe_gzip(args.mapping) as fh:
        cols = None
        for line in fh:
            if line.startswith("@@SEQUENCEID"):
                cols = [c.strip() for c in line.rstrip("\n").split("\t") if c.strip()]
                cols = [c[2:] if c.startswith("@@") else c for c in cols]
                break
            if not line.startswith("@"):
                sys.exit(f"ERROR: no @@SEQUENCEID column declaration in "
                         f"{args.mapping} (got {line[:80]!r})")
        if cols is None:
            sys.exit(f"ERROR: mapping has no @@SEQUENCEID declaration: {args.mapping}")
        for name in ("BINID", "TAXID", "contig_id"):
            if name not in cols:
                sys.exit(f"ERROR: mapping has no {name!r} column; declared: {cols}")
        i_bin, i_tax, i_ref = cols.index("BINID"), cols.index("TAXID"), cols.index("contig_id")
        n_rows = 0
        for line in fh:
            f = line.rstrip("\n").split("\t")
            if len(f) <= i_ref:
                continue
            n_rows += 1
            ref2bin.setdefault(f[i_ref], (f[i_bin], f[i_tax]))
    print(f"# mapping columns: {cols}", file=sys.stderr)
    print(f"# mapping rows: {n_rows}, distinct reference contigs: {len(ref2bin)}",
          file=sys.stderr)

    rows, n_bins, unmapped = [], set(), []
    seq_id = length = None
    with open(args.contigs, encoding="utf-8") as fh:
        for line in fh:
            if line.startswith(">"):
                if seq_id is not None:
                    rows.append((seq_id, length))
                seq_id, length = line[1:].strip(), 0
            else:
                length += len(line.strip())
    if seq_id is not None:
        rows.append((seq_id, length))

    out = [f"@Version:0.9.1", f"@SampleID:{args.sample}",
           "@@SEQUENCEID\tBINID\tTAXID\t_LENGTH"]
    n_mapped = 0
    total_bp = mapped_bp = 0
    for contig_id, contig_len in rows:
        ref = contig_id.split("_from_")[0]
        hit = ref2bin.get(ref)
        total_bp += contig_len
        if hit is None:
            unmapped.append(contig_id)
            continue
        genome_id, taxid = hit
        n_bins.add(genome_id)
        n_mapped += 1
        mapped_bp += contig_len
        out.append(f"{contig_id}\t{genome_id}\t{taxid}\t{contig_len}")

    with open(args.out, "w", encoding="utf-8") as fh:
        fh.write("\n".join(out) + "\n")

    print(f"# contigs: {len(rows)}  mapped: {n_mapped}  unmapped: {len(unmapped)}",
          file=sys.stderr)
    print(f"# genomes (gold-standard bins): {len(n_bins)}", file=sys.stderr)
    print(f"# bp mapped: {mapped_bp}/{total_bp} "
          f"({100.0 * mapped_bp / total_bp:.2f} %)", file=sys.stderr)
    for contig_id in unmapped[:10]:
        print(f"# UNMAPPED {contig_id}", file=sys.stderr)
    print(f"# wrote {args.out}", file=sys.stderr)
    if not n_mapped:
        sys.exit("ERROR: no contig of the subset could be mapped to a genome")


if __name__ == "__main__":
    main()
