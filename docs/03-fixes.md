# 03 — Fix batches (branch `comebin-optimizations`)

Workflow: fixes are applied to the COMEBin source **in batches**, one commit per batch
on branch `comebin-optimizations`. After **every** batch the full benchmark re-runs and
results land in `results/` + the table at the bottom of this file.

Candidate issues from the source review are listed in `PROGRESS.md` ("Known COMEBin
bugs / perf issues"). Grouping plan (proposed — adjust as evidence comes in):

| Batch | Theme | Candidates (PROGRESS.md #) | Benchmark |
|---|---|---|---|
| 0 | *baseline* — no changes | — | `results/baseline_unmodified.*` |
| 1 | Correctness: coverage precision (`int`→`float`), bin numbering | 3, 4 | TBD |
| 2 | Reproducibility: RNG seeds (augmentation, Leiden, torch/numpy) | 5 | TBD |
| 3 | Robustness: small-dataset crash, makedirs, shell hygiene, topk | 6, 7, 8, 9 | TBD |
| 4 | Perf: closed-form coverage/var (no per-base lists) | 11 | TBD |
| 5 | Perf: vectorized k-mer counting | 10 | TBD |
| 6 | Perf: set-based lookups + single-read TSV loading, Leiden sweep | 12, 13, 14 | TBD |

(Each batch must keep results *comparable*: same dataset, same parameters as baseline;
for seeded runs note that batch 2 intentionally changes the RNG regime — record both
pre/post-seed numbers.)

---

## Batch log

### Batch 0 — baseline (no changes)

- Source: pristine upstream, commit: `__fill__`
- Results: `results/baseline_unmodified.{csv,md}`
- Notes: __fill__

<!-- ### Batch 1 — <title>
- Commit: `<sha>` — message:
- Changed files:
- Benchmark: `results/batch1_*.csv`
- Impact vs baseline (time, bins, completeness/contamination):
-->
