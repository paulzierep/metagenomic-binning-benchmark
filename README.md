<!--AGENT-STATUS-->

> 🟢 **Agent status:** `running` · ⏱ `2026-09-24T06:43 CEST` · 🏃 train baseline_rerun_autorestart1: epoch 108/200 · loss 2.972137451171875 · top1 97.77668762207031 · 🧠 `mimo-v2.6-flash-free` · [status.log](status/status.log)

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

## Repository layout

```
docs/
  00-setup.md          environment, tools, watchdog/agent restart design
  01-datasets.md       dataset provenance, checksums, preparation
  02-comebin-baseline.md  baseline run: command, parameters, timings, results
  03-fixes.md          fix batches: one section per commit on the branch
  04-evaluation.md     CheckM2 + CheckM procedure and metric definitions
  09-optimization-strategy.md  optimization strategy + decision flowchart (issues #6/#7)
  10-data-preservation.md       Zenodo release checklist and provenance manifest
scripts/
  agent-watchdog.sh    cron watchdog: restarts agent on abort/quota, model rotation
  run_comebin_baseline.sh  reproducible baseline runner
  run_eval.sh          CheckM2 + CheckM evaluation runner
  make_release_manifest.py  streaming SHA-256 manifest for dataset releases
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
| `baseline_unmodified` | 2026-09-23 | [987db95](https://github.com/paulzierep/COMEBin/commit/987db95d8d399f30b7c82a5f5f40ed6bfdc906c7) (upstream) | COMEBin demo (29,434 contigs) | 32 | – | – | – | – | – | ⏹ failed at epoch 175/200 — see [Run history](#run-history--what-happened-and-whats-next) |

Column contract: **Wall time** = total seconds (plus per-stage breakdown in
`docs/02-comebin-baseline.md`), **Bins** = bins exported (≥200 kb filter noted),
**comp/cont** = mean completeness / mean contamination, **HQ/MQ counts** live in
`results/<run>.csv`. **Source commit** is always a clickable link to that exact
commit on GitHub. Fix batches on `comebin-optimizations` get one row each, so
performance deltas vs. baseline are visible directly in this table.

## Run history — what happened and what's next

One row per run attempt: exactly why it ended (or whether it is still going) and
the concrete next step. Kept current by the agent; raw evidence lives in each
run's `runs/<run>/run_meta.txt` + `comebin_run.log`.

| Run | Time (UTC) | Source | Result | What happened / why | Next step |
|---|---|---|---|---|---|
| `baseline_unmodified` | 2026-09-23 14:36 → 21:42 | [987db95](https://github.com/paulzierep/COMEBin/commit/987db95d8d399f30b7c82a5f5f40ed6bfdc906c7) upstream | **failed** at epoch 175/200 (no evaluation claimed) | Training ran 7 h; clustering then crashed twice over: hmmsearch `--cut_tc` found no marker hits so the `.seed` file was never written (`FileNotFoundError` in `gen_seed_idx`), and `biolib` was not installed (`ModuleNotFoundError`) → "Something went wrong with running clustering." Watchdog recorded the terminal reason instead of silently retrying. | Installed `biolib`; committed the graceful-missing-seed fix (`gen_seed_idx` → empty seed list) plus `np.zeros`/`gen_cov` crash fixes; launched the baseline rerun below. |
| `baseline_rerun` (refused launch) | 2026-09-24 00:29 | [904f649](https://github.com/paulzierep/COMEBin/commit/904f649ef5cbb4582a6f0e5ec8b0b1f45778d85b) | **no run** (guard worked) | Overlap guard refused to start a second run while a stale registration (`pid=262046`) existed — logged in `out.txt`, zero CPU spent. | Superseded one minute later by `baseline_rerun_autorestart1`; stale registration cleared by the watchdog. |
| `baseline_rerun_autorestart1` | 2026-09-24 00:30 → **running** | [904f649](https://github.com/paulzierep/COMEBin/commit/904f649ef5cbb4582a6f0e5ec8b0b1f45778d85b) | **in progress** — epoch 108/200 @ 04:40, loss 3.58 ↓, Top1 84 %, no errors | Watchdog-managed rerun on an immutable snapshot (crash fixes only: seed-file handling, `biolib`, `np.zeros`, `gen_cov`/`gen_var` KeyErrors); 32 threads, `--earlystop` armed. | ⏳ running · epoch 108/200 · loss 2.972137451171875 · top1 97.77668762207031 |
| `small_test` | 2026-09-23 23:12 → 23:13 (41 s) | [ee2e507](https://github.com/paulzierep/COMEBin/commit/ee2e5079ae8fd04caa381486a4bba8c2d2a34a14) | **failed**, exit 1 | Earlier attempt hit `gen_cov.py` `KeyError: scaffold_22978` (BAM header reference absent from the 300-contig assembly) — fixed in `47c1449`; rerun then died in `get_kmer_coverage` with `IndexError: index … out of bounds for axis 0 with size 300` because `np.empty` left the contig→kmer index array uninitialized when a name was missing. | `np.empty` → `np.zeros` committed as `904f649`; rerun as `small_test_v2`. |
| `small_test_v2` | 2026-09-23 23:39 → 23:40 (43 s) | [904f649](https://github.com/paulzierep/COMEBin/commit/904f649ef5cbb4582a6f0e5ec8b0b1f45778d85b) | **failed**, exit 1 | Past augmentation + 1 epoch, then `KeyError: 'BATS…scaffold_22978'` at `train_CLmodel.py:46`. Root cause: `aug0_datacoverage_mean.tsv` carried **29,434 rows — every BAM header reference** (`bedtools genomecov -bga` emits zero-depth rows for all refs; the aug0 `calculate_coverage` path had no input-contig filter) — while the small assembly has 300 contigs, so `lengths[seq_id]` missed. | Producer filter + defensive feature alignment committed on branch `comebin-small-fix` ([`5c77bc8`](https://github.com/paulzierep/COMEBin/commit/5c77bc8)); offline 300-contig/6-view feature test passes. **Next:** end-to-end rerun immediately after the baseline completes (no overlapping timed runs), then CheckM2/CheckM — this is the validation gate for the medium dataset. |

## Branch strategy

- `main` — documentation, harness scripts, result tables.
- `comebin-optimizations` — COMEBin source changes, **batched fixes, one commit per
  batch**; benchmark run recorded in the commit message and in `results/`.

## Optimization strategy

See [`docs/09-optimization-strategy.md`](docs/09-optimization-strategy.md) for the
decision-gate flowchart: every optimization batch is compared against the baseline
(timing + RAM + CheckM2/CheckM v1 + CAMI-style F1), committed only if it keeps or
improves quality, with ideas combined after failures.

## Data preservation and Zenodo

Newly generated benchmark data is staged for preservation with a streaming
SHA-256 manifest and a provenance/license checklist. The current release plan,
required owner inputs, and upload verification steps are in
[`docs/10-data-preservation.md`](docs/10-data-preservation.md). No Zenodo upload
is performed by the watchdogs; a verified DOI must be recorded before an issue
is considered fully addressed.

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
