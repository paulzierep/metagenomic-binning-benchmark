#!/usr/bin/env python3
"""make_per_bin_csv.py <rundir> [<rundir> ...]

Write one CheckM2 + CheckM v1 record per bin for each run into the
*repository* runs/<name>/per_bin_results.csv (issue #15: per-bin results for
all runs, stored under runs/ not the repo root).

Inputs (under <rundir>, on the benchmark volume):
  eval/checkm2/quality_report.tsv                     -> CheckM2 per-bin table
  eval/checkm/out/storage/bin_stats_ext.tsv            -> CheckM v1 dict rows

Bins are joined by id; a bin present in only one tool still gets a row with
empty cells for the missing tool. Writes a single combined CSV per run.
"""
import ast
import csv
import os
import sys


def _repo_root():
    """Locate the repository root.

    This helper is also installed as a standalone copy in
    /vol/data/benchmark/bin/, where `dirname(__file__)/..` is the benchmark data
    dir rather than the repo, so per_bin_results.csv would be written into a
    tree that git and the README never see. Validate candidates instead of
    assuming; BENCH_REPO overrides.
    """
    here = os.path.dirname(os.path.abspath(__file__))
    for cand in (os.environ.get("BENCH_REPO", "").strip(),
                 os.path.normpath(os.path.join(here, ".."))):
        if cand and os.path.isfile(os.path.join(cand, "README.md")) \
                and os.path.isdir(os.path.join(cand, "results")):
            return cand
    return "/vol/data/repos/metagenomic-binning-benchmark"


def read_checkm2(path):
    """Return {bin_id: dict} from a CheckM2 quality_report.tsv."""
    out = {}
    if not os.path.exists(path):
        return out
    with open(path, encoding="utf-8") as f:
        rows = csv.DictReader(f, delimiter="\t")
        for r in rows:
            out[r["Name"]] = r
    return out


def read_checkm1(path):
    """Return {bin_id: {'Completeness': .., 'Contamination': ..}} from CheckM v1
    bin_stats_ext.tsv ('<bin-id>\\t<dict literal>' per line)."""
    out = {}
    if not os.path.exists(path):
        return out
    with open(path, encoding="utf-8") as f:
        for line in f:
            p = line.rstrip("\n").split("\t", 1)
            if len(p) != 2:
                continue
            try:
                rec = ast.literal_eval(p[1])
            except (ValueError, SyntaxError):
                continue
            out[p[0]] = {
                "Completeness": rec.get("Completeness"),
                "Contamination": rec.get("Contamination"),
            }
    return out


COLS = [
    "bin",
    "checkm2_completeness",
    "checkm2_contamination",
    "checkm2_genome_size",
    "checkm2_contigs",
    "checkm2_n50",
    "checkm1_completeness",
    "checkm1_contamination",
]


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    for rundir in sys.argv[1:]:
        name = os.path.basename(rundir.rstrip("/"))
        out_dir = os.path.join(_repo_root(), "runs", name)
        out_dir = os.path.normpath(out_dir)
        os.makedirs(out_dir, exist_ok=True)
        mk2 = read_checkm2(os.path.join(rundir, "eval", "checkm2", "quality_report.tsv"))
        mk1 = read_checkm1(
            os.path.join(rundir, "eval", "checkm", "out", "storage", "bin_stats_ext.tsv")
        )
        # CheckM v1 keeps every input scaffold bin, even ones CheckM2 skipped:
        # union of ids, id order follows CheckM2 then CheckM v1.
        ids = list(mk2.keys()) + [i for i in mk1 if i not in mk2]
        # Sort naturally-ish: numeric ids numerically, others lexically.
        def key(i):
            try:
                return (0, float(i), "")
            except ValueError:
                return (1, float("inf"), i)

        ids.sort(key=key)
        out_path = os.path.join(out_dir, "per_bin_results.csv")
        with open(out_path, "w", newline="", encoding="utf-8") as f:
            w = csv.writer(f)
            w.writerow(COLS)
            for bin_id in ids:
                r2 = mk2.get(bin_id, {})
                r1 = mk1.get(bin_id, {})
                w.writerow([
                    bin_id,
                    r2.get("Completeness", ""),
                    r2.get("Contamination", ""),
                    r2.get("Genome_Size", ""),
                    r2.get("Total_Contigs", ""),
                    r2.get("Contig_N50", ""),
                    r1.get("Completeness", ""),
                    r1.get("Contamination", ""),
                ])
        n = len(ids)
        print(f"{name}: {n} per-bin rows -> {out_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())