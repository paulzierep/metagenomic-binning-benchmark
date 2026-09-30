# AMBER evaluation — CAMI II marine (issue #25 follow-on)

Status: ✅ **done** (2026-09-29). First official CAMI-standard evaluation of a
benchmark run, using [AMBER](https://github.com/CAMI-challenge/AMBER)
(`CAMI-challenge/AMBER`, cloned at `/vol/data/repos/CAMI-AMBER`) against the
official CAMI II marine gold standard.

## What was evaluated

- **Run**: `marine_v11_20260925` (COMEBin `95f5ea8`, v11 branch, seed 42,
  32 threads, 41,988 contigs) → 152 final bins.
- **Prediction**: `@@SEQUENCEID BINID` derived from
  `comebin_out/comebin_res/comebin_res_bins/*.fa` (40,210 contigs assigned to
  152 bins).
- **Gold standard**: official CAMI II marine `binning_gs.tsv`
  (`@Version:0.9.1`, `@SampleID:marine`, `@@SEQUENCEID BINID TAXID _LENGTH`,
  1,475,976 rows of `S0C* → Otu*`) from
  `/vol/data/datasets/cami_II/marine_reads/.../contigs/binning_gs.tsv`.

## Command

```
micromamba run -p /vol/data/envs/amber python3 CAMI-AMBER/amber.py \
  amber/marine_comebin.binning -g <binning_gs.tsv> -o output_marine -l comebin_v11
```

Inputs/outputs: `/vol/data/benchmark/amber/` (env `/vol/data/envs/amber`).
The prediction is regenerable with `scripts/make_amber_prediction.py
<run_dir> <sample_id>` and is archived here as
`results/amber/marine/comebin_v11_marine.binning` (regenerated + AMBER re-run
canonically on 2026-09-29; results.tsv below is from that canonical run).

## Results (comebin_v11 vs marine gold standard)

| metric (bp-weighted) | value | note |
|---|---|---|
| percentage_of_assigned_bps | 34.09 % | of the 41,988 contigs' bp assigned to a bin |
| accuracy_bp              | 0.294  | accuracy (assigned + correct) |
| precision_avg_bp         | 0.735  | avg bin purity |
| precision_weighted_bp    | 0.862  | seq-weighted precision |
| recall_avg_bp            | 0.213  | avg bin completeness |
| recall_weighted_bp       | 0.296  | seq-weighted recall |
| F1 score (bp)            | 0.330  | harmonic mean precision/recall (bp) |
| ARI (bp)                 | 0.844  | adjusted Rand index |
| misclassification_bp     | 0.138  | contamination rate |

Sequence-level equivalents in `results/amber/marine/amber_results.tsv`
(e.g. `f1_score_seq 0.267`, `accuracy_seq 0.019` — a minority of contigs are
binned at all at sequence-level because COMEBin keeps large contigs: only
2.7 % of sequences, 34 % of bp).

## Files in this repo

- `results/amber/marine/amber_results.tsv` — summary row (all metrics).
- `results/amber/marine/bin_metrics.tsv` — per-bin AMBER metrics.
- `results/amber/marine/amber_report.html` — full interactive AMBER report
  (Heatmap + per-bin tables).
- `results/amber/marine/heatmap_bar.png` — per-bin precision/recall heatmap.

## Notes / provenance

- AMBER 1.x (CAMI-challenge/AMBER, master `f8b3a60`), Python 3.11 env
  `/vol/data/envs/amber` (requirements.txt pinned).
- The prediction file only lists contigs kept in ≥1 of the 152 bins; unassigned
  contigs are therefore not "perfect-match" noise — AMBER treats them as
  unassigned, so `percentage_of_assigned_*` reflects real COMEBin assignment.
- This is the marine run's official CAMI benchmark number; the human + CAMI III
  evaluations are now done too — [docs/15](15-amber-cami2-human.md) (F1_bp
  0.681) and [docs/16](16-amber-cami3-toy.md) (F1_bp 0.743), so all three
  datasets are scored with the same AMBER version.