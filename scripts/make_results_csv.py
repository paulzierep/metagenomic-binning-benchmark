#!/usr/bin/env python3
# make_results_csv.py <rundir> [dataset] [threads] — build results/<run>.csv
# (README "Benchmark runs — performance" + docs/04-evaluation.md contract):
#   run,source_commit,dataset,threads,total_time_s,n_bins,
#   checkm2_mean_completeness,checkm2_mean_contamination,checkm2_HQ,checkm2_MQ,
#   checkm_mean_completeness,checkm_mean_contamination,checkm_HQ,checkm_MQ
# MIMAG thresholds: HQ = compl>90 & cont<5 ; MQ = compl>=50 & cont<10.
# Reads meta from <rundir>/run_meta.txt, per-bin scores from
# <rundir>/eval/checkm2/quality_report.tsv + <rundir>/eval/checkm/out/storage/bin_stats_ext.tsv.
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

commit = meta_val("commit")
t_total = meta_val("wall_s")
n_bins = meta_val("bins").split()[0] if meta_val("bins") else ""

def scores(path, ccol, tcol):
    """Return (compl list, cont list) with values as floats; tolerate missing files."""
    if not os.path.exists(path):
        return [], []
    cs, ts = [], []
    with open(path, newline="") as f:
        hdr = f.readline().rstrip("\n").split("\t")
        ci = hdr.index(ccol) if ccol in hdr else -1
        ti = hdr.index(tcol) if tcol in hdr else -1
        for line in f:
            p = line.rstrip("\n").split("\t")
            try:
                c = float(p[ci]) if ci >= 0 else None
                t = float(p[ti]) if ti >= 0 else None
            except (ValueError, IndexError):
                continue
            if c is not None:
                cs.append(c)
            if t is not None:
                ts.append(t)
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
c2 = summarize(mk2c, mk2t)
c1 = summarize(mkc, mkt)

os.makedirs(os.path.dirname(out), exist_ok=True)
header = ["run", "source_commit", "dataset", "threads", "total_time_s", "n_bins",
          "checkm2_mean_completeness", "checkm2_mean_contamination", "checkm2_HQ", "checkm2_MQ",
          "checkm_mean_completeness", "checkm_mean_contamination", "checkm_HQ", "checkm_MQ"]
row = [name, commit, dataset, threads, t_total, n_bins, *c2, *c1]
with open(out, "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(header)
    w.writerow(row)
print(f"wrote {out}")
print(",".join(row))