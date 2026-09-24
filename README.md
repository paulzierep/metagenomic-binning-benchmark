<!--AGENT-STATUS-->

> 🟢 **Agent status:** `running` · ⏱ `2026-09-24T08:34 CEST` · 🏃 train baseline_rerun_autorestart1: epoch 157/200 · loss 2.872771739959717 · top1 98.57096099853516 · 🧠 `mimo-v2.6-flash-free` · [status.log](status/status.log)

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

Seven COMEBin-executing attempts have been recorded: six terminal failures and
one active run. No successful end-to-end benchmark or CheckM evaluation has been
recorded yet. Run links point to tracked evidence mirrors. The first two
`small_test` directories were later reused, and the raw `baseline_rerun`
directory now contains only the final refusal's `out.txt`; their earlier evidence
survives in [`status/agent-run.log`](status/agent-run.log) and the Git mirror.
The status banner at the top of this file is authoritative for the active run.

### COMEBin-executing attempts

| Run / time (UTC) | Source | Result and cause | Next step |
|---|---|---|---|
| [`baseline_unmodified`](runs/baseline_unmodified/comebin_run.log) — 2026-09-23 14:36:06 → 21:30:28; watchdog classified 21:42:31 | [987db95](https://github.com/paulzierep/COMEBin/commit/987db95d8d399f30b7c82a5f5f40ed6bfdc906c7) upstream | **Failed after epoch 175/200; no bins or evaluation.** `test_getmarker_2quarter.pl` produced no `.seed`, then `cluster.py:368` unconditionally read it and raised `FileNotFoundError`; `get_result` then hit `ModuleNotFoundError: biolib`. | `biolib` import is now verified. [`586c7f7`](https://github.com/paulzierep/COMEBin/commit/586c7f72226171870615138687404767662c1225) hardens the later `gen_seed_idx` call but does not fix the observed line-368 read; fix and verify that read on a future clean run before claiming clustering success. |
| [`small_test` — attempt 1](status/agent-run.log) — 2026-09-23 22:39:28 → 22:39:45 (17 s) | [586c7f7](https://github.com/paulzierep/COMEBin/commit/586c7f72226171870615138687404767662c1225) | **Failed during augmentation, exit 1.** `gen_cov.py` raised `KeyError: scaffold_22978`, a BAM-header reference absent from the 300-contig assembly. It failed before clustering, so it did not validate the seed change. | Commit the contig filter in [`47c1449`](https://github.com/paulzierep/COMEBin/commit/47c1449e874c366defe4470f1d43abf91fb8117c), then rerun under a fresh name. |
| [`small_test` — attempt 2](status/agent-run.log) — ~2026-09-23 23:08:34 → 23:09:05 (31 s) | [47c1449](https://github.com/paulzierep/COMEBin/commit/47c1449e874c366defe4470f1d43abf91fb8117c) | **Failed during augmentation, exit 1.** The mean-coverage filter worked, but `gen_var.py` raised the equivalent `KeyError` for the same extra scaffold and its expected variance CSV was absent. | Apply the matching `gen_var.py` filter in [`ee2e507`](https://github.com/paulzierep/COMEBin/commit/ee2e5079ae8fd04caa381486a4bba8c2d2a34a14), then rerun under a fresh name. |
| [`small_test` — attempt 3](runs/small_test/comebin_run.log) — 2026-09-23 23:09:40 → 23:10:21 (41 s) | [ee2e507](https://github.com/paulzierep/COMEBin/commit/ee2e5079ae8fd04caa381486a4bba8c2d2a34a14) | **Failed, exit 1.** `get_kmer_coverage` indexed the 300-contig matrix with uninitialized values because `np.empty` left missing contig-to-k-mer positions unset, causing an out-of-bounds `IndexError`. | Replace `np.empty` with zero-initialized state in [`904f649`](https://github.com/paulzierep/COMEBin/commit/904f649ef5cbb4582a6f0e5ec8b0b1f45778d85b); rerun as `small_test_v2`. |
| [`small_test_v2`](runs/small_test_v2/comebin_run.log) — 2026-09-23 23:37:13 → 23:37:56 (43 s) | [904f649](https://github.com/paulzierep/COMEBin/commit/904f649ef5cbb4582a6f0e5ec8b0b1f45778d85b) | **Failed before completing epoch 0, exit 1.** `lengths[seq_id]` raised `KeyError`: `aug0_datacoverage_mean.tsv` contained all 29,434 BAM-header references instead of only the 300 input contigs. | Producer filtering and defensive alignment are committed on `comebin-small-fix` as [`5c77bc8`](https://github.com/paulzierep/COMEBin/commit/5c77bc87ce2c8a83be20016c8f62eb2d6b3feb88); the offline six-view test passes. After the baseline, run the end-to-end small gate and CheckM2/CheckM before building the medium set. |
| [`baseline_rerun` — attempt 1](runs/baseline_rerun/comebin_run.log) — 2026-09-24 00:15:46 → 00:25:46 (600 s) | [904f649](https://github.com/paulzierep/COMEBin/commit/904f649ef5cbb4582a6f0e5ec8b0b1f45778d85b) | **Failed, exit 143.** This was not a COMEBin exception: a foreground agent tool call imposed a 600 s timeout and sent `SIGTERM` after epoch 0 was logged and the next epoch started. | Never launch a multi-hour baseline in a foreground tool call. Start it detached in a fresh directory, verify `.active_run`, and let `benchmark-watchdog.sh` own the handoff. |
| [`baseline_rerun_autorestart1`](runs/baseline_rerun_autorestart1/comebin_run.log) — 2026-09-24 00:30:01 → **running** | [904f649](https://github.com/paulzierep/COMEBin/commit/904f649ef5cbb4582a6f0e5ec8b0b1f45778d85b) | **In progress.** The watchdog-managed run is advancing from an immutable snapshot and has not reached clustering; live epoch/loss/accuracy are in the top banner. No exit code, bins, or evaluation exist yet. | On clean exit, run `scripts/run_eval.sh` for CheckM2 + CheckM v1 and fill the performance table. If the line-368 seed read recurs, fix and verify it before rerunning; then run the queued small test without overlap. |

### Guard-only launches

Twelve launches stopped before COMEBin started. They are grouped by episode so
refusals are not mistaken for benchmark runs; raw watchdog refusals remain in
`/vol/data/benchmark/logs/*.launch.log`.

| Episode / time (UTC) | Count | Cause | Next step |
|---|---:|---|---|
| [`baseline_unmodified_autorestart1/2/3`](status/supervisor-run.log) — 21:33, 21:35, 21:40 | 3 | Pristine-baseline guard rejected commit `987db95` plus four dirty files. | Restore a clean committed source tree before retrying. |
| [Default-path baseline before the rerun](status/agent-run.log) — shortly before 00:15 | 1 | Existing `runs/baseline_unmodified` directory blocked an overwrite. | Pass a fresh explicit run directory. |
| [Small-test preflight before attempt 1](status/agent-run.log) — ~22:39 | 2 | Dirty-source guard rejected the uncommitted seed change. | Commit or clean the source before running. |
| [Small-test preflight before attempt 2](status/agent-run.log) — ~23:08 | 1 | Existing `runs/small_test` directory blocked an overwrite. | Use a fresh run name; preserve the prior evidence. |
| [Small-test preflight before attempt 3](status/agent-run.log) — ~23:09 | 2 | Start lock was held, then stale failed registration `pid=239956` blocked launch. | Do not delete lock/state files manually; let the benchmark watchdog triage them. |
| [Small-test-v2 preflight](status/agent-run.log) — ~23:37 | 1 | Dirty-source guard rejected the uncommitted `np.zeros` fix. | Commit or clean the source before running. |
| [`baseline_rerun` retry 1](status/agent-run.log) — ~00:26 | 1 | Existing timed-run artifacts blocked same-name overwrite; the follow-up then deleted the directory. | Never delete a run directory; preserve evidence and choose a fresh name. |
| [`baseline_rerun` retry 2](status/agent-run.log) — ~00:29 | 1 | `.active_run` still referenced failed wrapper `pid=262046` for the reused path. | Let `benchmark-watchdog.sh` classify exit 143 and perform the fresh-directory handoff. |

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
