#!/usr/bin/env python3
"""make_all_runs_table.py — regenerate `results/all_runs_table.md`.

Issue #22 (owner: "a summary table for all runs also the small ones") and
#24-e (README section e "the all run table as requested"). One row per run
ever launched (including failed and tiny/small reality checks), newest first:

  Run | Date | Duration | Dataset (+ public link) | Branch / commit
       | Size (contigs.gz/GB) | Bins | CheckM2 comp | CheckM2 cont
       | HQ/MQ | F1 | Comment

F1 is the harmonic mean of CheckM2 mean completeness and purity
(= 1 - contamination):  F1 = 2*c*p/(c+p), c = comp, p = 100 - cont.

NOTE on the heartbeat: status-heartbeat.sh rewrites README rows that start
with `| \`<runname>\` |` AND split into EXACTLY 13 fields (an 11-column
"performance table"). This table uses 12 data columns on purpose (split = 14
fields) so the heartbeat never misidentifies a row here and corrupts the
Comment column.

Run inside the comebin env (only env with nothing special needed, python3
only actually):

  micromamba run -p /vol/data/envs/comebin python scripts/make_all_runs_table.py
"""
import csv
import glob
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def repo_root():
    for cand in (os.environ.get("BENCH_REPO", "").strip(),
                 os.path.normpath(os.path.join(HERE, ".."))):
        if cand and os.path.isfile(os.path.join(cand, "README.md")) \
                and os.path.isdir(os.path.join(cand, "results")):
            return cand
    return "/vol/data/repos/metagenomic-binning-benchmark"


REPO = repo_root()
RESULTS = os.path.join(REPO, "results")
BENCH_RUNS = "/vol/data/benchmark/runs"

# Ordered priority of run dirs (benchmark disk) that mirror into REPO/runs.
RUN_DIRS = "/vol/data/benchmark/runs"

# dataset -> (display, public link, dataset dir size GB for contigs)
# Sizes measured 2026-09-28; contigs = the specific contigs.fa used by COMEBin.
DATASETS = {
    "demo": ("COMEBin demo (BATS, 29,434 contigs)",
             "<https://drive.google.com/uc?id=1xWpN2z8JTaAzWW4TcOl0Lr4Y_x--Fs5s> "
             "(COMEBin README)", "0.05 GB - 53 MB contigs.fa / 6.4 GB dir"),
    "small": ("comebin_small (300 contigs)", "derived - Zenodo "
              "[10.5281/zenodo.22935025](https://doi.org/10.5281/zenodo.22935025)",
              "0.003 GB - 3.5 MB contigs.fa / 0.1 GB dir"),
    "tiny": ("comebin_tiny (101 contigs)", "derived - "
             "[docs/01-datasets.md](docs/01-datasets.md)", "0.002 GB / 0.05 GB dir"),
    "medium": ("COMEBin medium (3,000 contigs)", "derived - "
               "[scripts/make_medium_dataset.sh](scripts/make_medium_dataset.sh)",
               "0.014 GB - 14 MB contigs.fa / 0.42 GB dir"),
    "human": ("CAMI II human (4,900 contigs)",
              "<https://frl.publisso.de/data/frl:6425518/> (CAMI II Toy HMP)",
              "0.17 GB contigs.fa / 25 GB dir"),
    "marine": ("CAMI II marine (41,988 contigs)",
               "<https://doi.org/10.5281/zenodo.5013479> (CAMI II asmbly record)",
               "0.32 GB contigs.fa / 5.9 GB dir"),
    "cami3": ("CAMI III toy human gut (5,000 contigs)",
              "<https://cami-challenge.org/datasets/> (CAMI III toy download)",
              "1.1 GB contigs.fa / 15 GB dir"),
    # Sibling-owned #28 regression dataset (local, not a public benchmark set).
    "regression": ("COMEBin small-mirror (300 contigs)",
                   "/tmp/opencode/realdata/ds (local, for issue #28)",
                   "0.004 GB - 3.5 MB contigs.fa"),
}


def classify(contigs_path):
    """Dataset key for a run_meta `contigs:` value."""
    c = contigs_path or ""
    for key, (display, _link, _size) in DATASETS.items():
        needle = {
            "demo": "BATS_SAMN07137077",
            "small": "comebin_small",
            "tiny": "comebin_tiny",
            "medium": "comebin_medium",
            "human": "cami_II_human",
            "marine": "cami_II/marine",
            "cami3": "cami_III",
            "regression": "/tmp/opencode/realdata/ds",
        }[key]
        if needle in c:
            return key
    return None


def fmt_duration(sec):
    if not sec:
        return "-"
    sec = int(sec)
    if sec >= 3600:
        return f"{sec // 3600}h{sec % 3600 // 60:02d}m"
    if sec >= 60:
        return f"{sec // 60}m{sec % 60:02d}s"
    return f"{sec}s"


def f1_score(comp, cont):
    """F1 = 2*c*p/(c+p) in percent; c = completeness, p = purity = 100 - cont."""
    try:
        c = float(comp)
        n = float(cont)
    except (TypeError, ValueError):
        return "-"
    p = max(0.0, 100.0 - n)
    if c + p <= 0:
        return "-"
    return f"{2 * c * p / (c + p):.1f}"


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
        return {}
    with open(path, encoding="utf-8") as f:
        return next(csv.DictReader(f), {}) or {}


def main():
    runs = []
    for run_dir in sorted(glob.glob(os.path.join(RUN_DIRS, "*"))):
        name = os.path.basename(run_dir)
        meta = read_meta(run_dir)
        a = agg_row(name)
        runs.append({"name": name, "meta": meta, "agg": a})

    now = None
    try:
        with open(os.path.join(REPO, "..", "..", "benchmark", ".active_run")) as f:
            now = os.path.basename(f.read().split()[3])
    except Exception:
        now = None

    rows = []
    for r in runs:
        meta, a = r["meta"], r["agg"]
        ds_key = classify(meta.get("contigs", ""))
        if ds_key:
            display, link, size = DATASETS[ds_key]
        else:
            display, link, size = (meta.get("contigs", "?").split("/")[-1] or "?",
                                   "-", "-")
        commit = meta.get("commit", "-")
        branch = meta.get("branch")
        if not branch or not branch.strip():
            src = meta.get("source", "")
            # Strip a trailing " (branch ...)" marker before matching dir names.
            src_dir = re.sub(r"\s*\(branch .*\)\s*$", "", src).rstrip("/")
            m = re.search(r"\(branch (.*?)\)", src)
            if m and m.group(1).strip():
                branch = m.group(1)
            elif src_dir.endswith("COMEBin") or src_dir.endswith("COMEBin-v11") or src_dir.endswith("COMEBin-v11-sweep"):
                if src_dir.endswith("COMEBin"):
                    branch = "master"
                elif src_dir.endswith("COMEBin-v11-sweep"):
                    branch = "comebin-optimizations-v11 (sweep worktree)"
                else:
                    branch = "comebin-optimizations-v11"
            elif src_dir.endswith("COMEBin-master904"):
                branch = "master (sweep worktree)"
            else:
                branch = "-"
        exit_code = meta.get("exit_code")
        if exit_code is None and r["name"] in runs:
            pass
        if r["name"] == "small_v11_issue28_regression":
            exit_code = "running"

        bins = a.get("n_bins", "-")
        comp = a.get("checkm2_mean_completeness", "-")
        cont = a.get("checkm2_mean_contamination", "-")
        hq = a.get("checkm2_HQ", "-")
        mq = a.get("checkm2_MQ", "-")
        f1 = f1_score(comp, cont) if comp != "-" else "-"

        comment = {
            "baseline_unmodified": "first baseline try (pre-dataset fixes); superseded",
            "baseline_rerun": "aborted/rerun; use baseline_rerun_autorestart1",
            "baseline_rerun_autorestart1": "final unmodified baseline on demo",
            "fix_v11_20260924": "fix batch 1 on demo, same params as baseline",
            "medium_v11_20260924": "fix batch 1 validation on medium gate",
            "small_test": "early small run - failed pre-fix",
            "small_test_v2": "early small run - failed pre-fix",
            "small_test_v3": "small gate after small-fix commits",
            "small_test_v4": "small gate OK after rebuild",
            "tiny_test_n100": "floor test: HNSW k=max_edges+1>N->exit 1 (#18a)",
            "tiny_test_n101": "smallest working dataset (101 contigs)",
            "human_v11_20260925": "first HQ-rich dataset (CAMI II human)",
            "marine_v11_20260925": "best-quality dataset so far (CAMI II marine)",
            "cami3_v11_20260926": "failed: FS full (ENOSPC) -> rerun",
            "cami3_v11_20260926_rerun": "492 bins, most HQ/MQ of any run (CAMI III)",
            "small_v11_issue28_regression": "issue #28 graceful-zero-bins validation",
            "sweep_001_ref": "sweep ref (v11 `95f5ea8`, seed 42, 8 thr) — grid baseline",
            "sweep_002_master": "sweep stock master `904f649` (unseeded) — failed: medium BAM/assembly mismatch → exit 1, 0 bins, documented",
            "sweep_003_issue28fix": "sweep issue-#28 fix `41606c8` — no regression vs ref",
            "sweep_004_temp005": "**#25 winner** temp 0.05 — top CheckM2 F1 (59.4), +9.3 pp comp vs ref",
            "sweep_005_temp030": "sweep temp 0.30",
            "sweep_006_temp050": "sweep temp 0.50",
            "sweep_007_emb1024": "sweep emb 1024",
            "sweep_008_emb4096": "sweep emb 4096",
            "sweep_009_embcov1024": "sweep emb_cov 1024",
            "sweep_010_embcov4096": "sweep emb_cov 4096",
            "sweep_011_batch512": "sweep batch 512 — 2× faster, +7.3 pp comp",
            "sweep_012_batch2048": "sweep batch 2048",
            "sweep_013_edges80": "sweep max_edges 80 — best cont (5.29) among top-4",
            "sweep_014_edges150": "sweep max_edges 150",
            "sweep_015_views4": "sweep n_views 4",
            "sweep_016_views8": "sweep n_views 8",
            "sweep_017_w4": "sweep leiden_workers 4",
            "sweep_018_w16": "sweep leiden_workers 16",
            "sweep_019_eval1e3": "sweep hmm_evalue 1e-3",
            "sweep_020_eval1e7": "sweep hmm_evalue 1e-7",
            "sweep_021_comboA": "sweep combo temp 0.3 + emb 1024 + batch 512",
            "sweep_022_comboB": "sweep combo temp 0.05 + emb 4096 + batch 2048",
            "sweep_023_embcov512_batch512": "sweep emb_cov 512 + batch 512 — #2 overall, fast (21 min)",
            "sweep_024_seed7": "sweep seed 7 (reproducibility sweep) — 37.4 comp vs 34.2 (seed 42) → seed-sensitive",
        }.get(r["name"], "-")

        if exit_code == "running":
            dur, bins, comp, cont, hq, mq, f1 = "-", "-", "-", "-", "-", "-", "-"
        else:
            dur = fmt_duration(a.get("total_time_s") or meta.get("wall_s"))

        rows.append([
            f"`{r['name']}`", meta.get("date", "-")[:10],
            dur, f"{display} · {link}", f"`{branch}` @ `{commit[:7]}`",
            size, bins, comp, cont,
            f"{hq} / {mq}", f1, comment,
        ])

    rows.sort(key=lambda x: x[1], reverse=True)
    header = ("| Run | Date | Duration | Dataset (public link) | Branch / commit "
              "| Size (contigs) | Bins | CheckM2 comp | CheckM2 cont | HQ / MQ | F1 | Comment |")
    sep = "|---|---|---|---|---|---|---|---|---|---|---|---|"

    out = [header, sep]
    for row in rows:
        out.append("| " + " | ".join(str(c) for c in row) + " |")
    table = "\n".join(out) + "\n"

    os.makedirs(RESULTS, exist_ok=True)
    table_path = os.path.join(RESULTS, "all_runs_table.md")
    with open(table_path, "w", encoding="utf-8") as f:
        f.write(table)
    print(f"wrote {table_path}")

    # Also inject the table into README section e between its markers.
    readme = os.path.join(REPO, "README.md")
    if os.path.exists(readme):
        with open(readme, encoding="utf-8") as f:
            content = f.read()
        start = "<!--ALL-RUNS:START-->"
        end = "<!--ALL-RUNS:END-->"
        if start in content and end in content:
            head, _ = content.split(start, 1)
            _, tail = content.split(end, 1)
            with open(readme, "w", encoding="utf-8") as f:
                f.write(head + start + "\n\n" + table + "\n" + end + tail)
            print(f"updated table block in {readme}")
        else:
            print(f"WARN: markers {start}/{end} not found in README")

    print(table)


if __name__ == "__main__":
    main()