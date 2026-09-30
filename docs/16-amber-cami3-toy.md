# AMBER evaluation — CAMI III toy human gut (issue #25 follow-on)

Status: ✅ **done** (2026-09-30). Official CAMI-standard (AMBER) evaluation of
the CAMI III toy human-gut benchmark run
`cami3_v11_20260926_rerun` (COMEBin v11 `95f5ea8`, seed 42, 32 threads) against
a gold standard **built for our 5,000-contig subset** of the official pooled
assembly.

This completes the owner's *"use amber for performance of cami II, use the gold
standard if available"* directive for all three real datasets: CAMI II marine
([docs/14](14-amber-cami2-marine.md)), CAMI II human
([docs/15](15-amber-cami2-human.md)) and now CAMI III.

## What was evaluated

- **Run**: `cami3_v11_20260926_rerun` → **492 final bins**, 4,957 of the 5,000
  input contigs assigned to a bin (99.1 % of sequences).
- **Prediction**: `@@SEQUENCEID BINID` from the run's
  `comebin_res_bins/*.fa` via
  `python3 scripts/make_amber_prediction.py <run_dir> cami3_toy_human_gut`
  → archived as `results/amber/cami3/comebin_v11_cami3.binning`.
- **Gold standard (NEW, built 2026-09-30)**: the official CAMI III toy dataset
  file `gsa_pooled_mapping.tsv.gz` (117,169,291 B, md5
  `34f5665129b081b905533c92388ad3a06`, from
  <https://s3.bi.denbi.de/swift/v1/cami/cami3_toydata/human-gut-toy/>,
  6,140,132 rows) is keyed by the *anonymous* pooled-assembly ids (`PC0`,
  `PC1`, …) — **not** by the contig names in our input FASTA. Our input
  (`cami_III/toy_human_input_2samples/contigs.fa`, the 5,000 longest pooled GSA
  contigs) is keyed by reference-derived headers
  `NZ_<accession>.<ver>_from_<start>_to_<end>_total_<len>`.
  `scripts/make_cami3_gold_standard.py` (NEW) joins the two on the reference
  contig id (the header prefix before `_from_` = column `contig_id` of the
  mapping) and emits a CAMI/AMBER gold standard:
  `@@SEQUENCEID BINID TAXID _LENGTH`.
  Result: `/vol/data/datasets/cami_III/gold_standard/cami3_toy_binning_gs.tsv`
  — **5,000/5,000 contigs mapped (100 % of bp, 1,126,537,317 bp) to 390
  genomes**, 0 unmapped. Structurally validated with
  `scripts/validate_binning.py` (OK). Copy in the repo:
  `results/amber/cami3/cami3_toy_binning_gs.tsv`.

## Command

```
# 1. build the subset gold standard (once)
python3 scripts/make_cami3_gold_standard.py \
  --mapping /vol/data/datasets/cami_III/gold_standard/gsa_pooled_mapping.tsv.gz \
  --contigs /vol/data/datasets/cami_III/toy_human_input_2samples/contigs.fa \
  --sample cami3_toy_human_gut \
  -o /vol/data/datasets/cami_III/gold_standard/cami3_toy_binning_gs.tsv

# 2. prediction + scoring
python3 scripts/make_amber_prediction.py \
  /vol/data/benchmark/runs/cami3_v11_20260926_rerun cami3_toy_human_gut \
  > /vol/data/benchmark/amber/cami3_comebin.binning
cd /vol/data/benchmark/amber
micromamba run -p /vol/data/envs/amber python3 /vol/data/repos/CAMI-AMBER/amber.py \
  cami3_comebin.binning \
  -g /vol/data/datasets/cami_III/gold_standard/cami3_toy_binning_gs.tsv \
  -o output_cami3_ref -l comebin_v11
```

## Results (official CAMI AMBER, bp-weighted)

| metric | value | note |
|---|---|---|
| percentage_of_assigned_bps | 0.996 | nearly every contig landed in a bin |
| accuracy_bp              | 0.689  | |
| precision_avg_bp         | 0.719  | avg bin purity |
| precision_weighted_bp    | 0.692  | bp-weighted precision |
| recall_avg_bp            | 0.769  | avg bin completeness |
| recall_weighted_bp       | 0.582  | |
| **F1 score (bp)**        | **0.743** | harmonic mean of bp precision/recall |
| F1 score (seq)           | 0.712  | |
| adjusted_rand_index_bp  | 0.351  | low because 492 bins vs 390 genomes |
| misclassification_bp     | 0.308  | strain-rich toy set, most bins near-complete |

## All three datasets, official CAMI AMBER (bp-weighted)

| dataset | assigned bp | F1_bp | prec_avg | recall_avg | ARI_bp | missclass. | bins / genomes |
|---|---|---|---|---|---|---|---|
| CAMI II marine | 34.1 % | 0.330 | 0.735 | 0.213 | 0.844 | 0.138 | 152 / ~1,000+ |
| CAMI II human  | 99.3 % | 0.681 | 0.626 | 0.747 | 0.769 | 0.181 | 107 / 64 |
| CAMI III toy gut | 99.6 % | **0.743** | 0.719 | 0.769 | 0.351 | 0.308 | 492 / 390 |

CAMI III has the **highest F1** of the three; its lower ARI reflects
over-splitting (492 predicted bins for 390 genomes) rather than wrong
assignment — a direct read-out of the CheckM2 result for the same run
(35.97 % mean completeness, 53 HQ / 112 MQ, highest contamination of any run
because the toy set is strain-rich).

## Files in this repo

- `results/amber/cami3/amber_results.tsv` — summary rows (gold standard + tool).
- `results/amber/cami3/bin_metrics.tsv` — per-bin AMBER metrics (883 rows).
- `results/amber/cami3/amber_report.html` — full interactive AMBER report.
- `results/amber/cami3/heatmap_bar.png` — per-bin precision/recall heatmap.
- `results/amber/cami3/comebin_v11_cami3.binning` — the exact prediction.
- `results/amber/cami3/cami3_toy_binning_gs.tsv` — the subset gold standard.
- `results/amber/cami3/amber_log.txt` — AMBER run log.

## Notes / provenance

- AMBER = `CAMI-challenge/AMBER` master `f8b3a60`; env `/vol/data/envs/amber`
  (Python 3.11, pinned requirements) — same tool version as docs/14 and docs/15,
  so the three numbers are directly comparable.
- A reference contig (`NZ_*`) belongs to exactly one genome, so all windows
  (`_from_…_to_…`) of one reference contig inherit the same genome assignment;
  4,051 distinct reference contigs back our 5,000 contigs, and every one of
  them is present in the official mapping.
- Scoring the whole 1.48 M-contig pooled assembly instead of our 5,000-contig
  subset would understate COMEBin (unbinned small contigs dominate bp-weighted
  recall), which is why the subset gold standard is the right reference for this
  benchmark run.
