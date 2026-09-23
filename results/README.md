# results/

Committed benchmark result tables — **one CSV(+MD) per benchmark run**.
Raw tool outputs stay in `/vol/data/benchmark/runs/<run>/` (not committed).

Column contract is defined in `docs/04-evaluation.md`. Every row must state:

- `run` id, `source_commit` (of the COMEBin code used), `dataset`, `threads`,
  wall-clock time, `n_bins`,
- CheckM2 mean completeness/contamination + HQ/MQ counts,
- CheckM v1 mean completeness/contamination + HQ/MQ counts.

Current status: **no runs yet** — baseline is next (see `PROGRESS.md`).

After writing a CSV here, always also update the row in the
[Benchmark runs — performance table](../README.md#benchmark-runs--performance) and push.
