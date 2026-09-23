# 07 — Fix batches (COMEBin `comebin-optimizations` branch)

One commit per batch; benchmark run after each batch; every run recorded in
`runs/<run>/` + the README performance table. Baseline reference: commit
`987db95d8d399f30b7c82a5f5f40ed6bfdc906c7` (pristine, `runs/baseline_unmodified/`).

## Batch 1 — bin numbering + coverage precision

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