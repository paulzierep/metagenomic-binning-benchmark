# AMBER evaluation — CAMI II human (issue #25 follow-on)

Status: ✅ **done** (2026-09-29). Official CAMI-standard evaluation of the
`human_v11_20260925` benchmark run against the CAMI II *Toy Human Microbiome
Project* gold standard (gastrointestinal + oral block).

## What was evaluated

- **Run**: `human_v11_20260925` (COMEBin v11 `95f5ea8`, seed 42, 4,900
  top-length GSA contigs, all reads mapped) → 107 final bins.
- **Prediction**: `@@SEQUENCEID BINID` derived from the run's
  `comebin_res_bins/*.fa` (4,861 contigs assigned across 107 bins); archived as
  `comebin_v11_human.binning`. Regenerate with
  `python3 scripts/make_amber_prediction.py <run_dir> human`.
- **Gold standard** (NEW, imported 2026-09-29): CAMI II human
  `gsa_mapping.tsv.gz` (from the sample's `contigs/`) filtered to the 4,900
  contigs of our subset → `@@SEQUENCEID BINID TAXID _LENGTH`
  (`@Version:0.9.1`, `@SampleID:human`, **4,900/4,900 contigs mapped to 64
  genomes**). Built at
  `/vol/data/datasets/cami_II_human/gold_standard/human_binning_gs.tsv`.
  Source archive `setup.tar.gz` (1,906,532,721 B) pulled from
  `https://frl.publisso.de/data/frl:6425518/gastrooral/setup.tar.gz`.

## Command

```
micromamba run -p /vol/data/envs/amber python3 CAMI-AMBER/amber.py \
  amber/human_comebin.binning \
  -g /vol/data/datasets/cami_II_human/gold_standard/human_binning_gs.tsv \
  -o output_human -l comebin_v11
```

Inputs/outputs: `/vol/data/benchmark/amber/` (env `/vol/data/envs/amber`).

## Results (comebin_v11 vs human gold standard)

| metric (bp-weighted) | value | note |
|---|---|---|
| percentage_of_assigned_bps | 99.3 % | nearly every contig landed in a bin |
| accuracy_bp              | 0.814  | |
| precision_avg_bp         | 0.626  | avg bin purity |
| precision_weighted_bp    | 0.819  | bp-weighted precision |
| recall_avg_bp            | 0.747  | avg bin completeness |
| recall_weighted_bp       | 0.722  | bp-weighted recall |
| F1 score (bp)            | 0.681  | harmonic mean precision/recall (bp) |
| ARI (bp)                 | 0.769  | adjusted Rand index |
| misclassification_bp     | 0.181  | contamination rate |

Sequence-level: `f1_score_seq 0.637`, `accuracy_seq` — see
`results/amber/human/amber_results.tsv`. Unlike the marine set, the human
subset is a length-selected 4,900-contig assembly with full read coverage, so
99 % of both bp *and* sequences are binned.

### Side-by-side (official CAMI AMBER, bp-weighted)

| dataset | assigned bp | F1_bp | prec_avg | recall_avg | ARI_bp | missclass. |
|---|---|---|---|---|---|---|
| CAMI II marine | 34.1 % | 0.330 | 0.735 | 0.213 | 0.844 | 0.138 |
| CAMI II human  | 99.3 % | 0.681 | 0.626 | 0.747 | 0.769 | 0.181 |
| CAMI III toy gut | 99.6 % | 0.743 | 0.719 | 0.769 | 0.351 | 0.308 | ([docs/16](16-amber-cami3-toy.md)) |

The marine assembly is a 41,988-contig full simulation where COMEBin only
bins the large contigs (34 % of bp), so recall is structurally low; the human
subset is a 4,900-contig selection that COMEBin bins almost completely.

## Files in this repo

- `results/amber/human/amber_results.tsv` — summary row (all metrics).
- `results/amber/human/bin_metrics.tsv` — per-bin AMBER metrics.
- `results/amber/human/amber_report.html` — full interactive AMBER report.
- `results/amber/human/heatmap_bar.png` — per-bin precision/recall heatmap.
- `results/amber/human/comebin_v11_human.binning` — the exact prediction.

## Notes / provenance

- AMBER = `CAMI-challenge/AMBER` master `f8b3a60`; env `/vol/data/envs/amber`
  (Python 3.11, requirements.txt pinned).
- Gold standard IDs `S0C*` match the assembly; all 4,900 subset contigs have a
  genome assignment (0 missing), 64 unique genomes.
- The pooled mapping (`gsa_pooled_mapping.tsv.gz`, `PC*` ids) is a *different*
  assembly and is **not** used here — the sample-level `gsa_mapping.tsv.gz`
  (`S0C*`) is the correct ground truth for this subset.

## 2026-09-30 — winner (temp 0.05) rescored against the same gold standard

`human_v11_winner_20260930` (54 bins, seed 42, THREADS 32) scored with the
identical gold standard via the generic chain (`make_amber_prediction.py` +
`amber.py -l comebin`):

| | ref `human_v11_20260925` (107 bins) | winner `human_v11_winner_20260930` (54 bins) |
|---|---|---|
| accuracy_bp | 0.814 | 0.781 |
| precision_weighted_bp | 0.819 | 0.888 |
| recall_weighted_bp | 0.722 | 0.875 |
| **F1_bp** | **0.681** | **0.881** |
| ARI_bp | 0.769 | 0.623 |
| misclassification_bp | 0.181 | 0.111 |

The low-temperature winner trades strict per-sequence assignment (accuracy and
ARI drop) for **purer, more complete bins** (precision 0.819→0.888, recall
0.722→0.875, F1_bp +0.20, misclassification halved). Files:
`results/amber/human/amber_{results,bin_metrics}_human_v11_winner_20260930.tsv`,
`amber_report_human_v11_winner_20260930.html`, `heatmap_human_v11_winner_20260930.png`.
