#!/usr/bin/env python3
"""make_major_steps_log.py — regenerate status/major-steps.log + last-10.

Issue #26 (owner: "one log file with human readable simple major steps - from
this make another only of the last 10 major steps link in readme").

The log is derived from ground truth on disk:
  1. every run dir under /vol/data/benchmark/runs (one line per run with a
     date, exit status and, when the results CSV exists, bin count + CheckM2);
  2. curated global milestones (Zenodo releases, issue resolutions) kept in
     the MILESTONES table below — edit that table when a new major event lands.

Outputs (both committed to the repo, linked from README section f):
  status/major-steps.log          — all steps, newest last
  status/major-steps-last10.log   — the last 10 lines
"""
import csv
import glob
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, ".."))
RUNS = "/vol/data/benchmark/runs"
RESULTS = os.path.join(REPO, "results")
STATUS = os.path.join(REPO, "status")

# Curated global milestones: (YYYY-MM-DD, "human readable line").
# These are high-level events not derivable from a single run_meta.txt.
MILESTONES = [
    ("2026-09-23", "Benchmark infra set up; baseline run launched (unmodified COMEBin)"),
    ("2026-09-24", "Baseline finished: 60 bins, CheckM2 25.01%/2.98% on COMEBin demo (6h45m)"),
    ("2026-09-24", "Small gate OK (small_test_v4): 3 bins, CheckM2 26.07%/2.02%"),
    ("2026-09-24", "Medium gate OK (medium_v11_20260924): 16 bins, CheckM2 35.93%/4.67%"),
    ("2026-09-25", "First fix-batch demo run (fix_v11_20260924): 71 bins vs 60 baseline"),
    ("2026-09-25", "CAMI II human run (human_v11_20260925): 107 bins, 20 HQ / 29 MQ"),
    ("2026-09-25", "CAMI II marine run (marine_v11_20260925): 152 bins, best CheckM2 so far"),
    ("2026-09-26", "CAMI III toy human gut run (cami3_v11_20260926_rerun): 492 bins, 53 HQ"),
    ("2026-09-26", "Zenodo releases published: v2 (22969763) and v3 (22973575, incl. CAMI III)"),
    ("2026-09-26", "Issues #6 (optimization) answered, #8 and #12 closed"),
    ("2026-09-28", "Full all-runs summary table generated (results/all_runs_table.md)"),
    ("2026-09-28", "4-dataset benchmark plot regenerated incl. CAMI III (issue #19)"),
    ("2026-09-28", "Issue #28 fix committed (41606c8): graceful 0 bins on no-marker edge"),
    ("2026-09-28", "Issue #28 regression run launched (small_v11_issue28_regression)"),
]


def read_meta(run_dir):
    meta = {}
    path = os.path.join(run_dir, "run_meta.txt")
    if not os.path.exists(path):
        return meta
    with open(path, encoding="utf-8") as f:
        for line in f:
            if ":" in line and not line.startswith(("cmd", "\t", " ")):
                key, val = line.split(":", 1)
                meta[key.strip()] = val.strip()
    return meta


def agg_row(run_name):
    path = os.path.join(RESULTS, run_name + ".csv")
    if not os.path.exists(path):
        return None
    with open(path, encoding="utf-8") as f:
        return next(csv.DictReader(f), None)


def run_line(meta, agg, name):
    date = (meta.get("date") or "????-??-??")[:10]
    exit_code = meta.get("exit_code", "?")
    wall = meta.get("wall_s")
    if wall:
        wall = int(wall)
        h, m = divmod(wall, 3600)
        wall_s = f"{h}h{m//60:02d}m" if h else f"{wall // 60}m{wall % 60:02d}s"
    else:
        wall_s = "?"
    if agg:
        return (f"{date} | run {name}: {agg['n_bins']} bins, "
                f"CheckM2 {agg['checkm2_mean_completeness']}%/"
                f"{agg['checkm2_mean_contamination']}% (HQ {agg['checkm2_HQ']}/"
                f"MQ {agg['checkm2_MQ']}), {wall_s} — exit {exit_code}")
    return (f"{date} | run {name}: no results CSV yet, "
            f"{wall_s}, exit {exit_code}")


def main():
    lines = []
    for run_dir in sorted(glob.glob(os.path.join(RUNS, "*"))):
        name = os.path.basename(run_dir)
        if name == "baseline_unmodified":
            continue  # superseded by baseline_rerun_autorestart1; avoid noise
        meta = read_meta(run_dir)
        if not meta:
            continue
        agg = agg_row(name)
        lines.append((meta.get("date", "????")[:10], run_line(meta, agg, name)))

    steps = sorted(set(lines) | set(MILESTONES))

    os.makedirs(STATUS, exist_ok=True)
    all_path = os.path.join(STATUS, "major-steps.log")
    last10_path = os.path.join(STATUS, "major-steps-last10.log")
    with open(all_path, "w", encoding="utf-8") as f:
        f.write("# Major benchmark steps (human readable)\n\n")
        f.write(f"# generated {__doc__.splitlines()[-1].strip()} by make_major_steps_log.py\n\n")
        for d, line in steps:
            f.write(f"- [{d}] {line}\n")
    with open(last10_path, "w", encoding="utf-8") as f:
        f.write("# Last 10 major benchmark steps\n\n")
        for d, line in steps[-10:]:
            f.write(f"- [{d}] {line}\n")
    print(f"wrote {all_path} ({len(steps)} steps)")
    print(f"wrote {last10_path}")


if __name__ == "__main__":
    main()