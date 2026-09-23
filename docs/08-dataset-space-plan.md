# 08 — Dataset & disk-space plan (issue #2)

Workflow rule (user directive, 2026-09-23, issue #2):
**ALL functional tests run on the small benchmark dataset
(`/vol/data/datasets/comebin_small`, 94 MB) and are logged as usual; a full
benchmark (timed COMEBin + CheckM2/CheckM eval) is run only after MAJOR
commits** (new fix batches, new versions, new datasets). Small-data runs take
minutes; full benchmark runs take hours and are never run concurrently
(timing comparability).

## Disk budget (492 GB volume)

Current usage (2026-09-23): 76 GB used / **391 GB free**.

| # | Data | Size now | Size planned | Status |
|---|------|----------|--------------|--------|
| 1 | COMEBin demo (BATS) | 6.4 GB + 5.2 GB zip | 6.4 GB (zip deletable → +5.2 GB) | baseline run in progress |
| 2 | Small dataset (issue #2) | 94 MB | kept permanently | ready |
| 3 | CAMI II marine — sample 0 short-read | 10 GB extracted (tars 4.6+0.36 GB) | keep **1–2 samples** (~11 GB/sample extracted) | sample 0 extracted |
| 4 | Human host-associated (CAMI II) | – | **1–2 samples, ≤ 30 GB** | to download |
| 5 | CAMI III (marine + human gut) | – | **≤ 50 GB** (verify sizes on frl.publisso.de before download) | to download |
| 6 | Eval refs + envs | checkm_ref 1.4 GB + checkm2db 2.9 GB + envs ~8 GB | unchanged | ready |

**Budget math:** demo 6.4 + small 0.1 + CAMI II marine 11 + human 30 + CAMI III
50 ≈ **~100 GB future** → stays far below 492 GB with >50 GB headroom.
Delete `comebin_test_data.zip` (5.2 GB) after the baseline run if needed.

## Human host-associated datasets (CAMI II, all real metagenome simulations)

- **CAMI II Multisample Human Microbiome Project** — DOI 10.4126/frl01-006425518
  (frl.publisso.de). Simulated Illumina short-read + PacBio long-read
  metagenomes from human body sites.
- **CAMI II Toy Human Microbiome** — frl:6425518; **49 samples across 5 body
  sites** (GI tract, oral, airways, skin, urogenital), 2×150 bp short-read
  (245 Gbp total) + PacBio. Downloadable per body-site via camiClient
  (`CAMI_Gastrointestinal_tract`, `CAMI_Oral`, `CAMI_Skin`, `CAMI_Airways`,
  `CAMI_Urogenital_tract`).
- **CAMI II Toy Mouse Gut** — frl:6421672 (64 samples, 320 Gbp) — backup option.

Plan: pick **1 GI-tract sample + 1 second body site** (host diversity), reuse the
same COMEBin input strategy as CAMI II marine (assemblies/BAMs or per-sample
mapping), evaluate with CheckM2/CheckM v1 against the provided ground-truth
binning.

## CAMI II marine samples (already finishing)

Per-sample (short-read): `_bam` ~4.6 GB + `_contigs` ~0.36–0.49 GB
(+`_reads` 5.2 GB, NOT needed for COMEBin — BAMs are supplied pre-mapped).
Sample 0 downloaded + verified (`gzip -t`) + extracted. If a second marine
sample is wanted, budget ~11 GB extracted.

## Cleanup / hygiene policy

- Delete source `.zip`/`.tar.gz` after md5/gzip-verified extraction, keeping the
  md5 + file listing in docs (dataset provenance stays in the repo).
- Keep only the chosen CAMI samples' extracted data; delete unneeded shooter
  (long-read/ONT) archives.
- `runs/<run>/` mirrors in the repo stay small (logs only; big artifacts
  gitignored), so the Git repo does not grow with benchmark bulk data.

Dataset build/run commands: `docs/06-benchmark-commands.md`; provenance:
`docs/01-datasets.md`.