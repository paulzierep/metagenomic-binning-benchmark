# results/

Committed benchmark result tables — **one aggregate CSV per benchmark run**, plus
small per-bin CSVs where available. Raw tool outputs stay in
`/vol/data/benchmark/runs/<run>/` (not committed).

The aggregate column contract is defined in `docs/04-evaluation.md`. Every row
states:

- `run` id, `source_commit` (of the COMEBin code used), `dataset`, `threads`,
  wall-clock time, `n_bins`,
- CheckM2 mean completeness/contamination + HQ/MQ counts,
- CheckM v1 mean completeness/contamination + HQ/MQ counts.

Current completed aggregate tables:

- [`baseline_rerun_autorestart1.csv`](baseline_rerun_autorestart1.csv)
- [`small_test_v4.csv`](small_test_v4.csv)
- [`medium_v11_20260924.csv`](medium_v11_20260924.csv)

The medium per-bin CheckM2 table is
[`medium_v11_20260924_checkm2_stats.csv`](../medium_v11_20260924_checkm2_stats.csv).
It is a reporting supplement; the aggregate CSV remains the canonical run row.
After writing a CSV here, update the corresponding row in
[`docs/11-run-results.md`](../docs/11-run-results.md) and push.
