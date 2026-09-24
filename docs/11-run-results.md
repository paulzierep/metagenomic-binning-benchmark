# Run results — full table

One row per benchmark run, updated by the agent after each run (timings from `runs/<run>/run_meta.txt` + stage timings in the run log; quality from the CheckM2/CheckM evaluation — see `docs/04-evaluation.md`). Raw per-run outputs stay in `/vol/data/benchmark/runs/`, parsed CSVs in `results/`.

| Run | Date | Source commit | Dataset | Threads | Wall time | Peak RAM | Bins | CheckM2 comp/cont % | CheckM comp/cont % | Status |
|---|---|---|---|---|---|---|---|---|---|---|
| `baseline_rerun_autorestart1` | 2026-09-24 | [904f649](https://github.com/paulzierep/COMEBin/commit/904f649ef5cbb4582a6f0e5ec8b0b1f45778d85b) | COMEBin demo (29,434 contigs) | 32 | 24,327 s | 5.42 GB | 60 | 25.01 / 2.98 | 21.23 / 3.40 | ✅ complete; 200/200 epochs |
| `small_test_v4` | 2026-09-24 | [c8f22e4](https://github.com/paulzierep/COMEBin/commit/c8f22e4935a66a0fd58b794489a9021671b15437) | `comebin_small` (300 contigs) | 8 | 122 s | 0.75 GB | 3 | 26.07 / 2.02 | 29.08 / 0.71 | ✅ functional gate passed |
| `medium_v11_20260924` | 2026-09-24 | [95f5ea8](https://github.com/paulzierep/COMEBin/commit/95f5ea820f9a4e76f5c2911c0b5ed507ab67b015) | `comebin_medium` (3,000 contigs) | 32 | 2,326 s | 10.69 GB | 16 | 35.93 / 4.67 | 33.83 / 6.03 | ✅ complete; 200/200 epochs, 61.23% Top1; [CSV](../results/medium_v11_20260924.csv) |
| `baseline_unmodified` | 2026-09-23 | [987db95](https://github.com/paulzierep/COMEBin/commit/987db95d8d399f30b7c82a5f5f40ed6bfdc906c7) (upstream) | COMEBin demo (29,434 contigs) | 32 | – | – | – | – | – | ⏹ failed at epoch 175/200 — see [Run history](#run-history--what-happened-and-whats-next) |

Column contract: **Wall time** = total seconds (plus per-stage breakdown in `docs/02-comebin-baseline.md`), **Bins** = bins exported (≥200 kb filter noted), **comp/cont** = mean completeness / mean contamination, **HQ/MQ counts** live in `results/<run>.csv`. **Source commit** is always a clickable link to that exact commit on GitHub. Per-bin CheckM2 values for the completed medium gate are in [`medium_v11_20260924_checkm2_stats.csv`](../medium_v11_20260924_checkm2_stats.csv).

## Run history — what happened and what's next

Ten COMEBin-executing attempts have been recorded: seven terminal failures and three completed runs. The baseline rerun, small functional gate, and medium derivative now have verified bin artifacts and CheckM2/CheckM outputs. Run links point to tracked evidence mirrors; the status banner at the top is authoritative for any active run.

### COMEBin-executing attempts

| Run / time (UTC) | Source | Result and cause | Next step |
|---|---|---|---|
| [`baseline_unmodified`](runs/baseline_unmodified/comebin_run.log) — 2026-09-23 14:36:06 → 21:30:28; watchdog classified 21:42:31 | [987db95](https://github.com/paulzierep/COMEBin/commit/987db95d8d399f30b7c82a5f5f40ed6bfdc906c7) upstream | **Failed after epoch 175/200; no bins or evaluation.** `test_getmarker_2quarter.pl` produced no `.seed`, then `cluster.py:368` unconditionally read it and raised `FileNotFoundError`; `get_result` then hit `ModuleNotFoundError: biolib`. | `biolib` import is now verified. [`586c7f7`](https://github.com/paulzierep/COMEBin/commit/586c7f72226171870615138687404767662c1225) hardens the later `gen_seed_idx` call but does not fix the observed line-368 read; fix and verify that read on a future clean run before claiming clustering success. |
| [`small_test` — attempt 1](status/agent-run.log) — 2026-09-23 22:39:28 → 22:39:45 (17 s) | [586c7f7](https://github.com/paulzierep/COMEBin/commit/586c7f72226171870615138687404767662c1225) | **Failed during augmentation, exit 1.** `gen_cov.py` raised `KeyError: scaffold_22978`, a BAM-header reference absent from the 300-contig assembly. It failed before clustering, so it did not validate the seed change. | Commit the contig filter in [`47c1449`](https://github.com/paulzierep/COMEBin/commit/47c1449e874c366defe4470f1d43abf91fb8117c), then rerun under a fresh name. |
| [`small_test` — attempt 2](status/agent-run.log) — ~2026-09-23 23:08:34 → 23:09:05 (31 s) | [47c1449](https://github.com/paulzierep/COMEBin/commit/47c1449e874c366defe4470f1d43abf91fb8117c) | **Failed during augmentation, exit 1.** The mean-coverage filter worked, but `gen_var.py` raised the equivalent `KeyError` for the same extra scaffold and its expected variance CSV was absent. | Apply the matching `gen_var.py` filter in [`ee2e507`](https://github.com/paulzierep/COMEBin/commit/ee2e5079ae8fd04caa381486a4bba8c2d2a34a14), then rerun under a fresh name. |
| [`small_test` — attempt 3](runs/small_test/comebin_run.log) — 2026-09-23 23:09:40 → 23:10:21 (41 s) | [ee2e507](https://github.com/paulzierep/COMEBin/commit/ee2e5079ae8fd04caa381486a4bba8c2d2a34a14) | **Failed, exit 1.** `get_kmer_coverage` indexed the 300-contig matrix with uninitialized values because `np.empty` left missing contig-to-k-mer positions unset, causing an out-of-bounds `IndexError`. | Replace `np.empty` with zero-initialized state in [`904f649`](https://github.com/paulzierep/COMEBin/commit/904f649ef5cbb4582a6f0e5ec8b0b1f45778d85b); rerun as `small_test_v2`. |
| [`small_test_v2`](runs/small_test_v2/comebin_run.log) — 2026-09-23 23:37:13 → 23:37:56 (43 s) | [904f649](https://github.com/paulzierep/COMEBin/commit/904f649ef5cbb4582a6f0e5ec8b0b1f45778d85b) | **Failed before completing epoch 0, exit 1.** `lengths[seq_id]` raised `KeyError`: `aug0_datacoverage_mean.tsv` contained all 29,434 BAM-header references instead of only the 300 input contigs. | Producer filtering and defensive alignment are committed on `comebin-small-fix` as [`5c77bc8`](https://github.com/paulzierep/COMEBin/commit/5c77bc87ce2c8a83be20016c8f62eb2d6b3feb88); the offline six-view test passes. After the baseline, run the end-to-end small gate and CheckM2/CheckM before building the medium set. |
| [`baseline_rerun` — attempt 1](runs/baseline_rerun/comebin_run.log) — 2026-09-24 00:15:46 → 00:25:46 (600 s) | [904f649](https://github.com/paulzierep/COMEBin/commit/904f649ef5cbb4582a6f0e5ec8b0b1f45778d85b) | **Failed, exit 143.** This was not a COMEBin exception: a foreground agent tool call imposed a 600 s timeout and sent `SIGTERM` after epoch 0 was logged and the next epoch started. | Never launch a multi-hour baseline in a foreground tool call. Start it detached in a fresh directory, verify `.active_run`, and let `benchmark-watchdog.sh` own the handoff. |
| [`small_test_v3`](runs/small_test_v3/comebin_run.log) — 2026-09-24 08:45:18 → 08:46:40 | [a0be243](https://github.com/paulzierep/COMEBin/commit/a0be243187c674b4e62b980ef100f8f2e8b83f54) | **Failed functional gate.** Training completed, but the small branch still had the pre-`358ddd8` KMeans call; `KMeans(n_jobs=-1)` raised `TypeError`, and the wrapper masked it as exit 0 with zero bins. | Apply the sklearn compatibility fix to `comebin-small-fix`; the runner now rejects zero-bin success. |
| [`baseline_rerun_autorestart1`](runs/baseline_rerun_autorestart1/comebin_run.log) — 2026-09-24 00:30:01 → 07:15:28 | [904f649](https://github.com/paulzierep/COMEBin/commit/904f649ef5cbb4582a6f0e5ec8b0b1f45778d85b) | **✅ Complete.** 200/200 epochs, 99.19% Top1. Clustering fixed (hmmer 3.1b2 + sklearn KMeans). CheckM2: 60 bins, 25.01% comp, 2.98% cont. CheckM v1: 60 bins, 21.23% comp, 3.40% cont. | Evaluation done via `scripts/run_eval.sh`. See `eval/checkm2/quality_report.tsv` and `eval/checkm/out/storage/bin_stats_ext.tsv`. |
| [`small_test_v4`](runs/small_test_v4/comebin_run.log) — 2026-09-24 08:48:33 → 08:50:35 | [c8f22e4](https://github.com/paulzierep/COMEBin/commit/c8f22e4935a66a0fd58b794489a9021671b15437) | **✅ Functional gate passed.** 30/30 epochs, 3 non-empty bins in 122 s. CheckM2: 26.07% mean completeness / 2.02% contamination. CheckM v1 (Python 3.10 + `pplacer` library path): 29.08% / 0.71%. | Small gate is complete; medium 3,000-contig derivative is next. See [`results/small_test_v4.csv`](results/small_test_v4.csv). |

| [`medium_v11_20260924`](../runs/medium_v11_20260924/comebin_run.log) — 2026-09-24 09:25:50 → 10:04:36 | [95f5ea8](https://github.com/paulzierep/COMEBin/commit/95f5ea820f9a4e76f5c2911c0b5ed507ab67b015) | **✅ Complete.** 200/200 epochs, 61.23% Top1, 16 non-empty bins in 2,326 s. CheckM2: 35.93% mean completeness / 4.67% contamination (MQ=2). CheckM v1: 33.83% / 6.03% (MQ=3). | Evaluation completed with `scripts/run_eval.sh`; see the [aggregate CSV](../results/medium_v11_20260924.csv) and the [per-bin tables](../runs/medium_v11_20260924/per_bin_results.csv) / [CheckM2 per-bin](../runs/medium_v11_20260924/checkm2_per_bin.csv). |

### Guard-only launches

Twelve launches stopped before COMEBin started. They are grouped by episode so refusals are not mistaken for benchmark runs; raw watchdog refusals remain in `/vol/data/benchmark/logs/*.launch.log`.

| Episode / time (UTC) | Count | Cause | Next step |
|---|---:|---|---|
| [`baseline_unmodified_autorestart1/2/3`](status/supervisor-run.log) — 21:33, 21:35, 21:40 | 3 | Pristine-baseline guard rejected commit `987db95` plus four dirty files. | Restore a clean committed source tree before retrying. |
| [Default-path baseline before the rerun](status/agent-run.log) — shortly before 00:15 | 1 | Existing `runs/baseline_unmodified` directory blocked an overwrite. | Pass a fresh explicit run name. |
| [Small-test preflight before attempt 1](status/agent-run.log) — ~22:39 | 2 | Dirty-source guard rejected the uncommitted seed change. | Commit or clean the source before running. |
| [Small-test preflight before attempt 2](status/agent-run.log) — ~23:08 | 1 | Existing `runs/small_test` directory blocked an overwrite. | Use a fresh run name; preserve the prior evidence. |
| [Small-test preflight before attempt 3](status/agent-run.log) — ~23:09 | 2 | Start lock was held, then stale failed registration `pid=239956` blocked launch. | Do not delete lock/state files manually; let the benchmark watchdog triage them. |
| [Small-test-v2 preflight](status/agent-run.log) — ~23:37 | 1 | Dirty-source guard rejected the uncommitted `np.zeros` fix. | Commit or clean the source before running. |
| [`baseline_rerun` retry 1](status/agent-run.log) — ~00:26 | 1 | Existing timed-run artifacts blocked same-name overwrite; the follow-up then deleted the directory. | Never delete a run directory; preserve evidence and choose a fresh name. |
| [`baseline_rerun` retry 2](status/agent-run.log) — ~00:29 | 1 | `.active_run` still referenced failed wrapper `pid=262046` for the reused path. | Let `benchmark-watchdog.sh` classify exit 143 and perform the fresh-directory handoff. |

## Data preservation and Zenodo

The verified small release is published as **[10.5281/zenodo.22935025](https://doi.org/10.5281/zenodo.22935025)** (version 1, CC BY 4.0). It contains the 95,216,539-byte release archive (SHA-256 `0c698d208639f4fadd4ac4477a67074320c975528b23dd61743c83ad1658b6d2`) and the 3,650-byte public manifest (SHA-256 `84131ae359d07a78db7ae7ca2005758f4f0ec9df67a33ec62f8af50ac1702f1b`). The archive was extracted and all 18 manifest entries were checked; the public record was independently verified through an unauthenticated Zenodo API request. The release checklist, provenance requirements, and future-version workflow are in `docs/10-data-preservation.md`. The watchdogs do not upload data automatically; the token is kept only in the mode-0600 local secret file. Version 1 remains CC BY 4.0; a later request to switch to MIT is being handled as an explicit new-version decision.

## How to resume (for a human or a restarted agent)

1. Read `PROGRESS.md` — it contains the full task definition and the current state checklist.
2. Verify the checklist against what is on disk under `/vol/data`.
3. Continue from the first unfinished item; update `PROGRESS.md` after each step.

See `docs/00-setup.md` for the agent watchdog that performs automatic restart + free-model rotation on token exhaustion.

## References

- Wang Z. et al. *Effective binning of metagenomic contigs using contrastive multi-view representation learning.* Nat Commun 15, 585 (2024).
- Parks D.H. et al. *CheckM...* Genome Res 25(7):1043–1055 (2015). (CheckM v1)
- Chklovsky A. et al. *CheckM2...* Nat Biotechnol (2024). (CheckM2)