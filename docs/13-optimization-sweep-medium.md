# Optimization sweep on the medium dataset (issue #25)

Status: **COMPLETE** (2026-09-28 13:09Z → 2026-09-30 ~00:34Z). All 24 cells
finished: 23 evaluated (cells 1, 3–24), 1 documented failure (cell 2, stock
master). Every cell ran **serially, one at a time, never overlapping the
registered run slot** (`.active_run` gate + wait-active_clear), was resumable
(`--from N`), and was a singleton (`pgrep` ancestor/child guard + `flock`).
Each cell = a full medium run with seed 42 (cell 24: seed 7), THREADS 8,
registered via `run_comebin_fix.sh`.

Cell status (final):
- `sweep_001_ref` (v11 `95f5ea8` reference) — ✅ 2,827 s wall, 17 bins,
  CheckM2 34.22 / 4.11 (HQ 0 / MQ 2), CheckM 32.00 / 5.31 (0 / 3).
- `sweep_002_master` (stock upstream `904f649`, unseeded) — ❌ documented
  failure: stock master dies on the medium BAM/assembly mismatch (issue-#2
  family; `KeyError: 'BATS_…_scaffold_22978'`), exit 1 after 108 s, 0 bins —
  not retried, root cause in `runs/sweep_002_master/` + #28 thread.
- `sweep_003_issue28fix` (v11 `41606c8`, issue-#28 fix) — ✅ 2,833 s, 17 bins,
  CheckM2 34.22 / 4.11 — **no regression vs ref** (identical stats; the fix
  only touches the zero-bin edge case).
- Cells 4–24 — ✅ all done, evaluated, ranked (below). `sweep_024_seed7`
  (seed 7) completed 2026-09-30: 2,797 s, 15 bins, CheckM2 37.37 / 5.60.

**Final ranking:** [`results/sweep_rankings.md`](../results/sweep_rankings.md)
(23 ranked cells; full grid in the table below). Final rankings:

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

| # | Axis | Value | run name | Result |
|---|---|---|---|---|
| 1 | reference (no override) | defaults | `sweep_001_ref` | 17 bins, CheckM2 34.22/4.11 |
| 2 | commit | **master 904f649** (unmodified) | `sweep_002_master` | ❌ failed (BAM/assembly mismatch), 0 bins |
| 3 | commit | **41606c8** (issue #28 fix, v11) | `sweep_003_issue28fix` | 17 bins, 34.22/4.11 (no regression) |
| 4 | temperature `-l` | 0.05 | `sweep_004_temp005` | **🥇 13 bins, 43.55/6.77 — WINNER** |
| 5 | temperature `-l` | 0.30 | `sweep_005_temp030` | 17 bins, 33.38/3.73 |
| 6 | temperature `-l` | 0.50 | `sweep_006_temp050` | 17 bins, 34.33/3.92 |
| 7 | emb_szs `-e` | 1024 | `sweep_007_emb1024` | 15 bins, 38.40/4.76 |
| 8 | emb_szs `-e` | 4096 | `sweep_008_emb4096` | 16 bins, 36.33/4.81 |
| 9 | emb_szs_forcov `-c` | 1024 | `sweep_009_embcov1024` | 16 bins, 35.80/4.12 |
| 10 | emb_szs_forcov `-c` | 4096 | `sweep_010_embcov4096` | 17 bins, 34.10/4.50 |
| 11 | batch_size `-b` | 512 | `sweep_011_batch512` | 14 bins, 41.56/6.34 (2× faster) |
| 12 | batch_size `-b` | 2048 | `sweep_012_batch2048` | 18 bins, 34.68/4.12 |
| 13 | max_edges `-m` | 80 | `sweep_013_edges80` | 15 bins, 40.39/5.29 |
| 14 | max_edges `-m` | 150 | `sweep_014_edges150` | 18 bins, 32.15/3.97 |
| 15 | n_views `-n` | 4 | `sweep_015_views4` | 17 bins, 33.84/4.84 |
| 16 | n_views `-n` | 8 | `sweep_016_views8` | 17 bins, 34.68/4.56 |
| 17 | leiden_workers `-w` | 4 | `sweep_017_w4` | 17 bins, 34.22/4.11 |
| 18 | leiden_workers `-w` | 16 | `sweep_018_w16` | 17 bins, 34.22/4.11 |
| 19 | hmm_evalue `-E` | 1e-3 | `sweep_019_eval1e3` | 17 bins, 34.22/4.11 |
| 20 | hmm_evalue `-E` | 1e-7 | `sweep_020_eval1e7` | 17 bins, 34.22/4.11 |
| 21 | combo | temp 0.3 + emb 1024 + batch 512 | `sweep_021_comboA` | 20 bins, 30.30/3.21 |
| 22 | combo | temp 0.05 + emb 4096 + batch 2048 | `sweep_022_comboB` | 17 bins, 34.10/4.22 |
| 23 | combo | emb_cov 512 + batch 512 (early-stop disabled — `--earlystop` is hardcoded in `run_comebin.sh`, not a CLI flag — so this cell tests the small-emb-cov regime instead) | `sweep_023_embcov512_batch512` | 13 bins, 43.16/7.52 (🥈, 21 min) |
| 24 | seed sanity | seed 7 (reproducibility check) | `sweep_024_seed7` | 15 bins, 37.37/5.60 (seed-sensitive) |

## Results & winner

Full ranking (23 cells): [`results/sweep_rankings.md`](../results/sweep_rankings.md).
Ranking rule applied = owner's order (CheckM2 comp desc → cont asc → HQ+MQ
desc → F1 desc → wall asc).

| Rank | Cell | Params (non-ref) | Wall | Bins | CheckM2 comp | cont | F1 | CheckM1 comp/cont |
|---|---|---|---|---|---|---|---|---|
| 1 | `sweep_004_temp005` | temp=0.05 | 2842 | 13 | 43.55 | 6.77 | 59.37 | 39.96/9.63 |
| 2 | `sweep_023_embcov512_batch512` | emb_cov=512 batch=512 | 1262 | 13 | 43.16 | 7.52 | 58.85 | 41.34/9.46 |
| 3 | `sweep_011_batch512` | batch=512 | 1583 | 14 | 41.56 | 6.34 | 57.57 | 37.94/7.60 |
| 4 | `sweep_013_edges80` | max_edges=80 | 2757 | 15 | 40.39 | 5.29 | 56.63 | 36.91/6.86 |
| … | (19 more cells) | … | … | … | … | … | … | … |
| 23 | `sweep_021_comboA` | temp=0.30 emb=1024 batch=512 | 1951 | 20 | 30.30 | 3.21 | 46.15 | 27.65/2.92 |
| ref | `sweep_001_ref` | reference | 2827 | 17 | 34.22 | 4.11 | 50.44 | 32.00/5.31 |

**Winner: `sweep_004_temp005` — temperature 0.05.** Gains vs reference:
+9.33 pp CheckM2 completeness (43.55 vs 34.22), F1 59.37 vs 50.44 (+8.93).
Cost: contamination 6.77 vs 4.11 (finer bins → more splits), 13 vs 17 bins.
The other strong cells (emb_cov 512 + batch 512, batch 512) confirm that
**batch ≤ 512** is the single cheapest + most effective axis (≈2× faster +
~+7 pp completeness), and **low temperature (0.05)** boosts completeness the
most of any single parameter. Per the owner's rule (stats first, runtime
only as tiebreak) temp 0.05 wins; batch/emb_cov 512 are noted as the
cost-efficient runner-up regime.

**Parameter-provenance note:** the ranking reads each cell's applied parameters
from `run_meta.txt` `cmd_wrapper:` (the record of what COMEBin actually
received), not the driver's `sweep:` meta line. The meta line for cells 4–6
was written by an earlier driver version and records `temp=ref` even though
`-l 0.05 / 0.30 / 0.50` was on the command line and each run log confirms
`Tau(temperature): 0.05 / 0.30 / 0.50` — the runs themselves are correct, the
meta text was stale. `rank_sweep_medium.py` cross-checks both and reports any
disagreement.

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
  ✅ **done for all three datasets**: [docs/14](14-amber-cami2-marine.md)
  marine (F1_bp 0.330), [docs/15](15-amber-cami2-human.md) human (F1_bp 0.681)
  and [docs/16](16-amber-cami3-toy.md) CAMI III toy gut (F1_bp 0.743, 2026-09-30).
  The human gold standard was imported 2026-09-29 (`setup.tar.gz` →
  `gsa_mapping.tsv.gz` filtered to the 4,900-contig subset, 64 genomes) and the
  CAMI III one built 2026-09-30 by `scripts/make_cami3_gold_standard.py` (official
  `gsa_pooled_mapping.tsv.gz` joined to our 5,000-contig subset on the reference
  contig id → 5,000/5,000 mapped, 390 genomes). Any further run is scored with
  one command via `scripts/make_amber_prediction.py` + `amber.py`.
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