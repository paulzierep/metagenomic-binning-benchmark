# Optimization sweep on the medium dataset (issue #25)

Status: **design / plan — not yet launched**. Launch blocked while
`/vol/data/benchmark/.active_run` is held (sibling's `small_v11_prepatch_baseline`).
This doc defines the grid, ranking rule, and follow-on steps so the sweep can be
run by any session once the run slot is free.

Owner's requirements (issue #25, verbatim intent):

> Run at least 20 runs with different params or commits on the medium dataset
> and take the best based on bin stats and if similar based on runtime before
> running on larger data. Only take cami ii and iii human for the larger data
> from now on. Archive the other benchmark data in zenodo and remove to get
> disc space. Use amber for performance of cami II, use the gold standard if
> available, do not trim the data if full assembly is there. Learn to export
> binning results as biobox format (CAMI standard), also export each binning
> result: bins in fasta, biobox output, stats.

## Dataset

- `comebin_medium` (3,000 contigs, 14.4 MB contigs.fa, real reads BAM):
  `/vol/data/datasets/comebin_medium/` — provenance in `PROVENANCE.txt`.
- Deterministic seed **42** for every run (issue #21).
- Medium wall-time scale: ~39 min/run → 20 runs ≈ 13 h serial, one at a time
  (never overlap the registered run; harness enforces via `.active_run`).

## Harness

- `/vol/data/benchmark/bin/run_comebin_fix.sh` with:
  `DATA=/vol/data/datasets/comebin_medium \
   CONTIGS=/vol/data/datasets/comebin_medium/contigs.fa \
   BAMDIR=/vol/data/datasets/comebin_medium/bamfiles \
   MODE=medium THREADS=8 SEED=42`
- **Param forwarding**: upstream `run_comebin.sh` (v11) already accepts
  `-l TEMP -e EMB_SZS -c EMB_SZS_FORCOV -b BATCH -m MAX_EDGES -w LEIDEN_WORKERS
  -E HMM_EVALUE`. The fixed-flag wrapper only forwards `-a -p -o -n -t -d -s`
  today. The sweep needs a small harness extension that maps env vars →
  these flags (e.g. `TEMP=0.30 EMB=1024 BATCH=512 MAX_EDGES=80`) before
  invoking `run_comebin.sh`. Keep the default values as the **reference run**
  (current `medium_v11_20260924`: 16 bins, CheckM2 35.93/4.67).

## Grid (24 cells — all seed 42, THREADS 8)

Purpose: one-factor-at-a-time around the reference defaults
(`-n 6`, temp 0.15, emb 2048, emb_cov 2048, batch 1024, max_edges 100,
leiden_workers = threads).

| # | Axis | Value | run name |
|---|---|---|---|
| 1 | reference (no override) | defaults | `sweep_001_ref` |
| 2 | commit | **master 904f649** (unmodified) | `sweep_002_master` |
| 3 | commit | **41606c8** (issue #28 fix, v11) | `sweep_003_issue28fix` |
| 4 | temperature `-l` | 0.05 | `sweep_004_temp005` |
| 5 | temperature `-l` | 0.30 | `sweep_005_temp030` |
| 6 | temperature `-l` | 0.50 | `sweep_006_temp050` |
| 7 | emb_szs `-e` | 1024 | `sweep_007_emb1024` |
| 8 | emb_szs `-e` | 4096 | `sweep_008_emb4096` |
| 9 | emb_szs_forcov `-c` | 1024 | `sweep_009_embcov1024` |
| 10 | emb_szs_forcov `-c` | 4096 | `sweep_010_embcov4096` |
| 11 | batch_size `-b` | 512 | `sweep_011_batch512` |
| 12 | batch_size `-b` | 2048 | `sweep_012_batch2048` |
| 13 | max_edges `-m` | 80 | `sweep_013_edges80` |
| 14 | max_edges `-m` | 150 | `sweep_014_edges150` |
| 15 | n_views `-n` | 4 | `sweep_015_views4` |
| 16 | n_views `-n` | 8 | `sweep_016_views8` |
| 17 | leiden_workers `-w` | 4 | `sweep_017_w4` |
| 18 | leiden_workers `-w` | 16 | `sweep_018_w16` |
| 19 | hmm_evalue `-E` | 1e-3 | `sweep_019_eval1e3` |
| 20 | hmm_evalue `-E` | 1e-7 | `sweep_020_eval1e7` |
| 21 | combo | temp 0.3 + emb 1024 + batch 512 | `sweep_021_comboA` |
| 22 | combo | temp 0.05 + emb 4096 + batch 2048 | `sweep_022_comboB` |
| 23 | combo | emb_cov 512 + batch 512 (early-stop disabled — `--earlystop` is hardcoded in `run_comebin.sh`, not a CLI flag — so this cell tests the small-emb-cov regime instead) | `sweep_023_embcov512_batch512` |
| 24 | seed sanity | seed 7 (reproducibility check) | `sweep_024_seed7` |

## Ranking rule (owner's order)

1. **Bin stats first**: CheckM2 mean completeness / contamination (HQ + MQ
   counts), then CheckM v1. Higher completeness + lower contamination +
   more HQ/MQ wins. F1 (harmonic mean of completeness and purity) as the
   summary.
2. **Runtime tiebreak**: if bin stats are statistically similar (~±1 pt), the
   shorter wall time wins.
3. Only the winning parameter set advances to **CAMI II & III human** runs.

## Follow-on per issue #25

- **Restrict large data to human**: CAMI II human (4,900 contigs) and CAMI III
  toy human (5,000) only; **archive** demo / marine / medium / small / tiny in
  Zenodo (already v2/v3 for main runs) and delete local copies to free disk.
- **AMBER**: use [AMBER](https://github.com/CAMI-challenge/AMBER) against the
  CAMI II gold standard (`binning_gs.tsv`) for official precision/recall/F1 on
  the human set once imported (docs/01: gold-standard binning lives in
  `setup.tar.gz` — not yet pulled in).
- **No trimming**: use the full assembly/contigs when present (CAMI II/III
  publish full assemblies); only the demo/medium/small/tiny derivations were
  length-filtered for COMEBin feasibility.
- **Biobox export (CAMI standard)**:
  `scripts/export_biobox.sh <run>` → per-run
  `runs/<run>/biobox/` containing bins in FASTA (`bin_*.fa`; already produced
  by COMEBin as `comebin_res_bins/*.fa`), a CAMI biobox `binning` tar.gz
  (folder `/<binning-engine>/<version>/binning/<sample>/<bin_id>.fna` +
  `binning_summary.tsv`), and per-run stats. Validate with the biobox
  validator (`bioboxes/validator` container) before pushing to Zenodo.
- **Archive each binning result**: bins FASTA + biobox output + stats shipped
  with the run's Zenodo archive record.