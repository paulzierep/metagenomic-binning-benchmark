#!/usr/bin/env python3
# parse_eval.py <rundir> — summarise CheckM2 + CheckM v1 results for a run:
# appends means to <rundir>/run_meta.txt and prints the README-table block.
import csv, os, sys

run = sys.argv[1]
meta = os.path.join(run, "run_meta.txt")

def find_cols(header, names):
    cols = header.strip().split("\t")
    return {n: cols.index(n) for n in names if n in cols}

rows = []
q = os.path.join(run, "eval", "checkm2", "quality_report.tsv")
if os.path.exists(q):
    n = c = ct = 0
    with open(q, newline="") as f:
        hdr = f.readline()
        cols = find_cols(hdr, ["Completeness", "Contamination"])
        for line in f:
            p = line.rstrip("\n").split("\t")
            try:
                c += float(p[cols["Completeness"]])
                ct += float(p[cols["Contamination"]])
                n += 1
            except (KeyError, ValueError, IndexError):
                pass
    if n:
        rows.append(f"checkm2_bins: {n} checkm2_compl_mean: {c/n:.2f} checkm2_cont_mean: {ct/n:.2f}")

b = os.path.join(run, "eval", "checkm", "out", "storage", "bin_stats_ext.tsv")
if os.path.exists(b):
    n = c = ct = 0
    with open(b) as f:
        hdr = f.readline()
        cols = find_cols(hdr, ["Completeness", "Contamination"])
        for line in f:
            p = line.rstrip("\n").split("\t")
            try:
                c += float(p[cols["Completeness"]])
                ct += float(p[cols["Contamination"]])
                n += 1
            except (KeyError, ValueError, IndexError):
                pass
    if n:
        rows.append(f"checkm_bins: {n} checkm_compl_mean: {c/n:.2f} checkm_cont_mean: {ct/n:.2f}")

with open(meta, "a") as f:
    for r in rows:
        f.write(r + "\n")
print("\n".join(rows) if rows else "no eval results found")