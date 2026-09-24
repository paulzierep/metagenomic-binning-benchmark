<!--AGENT-STATUS-->

> 🟢 **Agent status:** `running` · ⏱ `2026-09-24T06:56 CEST` · 🏃 train baseline_rerun_autorestart1: epoch 114/200 · loss 2.9342925548553467 · top1 97.84504699707031 · 🧠 `mimo-v2.6-flash-free` · [status.log](status/status.log)

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

One row per recorded attempt, including launches refused before any CPU was
used. Run links point to the tracked evidence mirrors. Refused watchdog launches
are retained in `/vol/data/benchmark/logs/*.launch.log` and
[`status/supervisor-run.log`](status/supervisor-run.log); the first `small_test`
directory was later reused, so its surviving evidence is the timestamped
[`status/agent-run.log`](status/agent-run.log) entry. The status banner at the
top of this file is authoritative for the running row.

| Run / time (UTC) | Source | Result and cause | Next step |
|---|---|---|---|
| [`baseline_unmodified`](runs/baseline_unmodified/comebin_run.log) — 2026-09-23 14:36 → 21:42 | [987db95](https://github.com/paulzierep/COMEBin/commit/987db95d8d399f30b7c82a5f5f40ed6bfdc906c7) upstream | **Failed after epoch 175/200; no evaluation claimed.** Clustering had no hmmsearch marker `.seed` file (`FileNotFoundError` in `gen_seed_idx`) and `biolib` was not installed. | Installed `biolib`; committed missing-seed handling in [`586c7f7`](https://github.com/paulzierep/COMEBin/commit/586c7f72226171870615138687404767662c1225) and later crash fixes through [`904f649`](https://github.com/paulzierep/COMEBin/commit/904f649ef5cbb4582a6f0e5ec8b0b1f45778d85b); use a fresh clean run. |
| [`baseline_unmodified_autorestart1`](status/supervisor-run.log) — 2026-09-23 21:33 | [987db95](https://github.com/paulzierep/COMEBin/commit/987db95d8d399f30b7c82a5f5f40ed6bfdc906c7) + 4 dirty files | **No run, 0 CPU.** The pristine-baseline guard rejected the launch because the COMEBin worktree was modified. | Commit or revert the source edits before retrying; preserve the original failure evidence. |
| [`baseline_unmodified_autorestart2`](status/supervisor-run.log) — 2026-09-23 21:35 | [987db95](https://github.com/paulzierep/COMEBin/commit/987db95d8d399f30b7c82a5f5f40ed6bfdc906c7) + 4 dirty files | **No run, 0 CPU.** The same dirty-source guard blocked a non-reproducible baseline launch. | Stop duplicate no-CPU retries and restore a clean source tree. |
| [`baseline_unmodified_autorestart3`](status/supervisor-run.log) — 2026-09-23 21:40 | [987db95](https://github.com/paulzierep/COMEBin/commit/987db95d8d399f30b7c82a5f5f40ed6bfdc906c7) + 4 dirty files | **No run, 0 CPU.** The third attempt had the same refusal and exhausted the watchdog restart budget. | Let the watchdog classify the original terminal failure; use committed source only for the next baseline. |
| [`small_test` — first smoke](status/agent-run.log) — 2026-09-23 22:39:28 → 22:39:45 (17 s) | [586c7f7](https://github.com/paulzierep/COMEBin/commit/586c7f72226171870615138687404767662c1225) | **Failed during augmentation, exit 1.** `gen_cov.py` raised `KeyError: scaffold_22978`, a BAM-header reference absent from the 300-contig assembly. Because it failed before clustering, this run did **not** validate the missing-seed fix. This first use of the run name was later overwritten. | Commit the contig filter in [`47c1449`](https://github.com/paulzierep/COMEBin/commit/47c1449e874c366defe4470f1d43abf91fb8117c), then rerun under a fresh name. |
| [`small_test` — logged rerun](runs/small_test/comebin_run.log) — 2026-09-23 23:09:40 → 23:10:21 (41 s) | [ee2e507](https://github.com/paulzierep/COMEBin/commit/ee2e5079ae8fd04caa381486a4bba8c2d2a34a14) | **Failed, exit 1.** `get_kmer_coverage` indexed the 300-contig matrix with uninitialized values because `np.empty` left missing contig-to-k-mer positions unset, causing an out-of-bounds `IndexError`. | Replace `np.empty` with zero-initialized state in [`904f649`](https://github.com/paulzierep/COMEBin/commit/904f649ef5cbb4582a6f0e5ec8b0b1f45778d85b); rerun as `small_test_v2`. |
| [`small_test_v2`](runs/small_test_v2/comebin_run.log) — 2026-09-23 23:37:13 → 23:37:56 (43 s) | [904f649](https://github.com/paulzierep/COMEBin/commit/904f649ef5cbb4582a6f0e5ec8b0b1f45778d85b) | **Failed, exit 1.** After augmentation and epoch 0, `lengths[seq_id]` raised `KeyError`: `aug0_datacoverage_mean.tsv` contained all 29,434 BAM-header references instead of only the 300 input contigs. | Producer filtering and defensive alignment are committed on `comebin-small-fix` as [`5c77bc8`](https://github.com/paulzierep/COMEBin/commit/5c77bc87ce2c8a83be20016c8f62eb2d6b3feb88); the offline six-view test passes. After the baseline, run the end-to-end small gate and CheckM2/CheckM before building the medium set. |
| [`baseline_rerun`](runs/baseline_rerun/comebin_run.log) — 2026-09-24 00:15:46 → 00:25:46 (600 s) | [904f649](https://github.com/paulzierep/COMEBin/commit/904f649ef5cbb4582a6f0e5ec8b0b1f45778d85b) | **Failed, exit 143.** This was not a COMEBin exception: a foreground agent tool call imposed a 600 s timeout and sent `SIGTERM` after augmentation, the first feature pass and epoch 0. | Never launch a multi-hour baseline in a foreground tool call. Start it detached in a fresh directory, verify `.active_run`, and let `benchmark-watchdog.sh` own the handoff. |
| `baseline_rerun` — [retry 1](status/agent-run.log) — ~2026-09-24 00:26 | [904f649](https://github.com/paulzierep/COMEBin/commit/904f649ef5cbb4582a6f0e5ec8b0b1f45778d85b) | **No run, 0 CPU.** The overwrite guard correctly rejected the same-name retry because the timed run already had `run_meta.txt` and `comebin_out/`; the follow-up then deleted that directory instead of preserving it. | Never delete or overwrite a run directory. Keep its evidence and choose a fresh run name. |
| `baseline_rerun` — [retry 2](status/agent-run.log) — ~2026-09-24 00:29 | [904f649](https://github.com/paulzierep/COMEBin/commit/904f649ef5cbb4582a6f0e5ec8b0b1f45778d85b) | **No run, 0 CPU.** `.active_run` still referenced the failed wrapper (`pid=262046`) for the reused path, so the overlap guard refused another launch. | Run `benchmark-watchdog.sh`; at 00:30 it classified exit 143, cleared the stale registration and launched `baseline_rerun_autorestart1`. |
| [`baseline_rerun_autorestart1`](runs/baseline_rerun_autorestart1/comebin_run.log) — 2026-09-24 00:30 → **running** | [904f649](https://github.com/paulzierep/COMEBin/commit/904f649ef5cbb4582a6f0e5ec8b0b1f45778d85b) | **In progress.** The watchdog-managed run is advancing normally from an immutable committed snapshot with the crash-only fixes, 32 threads and `--earlystop`; live epoch/loss/accuracy are in the top banner. | On clean exit, run `scripts/run_eval.sh` for CheckM2 + CheckM v1 and fill the performance table; then run the queued end-to-end small test without overlapping timed runs. |

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
