<!--AGENT-STATUS--> **Agent status** `2026-09-23T14:33:53Z UTC` · alive=`yes` · Staging dependency install into /vol/data/envs/comebin (scanpy tier solving; hnswlib + checkm-genome queued). Then: BAM index check -> baseline COMEBin run -> CheckM2/CheckM eval -> README table + PROGRESS.md update.
# metagenomic-binning-benchmark

Benchmarking metagenomic genome binners, starting with
[COMEBin](https://github.com/paulzierep/COMEBin), with bin quality scored by
**CheckM2** and **CheckM (v1)**.

## Goal

1. Run a **baseline benchmark of unmodified COMEBin** on the official demo dataset.
2. **Modify COMEBin** (bug fixes + performance improvements) on a branch, in batches —
   **one commit per batch**, re-running the benchmark after each batch.
3. Record for every run: dataset, exact parameters, wall-clock/CPU time, and
   CheckM2/CheckM quality metrics — so results are comparable across commits.

## Where everything lives (this machine)

All data, repos and results are on the `/vol/data` volume (492 GB disk):

| Path | Content |
|---|---|
| `/vol/data/repos/COMEBin` | pristine upstream clone (baseline source, commit recorded per run) |
| `/vol/data/repos/metagenomic-binning-benchmark` | this repo |
| `/vol/data/datasets/` | datasets (`comebin_test_data/`, later `cami_II/`, `cami_III/`) |
| `/vol/data/envs/` | micromamba environments (`comebin`, later `checkm2`, `checkm`) |
| `/vol/data/tools/bin/micromamba` | micromamba 2.9.0 |
| `/vol/data/benchmark/runs/` | raw outputs, one directory per run |
| `/vol/data/benchmark/results/` | parsed result tables |
| `/vol/data/benchmark/logs/` | install/run/watchdog logs |
| `/vol/data/benchmark/PROGRESS.md` | live resume document for the agent |
| `/vol/data/benchmark/TASK_COMPLETE` | sentinel — watchdog stops when present |

## Repository layout

```
docs/
  00-setup.md          environment, tools, watchdog/agent restart design
  01-datasets.md       dataset provenance, checksums, preparation
  02-comebin-baseline.md  baseline run: command, parameters, timings, results
  03-fixes.md          fix batches: one section per commit on the branch
  04-evaluation.md     CheckM2 + CheckM procedure and metric definitions
scripts/
  agent-watchdog.sh    cron watchdog: restarts agent on abort/quota, model rotation
  run_comebin_baseline.sh  reproducible baseline runner
  run_eval.sh          CheckM2 + CheckM evaluation runner
envs/                  exported environment YAMLs
results/               committed result tables (CSV/MD), one file per run
PROGRESS.md            resume state (mirrors /vol/data/benchmark/PROGRESS.md)
```

## Benchmark runs — performance

Living table: **one row per benchmark run**, updated by the agent immediately after
each run (timings from `runs/<run>/run_meta.txt` + stage timings in the run log;
quality from the CheckM2/CheckM evaluation — see `docs/04-evaluation.md`).
Raw per-run outputs stay in `/vol/data/benchmark/runs/`, parsed CSVs in `results/`.

| Run | Date | Source commit | Dataset | Threads | Wall time | Peak RAM | Bins | CheckM2 comp/cont % | CheckM comp/cont % | Status |
|---|---|---|---|---|---|---|---|---|---|---|
| `baseline_unmodified` | – | [987db95](https://github.com/paulzierep/COMEBin/commit/987db95d8d399f30b7c82a5f5f40ed6bfdc906c7) (upstream) | COMEBin demo (29,434 contigs) | 32 | – | – | – | – | – | ⏳ env finishing, next step |

Column contract: **Wall time** = total seconds (plus per-stage breakdown in
`docs/02-comebin-baseline.md`), **Bins** = bins exported (≥200 kb filter noted),
**comp/cont** = mean completeness / mean contamination, **HQ/MQ counts** live in
`results/<run>.csv`. **Source commit** is always a clickable link to that exact
commit on GitHub. Fix batches on `comebin-optimizations` get one row each, so
performance deltas vs. baseline are visible directly in this table.

## Branch strategy

- `main` — documentation, harness scripts, result tables.
- `comebin-optimizations` — COMEBin source changes, **batched fixes, one commit per
  batch**; benchmark run recorded in the commit message and in `results/`.

## How to resume (for a human or a restarted agent)

1. Read [`PROGRESS.md`](PROGRESS.md) — it contains the full task definition and the
   current state checklist.
2. Verify the checklist against what is on disk under `/vol/data`.
3. Continue from the first unfinished item; update `PROGRESS.md` after each step.

See [`docs/00-setup.md`](docs/00-setup.md) for the agent watchdog that performs
automatic restart + free-model rotation on token exhaustion.

## References

- Wang Z. et al. *Effective binning of metagenomic contigs using contrastive
  multi-view representation learning.* Nat Commun 15, 585 (2024).
- Parks D.H. et al. *CheckM...* Genome Res 25(7):1043–1055 (2015). (CheckM v1)
- Chklovsky A. et al. *CheckM2...* Nat Biotechnol (2024). (CheckM2)
