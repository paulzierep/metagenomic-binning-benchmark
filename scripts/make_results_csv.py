#!/usr/bin/env python3
# make_results_csv.py <rundir> [dataset] [threads] — build results/<run>.csv
# (README "Benchmark runs — performance" + docs/04-evaluation.md contract):
#   run,source_commit,dataset,threads,total_time_s,n_bins,
#   checkm2_mean_completeness,checkm2_mean_contamination,checkm2_HQ,checkm2_MQ,
#   checkm_mean_completeness,checkm_mean_contamination,checkm_HQ,checkm_MQ
# MIMAG thresholds: HQ = compl>90 & cont<5 ; MQ = compl>=50 & cont<10.
# Reads meta from <rundir>/run_meta.txt, per-bin scores from
# <rundir>/eval/checkm2/quality_report.tsv + <rundir>/eval/checkm/out/storage/bin_stats_ext.tsv.
import ast
import csv, os, sys

run = os.path.abspath(sys.argv[1])
name = os.path.basename(run)
dataset = sys.argv[2] if len(sys.argv) > 2 else ""
threads = sys.argv[3] if len(sys.argv) > 3 else ""
meta = os.path.join(run, "run_meta.txt")
repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
out = os.path.join(repo, "results", f"{name}.csv")

def meta_val(key):
    with open(meta) as f:
        for line in f:
            if line.startswith(key + ":"):
                return line.split(":", 1)[1].strip()
    return ""

def default_dataset(contigs_path):
    """Human-readable dataset label derived from the run's contigs path, for
    automatic (no-arg) regeneration after an evaluated run (issues #12/#15)."""
    if not contigs_path:
        return ""
    known = [
        ("BATS_SAMN07137077_METAG", "COMEBin demo (29,434 contigs)"),
        ("comebin_medium", "comebin_medium (3,000 contigs)"),
        ("comebin_small", "comebin_small (300 contigs)"),
        ("cami2", "CAMI II"),
        ("cami3", "CAMI III"),
    ]
    for key, label in known:
        if key in contigs_path:
            return label
    return os.path.basename(os.path.dirname(contigs_path))

commit = meta_val("commit")
t_total = meta_val("wall_s")
n_bins = meta_val("bins").split()[0] if meta_val("bins") else ""

def scores(path, ccol, tcol):
    """Return completeness/contamination lists from TSV or CheckM dict output."""
    if not os.path.exists(path):
        return [], []
    cs, ts = [], []
    with open(path, encoding="utf-8") as f:
        first = f.readline().rstrip("\n")
        first_parts = first.split("\t", 1)
        header_parts = first.split("\t")
        is_dict_row = len(first_parts) == 2 and first_parts[1].lstrip().startswith("{")
        if not is_dict_row and ccol in header_parts and tcol in header_parts:
            ci, ti = header_parts.index(ccol), header_parts.index(tcol)
            for line in [first, *f]:
                p = line.rstrip("\n").split("\t")
                try:
                    cs.append(float(p[ci]))
                    ts.append(float(p[ti]))
                except (ValueError, IndexError):
                    continue
            return cs, ts
        # CheckM v1 bin_stats_ext.tsv is '<bin-id>\\t<dict literal>' per line.
        lines = [first, *f] if is_dict_row else f
        for line in lines:
            p = line.rstrip("\n").split("\t", 1)
            if len(p) != 2:
                continue
            try:
                record = ast.literal_eval(p[1])
                cs.append(float(record[ccol]))
                ts.append(float(record[tcol]))
            except (KeyError, TypeError, ValueError, SyntaxError):
                continue
    return cs, ts

def summarize(cs, ts):
    if not cs:
        return "", "", "", ""
    mean_c = sum(cs) / len(cs)
    mean_t = sum(ts) / len(ts) if ts else 0.0
    hq = sum(1 for c, t in zip(cs, ts) if c > 90 and t < 5)
    mq = sum(1 for c, t in zip(cs, ts) if c >= 50 and t < 10)
    return f"{mean_c:.2f}", f"{mean_t:.2f}", str(hq), str(mq)

mk2c, mk2t = scores(os.path.join(run, "eval", "checkm2", "quality_report.tsv"), "Completeness", "Contamination")
mkc, mkt = scores(os.path.join(run, "eval", "checkm", "out", "storage", "bin_stats_ext.tsv"), "Completeness", "Contamination")
if not dataset:
    dataset = default_dataset(meta_val("contigs"))
if not threads:
    threads = meta_val("threads")
# Older baseline wrappers did not emit a `bins:` metadata line. Derive the
# count from the evaluator rows so the committed result table is complete.
if not n_bins:
    n_bins = str(len(mk2c or mk2t or mkc or mkt))
c2 = summarize(mk2c, mk2t)
c1 = summarize(mkc, mkt)

os.makedirs(os.path.dirname(out), exist_ok=True)
header = ["run", "source_commit", "dataset", "threads", "total_time_s", "n_bins",
          "checkm2_mean_completeness", "checkm2_mean_contamination", "checkm2_HQ", "checkm2_MQ",
          "checkm_mean_completeness", "checkm_mean_contamination", "checkm_HQ", "checkm_MQ"]
row = [name, commit, dataset, threads, t_total, n_bins, *c2, *c1]
with open(out, "w", newline="") as f:
    w = csv.writer(f, lineterminator="\n")
    w.writerow(header)
    w.writerow(row)
print(f"wrote {out}")
print(",".join(row))