#!/usr/bin/env python3
"""make_per_bin_plots.py <rundir> [<rundir> ...]

Issue #12: automatic per-bin quality plots for every evaluated run.

For each run with `runs/<name>/per_bin_results.csv` (from make_per_bin_csv.py)
it writes:
  runs/<name>/per_bins.png        — grouped bar chart: per-bin completeness and
                                    contamination for CheckM2 and CheckM v1
  results/figures/comp_vs_cont_<key>.png — scatter (completeness vs
                                    contamination, point = bin, color = run) for
                                    every run sharing the same comparison key
                                    (default: dataset name passed via -k/--key
                                    or the run's quoted dataset string).

Run inside the comebin env (only env with matplotlib):
  micromamba run -p /vol/data/envs/comebin python scripts/make_per_bin_plots.py <rundir>...
"""
import argparse
import csv
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, ".."))


def load_per_bin(run_dir, name):
    path = os.path.join(run_dir, "per_bin_results.csv")
    if not os.path.exists(path):
        return None
    with open(path, encoding="utf-8") as f:
        return list(csv.DictReader(f))


def run_bar_plot(plt, rows, out_path):
    """Single-run grouped bar chart: comp/cont per bin (checkm2 + checkm1)."""
    import numpy as np
    ids = [r["bin"] for r in rows]
    n = len(ids)
    if n == 0:
        return
    c2 = [float(r["checkm2_completeness"]) if r["checkm2_completeness"] else 0 for r in rows]
    t2 = [float(r["checkm2_contamination"]) if r["checkm2_contamination"] else 0 for r in rows]
    c1 = [float(r["checkm1_completeness"]) if r["checkm1_completeness"] else 0 for r in rows]
    t1 = [float(r["checkm1_contamination"]) if r["checkm1_contamination"] else 0 for r in rows]
    x = np.arange(n)
    w = 0.2
    fig, ax = plt.subplots(figsize=(max(8, n * 0.42), 5.2))
    ax.bar(x - 1.5 * w, c2, w, label="CheckM2 completeness", color="#2f7ed8")
    ax.bar(x - 0.5 * w, t2, w, label="CheckM2 contamination", color="#f28e2b")
    ax.bar(x + 0.5 * w, c1, w, label="CheckM v1 completeness", color="#4daf4a")
    ax.bar(x + 1.5 * w, t1, w, label="CheckM v1 contamination", color="#e15759")
    ax.set_xticks(x, ids, rotation=90, fontsize=7)
    ax.set_ylabel("percent")
    ax.set_title(f"Per-bin quality (n={n})")
    ax.legend(fontsize=8, ncol=2)
    ax.set_ylim(0, 100)
    fig.tight_layout()
    fig.savefig(out_path, dpi=130)
    plt.close(fig)


def comparison_scatter(plt, groups, out_path, key):
    """One point per bin; x = contamination, y = completeness; color = run."""
    fig, ax = plt.subplots(figsize=(8, 6))
    for run_name, rows in groups:
        xs = [float(r["checkm2_contamination"]) if r["checkm2_contamination"] else 0 for r in rows]
        ys = [float(r["checkm2_completeness"]) if r["checkm2_completeness"] else 0 for r in rows]
        ax.scatter(xs, ys, s=26, alpha=0.75, label=f"{run_name} (n={len(rows)})")
    ax.set_xlabel("contamination (%)")
    ax.set_ylabel("completeness (%)")
    ax.set_title(f"Per-bin CheckM2 quality — {key}")
    ax.legend(fontsize=8)
    ax.grid(alpha=0.3)
    fig.tight_layout()
    fig.savefig(out_path, dpi=130)
    plt.close(fig)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("rundirs", nargs="+")
    ap.add_argument("-k", "--key", help="comparison key (dataset) for the scatter")
    args = ap.parse_args()

    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    key = args.key or "all-runs"
    figures = os.path.join(REPO, "results", "figures")
    os.makedirs(figures, exist_ok=True)
    groups = []
    for rd in args.rundirs:
        name = os.path.basename(rd.rstrip("/"))
        run_dir = os.path.join(REPO, "runs", name)
        rows = load_per_bin(run_dir, name)
        if rows is None:
            print(f"{name}: no runs/{name}/per_bin_results.csv, skipping")
            continue
        os.makedirs(run_dir, exist_ok=True)
        out = os.path.join(run_dir, "per_bins.png")
        run_bar_plot(plt, rows, out)
        print(f"{name}: per-bin bar chart -> runs/{name}/per_bins.png")
        groups.append((name, rows))
    if len(groups) >= 1:
        out = os.path.join(figures, f"comp_vs_cont_{key}.png")
        comparison_scatter(plt, groups, out, key)
        print(f"comparison scatter ({key}) -> results/figures/comp_vs_cont_{key}.png")
    return 0


if __name__ == "__main__":
    sys.exit(main())