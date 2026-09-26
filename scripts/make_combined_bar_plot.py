#!/usr/bin/env python3
"""make_combined_bar_plot.py [--datasets demo human marine]

Issue #12 (owner request 2026-09-05..25): FAIRyMAGs-style combined bar plot for
the MAIN benchmark datasets, focused on three datasets:

    demo   — COMEBin demo large set (BATS, 29,434 contigs)
    human  — CAMI II human host-associated (4,900 contigs)
    marine — CAMI II marine (41,988 contigs)

Figure layout (mirrors FAIRyMAGs `combined_bar_plot.png`, extended to the three
main datasets):

  * 2 rows x 3 columns of subplots — one subplot per benchmark dataset (the
    columns), rows = contamination cutoffs (top < 5 %, bottom < 10 %).
  * Horizontal stacked bars, one bar per evaluated run of that dataset,
    segments = CheckM2 completeness thresholds (">90", ">80", ">70", ">60",
    ">50", plus "<50" so the bar end equals ALL bins passing the contamination
    cutoff) in the FAIRyMAGs teal palette.
  * Every bar is labelled on the y axis with run name + COMEBin commit (short)
    and branch, e.g. `fix_v11_20260924 · 95f5ea8 · comebin-optimizations-v11`.
  * Total count annotated at the bar end, x axis "#MAGs", dpi 300.

Also writes `results/main_runs_table.md`: the markdown stats table for exactly
those runs, meant to be embedded directly under the plot in README.md.

Run inside the comebin env (only env with matplotlib):

  micromamba run -p /vol/data/envs/comebin python scripts/make_combined_bar_plot.py
"""
import argparse
import csv
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def _repo_root():
    """Locate the repository root.

    This helper is also installed as a standalone copy in
    /vol/data/benchmark/bin/, where `dirname(__file__)/..` is the benchmark data
    dir rather than the repo, so the figure and stats table would be generated
    into a different tree than the one README.md embeds and git tracks.
    Validate candidates instead of assuming; BENCH_REPO overrides.
    """
    for cand in (os.environ.get("BENCH_REPO", "").strip(),
                 os.path.normpath(os.path.join(HERE, ".."))):
        if cand and os.path.isfile(os.path.join(cand, "README.md")) \
                and os.path.isdir(os.path.join(cand, "results")):
            return cand
    return "/vol/data/repos/metagenomic-binning-benchmark"


REPO = _repo_root()
RUNS = os.path.join(REPO, "runs")
RESULTS = os.path.join(REPO, "results")
FIGDIR = os.path.join(RESULTS, "figures")

# The three main benchmark datasets (issue #12: "focus only on 3 from now on").
# key -> (substring matched against run_meta `contigs:`, display name)
DATASETS = {
    "demo": ("BATS_SAMN07137077", "COMEBin demo (29,434 contigs)"),
    "human": ("cami_II_human", "CAMI II human (4,900 contigs)"),
    "marine": ("cami_II/marine", "CAMI II marine (41,988 contigs)"),
}
DEFAULT_ORDER = ["demo", "human", "marine"]

# FAIRyMAGs combined_bar_plot style
THRESHOLDS = [">90", ">80", ">70", ">60", ">50", "<50"]
COLORS = ["#004c4c", "#006666", "#008080", "#33a3a3", "#99d6d6", "#cce6e6"]
CUTOFFS = [(5, "Contamination < 5%"), (10, "Contamination < 10%")]


def read_run_meta(run_dir):
    meta = {}
    path = os.path.join(run_dir, "run_meta.txt")
    if not os.path.exists(path):
        return meta
    with open(path, encoding="utf-8") as f:
        for line in f:
            if ":" in line and not line.startswith(("cmd", "\t", " ")):
                key, val = line.split(":", 1)
                if key.strip() in ("source", "commit", "contigs", "seed", "wall_s"):
                    meta[key.strip()] = val.strip()
    return meta


def dataset_key(contigs):
    for key, (needle, _name) in DATASETS.items():
        if needle in contigs:
            return key
    return None


def branch_of(source):
    """`source` may be '... (branch NAME)' or a plain path."""
    if not source:
        return "-"
    if "(branch " in source:
        return source.split("(branch ", 1)[1].rstrip(")")
    path = source.split(" (", 1)[0].strip()
    try:
        out = subprocess.run(
            ["git", "-C", path, "rev-parse", "--abbrev-ref", "HEAD"],
            capture_output=True, text=True, timeout=10,
        )
        if out.returncode == 0:
            return out.stdout.strip() or "-"
    except Exception:
        pass
    return "-"


def load_runs(wanted):
    """-> {dataset_key: [run_info, ...]} for evaluated runs of wanted datasets."""
    found = {k: [] for k in wanted}
    if not os.path.isdir(RUNS):
        return found
    for name in sorted(os.listdir(RUNS)):
        csv_path = os.path.join(RUNS, name, "per_bin_results.csv")
        if not os.path.exists(csv_path):
            continue
        meta = read_run_meta(os.path.join(RUNS, name))
        key = dataset_key(meta.get("contigs", ""))
        if key not in wanted:
            continue
        with open(csv_path, encoding="utf-8") as f:
            rows = list(csv.DictReader(f))
        commit = meta.get("commit", "-")
        found[key].append({
            "name": name,
            "rows": rows,
            "commit7": commit[:7] if commit != "-" else "-",
            "branch": branch_of(meta.get("source", "")),
            "seed": meta.get("seed", "-"),
            "wall_s": meta.get("wall_s", "-"),
        })
    return found


def counts(rows, cutoff):
    """Stacked segment counts for one run at one contamination cutoff."""
    seg = {thr: 0 for thr in THRESHOLDS}
    total = 0
    for row in rows:
        try:
            comp = float(row["checkm2_completeness"])
            cont = float(row["checkm2_contamination"])
        except (KeyError, TypeError, ValueError):
            continue
        if not (cont < cutoff):
            continue
        total += 1
        for thr in THRESHOLDS[:-1]:
            if comp >= int(thr[1:]):
                seg[thr] += 1
                break
        else:
            seg["<50"] += 1
    return seg, total


def load_aggregates():
    """run -> aggregate stats row from results/<run>.csv (auto-report output)."""
    agg = {}
    for name in os.listdir(RESULTS) if os.path.isdir(RESULTS) else []:
        if not name.endswith(".csv"):
            continue
        path = os.path.join(RESULTS, name)
        try:
            with open(path, encoding="utf-8") as f:
                row = next(csv.DictReader(f), None)
            if row:
                agg[row.get("run") or name[:-4]] = row
        except OSError:
            continue
    return agg


def fmt_wall(wall_s):
    try:
        sec = int(float(wall_s))
    except (TypeError, ValueError):
        return "-"
    if sec >= 3600:
        return f"{sec // 3600}h{(sec % 3600) // 60:02d}m"
    return f"{sec // 60}m{sec % 60:02d}s"


def make_table(ordered_runs, agg):
    """Markdown stats table for the runs shown in the plot (#12: table under
    the bar plot)."""
    lines = [
        "| Run | Dataset | COMEBin version | Seed | Wall time | Bins "
        "| CheckM2 comp / cont | CheckM2 HQ / MQ | CheckM v1 comp / cont "
        "| CheckM v1 HQ / MQ |",
        "|---|---|---|---|---|---|---|---|---|---|",
    ]
    for key, run in ordered_runs:
        a = agg.get(run["name"], {})
        version = f"`{run['commit7']}` ({run['branch']})"
        lines.append(
            "| `{name}` | {ds} | {ver} | {seed} | {wall} | {bins} "
            "| {c2c} / {c2n} | {h2} / {m2} | {c1c} / {c1n} | {h1} / {m1} |".format(
                name=run["name"],
                ds=DATASETS[key][1],
                ver=version,
                seed=run["seed"],
                wall=fmt_wall(a.get("total_time_s", run["wall_s"])),
                bins=a.get("n_bins", len(run["rows"])),
                c2c=a.get("checkm2_mean_completeness", "-"),
                c2n=a.get("checkm2_mean_contamination", "-"),
                h2=a.get("checkm2_HQ", "-"),
                m2=a.get("checkm2_MQ", "-"),
                c1c=a.get("checkm_mean_completeness", "-"),
                c1n=a.get("checkm_mean_contamination", "-"),
                h1=a.get("checkm_HQ", "-"),
                m1=a.get("checkm_MQ", "-"),
            )
        )
    return "\n".join(lines) + "\n"


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--datasets", nargs="+", default=DEFAULT_ORDER,
                    choices=sorted(DATASETS), help="datasets (subplots) to show")
    ap.add_argument("--png", default=os.path.join(FIGDIR, "combined_bar_plot.png"))
    ap.add_argument("--table", default=os.path.join(RESULTS, "main_runs_table.md"))
    args = ap.parse_args()

    wanted = [d for d in DEFAULT_ORDER if d in args.datasets]
    found = load_runs(wanted)

    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        import numpy as np
    except ImportError:
        sys.exit("ERROR: matplotlib/numpy missing — run inside the comebin env "
                 "(micromamba run -p /vol/data/envs/comebin ...)")

    # Flatten in subplot order for the stats table.
    ordered_runs = [(k, r) for k in wanted for r in found[k]]
    if not ordered_runs:
        sys.exit("ERROR: no evaluated runs found for datasets: "
                 + ", ".join(wanted))

    ncol = len(wanted)
    fig, axs = plt.subplots(len(CUTOFFS), ncol,
                            figsize=(6.4 * ncol, 5.2 * len(CUTOFFS)),
                            squeeze=False)

    for row_i, (cutoff, row_title) in enumerate(CUTOFFS):
        for col_i, key in enumerate(wanted):
            ax = axs[row_i][col_i]
            runs = found[key]
            ax.set_title(f"{DATASETS[key][1]}\n{row_title}",
                         fontsize=14 if ncol > 1 else 16)
            if not runs:
                ax.text(0.5, 0.5, "no evaluated run yet",
                        transform=ax.transAxes, ha="center", va="center",
                        fontsize=13, color="#666666")
                ax.set_yticks([])
                continue
            names = [f"{r['name']} · {r['commit7']} · {r['branch']}"
                     for r in runs]
            y = np.arange(len(runs))
            left = np.zeros(len(runs))
            for t_i, thr in enumerate(THRESHOLDS):
                values = [counts(r["rows"], cutoff)[0][thr] for r in runs]
                ax.barh(y, values, left=left, color=COLORS[t_i],
                        label=thr, height=0.6)
                left = left + np.array(values, dtype=float)
            for i in range(len(runs)):
                ax.text(left[i] + (max(left.max(), 1) * 0.02), i,
                        str(int(left[i])), va="center", ha="left",
                        fontsize=13)
            ax.set_xlim(0, max(left.max(), 1) * 1.25)
            ax.set_yticks(y)
            ax.set_yticklabels(names, fontsize=11)
            ax.set_xlabel("#MAGs", fontsize=13)
            ax.tick_params(axis="x", labelsize=12)

    # Legend: prefer the top-right subplot; fall back to the first subplot
    # that has data (top-right may be an unevaluated dataset).
    handles, labels = axs[0][ncol - 1].get_legend_handles_labels()
    if not handles:
        for ax_row in axs:
            for ax in ax_row:
                handles, labels = ax.get_legend_handles_labels()
                if handles:
                    break
            if handles:
                break
    if handles:
        axs[0][ncol - 1].legend(handles, labels, title="Completeness",
                                loc="upper right", fontsize=12,
                                title_fontsize=13)

    fig.suptitle("COMEBin benchmark — bins per completeness threshold "
                 "(CheckM2), by run and COMEBin version",
                 fontsize=16, y=1.0)
    fig.tight_layout(rect=(0, 0, 1, 0.97))
    os.makedirs(os.path.dirname(args.png), exist_ok=True)
    fig.savefig(args.png, dpi=300, bbox_inches="tight")
    # Deterministic SVG: a fixed hashsalt plus a pinned metadata date keeps the
    # element ids stable and drops the "now" timestamp, so an unchanged figure
    # regenerates byte-identically and the automatic post-eval commit only
    # contains a real change instead of timestamp/id churn.
    try:
        matplotlib.rcParams["svg.hashsalt"] = "metagenomic-binning-benchmark"
    except Exception:
        pass
    fig.savefig(os.path.splitext(args.png)[0] + ".svg", dpi=300,
                bbox_inches="tight", metadata={"Date": None})
    print(f"wrote {args.png}")

    table = make_table(ordered_runs, load_aggregates())
    os.makedirs(os.path.dirname(args.table), exist_ok=True)
    with open(args.table, "w", encoding="utf-8") as f:
        f.write(table)
    print(f"wrote {args.table}")
    print(table)


if __name__ == "__main__":
    main()
