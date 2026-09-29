# Optimization sweep on the medium dataset (issue #25)

Status: **LIVE** (2026-09-28 13:09Z – …). Driver `scripts/run_sweep_medium.sh`
runs the 24 cells **serially, one at a time, never overlapping the registered
run slot** (`.active_run` gate + wait-active_clear), is resumable (`--from N`
skips completed cells, RESUME-evals orphaned rc=0 runs), and is a singleton
(`pgrep` ancestor/child guard + `flock`). Each cell is a full medium run with
seed 42, THREADS 8, registered via `run_comebin_fix.sh`.

Cell status (2026-09-29 01:10Z):
- `sweep_001_ref` (v11 `95f5ea8` reference) — ✅ done, eval'd: 2,827 s wall,
  17 bins, CheckM2 34.22 / 4.11 (HQ 0 / MQ 2), CheckM 32.00 / 5.31 (0 / 3).
- `sweep_002_master` (stock upstream `904f649`, unseeded) — ❌ documented
  failure: stock master dies on the medium BAM/assembly mismatch (issue-#2
  family; `KeyError: 'BATS_…_scaffold_22978'`), exit 1 after 108 s, 0 bins —
  not retried, root cause in `runs/sweep_002_master/` + #28 thread.
- `sweep_003_issue28fix` (v11 `41606c8`, issue-#28 fix) — 🟡 training
  (2026-09-29 00:41Z…).
- cells 4–24 — pending, in grid order below.

Harness fixes landed while the sweep stalled (see #28 thread, commits
`fa69730a 55ad99dd 57b9cb5d 20ca7e39`): `${TEMP:-}`-style `set -u` guards +
`-l/-e/-b/-m/-w/-E` forwarding in `run_comebin_fix.sh`; singleton-guard
self-match fix (ancestor/child walk, ≥5 s age, double probe).

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
  CAMI II gold standard (`binning_gs.tsv`) for official precision/recall/F1.
  ✅ **done**: [docs/14](14-amber-cami2-marine.md) marine (F1_bp 0.330) and
  [docs/15](15-amber-cami2-human.md) human (F1_bp 0.681). The human gold
  standard was imported 2026-09-29 (`setup.tar.gz` → `gsa_mapping.tsv.gz`
  filtered to the 4,900-contig subset, 64 genomes) and the winner run can be
  scored with one command via `scripts/make_amber_prediction.py`.
- **No trimming**: use the full assembly/contigs when present (CAMI II/III
  publish full assemblies); only the demo/medium/small/tiny derivations were
  length-filtered for COMEBin feasibility.
- **Biobox export (CAMI standard)**:
  `bash scripts/export_biobox.sh <run>` → per-run
  `runs/<run>/biobox/` containing:
  - `<sample>.binning` — the **authoritative CAMI binning format v0.9.1**
    (`@Version`/`@SampleID` + `@@SEQUENCEID BINID`), the same file AMBER
    consumes; this is the actual CAMI standard output.
  - `tree/<engine>/<version>/binning/<sample>/<bin_id>.fna` + a
    `binning_summary.tsv` with **computed numeric** contig lengths (COMEBin
    deflines carry no `length=`), plus `bins.fasta.gz` (all bins) and
    `stats.csv` (per-bin CheckM2/CheckM v1).
  Validate structurally before Zenodo:
  `python3 scripts/validate_binning.py runs/<run>/biobox/<sample>.binning`
  (the upstream `bioboxes/validator` container is only published for the
  *assembler* task — not the genome-binning task — so it cannot be pulled).
  ✅ generated for marine (152 bins), human (107), medium and cami3 (492).
- **Archive each binning result**: bins FASTA + biobox output + stats shipped
  with the run's Zenodo archive record.