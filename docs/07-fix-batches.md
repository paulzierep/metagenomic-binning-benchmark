# 07 — Fix batches (COMEBin `comebin-optimizations` branch)

One commit per batch; **functional validation always on the small benchmark
dataset** (`/vol/data/datasets/comebin_small`, minutes); full benchmark runs
(timed + CheckM2/CheckM eval) are run **only after major commits** (user
directive, 2026-09-23, issue #2). Every run recorded in `runs/<run>/` + the
README performance table. Baseline reference: commit
`987db95d8d399f30b7c82a5f5f40ed6bfdc906c7` (pristine, `runs/baseline_unmodified/`).

## Fork update (2026-09-23): work now continues on COMEBin v1.1.0

User pushed the updated fork (`origin/master` → `1b476a4`, "Release v1.1.0").
v1.1.0 rewrites `data_aug/gen_cov.py` (float64 Welford means + variance — the
old batch-1 coverage-precision fix is **already upstream**), **removes
`data_aug/gen_var.py`** (`--addvars/--vars_sqrt` still supported) and adds CLI
flags `-w -m -d cpu -s seed -E -V`. The bin-numbering bug survives, so:

- Branch **`comebin-optimizations-v11`** @ `95f5ea8` (worktree
  `/vol/data/repos/COMEBin-v11`, based on `1b476a4`): **sequential bin
  numbering + no empty/missing bins** in `filter_small_bins.py` +
  `scripts/gen_bins_from_tsv.py` (verified: py_compile + synthetic functional
  test PASS). Pushed to the fork.
- New runs must pass `-d cpu` (no GPU) and may use `-s <seed>` for reproducible
  fix-batch runs. The running baseline (`987db95`, v1.0.4-era) is unaffected;
  the README table records version+commit per row.

## Batch 1 (original, pre-v1.1.0) — bin numbering + coverage precision

- Commit: `03670d6aa928cbbf3c0fd14b311206eeaff7f079` → branch
  `comebin-optimizations`
- Worktree: `/vol/data/repos/COMEBin-opt` (the pristine clone
  `/vol/data/repos/COMEBin` stays on `master` for baseline reproducibility)
- Changes:
  1. **Sequential bin numbering** — `COMEBin/filter_small_bins.py` and
     `COMEBin/scripts/gen_bins_from_tsv.py` (`gen_bins`): `bin_name` used to be
     incremented inside the per-*contig* loop → bin file names equalled the
     cumulative contig count instead of being sequential per bin, and a cluster
     whose first contig was missing produced an empty stray file. Now numbered
     `0,1,2,…` once per cluster/bin; contig lookup via `dict.get()`.
  2. **Fractional coverage** — `COMEBin/data_aug/gen_cov.py` +
     `COMEBin/data_aug/gen_var.py`: per-base depth `int(float(x))` →
     `float(x)`, keeps coverage precision instead of truncating to integers.
- Verified: `python -m py_compile` OK on all 4 files.
- Benchmark: **re-run pending** — must wait for the baseline run to finish
  (CPU policy: no concurrent timed runs). Re-run via
  `scripts/run_comebin_fix.sh runs/fix_batch1` (defaults to the worktree).

## Planned batches (candidate pool, from the initial source review)

- reproducibility: seed everything (CL random, KMeans/MiniBatch, HNSW init,
  torch); record seeds in `run_meta.txt`
- data augmentation: batch cap / `drop_last` on small datasets, topk
  `n_views` guard (small-dataset bugs from issue #2)
- cluster stage: KMeans `n_jobs`/`algorithm` API cleanup (newer sklearn),
  guard `fit_hnsw_index` / leiden / seed-KMeans on <2 elements
- memory/perf: replace per-position lists (`[value] * length`) with
  compressed runs for large contigs; optional kmer vectorization