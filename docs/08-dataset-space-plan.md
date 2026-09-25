# 08 — Dataset & disk-space plan (issue #2)

Workflow rule (user directive, 2026-09-23, issue #2), in order:

1. **Small functional tests first:** every fix batch/version is exercised on
   `/vol/data/datasets/comebin_small` (94 MB) and logged like every other run.
2. **Medium benchmark after the small run passes:** derive and record a larger
   real-data set (initial target: 3,000 top-length demo contigs plus overlapping
   reads; cap at 5 GB and publish measured size/provenance). Run COMEBin and
   CheckM2/CheckM on it only after the end-to-end small test succeeds.
3. **Large benchmarks last:** run the multi-hour full dataset only after a
   **major commit** (new fix batch, upstream release, or dataset change).

Small/medium/full runs are never concurrent, so timing remains comparable.

## Disk budget (492 GB volume)

Current usage (2026-09-23): 76 GB used / **391 GB free**.

| # | Data | Size now | Size planned | Status |
|---|------|----------|--------------|--------|
| 1 | COMEBin demo (BATS) | 6.4 GB + 5.2 GB zip | 6.4 GB (zip deletable → +5.2 GB) | baseline run in progress |
| 2 | Small dataset (issue #2) | 94 MB | kept permanently | ready |
| 3 | Medium derived dataset | – | target 3,000 contigs, hard cap **5 GB** | build only after small test passes |
| 4 | CAMI II marine — sample 0 short-read | 10 GB extracted (tars 4.6+0.36 GB) | keep **1–2 samples** (~11 GB/sample extracted) | sample 0 extracted |
| 5 | Human host-associated (CAMI II) | sample_0 tarball 9.7 GB + extracted contigs/reads 11 GB + input build ~0.5 GB | **1–2 samples, ≤ 30 GB** | ✅ sample 0 downloaded + md5-verified 2026-09-25, input prep running |
| 5b | Tiny functional set (issue #18) | `comebin_tiny` 43 MB + `comebin_tiny_101` 47 MB | kept permanently (floor = 101 contigs) | ✅ built, `tiny_test_n101` passed end-to-end |
| 6 | CAMI III (marine + human gut) | – | **≤ 50 GB** (verify sizes on frl.publisso.de before download) | to download |
| 7 | Eval refs + envs | checkm_ref 1.4 GB + checkm2db 2.9 GB + envs ~8 GB | unchanged | ready |

**Budget math:** demo 6.4 + small 0.1 + medium ≤5 + CAMI II marine 11 + human
30 + CAMI III 50 ≈ **~105 GB future** → stays far below 492 GB with >50 GB
headroom.
Delete `comebin_test_data.zip` (5.2 GB) after the baseline run if needed.

## Medium derived benchmark (gated)

After the 300-contig small run completes successfully through COMEBin (not just
`py_compile`), rebuild with the same real-data method and `N=3000`, record the
measured FASTA/BAM size and read count, then run COMEBin plus CheckM2/CheckM v1.
If the result would exceed 5 GB, reduce N before downloading/extracting more
data. This stage is intentionally **not** built while the active baseline is
running and is not a substitute for the post-major-commit large benchmark.

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

**Status 2026-09-25 (issue #18, "1/6 the size of the big one"):** the GI-tract
block archive `gastrooral/sample_0.tar.gz` (9,738,621,091 B, md5
`60e04c041c38ea168af03fc55dff15d6`) is downloaded and verified; `contigs/` +
`reads/` extracted (`bam/` skipped — the 139 per-OTU BAMs cannot be merged).
The input build subsets the gold-standard assembly from 68,417 to the **top
4,900 contigs by length (166.0 Mbp ≈ 29,434 / 6)** and maps all 10.6 GB of
interleaved reads with `bwa mem -p -t 32` →
`/vol/data/datasets/cami_II_human/human_sample0_input/`
(`scripts/prep_cami2_human.sh`). Expected benchmark wall time ≈ 1 h vs 6.9 h
for the full demo. Ground-truth binning (`binning_gs.tsv`) is not in this
tarball — see docs/01.

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